// Original MIT. ADR026 fixed native arena, FIFO reservations and joined lifecycle.
#include "flight/local_players/service.hpp"
#include <algorithm>
#include <condition_variable>
#include <cstring>
#include <mutex>
#include <new>

namespace flight::local_players {
namespace {
constexpr std::size_t page=4096,arena_bytes=33554432,control_bytes=131072;
constexpr std::size_t index_offset=control_bytes,index_bytes=1048576;
constexpr std::size_t text_offset=index_offset+index_bytes,text_bytes=655360;
constexpr std::size_t row_offset=text_offset+text_bytes,row_bytes=98304;
constexpr std::size_t io_offset=row_offset+row_bytes,io_bytes=65536;
constexpr std::size_t hash_offset=io_offset+io_bytes,hash_bytes=65536;
constexpr std::size_t metadata_offset=hash_offset+hash_bytes,metadata_bytes=32768;
constexpr std::size_t transient_offset=metadata_offset+metadata_bytes;
static_assert(transient_offset==2097152);
constexpr std::size_t first_page=transient_offset/page,total_pages=arena_bytes/page;
constexpr std::size_t spool_pages=18874368/page;
// Opaque delivery tokens cannot coincide between services in this component.
// This fixed atomic is executable/static data, not an owned variable pool.
std::atomic<std::uint64_t> delivered_lease_counter{};
std::mutex registry_mutex;
Service* registry_head{};
// Monotonic module-lifetime latch, protected by registry_mutex. No resetting
// or reinitializing the component can admit a start after unload preflight.
bool registry_closing{};
bool lease_batch(std::uint8_t count,std::uint64_t& first)noexcept {
 if(!count){first=0;return true;}
 auto prior=delivered_lease_counter.load(std::memory_order_relaxed);
 do{if(UINT64_MAX-prior<count)return false;}
 while(!delivered_lease_counter.compare_exchange_weak(prior,prior+count,std::memory_order_relaxed));
 first=prior+1;return true;
}
struct Extent {std::uint16_t first{},count{};explicit operator bool()const noexcept{return count!=0;}};
struct RequestHeader {std::uint32_t bytes{};JobKind kind{};FixedText<32> id{};};
struct TerminalHeader {std::uint32_t bytes{};FixedText<32> id{};};
static_assert(sizeof(RequestHeader)<=128&&sizeof(TerminalHeader)<=128);
enum class SlotState : std::uint8_t { free,pending,running,done,delivering };
struct Slot {
 SlotState state{};JobKind kind{};FixedText<32> id{};std::uint64_t ordinal{};
 Extent request{},terminal{},delivery{};std::uint32_t request_bytes{},terminal_bytes{};
 std::uint64_t delivery_lease{};std::array<std::uint64_t,3> allocation_ordinals{};
};
bool is_write(JobKind k)noexcept {switch(k){case JobKind::create_player:case JobKind::rename_player:case JobKind::save_preferences:case JobKind::begin_practice:case JobKind::observe_practice:case JobKind::end_practice:case JobKind::link_archive:case JobKind::prune_practice:case JobKind::delete_player:return true;default:return false;}}
bool allowed(ServiceState state,bool management,JobKind kind) noexcept {
 if(state==ServiceState::ready)return kind!=JobKind::delete_recovery;
 if(state==ServiceState::read_only)return !is_write(kind)&&kind!=JobKind::delete_recovery;
 if(state==ServiceState::unavailable)return kind==JobKind::list_recovery||(management&&kind==JobKind::delete_recovery);
 return false;
}
std::string_view result_state(ResultState s)noexcept {switch(s){case ResultState::read:return "read";case ResultState::committed:return "committed";case ResultState::no_change:return "no_change";case ResultState::failed:return "failed";case ResultState::uncertain:return "uncertain";case ResultState::recovery_required:return "recovery_required";}return "failed";}
bool uncertain(Error e)noexcept{return e==Error::commit_unknown||e==Error::verification_failed;}
} // namespace
struct Service::Control {
 explicit Control(StoreAccess&& token):access(std::move(token)){allocation_ordinals=access.allocation_ordinals_;for(unsigned i=0;i<8;++i)pages[i]=UINT64_MAX;}
 mutable std::mutex mutex;
 std::condition_variable wake;
 std::thread worker;
 StoreAccess access;
 alignas(Store) std::array<std::byte,sizeof(Store)> store_storage{};Store* store{};
 std::array<Slot,16> slots{};
 std::array<std::uint64_t,128> pages{};
 std::array<std::uint64_t,6> allocation_ordinals{};
 std::array<std::uint64_t,75> occurrences{};
 std::atomic_flag codec_lease=ATOMIC_FLAG_INIT;
 ServiceState state{ServiceState::new_service};Error diagnostic{Error::none};
 bool worker_created{},worker_exited{},worker_joined{},worker_handles_closed{},shutdown{},management{},qualified{},start_in_progress{};
 std::uint8_t pending{},undelivered{};
 std::uint64_t accepted_ordinal{};
 Extent spool{};std::uint8_t export_users{};std::uint64_t spool_allocation_ordinal{};
 // Owner batch scalar observations are charged Control storage, not a second
 // native variable buffer. The sole worker uses independent scalar notices.
 std::array<ReservationObservation,32> owner_notices{};
 // Owner-only canonical text must remain stable through admission callbacks.
 // This scalar rejects reentrant submits; the worker never waits on it.
 bool admission_active{};
 bool observer_failed{};FixedText<4096> last_root;
 Extent find(std::size_t bytes)const noexcept {
  auto need=(bytes+page-1)/page;if(!need||need>total_pages-first_page)return {};
  std::size_t run=0;for(std::size_t i=first_page;i<total_pages;++i){if((pages[i/64]&(std::uint64_t{1}<<(i%64)))==0){if(++run==need)return {static_cast<std::uint16_t>(i+1-need),static_cast<std::uint16_t>(need)};}else run=0;}return {};
 }
 void mark(Extent e,bool used)noexcept {for(std::size_t i=e.first;i<e.first+e.count;++i){auto bit=std::uint64_t{1}<<(i%64);if(used)pages[i/64]|=bit;else pages[i/64]&=~bit;}}
 std::uint32_t live_pages()const noexcept {std::uint32_t n=0;for(auto bits:pages)n+=std::popcount(bits);return n;}
 ReservationObservation notice(ReservationObservation::Action action,AllocationCategory category,std::uint64_t request,std::uint64_t allocation,std::uint32_t requested,Extent extent)const noexcept {
  return {action,category,access.service_ordinal_,request,allocation,requested,static_cast<std::uint32_t>(extent.count*page),live_pages(),live_pages()};
 }
 bool notify(const ReservationObservation& observation)noexcept {
  if(!access.observer_)return true;try{access.observer_->observe_reservation(observation);return true;}catch(...){return false;}
 }
 void diagnostic_error(Error e)noexcept {if(e==Error::none)return;if(uncertain(e)||!uncertain(diagnostic))diagnostic=e;}
};
Service::Service(std::byte* arena)noexcept:arena_(arena),owner_(std::this_thread::get_id()) {}
Service* Service::create(StoreAccess&& token)noexcept {
 // Service wrapper64B and aligned Control share the permanent131072B region.
 // There is no second owned native control allocation beside the arena.
 static_assert(sizeof(Service)<=64&&alignof(Control)<=64);
 static_assert(64+sizeof(Control)<=control_bytes);
 if(!token.valid())return nullptr;
 auto allow=[&](AllocationCategory category,std::uint32_t bytes){
  auto& ordinal=token.allocation_ordinals_[static_cast<unsigned>(category)];if(ordinal==UINT64_MAX)return false;++ordinal;
  return !token.observer_||token.observer_->allow_allocation({category,token.service_ordinal_,0,ordinal,bytes,bytes,0,0});
 };
 try{if(!allow(AllocationCategory::control,control_bytes)||!allow(AllocationCategory::workspace,transient_offset-control_bytes))return nullptr;}catch(...){return nullptr;}
 auto* arena=static_cast<std::byte*>(::operator new(arena_bytes,std::align_val_t{64},std::nothrow));
 if(!arena)return nullptr;
 auto* instance=new(arena)Service(arena);
 try{instance->control_=new(arena+64)Control(std::move(token));}
 catch(...){instance->~Service();::operator delete(arena,std::align_val_t{64});return nullptr;}
 // Actual permanent ownership is established, no queue mutex is held.
 auto& c=*instance->control_;
 if(c.access.observer_){
  try{for(auto category:{AllocationCategory::control,AllocationCategory::workspace}){
   auto bytes=category==AllocationCategory::control?control_bytes:transient_offset-control_bytes;
   c.access.observer_->observe_reservation({ReservationObservation::Action::claim,category,c.access.service_ordinal_,0,c.allocation_ordinals[static_cast<unsigned>(category)],static_cast<std::uint32_t>(bytes),static_cast<std::uint32_t>(bytes),static_cast<std::uint32_t>(transient_offset/page),static_cast<std::uint32_t>(transient_offset/page)});
  }}catch(...){
   // Null preserves the SAME caller token, platform and consumed attempt
   // ordinals. No worker/root/accepted state exists at this construction stage.
   c.access.allocation_ordinals_=c.allocation_ordinals;
   token=std::move(c.access);
   auto* observer=token.observer_;auto service_ordinal=token.service_ordinal_;
   auto control_ordinal=token.allocation_ordinals_[static_cast<unsigned>(AllocationCategory::control)];
   auto workspace_ordinal=token.allocation_ordinals_[static_cast<unsigned>(AllocationCategory::workspace)];
   c.~Control();instance->~Service();::operator delete(arena,std::align_val_t{64});
   // Free is actual even when the claim observer threw; release observations
   // are best-effort scalar notifications and cannot consume the restored token.
   if(observer){for(auto category:{AllocationCategory::workspace,AllocationCategory::control}){
    auto bytes=category==AllocationCategory::control?control_bytes:transient_offset-control_bytes;
    auto ordinal=category==AllocationCategory::control?control_ordinal:workspace_ordinal;
    try{observer->observe_reservation({ReservationObservation::Action::release,category,service_ordinal,0,ordinal,static_cast<std::uint32_t>(bytes),static_cast<std::uint32_t>(bytes),0,0});}catch(...){}
   }}
   return nullptr;
  }
 }
 return instance;
}
bool Service::destroy(Service* instance)noexcept {
 if(!instance)return true;if(!instance->is_owner())return false;
 auto* c=instance->control_;
 // No detach, automatic blocking join or free-live-worker destruction path.
 if(c->worker_created&&!c->worker_joined)return false;
 if(c->state!=ServiceState::closed&&c->accepted_ordinal!=0)return false;
 if(c->state!=ServiceState::closed&&c->access.filesystem_&&(c->access.filesystem_->has_worker_handles()||c->access.filesystem_->has_lock()))return false;
 {
  std::lock_guard guard(registry_mutex);
  if(instance->registered_){
   if(instance->registry_previous_)instance->registry_previous_->registry_next_=instance->registry_next_;else registry_head=instance->registry_next_;
   if(instance->registry_next_)instance->registry_next_->registry_previous_=instance->registry_previous_;
   instance->registered_=false;
  }
 }
 auto* observer=c->access.observer_;auto service_ordinal=c->access.service_ordinal_;
 auto control_ordinal=c->allocation_ordinals[static_cast<unsigned>(AllocationCategory::control)],workspace_ordinal=c->allocation_ordinals[static_cast<unsigned>(AllocationCategory::workspace)];
 auto* arena=instance->arena_;if(c->store){c->store->~Store();c->store=nullptr;}c->~Control();instance->~Service();
 ::operator delete(arena,std::align_val_t{64});
 // Observer outlives the sealed service capability. These are scalar receipts
 // after the ACTUAL whole-arena free, not fictitious releases before closure.
 if(observer){try{observer->observe_reservation({ReservationObservation::Action::release,AllocationCategory::workspace,service_ordinal,0,workspace_ordinal,static_cast<std::uint32_t>(transient_offset-control_bytes),static_cast<std::uint32_t>(transient_offset-control_bytes),0,0});observer->observe_reservation({ReservationObservation::Action::release,AllocationCategory::control,service_ordinal,0,control_ordinal,control_bytes,control_bytes,0,0});}catch(...){}}
 return true;
}
bool Service::begin_shutdown_registered()noexcept {
 std::lock_guard guard(registry_mutex);
 for(auto* p=registry_head;p;p=p->registry_next_)if(!p->is_owner())return false;
 // Preflight is all-or-nothing. Start checks this same latch while registering.
 registry_closing=true;
 // begin_shutdown holds only a short Control mutex: no IO or observer callback.
 for(auto* p=registry_head;p;p=p->registry_next_)if(!p->begin_shutdown())return false;
 return true;
}
bool Service::try_join_registered()noexcept {
 Service* current{};
 {std::lock_guard guard(registry_mutex);if(!registry_closing)return false;for(auto* p=registry_head;p;p=p->registry_next_)if(!p->is_owner())return false;current=registry_head;}
 bool joined=true;
 while(current){
  Service* next{};{std::lock_guard guard(registry_mutex);next=current->registry_next_;}
  // All preflighted nodes belong to this calling thread; no foreign thread can
  // destroy one. The closing latch prevents any later accepted start.
  joined=current->try_join()&&joined;current=next;
 }
 {std::lock_guard guard(registry_mutex);
  for(auto* p=registry_head;p;p=p->registry_next_){if(!p->is_owner())return false;std::lock_guard state_guard(p->control_->mutex);if(p->control_->state!=ServiceState::closed||p->control_->start_in_progress)return false;}
 }
 return joined;
}
Admission Service::start(bool management)noexcept {
 if(!is_owner())return {false,Error::wrong_thread,{}};
 if(!control_)return {false,Error::out_of_memory,{}};
 {
  // Lock order is registry then Control. No observer, allocation, random source,
  // IO, thread creation or actual join runs while the registry lock is held.
  std::lock_guard registry_guard(registry_mutex);
  if(registry_closing)return {false,Error::invalid_state,{}};
  std::lock_guard state_guard(control_->mutex);
  if(control_->state!=ServiceState::new_service||control_->shutdown||control_->start_in_progress)return {false,Error::invalid_state,{}};
  control_->start_in_progress=true;
  if(!registered_){registry_next_=registry_head;if(registry_head)registry_head->registry_previous_=this;registry_head=this;registered_=true;}
 }
 // Even an admission observer or allocation failure cannot make a registered
 // in-flight start look quiescent to module termination.
 struct Starting {Control& c;~Starting(){std::lock_guard guard(c.mutex);c.start_in_progress=false;}}starting{*control_};
 auto a=admit(management?JobKind::start_management:JobKind::start,{},0);if(!a.accepted)return a;
 {std::lock_guard guard(control_->mutex);control_->management=management;if(!control_->shutdown)control_->state=ServiceState::opening;}
 try{auto* retained=control_;auto* arena=arena_;control_->worker=std::thread([retained,arena]{work(retained,arena);});std::lock_guard guard(control_->mutex);control_->worker_created=true;}
 catch(...){
  std::lock_guard guard(control_->mutex);auto& s=control_->slots[0];
  Writer w({reinterpret_cast<char*>(arena_+s.terminal.first*page)+128,max_message-128});
  w.raw("{\"commit_sequence\":null,\"error_code\":\"worker_lost\",\"kind\":");w.string(kind_name(s.kind));w.raw(",\"request_id\":");w.string(s.id.view());w.raw(",\"state\":\"failed\",\"value\":null}");
  auto* h=reinterpret_cast<TerminalHeader*>(arena_+s.terminal.first*page);*h={static_cast<std::uint32_t>(w.bytes().size()),s.id};s.terminal_bytes=h->bytes;s.state=SlotState::done;
  control_->mark(s.request,false);s.request={};control_->pending=0;control_->undelivered=1;control_->state=ServiceState::unavailable;control_->diagnostic=Error::worker_lost;control_->worker_handles_closed=true;
 }
 return a;
}
Admission Service::submit(const AdmissionSource& source)noexcept {
 if(!is_owner())return {false,Error::wrong_thread,{}};if(!control_)return {false,Error::out_of_memory,{}};
 ServiceState state;bool management;{std::lock_guard guard(control_->mutex);state=control_->shutdown?ServiceState::closing:control_->state;management=control_->management;}
 if(state==ServiceState::new_service||state==ServiceState::opening||state==ServiceState::closing||state==ServiceState::closed)return {false,Error::invalid_state,{}};
 JobKind kind;auto e=source.outer_kind(kind);if(e!=Error::none)return {false,e,{}};
 if(kind==JobKind::start||kind==JobKind::start_management)return {false,Error::invalid_request,{}};
 if(!allowed(state,management,kind))return {false,Error::invalid_state,{}};
 if(control_->admission_active)return {false,Error::out_of_memory,{}};
 control_->admission_active=true;
 struct OwnerText{Control& c;~OwnerText(){c.admission_active=false;}}owner_text{*control_};
 std::string_view canonical_request;
 {
 if(control_->codec_lease.test_and_set(std::memory_order_acquire))return {false,Error::out_of_memory,{}};
 struct Release{std::atomic_flag&f;~Release(){f.clear(std::memory_order_release);}}release{control_->codec_lease};
 auto cells=std::span(reinterpret_cast<JsonCell*>(arena_+index_offset),index_bytes/sizeof(JsonCell));
 auto text=std::span(reinterpret_cast<char*>(arena_+text_offset),text_bytes);
 DocumentView d;e=source.capture(cells,text,d);if(e!=Error::none)return {false,e,{}};
 // A source returns only prefixes of the supplied spans. It cannot smuggle a
 // borrowed external tree/string through a valid flag or retained caller view.
 if(d.cells.data()!=cells.data()||d.cells.size()>cells.size()||d.bytes.data()!=text.data()||d.bytes.size()>text.size())return {false,Error::invalid_record,{}};
 if((e=validate_capture(d,Limits{max_message,30000,12,4096,4096}))!=Error::none)return {false,e,{}};
 RequestView request;e=validate_request(d,request,false,cells);if(e!=Error::none)return {false,e,{}};
 if(request.kind!=kind)return {false,Error::invalid_request,{}};
 auto count=Writer::measure(max_message-128);
 if(!count.value(d,d.root)||!count.good())return {false,Error::payload_limit,{}};
 // Actual codec roundtrip/full validation precedes EVERY queue/page claim.
 // Closed schema bounds leave the unused suffix of the charged1MiB index free:
 // at most two presets, each8 devices/8 axes/30 unique actions/four sources and
 // four keys, plus4 v2 systems. Even conservative4096 cells leave917504B, more
 // than the entire655360B canonical cap. This is not a generic scanner reduction.
 std::size_t restored_cells=d.cells.size();for(const auto& cell:d.cells)if(cell.kind==ValueKind::real)++restored_cells;
 if(restored_cells>cells.size()||count.size()>(cells.size()-restored_cells)*sizeof(JsonCell))return {false,Error::out_of_memory,{}};
 auto scratch=std::span(reinterpret_cast<char*>(cells.data()+restored_cells),(cells.size()-restored_cells)*sizeof(JsonCell));
 Writer canonical(scratch);if(!canonical.value(d,d.root)||canonical.size()!=count.size())return {false,Error::invalid_record,{}};
 // Parsing may now replace captured cells/text: canonical source occupies only
 // the index suffix beyond the exactly pre-counted restored cell prefix.
 auto roundtrip=parse_json(canonical.bytes(),cells.first(restored_cells),std::as_writable_bytes(text),Limits{max_message,30000,12,4096,4096});
 RequestView decoded;e=roundtrip?validate_request(roundtrip.value,decoded,true,cells):roundtrip.error;
 if(e!=Error::none||decoded.kind!=kind)return {false,e==Error::none?Error::invalid_request:e,{}};
 Writer restored(text);if(!restored.value(roundtrip.value,roundtrip.value.root)||restored.bytes()!=canonical.bytes())return {false,Error::invalid_record,{}};
 canonical_request=restored.bytes();
 } // Release the shared INDEX lease before any queue lock/observer/allocation.
 // Permanent text is owner-only. The worker uses its running slot's reserved
 // delivery block as codec scratch, so these canonical bytes remain stable
 // through queue/count/reservation callbacks until the real R copy completes.
 return admit(kind,DocumentView{canonical_request,{},no_cell},canonical_request.size());
}
Admission Service::admit(JobKind kind,DocumentView document,std::size_t bytes)noexcept {
 auto& c=*control_;std::uint64_t ordinal;std::uint32_t live;std::uint8_t free_slot=16;
 bool export_job=kind==JobKind::export_player,export_credit=false,claimed_spool=false;Extent shared_spool{};ReservationObservation shared_notice{};
 {std::lock_guard guard(c.mutex);
  if(c.shutdown||((kind!=JobKind::start&&kind!=JobKind::start_management)&&!allowed(c.state,c.management,kind)))return {false,Error::invalid_state,{}};
  if(c.pending+c.undelivered==16)return {false,Error::queue_full,{}};
  for(std::uint8_t i=0;i<16;++i)if(c.slots[i].state==SlotState::free){free_slot=i;break;}
  ordinal=c.accepted_ordinal+1;live=c.live_pages();
  // Pin an existing shared reservation across allocation-observer calls. No
  // observer is invoked under the mutex; the worker cannot free credited E.
  if(export_job&&c.spool){++c.export_users;export_credit=true;shared_spool=c.spool;shared_notice=c.notice(ReservationObservation::Action::share,AllocationCategory::export_spool,ordinal,c.spool_allocation_ordinal,spool_pages*page,c.spool);}
 }
 auto release_credit=[&]{if(export_credit){ReservationObservation unshare{},release{};bool freed=false;{std::lock_guard guard(c.mutex);if(--c.export_users==0&&c.spool){c.mark(c.spool,false);c.spool={};freed=true;}unshare=c.notice(ReservationObservation::Action::unshare,AllocationCategory::export_spool,ordinal,c.spool_allocation_ordinal,spool_pages*page,shared_spool);if(freed)release=c.notice(ReservationObservation::Action::release,AllocationCategory::export_spool,ordinal,c.spool_allocation_ordinal,spool_pages*page,shared_spool);export_credit=false;}c.notify(unshare);if(freed)c.notify(release);}};
 if(export_credit&&!c.notify(shared_notice)){release_credit();return {false,Error::out_of_memory,{}};}
 if(free_slot==16||ordinal==0){release_credit();return {false,Error::out_of_memory,{}};}
 auto permit=[&](AllocationCategory category,std::size_t size){auto index=static_cast<unsigned>(category);auto next=c.allocation_ordinals[index]+1;if(next==0)return false;AllocationObservation o{category,c.access.service_ordinal_,ordinal,next,static_cast<std::uint32_t>(size),static_cast<std::uint32_t>((size+page-1)/page*page),live,live};c.allocation_ordinals[index]=next;if(c.access.observer_){try{if(!c.access.observer_->allow_allocation(o))return false;}catch(...){return false;}}return true;};
 if(!permit(AllocationCategory::request,bytes+128)||!permit(AllocationCategory::terminal,max_message)||!permit(AllocationCategory::delivery,max_message)||(export_job&&!export_credit&&!permit(AllocationCategory::export_spool,spool_pages*page))){release_credit();return {false,Error::out_of_memory,{}};}
 Slot proposed;proposed.kind=kind;proposed.ordinal=ordinal;for(unsigned i=0;i<3;++i)proposed.allocation_ordinals[i]=c.allocation_ordinals[static_cast<unsigned>(AllocationCategory::request)+i];
 bool allocation_failed=false;
 {std::lock_guard guard(c.mutex);
  proposed.request=c.find(bytes+128);if(proposed.request)c.mark(proposed.request,true);
  proposed.terminal=c.find(max_message);if(proposed.terminal)c.mark(proposed.terminal,true);
  proposed.delivery=c.find(max_message);if(proposed.delivery)c.mark(proposed.delivery,true);
  if(export_job&&!export_credit){c.spool=c.find(spool_pages*page);if(c.spool){c.mark(c.spool,true);c.spool_allocation_ordinal=c.allocation_ordinals[static_cast<unsigned>(AllocationCategory::export_spool)];++c.export_users;export_credit=true;claimed_spool=true;shared_spool=c.spool;}}
  if(export_job&&!export_credit)c.spool_allocation_ordinal=c.allocation_ordinals[static_cast<unsigned>(AllocationCategory::export_spool)];
  allocation_failed=!proposed.request||!proposed.terminal||!proposed.delivery||(export_job&&!export_credit);
 }
 auto observe_extent=[&](ReservationObservation::Action action,AllocationCategory category,Extent extent,std::uint64_t allocation,std::uint32_t requested){
  if(!extent)return true;ReservationObservation observation;{std::lock_guard guard(c.mutex);observation=c.notice(action,category,ordinal,allocation,requested,extent);}return c.notify(observation);
 };
 auto undo=[&]{
  Extent spool_released{};bool unshared=export_credit;
  {std::lock_guard guard(c.mutex);c.mark(proposed.request,false);c.mark(proposed.terminal,false);c.mark(proposed.delivery,false);if(export_credit){if(--c.export_users==0&&c.spool){spool_released=c.spool;c.mark(c.spool,false);c.spool={};}export_credit=false;}}
  observe_extent(ReservationObservation::Action::release,AllocationCategory::request,proposed.request,proposed.allocation_ordinals[0],static_cast<std::uint32_t>(bytes+128));
  observe_extent(ReservationObservation::Action::release,AllocationCategory::terminal,proposed.terminal,proposed.allocation_ordinals[1],max_message);
  observe_extent(ReservationObservation::Action::release,AllocationCategory::delivery,proposed.delivery,proposed.allocation_ordinals[2],max_message);
  if(unshared){Extent extent=shared_spool;observe_extent(ReservationObservation::Action::unshare,AllocationCategory::export_spool,extent,c.spool_allocation_ordinal,spool_pages*page);}
  if(spool_released)observe_extent(ReservationObservation::Action::release,AllocationCategory::export_spool,spool_released,c.spool_allocation_ordinal,spool_pages*page);
 };
 bool notified=observe_extent(ReservationObservation::Action::claim,AllocationCategory::request,proposed.request,proposed.allocation_ordinals[0],static_cast<std::uint32_t>(bytes+128));
 notified=observe_extent(ReservationObservation::Action::claim,AllocationCategory::terminal,proposed.terminal,proposed.allocation_ordinals[1],max_message)&&notified;
 notified=observe_extent(ReservationObservation::Action::claim,AllocationCategory::delivery,proposed.delivery,proposed.allocation_ordinals[2],max_message)&&notified;
 if(claimed_spool){notified=observe_extent(ReservationObservation::Action::claim,AllocationCategory::export_spool,shared_spool,c.spool_allocation_ordinal,spool_pages*page)&&notified;notified=observe_extent(ReservationObservation::Action::share,AllocationCategory::export_spool,shared_spool,c.spool_allocation_ordinal,spool_pages*page)&&notified;}
 if(!notified){undo();return {false,Error::out_of_memory,{}};}
 if(allocation_failed){undo();return {false,Error::out_of_memory,{}};}
 auto destination=reinterpret_cast<char*>(arena_+proposed.request.first*page)+128;
 if(kind!=JobKind::start&&kind!=JobKind::start_management){
  if(document.bytes.size()!=bytes){undo();return {false,Error::invalid_record,{}};}
  std::memcpy(destination,document.bytes.data(),bytes);
 }
 proposed.request_bytes=static_cast<std::uint32_t>(bytes);
 FixedText<32> id;
 if(!c.access.filesystem_||c.access.filesystem_->random_id(id)!=Error::none){undo();return {false,Error::out_of_memory,{}};}
 {std::lock_guard guard(c.mutex);
  if(!c.shutdown&&((kind==JobKind::start||kind==JobKind::start_management)||allowed(c.state,c.management,kind))){
   proposed.id=id;proposed.state=SlotState::pending;auto* h=reinterpret_cast<RequestHeader*>(arena_+proposed.request.first*page);*h={proposed.request_bytes,kind,id};c.slots[free_slot]=proposed;c.accepted_ordinal=ordinal;++c.pending;c.wake.notify_one();return {true,Error::none,id};
  }
 }
 undo();return {false,Error::invalid_state,{}};
}
bool Service::status(Status& out)const noexcept {
 if(!is_owner()||!control_)return false;auto& c=*control_;std::lock_guard guard(c.mutex);out={c.state,c.diagnostic,c.pending,c.undelivered,c.worker_created&&!c.worker_exited,c.last_root.size!=0,c.qualified,c.last_root};return true;
}
bool Service::begin_shutdown()noexcept {if(!is_owner()||!control_)return false;auto&c=*control_;std::lock_guard guard(c.mutex);c.shutdown=true;if(c.state!=ServiceState::closed)c.state=ServiceState::closing;c.wake.notify_one();return true;}
bool Service::try_join()noexcept {
 if(!is_owner()||!control_)return false;auto& c=*control_;
 {std::lock_guard guard(c.mutex);if(c.start_in_progress)return false;if(c.state==ServiceState::closed)return true;
  if(!c.worker_created){if(!c.shutdown||c.pending||(c.access.filesystem_&&(c.access.filesystem_->has_worker_handles()||c.access.filesystem_->has_lock())))return false;c.state=ServiceState::closed;return true;}
  if(!c.worker_exited||c.pending)return false;c.shutdown=true;
 }
 // No worker remains to touch the retained Control-owned Store. Failed actual
 // SQL/Win32 closes keep their exact owners for a later owner retry, not an
 // expired stack object or a fabricated joined-and-closed receipt.
 if(c.worker.joinable())c.worker.join();
 {std::lock_guard guard(c.mutex);c.worker_joined=true;}
 bool closed=c.store&&c.store->close();
 {std::lock_guard guard(c.mutex);c.worker_handles_closed=closed;if(!closed){c.diagnostic_error(Error::io_error);return false;}}
 if(!c.access.filesystem_->release_lock_after_join()){std::lock_guard guard(c.mutex);c.diagnostic_error(Error::io_error);return false;}
 {std::lock_guard guard(c.mutex);c.state=ServiceState::closed;}return true;
}
bool Service::peek(std::uint8_t limit,std::span<DeliveryView> out,std::uint8_t& count)noexcept {
 if(!is_owner()||!control_||limit<1||limit>16||out.size()<limit)return false;auto&c=*control_;std::lock_guard guard(c.mutex);
 for(auto&s:c.slots)if(s.state==SlotState::delivering)return false;
 std::array<Slot*,16> batch{};std::uint8_t ready=0;std::uint64_t previous=0;
 while(ready<limit){Slot* selected=nullptr;for(auto&s:c.slots)if(s.state==SlotState::done&&s.ordinal>previous&&(!selected||s.ordinal<selected->ordinal))selected=&s;if(!selected)break;
  // FIFO never passes an earlier accepted pending/running request.
  bool earlier=false;for(auto&s:c.slots)if((s.state==SlotState::pending||s.state==SlotState::running)&&s.ordinal<selected->ordinal)earlier=true;
  if(earlier)break;batch[ready++]=selected;previous=selected->ordinal;
 }
 std::uint64_t first{};if(!lease_batch(ready,first))return false;
 for(std::uint8_t i=0;i<ready;++i){auto* selected=batch[i];auto lease=first+i;
  auto from=arena_+selected->terminal.first*page;auto to=arena_+selected->delivery.first*page;std::memcpy(to,from,128+selected->terminal_bytes);
  selected->state=SlotState::delivering;selected->delivery_lease=lease;
  out[i]={{reinterpret_cast<char*>(to)+128,selected->terminal_bytes},lease};
 }
 count=ready;return true;
}
bool Service::acknowledge(std::span<const std::uint64_t> leases)noexcept {
 if(!is_owner()||!control_)return false;auto&c=*control_;std::size_t notices=0;
 {
  std::lock_guard guard(c.mutex);
  std::size_t delivering=0;for(auto&s:c.slots)if(s.state==SlotState::delivering)++delivering;if(delivering!=leases.size())return false;
  for(std::size_t i=0;i<leases.size();++i){bool found=false;for(auto&s:c.slots)found|=s.state==SlotState::delivering&&s.delivery_lease==leases[i];if(!found)return false;for(std::size_t j=0;j<i;++j)if(leases[i]==leases[j])return false;}
  for(auto&s:c.slots)if(s.state==SlotState::delivering){
   c.mark(s.terminal,false);c.mark(s.delivery,false);
   c.owner_notices[notices++]=c.notice(ReservationObservation::Action::release,AllocationCategory::terminal,s.ordinal,s.allocation_ordinals[1],max_message,s.terminal);
   c.owner_notices[notices++]=c.notice(ReservationObservation::Action::release,AllocationCategory::delivery,s.ordinal,s.allocation_ordinals[2],max_message,s.delivery);
   s=Slot{};--c.undelivered;
  }
 }
 // Complete batch is consumed atomically before observation. A test observer
 // failure cannot make an already-drained batch appear pending or be re-acked.
 for(std::size_t i=0;i<notices;++i)c.notify(c.owner_notices[i]);return true;
}
bool Service::abandon(std::span<const std::uint64_t> leases)noexcept {
 if(!is_owner()||!control_)return false;auto&c=*control_;std::lock_guard guard(c.mutex);std::size_t count=0;for(auto&s:c.slots)if(s.state==SlotState::delivering)++count;if(count!=leases.size())return false;
 for(std::size_t i=0;i<leases.size();++i){bool found=false;for(auto&s:c.slots)found|=s.state==SlotState::delivering&&s.delivery_lease==leases[i];if(!found)return false;for(std::size_t j=0;j<i;++j)if(leases[i]==leases[j])return false;}
 for(auto&s:c.slots)if(s.state==SlotState::delivering){s.state=SlotState::done;s.delivery_lease=0;}return true;
}
void Service::work(Control* retained,std::byte* arena_)noexcept {
 auto& c=*retained;
 WorkingMemory memory{{{reinterpret_cast<JsonCell*>(arena_+index_offset),index_bytes/sizeof(JsonCell)},{},&c.codec_lease}, {reinterpret_cast<char*>(arena_+row_offset),row_bytes},{arena_+io_offset,io_bytes},{reinterpret_cast<char*>(arena_+hash_offset),hash_bytes+metadata_bytes},&c.codec_lease};
 Store& store=*(c.store=new(c.store_storage.data())Store(c.access,memory));
 for(;;){Slot* slot=nullptr;Extent active_spool{};
  {std::unique_lock guard(c.mutex);c.wake.wait(guard,[&]{if(c.shutdown)return true;for(auto&s:c.slots)if(s.state==SlotState::pending)return true;return false;});
   for(auto&s:c.slots)if(s.state==SlotState::pending&&(!slot||s.ordinal<slot->ordinal))slot=&s;
   if(!slot){if(c.shutdown)break;continue;}slot->state=SlotState::running;if(slot->kind==JobKind::export_player)active_spool=c.spool;
  }
  // D exists from atomic admission through eventual owner acknowledgement.
  // A running slot cannot be peeked. Its entire D block can therefore back the
  // worker's duplicate table/transcoding scratch; T is a disjoint terminal.
  // parse_json views borrow their INPUT (owned R/row/T), not this table. Every
  // D-backed encoder output is copied to T/row within the pure codec lease.
  store.memory_.codec.text={reinterpret_cast<char*>(arena_+slot->delivery.first*page),slot->delivery.count*page};
  NativeContext context{c.access.observer_,c.access.service_ordinal_,slot->ordinal,slot->kind,&c.occurrences,slot->id.view()};c.occurrences.fill(0);
  auto base=reinterpret_cast<char*>(arena_+slot->terminal.first*page)+128;
  Writer value({base+512,max_message-128-512});RepositoryResult result;
  try{if(c.observer_failed){
    auto request=reinterpret_cast<char*>(arena_+slot->request.first*page)+128;
    result=store.fail_unstarted(slot->kind,{request,slot->request_bytes},value,context);
   }
   else if(slot->kind==JobKind::start||slot->kind==JobKind::start_management)result=store.start(slot->kind==JobKind::start_management,value,context);
   else{auto request=reinterpret_cast<char*>(arena_+slot->request.first*page)+128;auto spool=active_spool?std::span<char>(reinterpret_cast<char*>(arena_+active_spool.first*page),active_spool.count*page):std::span<char>{};result=store.execute({request,slot->request_bytes},value,spool,context);}}
  catch(...){result=store.recover_unexpected(slot->kind,value,context);}
  // Failure values are null except the two effect-aware file/management
  // receipts. This also removes stale scratch left by early qualification,
  // checkpoint or BEGIN errors before publication into the reserved terminal.
  if((result.state==ResultState::failed||result.state==ResultState::uncertain)&&slot->kind!=JobKind::export_player&&slot->kind!=JobKind::delete_recovery){value.reset();value.raw("null");}
  if(!value.good()||value.bytes().empty()){
   if(slot->kind==JobKind::export_player||slot->kind==JobKind::delete_recovery||slot->kind==JobKind::list_recovery)result=store.recover_unexpected(slot->kind,value,context);
   else if(is_write(slot->kind)||slot->kind==JobKind::start){store.disable_writes();result={ResultState::uncertain,Error::verification_failed,{},false,0,true,false,store.qualified()};value.reset();value.raw("null");}
   else{result={ResultState::failed,Error::io_error,{},false,0,store.read_only(),false,store.qualified()};value.reset();value.raw("null");}
  }
  Writer prefix({base,512});prefix.raw("{\"commit_sequence\":");if(result.has_sequence)prefix.string(result.commit_sequence.view());else prefix.raw("null");prefix.raw(",\"error_code\":");prefix.string(error_name(result.error));prefix.raw(",\"kind\":");prefix.string(kind_name(slot->kind));prefix.raw(",\"request_id\":");prefix.string(slot->id.view());prefix.raw(",\"state\":");prefix.string(result_state(result.state));prefix.raw(",\"value\":");
  auto length=value.bytes().size();std::memmove(base+prefix.bytes().size(),value.bytes().data(),length);base[prefix.bytes().size()+length]='}';slot->terminal_bytes=static_cast<std::uint32_t>(prefix.bytes().size()+length+1);auto*h=reinterpret_cast<TerminalHeader*>(base-128);*h={slot->terminal_bytes,slot->id};
  NativeObservation event;event.phase=Phase::publish_ack;event.scope=Scope::service;event.edge=Edge::before;event.occurrence=context.next(event.phase,event.scope);
  {std::lock_guard guard(c.mutex);event.pending=c.pending;event.undelivered=c.undelivered;}try{context.event(event);}catch(...){std::lock_guard guard(c.mutex);c.observer_failed=true;c.shutdown=true;c.state=ServiceState::closing;c.diagnostic_error(Error::worker_lost);}
  // No codec borrower remains when this slot becomes done. peek later copies
  // the immutable T bytes over D before exposing a caller delivery lease.
  store.memory_.codec.text={};
  ReservationObservation released_request{},unshared_spool{},released_spool{};bool had_spool=false,freed_spool=false;
  {std::lock_guard guard(c.mutex);auto request_extent=slot->request;c.mark(request_extent,false);released_request=c.notice(ReservationObservation::Action::release,AllocationCategory::request,slot->ordinal,slot->allocation_ordinals[0],slot->request_bytes+128,request_extent);slot->request={};slot->state=SlotState::done;--c.pending;++c.undelivered;
   if(slot->kind==JobKind::export_player){had_spool=true;auto extent=c.spool;if(--c.export_users==0){c.mark(c.spool,false);c.spool={};freed_spool=true;}unshared_spool=c.notice(ReservationObservation::Action::unshare,AllocationCategory::export_spool,slot->ordinal,c.spool_allocation_ordinal,spool_pages*page,extent);if(freed_spool)released_spool=c.notice(ReservationObservation::Action::release,AllocationCategory::export_spool,slot->ordinal,c.spool_allocation_ordinal,spool_pages*page,extent);}
   c.qualified=store.qualified();if(c.access.filesystem_->has_lock())c.last_root.assign(c.access.filesystem_->root());
   if(!c.shutdown&&result.read_only)c.state=ServiceState::read_only;else if(!c.shutdown&&result.unavailable)c.state=ServiceState::unavailable;else if(slot->kind==JobKind::start&&!c.shutdown)c.state=ServiceState::ready;else if(slot->kind==JobKind::start_management&&!c.shutdown)c.state=ServiceState::unavailable;
   if(slot->kind==JobKind::start||slot->kind==JobKind::start_management||result.state==ResultState::uncertain)c.diagnostic_error(result.error);
   event.edge=Edge::after;event.pending=c.pending;event.undelivered=c.undelivered;
  }c.notify(released_request);if(had_spool)c.notify(unshared_spool);if(freed_spool)c.notify(released_spool);try{context.event(event);}catch(...){std::lock_guard guard(c.mutex);c.observer_failed=true;c.shutdown=true;c.state=ServiceState::closing;c.diagnostic_error(Error::worker_lost);}
 }
 bool closed=store.close();{std::lock_guard guard(c.mutex);c.worker_handles_closed=closed;if(!closed)c.diagnostic_error(Error::io_error);c.worker_exited=true;}
}
} // namespace flight::local_players
