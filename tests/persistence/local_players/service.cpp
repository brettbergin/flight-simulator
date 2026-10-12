// Original MIT. Independent test-owned values; real Service/SQLite/Win32 only.
#include "test_capability.hpp"
#include "flight/local_players/service.hpp"
#include <algorithm>
#include <charconv>
#include <array>
#include <atomic>
#include <bit>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <exception>
#include <iostream>
#include <limits>
#include <map>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <source_location>
#include <string>
#include <thread>
#include <utility>
#include <vector>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <tlhelp32.h>
namespace {
using namespace flight::local_players;
using namespace flight::local_players::testing;
std::atomic_size_t checks{},actual_events{};
[[maybe_unused]] void require(bool value,std::string_view label){++checks;if(!value)throw std::runtime_error(std::string(label));}
[[maybe_unused]] std::string digest_text(std::string_view value){auto h=sha256_hex(value);return {h.data(),h.size()};}
struct Raw {
 std::string bytes;std::vector<JsonCell> cells;std::vector<std::byte> scratch;DocumentView d;
 explicit Raw(std::string value):bytes(std::move(value)),cells(30000),scratch(524288){
  auto parsed=parse_json(bytes,cells,scratch,Limits{33554432,30000,12,4096,262144});
  require(static_cast<bool>(parsed),"actual JSON complete grammar");d=parsed.value;
 }
 Raw(const Raw&)=delete;Raw&operator=(const Raw&)=delete;
};
[[maybe_unused]] std::uint32_t member(DocumentView d,std::uint32_t node,std::string_view key){auto n=d.member(node,key);require(n!=no_cell,"required actual member");return n;}
[[maybe_unused]] std::string text(DocumentView d,std::uint32_t n){std::vector<char>b(655360);std::size_t used{};require(copy_string(d,n,b,used),"actual String");return {b.data(),used};}
[[maybe_unused]] std::string field(DocumentView d,std::uint32_t n,std::string_view key){return text(d,member(d,n,key));}
[[maybe_unused]] std::uint64_t natural(DocumentView d,std::uint32_t n,std::uint64_t maximum){auto*c=d.at(n);require(c&&c->kind==ValueKind::integer&&c->scalar<=maximum,"actual bounded INT");return c->scalar;}
[[maybe_unused]] bool nil(DocumentView d,std::uint32_t n){auto*c=d.at(n);return c&&c->kind==ValueKind::null;}
[[maybe_unused]] std::string canonical(DocumentView d,std::uint32_t n){std::vector<char>b(655360);Writer w(b);require(w.value(d,n),"bounded actual canonical value");return std::string(w.bytes());}
[[maybe_unused]] std::vector<std::uint32_t> array(DocumentView d,std::uint32_t n){auto*c=d.at(n);require(c&&c->kind==ValueKind::array,"actual Array");std::vector<std::uint32_t>out;for(auto i=c->first;i!=no_cell;i=d.at(i)->next){require(out.size()<30000&&d.at(i),"finite actual Array");out.push_back(i);}return out;}

// Independent literal typed values. FLOAT values are authored IEEE bits, not
// obtained through a decimal parser or production encode/decode roundtrip.
struct V {
 ValueKind kind{ValueKind::null};std::uint64_t bits{};std::string string;
 std::vector<V> items;std::vector<std::pair<std::string,V>> fields;
 static V null(){return {};}
 static V b(bool x){V v;v.kind=ValueKind::boolean;v.bits=x?1:0;return v;}
 static V i(std::int64_t x){V v;v.kind=ValueKind::integer;v.bits=std::bit_cast<std::uint64_t>(x);return v;}
 static V f(std::uint64_t x){V v;v.kind=ValueKind::real;v.bits=x;return v;}
 static V s(std::string x){V v;v.kind=ValueKind::string;v.string=std::move(x);return v;}
 static V a(std::vector<V>x={}){V v;v.kind=ValueKind::array;v.items=std::move(x);return v;}
 static V o(std::vector<std::pair<std::string,V>>x){V v;v.kind=ValueKind::object;v.fields=std::move(x);return v;}
 V& get(std::string_view key){for(auto&x:fields)if(x.first==key)return x.second;throw std::runtime_error("test field missing");}
};
struct Capture final:AdmissionSource {
 JobKind kind;V value;Error outer_error{Error::none};mutable std::size_t captures{};
 Capture(JobKind k,V payload):kind(k),value(V::o({{"kind",V::s(std::string(kind_name(k)))},{"payload",std::move(payload)}})){}
 Error outer_kind(JobKind& out)const noexcept override {out=kind;return outer_error;}
 Error capture(std::span<JsonCell> cells,std::span<char> bytes,DocumentView& out)const noexcept override {
  ++captures;std::size_t used=0,count=0;Error error=Error::none;
  auto append=[&](auto&&self,const V&v,std::string_view key)->std::uint32_t{
   if(error!=Error::none)return no_cell;
   if(count>=cells.size()||count>=30000||key.size()>UINT16_MAX||key.size()+v.string.size()>bytes.size()-used){error=Error::payload_limit;return no_cell;}
   auto at=static_cast<std::uint32_t>(count++);JsonCell c;c.kind=v.kind;c.scalar=v.bits;c.flags=1;
   c.key_offset=static_cast<std::uint32_t>(used);c.key_length=static_cast<std::uint16_t>(key.size());
   if(!key.empty())std::memcpy(bytes.data()+used,key.data(),key.size());used+=key.size();c.offset=static_cast<std::uint32_t>(used);c.length=static_cast<std::uint32_t>(v.string.size());
   std::memcpy(bytes.data()+used,v.string.data(),v.string.size());used+=v.string.size();cells[at]=c;auto previous=no_cell;
   auto add=[&](const V&child,std::string_view name){auto n=self(self,child,name);if(n==no_cell)return;if(previous==no_cell)cells[at].first=n;else cells[previous].next=n;previous=n;};
   for(const auto&x:v.items)add(x,{});for(const auto&x:v.fields)add(x.second,x.first);return at;
  };
  auto root=append(append,value,{});if(error!=Error::none)return error;out={{bytes.data(),used},cells.first(count),root};return Error::none;
 }
};
[[maybe_unused]] V audio(std::uint64_t gain=UINT64_C(0x3ff0000000000000)){
 return V::o({{"enabled",V::b(true)},{"engine_gain",V::f(gain)},{"airflow_gain",V::f(UINT64_C(0x3ff0000000000000))},{"show_panel_captions",V::b(true)}});
}
[[maybe_unused]] V seed_audio(std::uint64_t gain){return V::o({{"legacy_input",V::null()},{"piston_input",V::null()},{"audio",audio(gain)}});}
[[maybe_unused]] V source(std::string session="synthetic-service-reference-1",std::string start="ground-ready"){
 // Frozen service-reference synthetic descriptor: not a claimed native identity.
 return V::o({{"session_id",V::s(std::move(session))},{"model_identity",V::o({{"id",V::s("original-interactive-prototype")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-interactive")}})},
  {"source_variant",V::s("jsbsim-1.3.1-upstream")},{"native_source_fingerprint",V::s(std::string(64,'1'))},{"prepared_world_sha256",V::s(std::string(64,'2'))},
  {"named_start",V::s(std::move(start))},{"wind_profile",V::s("calm")},{"angular_integration_method",V::null()}});
}
[[maybe_unused]] V player_seed(std::string id,std::string name="Alice"){return V::o({{"id",V::s(std::move(id))},{"name",V::s(std::move(name))},{"utc",V::s("2026-10-03T12:00:00Z")}});}
[[maybe_unused]] V begin_seed(std::string id,std::string player,std::string session="synthetic-service-reference-1",std::string tick="9007199254740993"){
 return V::o({{"seed",V::o({{"id",V::s(std::move(id))},{"player_id",V::s(std::move(player))},{"source",source(std::move(session))},{"started_utc",V::s("2026-10-03T12:01:00Z")},{"first_tick",V::s(std::move(tick))}})}});
}
[[maybe_unused]] V observe_seed(std::string id,std::string player,std::string rev,std::string tick="9007199254741000",std::string session="synthetic-service-reference-1"){
 return V::o({{"practice_id",V::s(std::move(id))},{"player_id",V::s(std::move(player))},{"expected_revision",V::s(std::move(rev))},{"expected_source",source(std::move(session))},{"last_tick",V::s(std::move(tick))},{"utc",V::s("2026-10-03T12:02:00Z")}});
}
[[maybe_unused]] V end_seed(std::string id,std::string player,std::string rev,std::string tick="9007199254741000",std::string session="synthetic-service-reference-1"){
 V v=observe_seed(std::move(id),std::move(player),std::move(rev),std::move(tick),std::move(session));v.fields.emplace_back("status",V::s("manually_ended"));v.fields.emplace_back("end_reason",V::s("user_end"));return v;
}

// Test-only observer holds only at actual production notifications. No SQL or
// Win32 result is substituted; allocation refusal is the accepted native seam.
struct Probe final:QualificationObserver {
 std::mutex mutex;std::condition_variable cv;std::vector<NativeObservation> events;std::vector<AllocationObservation> allocations;
 std::size_t maximum;bool armed{},arrived{},released{},throw_after_release{},throw_claim{},refuse_next{};
 JobKind gate_kind{};Phase gate_phase{};Edge gate_edge{};std::optional<AllocationCategory> allocation_gate;
 std::size_t claims{};bool overflow{},allocation_armed{},allocation_arrived{},allocation_released{};

 // Test-owned bounded history, not charged production arena storage.
 std::vector<ReservationObservation> reservations;
 struct AllocationSelector {AllocationCategory category;std::uint64_t service,request,ordinal;};
 std::optional<AllocationSelector> denied;std::size_t denied_count{};
 std::uint64_t throw_publish_request{};
 void deny_allocation(AllocationCategory category,std::uint64_t service,std::uint64_t request,std::uint64_t ordinal){std::lock_guard lock(mutex);require(!denied,"one exact refusal selector");denied=AllocationSelector{category,service,request,ordinal};}
 void throw_publish_for(std::uint64_t request){std::lock_guard lock(mutex);require(request&&!throw_publish_request,"one exact ACK observer throw");throw_publish_request=request;}
 std::size_t event_count(){std::lock_guard lock(mutex);return events.size();}
 std::size_t allocation_count(){std::lock_guard lock(mutex);return allocations.size();}
 std::uint64_t last_request(){std::lock_guard lock(mutex);require(!allocations.empty(),"observed allocation request identity");return allocations.back().request_ordinal;}
 void wait_published(std::uint64_t request){std::unique_lock lock(mutex);require(cv.wait_for(lock,std::chrono::seconds(30),[&]{return overflow||std::any_of(events.begin(),events.end(),[&](const NativeObservation&o){return o.request_ordinal==request&&o.phase==Phase::publish_ack&&o.edge==Edge::after;});}),"actual post-release publication observed");require(!overflow,"publication preserves original observation cap");}
 void no_effects_since(std::size_t before){std::lock_guard lock(mutex);require(events.size()==before,"refused admission has no new SQL/file/native event");require(!denied,"exact allocation selector consumed");}
 std::uint64_t reserved_bytes(){
  std::lock_guard lock(mutex);std::map<std::array<std::uint64_t,4>,std::uint32_t> live;
  // E is shared across request identities: its claim belongs to the first
  // borrower and release to the last. All other extents remain request-bound.
  for(const auto&o:reservations){require(o.reserved_pages<=8192&&o.live_pages<=8192,"actual reported ownership never exceeds32MiB");auto key=std::array<std::uint64_t,4>{static_cast<std::uint64_t>(o.category),o.service_ordinal,o.category==AllocationCategory::export_spool?0:o.request_ordinal,o.allocation_ordinal};
   if(o.action==ReservationObservation::Action::claim){require(o.rounded&&o.rounded%4096==0&&!live.contains(key),"unique actual page-rounded claim");live.emplace(key,o.rounded);}
   else if(o.action==ReservationObservation::Action::release){auto i=live.find(key);require(i!=live.end()&&i->second==o.rounded,"release exactly an observed actual reservation");live.erase(i);}
  }
  std::uint64_t total=0;for(const auto&entry:live)total+=entry.second;require(total<=33554432,"independent live claim ledger bounded32MiB");return total;
 }
 explicit Probe(std::size_t cap):maximum(cap){events.reserve(cap);allocations.reserve(cap);reservations.reserve(cap);}
 void arm(JobKind k,Phase p,Edge e,bool throws=false){std::lock_guard lock(mutex);require(!armed,"one actual test barrier");gate_kind=k;gate_phase=p;gate_edge=e;armed=true;arrived=false;released=false;throw_after_release=throws;allocation_gate.reset();}
 void arm_allocation(AllocationCategory c){std::lock_guard lock(mutex);require(!allocation_armed,"one allocation barrier");allocation_armed=true;allocation_arrived=false;allocation_released=false;allocation_gate=c;}
 void wait_allocation(){std::unique_lock lock(mutex);require(cv.wait_for(lock,std::chrono::seconds(30),[&]{return allocation_arrived||overflow;}),"actual allocation notification arrived");require(allocation_arrived&&!overflow,"valid allocation arrival");}
 void release_allocation(){std::lock_guard lock(mutex);allocation_released=true;cv.notify_all();}
 void wait(){std::unique_lock lock(mutex);require(cv.wait_for(lock,std::chrono::seconds(30),[&]{return arrived||overflow;}),"actual notification arrived before test deadline");require(arrived&&!overflow,"actual valid barrier arrival");}
 void release(){std::lock_guard lock(mutex);released=true;cv.notify_all();}
 void hold(std::unique_lock<std::mutex>&lock){arrived=true;cv.notify_all();bool ok=cv.wait_for(lock,std::chrono::seconds(30),[&]{return released;});armed=false;if(!ok)throw std::runtime_error("test barrier expired");if(throw_after_release){throw_after_release=false;throw std::runtime_error("selected actual observer throw");}}
 void observe(const NativeObservation&o)override {
  std::unique_lock lock(mutex);if(actual_events.fetch_add(1)>=maximum||events.size()>=maximum){overflow=true;throw std::runtime_error("test observation capacity");}events.push_back(o);cv.notify_all();
  if(throw_publish_request&&o.request_ordinal==throw_publish_request&&o.phase==Phase::publish_ack&&o.edge==Edge::before){throw_publish_request=0;throw std::runtime_error("selected actual publish observer throw");}
  if(armed&&o.kind==gate_kind&&o.phase==gate_phase&&o.edge==gate_edge)hold(lock);
 }
 bool allow_allocation(const AllocationObservation&o)override {
  std::unique_lock lock(mutex);if(actual_events.fetch_add(1)>=maximum||allocations.size()>=maximum){overflow=true;return false;}allocations.push_back(o);cv.notify_all();
  if(allocation_armed&&allocation_gate&&o.category==*allocation_gate){allocation_arrived=true;cv.notify_all();bool ok=cv.wait_for(lock,std::chrono::seconds(30),[&]{return allocation_released;});allocation_armed=false;if(!ok)throw std::runtime_error("allocation test barrier expired");}
  if(denied&&o.category==denied->category&&o.service_ordinal==denied->service&&o.request_ordinal==denied->request&&o.ordinal==denied->ordinal){denied.reset();++denied_count;return false;}
  if(refuse_next){refuse_next=false;return false;}return true;
 }
 void observe_reservation(const ReservationObservation&o)override {std::lock_guard lock(mutex);++claims;if(actual_events.fetch_add(1)>=maximum||reservations.size()>=maximum){overflow=true;throw std::runtime_error("reservation event capacity");}reservations.push_back(o);if(throw_claim){throw_claim=false;throw std::runtime_error("selected create claim throw");}}
 bool saw(JobKind kind,Phase phase,Edge edge){std::lock_guard lock(mutex);return std::any_of(events.begin(),events.end(),[&](auto&e){return e.kind==kind&&e.phase==phase&&e.edge==edge;});}
 bool await_event(JobKind kind,Phase phase,Edge edge){std::unique_lock lock(mutex);return cv.wait_for(lock,std::chrono::seconds(15),[&]{return std::any_of(events.begin(),events.end(),[&](auto&e){return e.kind==kind&&e.phase==phase&&e.edge==edge&&e.scope==Scope::original&&e.verified_rows>=1;});});}
 ~Probe(){release_allocation();release();}
};
[[maybe_unused]] Status status(Service* s){Status out;require(s->status(out),"owner actual status");require(out.pending+out.undelivered<=16,"native queue invariant");return out;}
[[maybe_unused]] bool same_status(const Status&a,const Status&b){return a.state==b.state&&a.error==b.error&&a.pending==b.pending&&a.undelivered==b.undelivered&&a.writer_alive==b.writer_alive&&a.has_root==b.has_root&&a.has_store_version==b.has_store_version&&a.resolved_root.view()==b.resolved_root.view();}
struct Fixture {
 Capability cap;Service* service{};bool joined{};
 Fixture(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,Probe&probe,std::uint64_t ordinal):cap(TestRootFactory::admit_bytes(descriptor,digest,trust,&probe,ordinal)){
  require(cap.valid(),"isolated real capability admitted");auto token=cap.take_access();require(token&&token->isolated_test(),"sealed isolated token");service=Service::create(std::move(*token));require(service!=nullptr,"actual arena create");
 }
 Fixture(Capability&& admitted,Service* created):cap(std::move(admitted)),service(created){require(service!=nullptr,"owned explicit-retry Service");}
 void close(){if(!service||joined)return;require(service->begin_shutdown(),"owner actual shutdown");auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(30);while(!service->try_join()){if(std::chrono::steady_clock::now()>=deadline)std::terminate();std::this_thread::yield();}joined=true;require(status(service).state==ServiceState::closed,"real joined/quiescent closed");}
 ~Fixture(){if(service){if(!joined){if(!service->begin_shutdown())std::terminate();auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(30);while(!service->try_join()){if(std::chrono::steady_clock::now()>=deadline)std::terminate();std::this_thread::yield();}}if(!Service::destroy(service))std::terminate();service=nullptr;}cap.release_leases_after_join();}
};
[[maybe_unused]] std::vector<std::string> receive(Service*s,std::size_t wanted){
 std::vector<std::string> out;auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(30);
 while(out.size()<wanted){std::array<DeliveryView,16>views{};std::uint8_t count{};require(s->peek(16,views,count),"owner batch peek");
  if(count){std::array<std::uint64_t,16>leases{};for(std::uint8_t i=0;i<count;++i){out.emplace_back(views[i].bytes);leases[i]=views[i].lease;}require(s->acknowledge(std::span(leases).first(count)),"whole batch acknowledged");}
  else{require(std::chrono::steady_clock::now()<deadline,"real terminal deadline");std::this_thread::yield();}
 }require(out.size()==wanted,"exact terminal count");return out;
}
[[maybe_unused]] void terminal_value(Raw&r,JobKind kind,std::string_view state){
 auto v=member(r.d,r.d.root,"value");bool failed=state=="failed"||state=="uncertain";
 auto integer=[&](std::uint32_t n,std::uint64_t max){return natural(r.d,n,max);};
 auto boolean=[&](std::uint32_t n){auto*c=r.d.at(n);require(c&&c->kind==ValueKind::boolean&&c->scalar<=1,"actual BOOL branch");};
 auto ids=[&](std::uint32_t n){for(auto x:array(r.d,n))require(lower_hex(text(r.d,x),32),"closed ID Array leaves");};
 if(failed&&kind!=JobKind::export_player&&kind!=JobKind::delete_recovery){require(nil(r.d,v),"failed ordinary actual null");return;}
 if(kind==JobKind::start){require(closed(r.d,v,{"store_version","interrupted_rows","created"})==Error::none&&integer(member(r.d,v,"store_version"),1)==1,"complete start record");integer(member(r.d,v,"interrupted_rows"),1);boolean(member(r.d,v,"created"));}
 else if(kind==JobKind::start_management){require(closed(r.d,v,{"management_only"})==Error::none,"management record");boolean(member(r.d,v,"management_only"));require(r.d.at(member(r.d,v,"management_only"))->scalar==1,"management true");}
 else if(kind==JobKind::list_players){require(closed(r.d,v,{"players"})==Error::none,"list players value");auto rows=array(r.d,member(r.d,v,"players"));require(rows.size()<=8,"player count ceiling");for(auto n:rows){require(closed(r.d,n,{"id","name","revision"})==Error::none&&lower_hex(field(r.d,n,"id"),32)&&valid_player_name(field(r.d,n,"name")),"full player summary");U64 rev;require(U64::parse(field(r.d,n,"revision"),rev,true),"summary revision");}}
 else if(kind==JobKind::create_player||kind==JobKind::load_player||kind==JobKind::rename_player||kind==JobKind::save_preferences){require(closed(r.d,v,{"player","preferences"})==Error::none,"paired value closed");auto p=member(r.d,v,"player"),a=member(r.d,v,"preferences");require(validate_player(r.d,p)==Error::none&&validate_preferences(r.d,a,true,r.cells)==Error::none,"full typed pair");require(field(r.d,p,"id")==field(r.d,a,"player_id")&&field(r.d,p,"revision")==field(r.d,a,"revision"),"actual cross-pair equality");}
 else if(kind==JobKind::begin_practice||kind==JobKind::observe_practice||kind==JobKind::end_practice||kind==JobKind::link_archive||kind==JobKind::load_practice){require(closed(r.d,v,{"practice"})==Error::none&&validate_practice(r.d,member(r.d,v,"practice"))==Error::none,"full closed actual Practice");}
 else if(kind==JobKind::list_practice){require(closed(r.d,v,{"practice","next_before_creation_sequence"})==Error::none,"closed practice page");auto rows=array(r.d,member(r.d,v,"practice"));require(rows.size()<=50,"page ceiling");for(auto n:rows)require(validate_practice(r.d,n,true)==Error::none,"full closed actual summary");auto cursor=member(r.d,v,"next_before_creation_sequence");if(!nil(r.d,cursor)){U64 u;require(U64::parse(text(r.d,cursor),u),"canonical exact cursor");}}
 else if(kind==JobKind::prune_practice){require(closed(r.d,v,{"deleted_ids"})==Error::none,"prune value");ids(member(r.d,v,"deleted_ids"));}
 else if(kind==JobKind::delete_player){require(closed(r.d,v,{"deleted_player_id"})==Error::none&&lower_hex(field(r.d,v,"deleted_player_id"),32),"deleted selected ID");}
 else if(kind==JobKind::delete_recovery){if(failed&&nil(r.d,v))return;require(closed(r.d,v,{"deleted_ids","retained_ids"})==Error::none,"deletion actual closed partition");ids(member(r.d,v,"deleted_ids"));ids(member(r.d,v,"retained_ids"));}
 else if(kind==JobKind::list_recovery){require(closed(r.d,v,{"snapshots"})==Error::none,"closed recovery list");auto rows=array(r.d,member(r.d,v,"snapshots"));require(rows.size()<=2,"recovery count ceiling");for(auto n:rows){require(closed(r.d,n,{"id","state","created_utc","bytes","manifest_sha256"})==Error::none&&lower_hex(field(r.d,n,"id"),32)&&valid_utc(field(r.d,n,"created_utc")),"closed retained summary");auto s=field(r.d,n,"state");require(s=="complete"||s=="partial","retained state enum");integer(member(r.d,n,"bytes"),337U*1024U*1024U);auto h=member(r.d,n,"manifest_sha256");require(nil(r.d,h)||lower_hex(text(r.d,h),64),"retained optional actual manifest hash");}}
 else if(kind==JobKind::export_player){require(closed(r.d,v,{"operation_id","outcome","phase","target_absolute_path","temporary_absolute_path","installed","bytes","sha256","player_id","preferences_revision","practice_count"})==Error::none,"export failure/success always full observed receipt");require(field(r.d,v,"operation_id")==field(r.d,r.d.root,"request_id")&&valid_local_absolute_path(field(r.d,v,"target_absolute_path")),"export operation/target");auto installed=member(r.d,v,"installed");if(!nil(r.d,installed))boolean(installed);}
 else require(false,"uncovered terminal kind");
}
// Never print an unrecognized terminal String: diagnostics contain only closed
// protocol enums, fixed source basename/line and scalar test counters.
std::string_view diagnostic_state(std::string_view value){for(auto name:{"read","committed","no_change","failed","uncertain","recovery_required"})if(value==name)return value;return "<invalid-state>";}
std::string_view diagnostic_error(std::string_view value){for(unsigned i=0;i<=static_cast<unsigned>(Error::file_recovery_required);++i)if(value==error_name(static_cast<Error>(i)))return value;return "<invalid-error>";}
[[maybe_unused]] void result(std::string_view raw,std::string_view id,JobKind kind,std::string_view state,std::string_view error="",std::string_view sequence={},std::source_location site=std::source_location::current()){
 Raw r{std::string(raw)};require(closed(r.d,r.d.root,{"request_id","kind","state","error_code","commit_sequence","value"})==Error::none,"closed actual terminal including value");
 require(field(r.d,r.d.root,"request_id")==id&&field(r.d,r.d.root,"kind")==kind_name(kind),"exact accepted ID/kind FIFO");
 const auto actual_state=field(r.d,r.d.root,"state"),actual_error=field(r.d,r.d.root,"error_code");
 const bool matches=actual_state==state&&actual_error==error;
 if(!matches){
  const auto label=std::string("exact actual state/error at service.cpp:")+std::to_string(site.line())+" kind="+std::string(kind_name(kind))+" expected_state="+std::string(diagnostic_state(state))+" actual_state="+std::string(diagnostic_state(actual_state))+" expected_error="+std::string(diagnostic_error(error))+" actual_error="+std::string(diagnostic_error(actual_error))+" checks="+std::to_string(checks.load()+1);
  require(false,label);
 }else require(true,"exact actual state/error");auto seq=member(r.d,r.d.root,"commit_sequence");
 require(sequence.empty()?nil(r.d,seq):text(r.d,seq)==sequence,"exact commit sequence branch/value");
 terminal_value(r,kind,state);
}
[[maybe_unused]] std::string job(Service*s,JobKind kind,V payload,std::string_view state,std::string_view error="",std::string_view sequence={},std::source_location site=std::source_location::current()){
 Capture input(kind,std::move(payload));auto a=s->submit(input);require(a.accepted&&a.error==Error::none,"actual accepted request");auto rows=receive(s,1);result(rows[0],a.request_id.view(),kind,state,error,sequence,site);return rows[0];
}
[[maybe_unused]] void start(Fixture&f,bool management=false,bool fresh=false,std::source_location site=std::source_location::current()){auto a=f.service->start(management);require(a.accepted,"actual worker start accepted");auto rows=receive(f.service,1);result(rows[0],a.request_id.view(),management?JobKind::start_management:JobKind::start,fresh?"committed":"read","",fresh?"1":"",site);Raw r(rows[0]);auto value=member(r.d,r.d.root,"value");if(management)require(closed(r.d,value,{"management_only"})==Error::none,"closed management result");else require(closed(r.d,value,{"store_version","interrupted_rows","created"})==Error::none,"closed start result");}

// AUTHENTICATED CONTEXT HELPERS INSERTED BY source-only prepare.py from the
// independently pinned lock-actor proposal. No production root fallback.
constexpr std::size_t input_cap=65536,frame_cap=4096;
// Single-thread actor-only fixed parsing storage. No hidden variable allocation.
struct ParsingStorage {std::array<JsonCell,64> cells{};std::array<std::byte,524288> duplicate{};};
ParsingStorage parsing;
struct Handle {
 HANDLE value{INVALID_HANDLE_VALUE};
 Handle()=default;explicit Handle(HANDLE h):value(h){}
 Handle(const Handle&)=delete;Handle& operator=(const Handle&)=delete;
 ~Handle(){if(!close())std::terminate();}
 bool good()const noexcept{return value&&value!=INVALID_HANDLE_VALUE;}
 bool close()noexcept{if(!good())return true;if(!CloseHandle(value))return false;value=INVALID_HANDLE_VALUE;return true;}
};
struct Wide {
 std::array<wchar_t,4097> value{};int size{};
 bool set(std::string_view s)noexcept{
  if(!valid_local_absolute_path(s)||s.size()>4096||s.find('/')!=s.npos)return false;
  size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s.data(),static_cast<int>(s.size()),value.data(),4096);
  if(size<3)return false;value[size]=0;return true;
 }
};
// This temporary operand is used only by CreateFileW. Canonical DOS paths,
// DTOs, expected paths, final-name checks and all other API operands are unchanged.
// Wide::set already admitted a bounded absolute drive path with backslashes.
struct ExtendedFileOperand {
 std::array<wchar_t,4101> value{};
 explicit ExtendedFileOperand(const Wide&w)noexcept {
  value[0]=L'\\';value[1]=L'\\';value[2]=L'?';value[3]=L'\\';
  std::copy_n(w.value.data(),static_cast<std::size_t>(w.size)+1,value.data()+4);
 }
};
[[maybe_unused]] bool utf8(std::wstring_view in,FixedText<4096>& out)noexcept{
 if(in.empty()||in.size()>32767)return false;
 int n=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,in.data(),static_cast<int>(in.size()),out.data.data(),4096,nullptr,nullptr);
 if(n<1)return false;out.size=static_cast<std::uint32_t>(n);out.data[n]=0;return true;
}
[[maybe_unused]] bool same_identity(const FileIdentity&a,const FileIdentity&b)noexcept{
 return a.valid&&b.valid&&a.volume_serial==b.volume_serial&&a.file_id==b.file_id;
}
[[maybe_unused]] bool observe_identity(HANDLE h,bool directory,FileIdentity& out)noexcept{
 FILE_ID_INFO id{};FILE_STANDARD_INFO standard{};FILE_ATTRIBUTE_TAG_INFO tag{};
 if(!GetFileInformationByHandleEx(h,FileIdInfo,&id,sizeof(id))||
    !GetFileInformationByHandleEx(h,FileStandardInfo,&standard,sizeof(standard))||
    !GetFileInformationByHandleEx(h,FileAttributeTagInfo,&tag,sizeof(tag))||
    bool(standard.Directory)!=directory||(tag.FileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)||
    (!directory&&standard.NumberOfLinks!=1))return false;
 out={};out.valid=true;out.volume_serial=id.VolumeSerialNumber;out.links=standard.NumberOfLinks;
 std::memcpy(out.file_id.data(),id.FileId.Identifier,16);return true;
}
[[maybe_unused]] bool final_equal(HANDLE h,const Wide&w)noexcept{
 std::array<wchar_t,4097> final{};
 auto n=GetFinalPathNameByHandleW(h,final.data(),static_cast<DWORD>(final.size()),FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
 return n>4&&n<final.size()&&std::wstring_view(final.data(),4)==L"\\\\?\\"&&
  CompareStringOrdinal(final.data()+4,static_cast<int>(n-4),w.value.data(),w.size,TRUE)==CSTR_EQUAL;
}
[[maybe_unused]] bool at_or_within(std::string_view path,std::string_view root)noexcept{
 if(path.size()<root.size()||(path.size()>root.size()&&path[root.size()]!='\\'))return false;
 Wide a,b;if(!a.set(path.substr(0,root.size()))||!b.set(root))return false;
 return CompareStringOrdinal(a.value.data(),a.size,b.value.data(),b.size,TRUE)==CSTR_EQUAL;
}
[[maybe_unused]] bool ordinary_ancestors(const Wide&w)noexcept{
 Wide part=w;
 for(int i=3;i<w.size;++i){if(w.value[i]!='\\')continue;
  part.value[i]=0;part.size=i;
  Handle h(CreateFileW(ExtendedFileOperand(part).value.data(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,
                      OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
  FileIdentity id;bool ok=h.good()&&observe_identity(h.value,true,id)&&final_equal(h.value,part);
  bool closed=h.close();part.value[i]=w.value[i];if(!ok||!closed)return false;
 }
 wchar_t fs[32]{};wchar_t volume[4097]{};
 return GetVolumePathNameW(w.value.data(),volume,4097)&&GetDriveTypeW(volume)==DRIVE_FIXED&&
  GetVolumeInformationW(volume,nullptr,0,nullptr,nullptr,nullptr,fs,32)&&
  CompareStringOrdinal(fs,-1,L"NTFS",-1,TRUE)==CSTR_EQUAL;
}
[[maybe_unused]] bool open_ordinary(std::string_view path,Handle& h,DWORD access=GENERIC_READ,DWORD share=FILE_SHARE_READ)noexcept{
 Wide w;if(!w.set(path)||!ordinary_ancestors(w))return false;
 h.value=CreateFileW(ExtendedFileOperand(w).value.data(),access,share,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
 FileIdentity id;return h.good()&&observe_identity(h.value,false,id)&&final_equal(h.value,w);
}
struct InputFile {Handle handle;std::array<char,input_cap> bytes{};std::size_t size{};};
// Keep the three bounded inputs off the Windows thread stack. These handles
// are explicitly checked/retired before positive CLOSED, not by static teardown.
struct InputStorage {InputFile context,plan,descriptor;};
InputStorage inputs;
[[maybe_unused]] bool load_input(std::string_view path,std::string_view expected,InputFile& out)noexcept{
 if(!lower_hex(expected,64)||!open_ordinary(path,out.handle))return false;
 LARGE_INTEGER length{};
 if(!GetFileSizeEx(out.handle.value,&length)||length.QuadPart<1||length.QuadPart>input_cap)return false;
 out.size=static_cast<std::size_t>(length.QuadPart);std::size_t done=0;
 while(done<out.size){DWORD n{};if(!ReadFile(out.handle.value,out.bytes.data()+done,
  static_cast<DWORD>(out.size-done),&n,nullptr)||!n||n>out.size-done)return false;done+=n;}
 char extra;DWORD n{};if(!ReadFile(out.handle.value,&extra,1,&n,nullptr)||n)return false;
 auto hash=sha256_hex({out.bytes.data(),out.size});return std::string_view(hash.data(),hash.size())==expected;
}
[[maybe_unused]] bool module_hash(std::string_view expected)noexcept{
 std::array<wchar_t,32768> path{};auto n=GetModuleFileNameW(nullptr,path.data(),static_cast<DWORD>(path.size()));
 FixedText<4096> text;if(!n||n>=path.size()||!utf8({path.data(),n},text))return false;
 Handle h;if(!open_ordinary(text.view(),h))return false;
 LARGE_INTEGER length{};if(!GetFileSizeEx(h.value,&length)||length.QuadPart<1||length.QuadPart>256*1024*1024)return false;
 Sha256 hash;std::array<std::byte,65536> chunk{};
 std::uint64_t total=0;
 for(;;){DWORD used{};if(!ReadFile(h.value,chunk.data(),static_cast<DWORD>(chunk.size()),&used,nullptr))return false;
  if(!used)break;total+=used;if(total>static_cast<std::uint64_t>(length.QuadPart))return false;
  hash.update(std::span<const std::byte>(chunk).first(used));}
 auto raw=hash.finish();constexpr char digits[]="0123456789abcdef";std::array<char,64> hex{};
 for(std::size_t i=0;i<32;++i){auto b=std::to_integer<unsigned>(raw[i]);hex[2*i]=digits[b>>4];hex[2*i+1]=digits[b&15];}
 bool closed=h.close();return closed&&total==static_cast<std::uint64_t>(length.QuadPart)&&std::string_view(hex.data(),hex.size())==expected;
}
[[maybe_unused]] ParseResult parse(std::string_view bytes)noexcept{
 return parse_json(bytes,parsing.cells,parsing.duplicate,Limits{input_cap,64,2,4096,4096});
}
[[maybe_unused]] bool positive_int(DocumentView d,std::uint32_t n,std::uint64_t max,std::uint64_t& out)noexcept{
 auto c=d.at(n);if(!c||c->kind!=ValueKind::integer||!c->scalar||c->scalar>max)return false;out=c->scalar;return true;
}
[[maybe_unused]] bool decimal(DocumentView d,std::uint32_t n,std::uint64_t& out,bool positive=false)noexcept{
 FixedText<20> text;U64 parsed;if(!text.from(d,n)||!U64::parse(text.view(),parsed,positive))return false;
 out=0;for(char c:text.view())out=out*10+static_cast<unsigned>(c-'0');return true;
}
[[maybe_unused]] bool decimal_text(Writer&w,std::uint64_t value)noexcept{
 std::array<char,20> b{};auto result=std::to_chars(b.data(),b.data()+b.size(),value);
 return result.ec==std::errc{}&&w.string({b.data(),static_cast<std::size_t>(result.ptr-b.data())});
}
[[maybe_unused]] bool decode_id(std::string_view s,FileIdentity& id)noexcept{
 if(!lower_hex(s,32))return false;
 auto digit=[](char c){return static_cast<unsigned>(c<='9'?c-'0':c-'a'+10);};
 for(std::size_t i=0;i<16;++i)id.file_id[i]=static_cast<std::byte>((digit(s[2*i])<<4)|digit(s[2*i+1]));return true;
}
[[maybe_unused]] bool id_text(Writer&w,const FileIdentity&id)noexcept{
 constexpr char digits[]="0123456789abcdef";std::array<char,32> out{};
 for(std::size_t i=0;i<16;++i){auto b=std::to_integer<unsigned>(id.file_id[i]);out[2*i]=digits[b>>4];out[2*i+1]=digits[b&15];}
 return w.string({out.data(),out.size()});
}
struct Context {
 FixedText<4096> source,parent;FixedText<64> actor_sha,capability_sha,plan_sha;
 DWORD parent_pid{};std::uint64_t creation{};
};
[[maybe_unused]] bool context_from(std::string_view bytes,Context&out,std::string_view role)noexcept{
 auto p=parse(bytes);if(!p)return false;auto d=p.value;auto n=d.root;
 if(closed(d,n,{"schema","role","source_root","proof_parent","parent_pid","parent_creation_filetime",
                "actor_sha256","capability_sha256","plan_sha256"})!=Error::none||
    !d.string_is(d.member(n,"schema"),"LocalPlayersNativeTestContext/v1")||
    !d.string_is(d.member(n,"role"),role))return false;
 std::uint64_t pid{};
 if(!out.source.from(d,d.member(n,"source_root"))||!out.parent.from(d,d.member(n,"proof_parent"))||
    !out.actor_sha.from(d,d.member(n,"actor_sha256"))||!out.capability_sha.from(d,d.member(n,"capability_sha256"))||
    !out.plan_sha.from(d,d.member(n,"plan_sha256"))||!positive_int(d,d.member(n,"parent_pid"),MAXDWORD,pid)||
    !decimal(d,d.member(n,"parent_creation_filetime"),out.creation,true))return false;
 out.parent_pid=static_cast<DWORD>(pid);
 return valid_local_absolute_path(out.source.view())&&valid_local_absolute_path(out.parent.view())&&
  lower_hex(out.actor_sha.view(),64)&&lower_hex(out.capability_sha.view(),64)&&lower_hex(out.plan_sha.view(),64);
}
[[maybe_unused]] std::uint64_t filetime(FILETIME t)noexcept{return(static_cast<std::uint64_t>(t.dwHighDateTime)<<32)|t.dwLowDateTime;}
[[maybe_unused]] bool parent_from(const Context&ctx,Handle&parent)noexcept{
 if(ctx.parent_pid==GetCurrentProcessId())return false;
 parent.value=OpenProcess(SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION,FALSE,ctx.parent_pid);
 FILETIME c{},e{},k{},u{};return parent.good()&&GetProcessTimes(parent.value,&c,&e,&k,&u)&&
  filetime(c)==ctx.creation&&WaitForSingleObject(parent.value,0)==WAIT_TIMEOUT;
}

struct Plan {FixedText<32> nonce;std::uint64_t service{};std::size_t events{};};
constexpr std::array<std::string_view,8> service_case_ids={"same_token_create_retry","foreign_owner_inert","fifo_capacity_copy","atomic_delivery_batch","worker_progress_during_owner_barrier","closed_poll_after_join","management_loss_closed_failures","source_bound_terminal_shapes"};
constexpr std::array<std::string_view,8> store_case_ids={"two_players_revisions","typed_audio_signed_zero","source_identifier_admission","exact_tick_history","creation_cursor_archive","selected_export_receipt","prune_delete_isolation","real_close_reopen_recovery"};
[[maybe_unused]] bool plan_from(std::string_view bytes,Plan&out,std::string_view suite)noexcept{
 auto p=parse(bytes);if(!p)return false;auto d=p.value;auto n=d.root;std::uint64_t events{};
 if(closed(d,n,{"schema","nonce","first_service_ordinal","maximum_actual_events","suite","cases"})!=Error::none||!d.string_is(d.member(n,"schema"),"LocalPlayersNativeTestPlan/v1")||!d.string_is(d.member(n,"suite"),suite)||!out.nonce.from(d,d.member(n,"nonce"))||!lower_hex(out.nonce.view(),32)||!positive_int(d,d.member(n,"first_service_ordinal"),INT64_MAX-8,out.service)||!positive_int(d,d.member(n,"maximum_actual_events"),16384,events)||events!=16384)return false;
 out.events=static_cast<std::size_t>(events);auto a=d.member(n,"cases");auto c=d.at(a);if(!c||c->kind!=ValueKind::array)return false;auto i=c->first;
 if(suite=="crash")return i==no_cell;auto&ids=suite=="service"?service_case_ids:store_case_ids;
 for(auto name:ids){if(i==no_cell||!d.string_is(i,name))return false;i=d.at(i)->next;}return i==no_cell;
}
[[maybe_unused]] bool descriptor_root(std::string_view bytes,const Plan&plan,FixedText<4096>&root)noexcept{
 auto p=parse(bytes);if(!p)return false;auto d=p.value;auto n=d.root;
 return closed(d,n,{"schema","root","parent","nonce","root_volume_serial","root_file_id","parent_volume_serial","parent_file_id","sentinel_sha256"})==Error::none&&d.string_is(d.member(n,"schema"),"LocalPlayersTestRootDescriptor/v1")&&d.string_is(d.member(n,"nonce"),plan.nonce.view())&&root.from(d,d.member(n,"root"));
}
[[maybe_unused]] bool actual_parent(DWORD expected)noexcept{
 Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0));if(!snapshot.good())return false;PROCESSENTRY32W entry{};entry.dwSize=sizeof(entry);bool found=false,match=false;
 if(Process32FirstW(snapshot.value,&entry)){do{if(entry.th32ProcessID==GetCurrentProcessId()){found=true;match=entry.th32ParentProcessID==expected;break;}}while(Process32NextW(snapshot.value,&entry));}
 return snapshot.close()&&found&&match;
}
struct Arguments {FixedText<4096> context,descriptor,plan;FixedText<64> context_sha,descriptor_sha,plan_sha;std::string suite;};
[[maybe_unused]] bool arguments(int argc,wchar_t**argv,Arguments&out,bool native)noexcept{
 if(argc!=(native?15:13))return false;unsigned seen=0;
 for(int i=1;i<argc;i+=2){std::wstring_view key(argv[i]);unsigned bit{};FixedText<4096> text;if(!utf8(argv[i+1],text))return false;
  if(key==L"--context"){bit=1;out.context=text;}else if(key==L"--descriptor"){bit=2;out.descriptor=text;}else if(key==L"--plan"){bit=4;out.plan=text;}
  else if(key==L"--context-sha256"){bit=8;if(!out.context_sha.assign(text.view()))return false;}else if(key==L"--descriptor-sha256"){bit=16;if(!out.descriptor_sha.assign(text.view()))return false;}else if(key==L"--plan-sha256"){bit=32;if(!out.plan_sha.assign(text.view()))return false;}
  else if(native&&key==L"--suite"){bit=64;out.suite=text.view();if(out.suite!="store"&&out.suite!="crash")return false;}else return false;
  if(seen&bit)return false;seen|=bit;
 }if(!native)out.suite="service";return seen==(native?127U:63U)&&lower_hex(out.context_sha.view(),64)&&lower_hex(out.descriptor_sha.view(),64)&&lower_hex(out.plan_sha.view(),64);
}

[[maybe_unused]] void wait_done(Service*s,std::uint8_t n){auto end=std::chrono::steady_clock::now()+std::chrono::seconds(30);while(status(s).pending){require(std::chrono::steady_clock::now()<end,"actual pending drain deadline");std::this_thread::yield();}require(status(s).undelivered==n,"exact actual undelivered count");}
[[maybe_unused]] void refused(Service*s,JobKind k,V payload,Error expected){auto before=status(s);Capture c(k,std::move(payload));auto a=s->submit(c);require(!a.accepted&&a.error==expected&&a.request_id.size==0,"exact admission rejection");require(same_status(before,status(s)),"admission leaves service counters/state/root unchanged");}
[[maybe_unused]] std::uint32_t value(Raw&r){return member(r.d,r.d.root,"value");}
[[maybe_unused]] std::uint32_t practice(Raw&r){auto p=member(r.d,value(r),"practice");require(validate_practice(r.d,p)==Error::none,"complete actual Practice semantic validation");return p;}
[[maybe_unused]] void paired(std::string_view bytes,std::string_view id,std::string_view revision,std::string_view name){Raw r{std::string(bytes)};auto v=value(r);require(closed(r.d,v,{"player","preferences"})==Error::none,"closed actual pair");auto p=member(r.d,v,"player"),prefs=member(r.d,v,"preferences");require(validate_player(r.d,p)==Error::none,"complete actual Player");require(validate_preferences(r.d,prefs,true,r.cells)==Error::none,"complete restored actual preferences");require(field(r.d,p,"id")==id&&field(r.d,p,"revision")==revision&&field(r.d,p,"name")==name&&field(r.d,prefs,"player_id")==id&&field(r.d,prefs,"revision")==revision,"paired identity/revision/content");}
[[maybe_unused]] V rename_seed(std::string id,std::string rev,std::string name){return V::o({{"player_id",V::s(std::move(id))},{"expected_revision",V::s(std::move(rev))},{"name",V::s(std::move(name))},{"utc",V::s("2026-10-03T12:03:00Z")}});}


// S08 plus category/attempt companions. Same unconsumed capability/token;
// every refusal precedes accepted start, resolver, worker, SQL and file events.
[[maybe_unused]] void reservation_category_cases(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,std::uint64_t ordinal,std::size_t cap){
 Probe p(cap);auto capability=TestRootFactory::admit_bytes(descriptor,digest,trust,&p,ordinal);require(capability.valid(),"reservation category capability");auto token=capability.take_access();require(token&&token->isolated_test(),"reservation same sealed token");
 for(auto category:{AllocationCategory::control,AllocationCategory::workspace})for(std::uint64_t attempt=1;attempt<=2;++attempt){
  p.deny_allocation(category,ordinal,0,attempt);auto effects=p.event_count();auto count=p.denied_count;
  require(Service::create(std::move(*token))==nullptr&&token->isolated_test(),"category refusal keeps original unconsumed token");p.no_effects_since(effects);require(p.denied_count==count+1&&p.reserved_bytes()==0,"one exact denied attempt creates no arena reservation");
 }
 auto* created=Service::create(std::move(*token));require(created!=nullptr,"explicit create retry after four refusals");Fixture f(std::move(capability),created);
 require(p.reserved_bytes()==2097152,"L01 permanent control/workspace charged exactly");
 // Prior categories continue to consume allocation attempts but not request IDs.
 const std::array<std::pair<AllocationCategory,std::uint64_t>,3> categories={{{AllocationCategory::request,1},{AllocationCategory::terminal,1},{AllocationCategory::delivery,1}}};
 for(const auto&entry:categories)for(std::uint64_t attempt=entry.second;attempt<entry.second+2;++attempt){
  auto before=status(f.service);auto effects=p.event_count();auto count=p.denied_count;p.deny_allocation(entry.first,ordinal,1,attempt);
  auto a=f.service->start(true);require(!a.accepted&&a.error==Error::out_of_memory&&a.request_id.size==0&&same_status(before,status(f.service)),"exact pre-start refusal preserves all public status");
  p.no_effects_since(effects);require(p.denied_count==count+1&&p.reserved_bytes()==2097152,"denied start publishes no slot or root IO");
 }
 auto a=f.service->start(true);require(a.accepted,"explicit management start retry");auto rows=receive(f.service,1);p.wait_published(1);result(rows[0],a.request_id.view(),JobKind::start_management,"read");
 require(p.reserved_bytes()==2097152,"retry terminal transfer releases all R/T/D");
 {std::lock_guard lock(p.mutex);std::array<std::uint64_t,6> last{};for(const auto&o:p.allocations){auto i=static_cast<unsigned>(o.category);require(o.service_ordinal==ordinal&&o.ordinal==last[i]+1,"every category attempt advances exactly once");last[i]=o.ordinal;}require(last[static_cast<unsigned>(AllocationCategory::control)]==5&&last[static_cast<unsigned>(AllocationCategory::workspace)]==3,"same-token control/workspace attempt history retained");require(last[static_cast<unsigned>(AllocationCategory::request)]==7&&last[static_cast<unsigned>(AllocationCategory::terminal)]==5&&last[static_cast<unsigned>(AllocationCategory::delivery)]==3,"failed starts do not reuse category ordinals");for(const auto&o:p.events)require(o.phase!=Phase::before_open&&o.phase!=Phase::before_begin,"management retry never opens SQLite");}
 f.close();
}

[[maybe_unused]] void export_reservation_refusal(Service*service,Probe&p,std::uint64_t ordinal){
 p.wait_published(17);
 const auto root=std::string(status(service).resolved_root.view());require(!root.empty(),"ready store root qualified");
 auto payload=[&]{return V::o({{"player_id",V::s(std::string(32,'9'))},{"expected_revision",V::s("1")},{"target_absolute_path",V::s(root+".reservation-export.json")}});};
 // Existing fixed schedule: start +16 FIFO jobs; earlier rejected allocation
 // does not increment accepted ordinal. The nonexistent selected ID prevents
 // target IO on the final accepted retry without fabricating file outcomes.
 for(std::uint64_t attempt=1;attempt<=2;++attempt){auto before=status(service);auto effects=p.event_count();auto count=p.denied_count;p.deny_allocation(AllocationCategory::export_spool,ordinal,18,attempt);Capture c(JobKind::export_player,payload());auto a=service->submit(c);require(!a.accepted&&a.error==Error::out_of_memory&&a.request_id.size==0&&same_status(before,status(service)),"exact export E refusal is pre-admission");p.no_effects_since(effects);require(p.denied_count==count+1&&p.reserved_bytes()==2097152,"failed E attempt rolls back all credit without a slot");}
 auto before=p.event_count();job(service,JobKind::export_player,payload(),"failed","not_found");p.wait_published(18);require(p.reserved_bytes()==2097152,"explicit accepted export retry retires E/R/T/D");
 {std::lock_guard lock(p.mutex);for(auto i=before;i<p.events.size();++i)require(p.events[i].scope!=Scope::export_file,"nonexistent selected player never touches target");}
}

[[maybe_unused]] void reserved_failure_fifo(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,std::uint64_t ordinal,std::size_t cap){
 Probe p(cap);Fixture f(trust,descriptor,digest,p,ordinal);start(f);
 // Deliberately selected test observer exceptions, not real SQLite IOERR or
 // process crash. Actual after-COMMIT is first held; ACK throw stops the worker
 // from treating later queued mutations as fresh executable work.
 p.arm(JobKind::rename_player,Phase::after_commit,Edge::after,true);Capture rename(JobKind::rename_player,rename_seed(std::string(32,'1'),"2","Alice caught"));auto first=f.service->submit(rename);require(first.accepted,"caught-failure mutation accepted with prepaid terminal");p.wait();auto request=p.last_request();p.throw_publish_for(request);
 Capture read(JobKind::list_players,V::o({}));auto second=f.service->submit(read);Capture later(JobKind::rename_player,rename_seed(std::string(32,'1'),"2","Must not run"));auto third=f.service->submit(later);require(second.accepted&&third.accepted,"two later FIFO terminals prepaid before selected exceptions");
 auto allocations=p.allocation_count();auto last_request=p.last_request();p.release();wait_done(f.service,3);p.wait_published(last_request);require(p.allocation_count()==allocations,"caught failure and all terminal publications make no new reservation attempt");
 require(p.reserved_bytes()==2097152+3*1310720,"L13 three completed slots retain full independent T/D");f.close();auto rows=receive(f.service,3);
 result(rows[0],first.request_id.view(),JobKind::rename_player,"uncertain","commit_unknown");result(rows[1],second.request_id.view(),JobKind::list_players,"failed","worker_lost");result(rows[2],third.request_id.view(),JobKind::rename_player,"failed","worker_lost");
 require(p.reserved_bytes()==2097152&&status(f.service).undelivered==0,"joined closed poll releases only prepaid terminals");
}

[[maybe_unused]] void service_cases(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,std::uint64_t ordinal,std::size_t cap){
 reservation_category_cases(trust,descriptor,digest,ordinal++,cap);
 // R1: the exact SAME unconsumed sealed token, with retained attempted ordinals.
 {Probe p(cap);auto c=TestRootFactory::admit_bytes(descriptor,digest,trust,&p,ordinal++);require(c.valid(),"R1 capability");auto token=c.take_access();require(token&&token->isolated_test(),"R1 original isolated token");p.throw_claim=true;require(Service::create(std::move(*token))==nullptr,"R1 selected reservation observer refusal");require(token->isolated_test(),"R1 failed create retains token");auto*s=Service::create(std::move(*token));require(s!=nullptr,"R1 same token retry creates");std::uint64_t control=0,workspace=0;for(auto&a:p.allocations){auto&last=a.category==AllocationCategory::control?control:workspace;require(a.ordinal>last,"R1 retained per-category attempt ordinal");last=a.ordinal;}require(control>=2,"R1 control attempts not reused");require(!s->try_join(),"never-created worker is not closed without shutdown");require(s->begin_shutdown()&&s->try_join(),"explicit no-worker quiescence");require(status(s).state==ServiceState::closed,"quiescent closed state");require(Service::destroy(s),"destroy only quiescent Service");c.release_leases_after_join();}
 const auto primary_ordinal=ordinal;Probe p(cap);Fixture f(trust,descriptor,digest,p,ordinal++);
 {auto before=status(f.service);Capture c(JobKind::list_players,V::o({}));Admission a;Status foreign;bool read=true,shutdown=true,join=true,destroy=true;std::thread t([&]{a=f.service->submit(c);read=f.service->status(foreign);shutdown=f.service->begin_shutdown();join=f.service->try_join();destroy=Service::destroy(f.service);});t.join();require(!a.accepted&&a.error==Error::wrong_thread&&!read&&!shutdown&&!join&&!destroy&&c.captures==0,"foreign owner rejects before capture/lifecycle effects");require(same_status(before,status(f.service)),"foreign calls exact owner status unchanged");}
 start(f,false,true);
 // Hold an ACTUAL worker SQL boundary, not a sleep-based guessed queue state.
 p.arm(JobKind::list_players,Phase::before_begin,Edge::before);Capture first(JobKind::list_players,V::o({}));auto a=f.service->submit(first);require(a.accepted,"queue first read accepted");p.wait();
 std::vector<std::pair<std::string,JobKind>> accepted{{std::string(a.request_id.view()),JobKind::list_players}};
 Capture copied(JobKind::create_player,player_seed(std::string(32,'1')));auto ca=f.service->submit(copied);require(ca.accepted,"copied create admitted");accepted.emplace_back(ca.request_id.view(),JobKind::create_player);copied.value.get("payload").get("name")=V::s("Caller mutation must not escape");
 for(unsigned i=0;i<14;++i){Capture c(JobKind::list_players,V::o({}));auto r=f.service->submit(c);require(r.accepted,"sixteen total pending including held job");accepted.emplace_back(r.request_id.view(),JobKind::list_players);}
 require(status(f.service).pending==16&&status(f.service).undelivered==0,"real held queue full");refused(f.service,JobKind::list_players,V::o({}),Error::queue_full);
 refused(f.service,JobKind::create_player,player_seed("not-an-id"),Error::invalid_record); // invalid field outranks queue_full
 p.release();wait_done(f.service,16);
 std::array<DeliveryView,16> views{};std::uint8_t count{};require(!f.service->peek(0,views,count)&&!f.service->peek(17,views,count),"native numeric limit guards");require(f.service->peek(2,views,count)&&count==2,"actual two-result borrowed batch");
 std::array<std::uint64_t,2> leases{views[0].lease,views[1].lease};std::array<std::string,2> owned{std::string(views[0].bytes),std::string(views[1].bytes)};auto before=status(f.service);
 {Probe other_probe(cap);Fixture other(trust,descriptor,digest,other_probe,ordinal++);auto oa=other.service->start();require(oa.accepted,"second real Service attempts actual exclusive store ownership");wait_done(other.service,1);std::array<DeliveryView,1> ov{};std::uint8_t on{};require(other.service->peek(1,ov,on)&&on==1,"real cross-Service lease");result(ov[0].bytes,oa.request_id.view(),JobKind::start,"failed","store_locked");auto foreign=leases;foreign[1]=ov[0].lease;require(!f.service->acknowledge(foreign)&&same_status(before,status(f.service)),"legitimate other-Service lease cannot consume this batch");std::array<std::uint64_t,1> ol{ov[0].lease};require(other.service->acknowledge(ol),"other owner consumes only own terminal");other.close();}
 require(!f.service->acknowledge(std::span(leases).first(1)),"partial batch rejected");auto duplicate=leases;duplicate[1]=duplicate[0];require(!f.service->acknowledge(duplicate),"duplicate batch rejected");auto wrong=leases;wrong[1]=UINT64_MAX;require(!f.service->abandon(wrong),"unknown lease rejected");bool foreign_ack=true;std::thread t([&]{foreign_ack=f.service->acknowledge(leases);});t.join();require(!foreign_ack&&same_status(before,status(f.service)),"invalid batch calls atomic/no mutation");require(!f.service->peek(1,views,count),"second peek refuses outstanding batch");require(f.service->abandon(leases),"whole batch abandoned");require(f.service->peek(2,views,count)&&count==2,"same FIFO batch reacquired");std::array<std::uint64_t,2> newleases{views[0].lease,views[1].lease};require(newleases!=leases&&views[0].bytes==owned[0]&&views[1].bytes==owned[1],"abandon preserves exact bytes with fresh leases");require(!f.service->acknowledge(leases),"stale batch cannot acknowledge new batch");require(f.service->acknowledge(newleases),"exact new whole batch acknowledged");
 result(owned[0],accepted[0].first,accepted[0].second,"read");result(owned[1],accepted[1].first,accepted[1].second,"committed","","2");paired(owned[1],std::string(32,'1'),"1","Alice");auto remainder=receive(f.service,14);for(std::size_t i=0;i<remainder.size();++i)result(remainder[i],accepted[i+2].first,accepted[i+2].second,"read");
 {auto before_oom=status(f.service);p.refuse_next=true;Capture denied(JobKind::list_players,V::o({}));auto rejected=f.service->submit(denied);require(!rejected.accepted&&rejected.error==Error::out_of_memory&&rejected.request_id.size==0&&same_status(before_oom,status(f.service)),"actual pre-effect allocator refusal preserves owner state and terminal slots");}
 export_reservation_refusal(f.service,p,primary_ordinal);
 // R5: owner allocation observer held while an already-running real SQL job
 // must advance through actual post-COMMIT row/codec verification. BEGIN alone
 // would not require the worker codec and would be a vacuous deadlock check.
 // This detects a codec
 // lease spanning owner callbacks without substituting any SQLite result.
 p.arm(JobKind::rename_player,Phase::before_begin,Edge::before);Capture rename(JobKind::rename_player,rename_seed(std::string(32,'1'),"1","Alice two"));auto ra=f.service->submit(rename);require(ra.accepted,"R5 worker rename admitted");p.wait();p.arm_allocation(AllocationCategory::request);bool progressed=false;
 std::jthread controller([&]{try{p.wait_allocation();p.release();progressed=p.await_event(JobKind::rename_player,Phase::postverify,Edge::after);}catch(...){progressed=false;}p.release_allocation();p.release();});
 Capture read(JobKind::list_players,V::o({}));auto rb=f.service->submit(read);controller.join();require(rb.accepted&&progressed,"R5 worker progresses while owner reservation barrier held");auto r5=receive(f.service,2);result(r5[0],ra.request_id.view(),JobKind::rename_player,"committed","","3");result(r5[1],rb.request_id.view(),JobKind::list_players,"read");
 // Accepted terminal storage survives actual join; closed owner poll drains it.
 Capture final(JobKind::list_players,V::o({}));auto fa=f.service->submit(final);require(fa.accepted,"pre-shutdown request accepted");f.close();require(status(f.service).undelivered==1&&!status(f.service).writer_alive,"actual worker exit with undelivered terminal retained");refused(f.service,JobKind::list_players,V::o({}),Error::invalid_state);require(!f.service->start().accepted,"closed same-instance restart refused");auto last=receive(f.service,1);result(last[0],fa.request_id.view(),JobKind::list_players,"read");require(status(f.service).undelivered==0,"closed poll drains exact retained result");
 reserved_failure_fifo(trust,descriptor,digest,ordinal++,cap);
 // R2: management never accesses SQLite. Selected observer loss drains each
 // queued recovery-only kind using its actual legal failed/null shape.
 Probe management(cap);Fixture m(trust,descriptor,digest,management,ordinal++);management.arm(JobKind::start_management,Phase::publish_ack,Edge::after,true);auto ma=m.service->start(true);require(ma.accepted,"actual management start accepted");management.wait();Capture list(JobKind::list_recovery,V::o({}));auto ml=m.service->submit(list);Capture del(JobKind::delete_recovery,V::o({{"snapshot_ids",V::a({V::s(std::string(32,'a'))})}}));auto md=m.service->submit(del);require(ml.accepted&&md.accepted,"recovery-only queued while actual management ACK held");management.release();auto drained=receive(m.service,3);result(drained[0],ma.request_id.view(),JobKind::start_management,"read");result(drained[1],ml.request_id.view(),JobKind::list_recovery,"failed","snapshot_failed");result(drained[2],md.request_id.view(),JobKind::delete_recovery,"failed","snapshot_failed");{Raw r(drained[2]);require(nil(r.d,value(r)),"no validated deletion effect means null");}m.close();
}


} // namespace
#endif

#if defined(_WIN32)
int wmain(int argc,wchar_t**argv){
 try{Arguments args;require(arguments(argc,argv,args,false),"closed argv");auto&cf=inputs.context;auto&pf=inputs.plan;auto&df=inputs.descriptor;Context ctx;Plan plan;FixedText<4096>root;
 require(load_input(args.context.view(),args.context_sha.view(),cf)&&context_from({cf.bytes.data(),cf.size},ctx,args.suite),"actual immutable context input");require(ctx.capability_sha.view()==args.descriptor_sha.view()&&ctx.plan_sha.view()==args.plan_sha.view(),"context binds both supplied raw input hashes");
 require(load_input(args.plan.view(),args.plan_sha.view(),pf)&&plan_from({pf.bytes.data(),pf.size},plan,args.suite),"closed ordered source-frozen test plan");require(load_input(args.descriptor.view(),args.descriptor_sha.view(),df)&&descriptor_root({df.bytes.data(),df.size},plan,root),"bound root descriptor and nonce");
 require(!at_or_within(args.context.view(),root.view())&&!at_or_within(args.plan.view(),root.view())&&!at_or_within(args.descriptor.view(),root.view())&&module_hash(ctx.actor_sha.view()),"inputs outside selected root and actual executable hash");Handle parent;require(actual_parent(ctx.parent_pid)&&parent_from(ctx,parent),"actual direct parent PID plus creation/liveness");
 if(args.suite=="crash"){std::cerr<<"UNAVAILABLE: actual crash actor and Root authenticated supervisor are not authored in this focused source packet\n";return 3;}
 auto trust=TestRootFactory::prepare_prerequisite(ctx.source.view(),ctx.parent.view());require(trust.valid(),"actual read-only source/proof/KnownFolder prerequisite");
 service_cases(trust,{df.bytes.data(),df.size},args.descriptor_sha.view(),plan.service,plan.events);
 require(WaitForSingleObject(parent.value,0)==WAIT_TIMEOUT,"actual supervisor still alive at final result");require(trust.retire()&&cf.handle.close()&&pf.handle.close()&&df.handle.close()&&parent.close(),"explicit prerequisite/input/parent retirement");
 std::cout<<"LocalPlayers focused "<<args.suite<<" checks="<<checks.load()<<" actual_events="<<actual_events.load()<<" PASS\n";return 0;
 }catch(const std::exception&e){std::cerr<<"LocalPlayers focused failure: "<<e.what()<<"\n";return 1;}catch(...){std::cerr<<"LocalPlayers focused unknown failure\n";return 1;}
}
#else
int main(){std::cerr<<"Windows-only real storage test; Linux codec has its separate allocated executable\n";return 2;}
#endif
