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
#include <memory>
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
#include "sqlite3.h"
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

 std::optional<std::uint64_t> gate_request,next_gate_request;std::size_t arrivals{};
 void follow_request(std::uint64_t request){std::lock_guard lock(mutex);require(armed&&arrived&&request&&!next_gate_request,"install exactly one next same-phase request barrier");next_gate_request=request;}
 void wait_arrival(std::size_t wanted){std::unique_lock lock(mutex);require(cv.wait_for(lock,std::chrono::seconds(30),[&]{return arrivals>=wanted||overflow;}),"exact source-bound export barrier arrival");require(arrivals==wanted&&!overflow,"no stale or skipped export arrival");}
 void shared_spool(std::size_t expected_claims,std::size_t shares,std::size_t unshares,std::size_t releases){std::lock_guard lock(mutex);std::array<std::size_t,4> counts{};std::uint64_t identity=0;for(const auto&o:reservations)if(o.category==AllocationCategory::export_spool){require(o.rounded==18874368,"every E observation is exact18MiB");if(!identity)identity=o.allocation_ordinal;require(identity==o.allocation_ordinal,"one actual shared spool allocation identity");++counts[static_cast<unsigned>(o.action)];}require(counts==std::array<std::size_t,4>{expected_claims,releases,shares,unshares},"exact exclusive E claim/share/unshare/release history");}
 void arm(JobKind k,Phase p,Edge e,bool throws=false){std::lock_guard lock(mutex);require(!armed,"one actual test barrier");gate_kind=k;gate_phase=p;gate_edge=e;armed=true;arrived=false;released=false;throw_after_release=throws;allocation_gate.reset();gate_request.reset();next_gate_request.reset();}
 void arm_allocation(AllocationCategory c){std::lock_guard lock(mutex);require(!allocation_armed,"one allocation barrier");allocation_armed=true;allocation_arrived=false;allocation_released=false;allocation_gate=c;}
 void wait_allocation(){std::unique_lock lock(mutex);require(cv.wait_for(lock,std::chrono::seconds(30),[&]{return allocation_arrived||overflow;}),"actual allocation notification arrived");require(allocation_arrived&&!overflow,"valid allocation arrival");}
 void release_allocation(){std::lock_guard lock(mutex);allocation_released=true;cv.notify_all();}
 void wait(){std::unique_lock lock(mutex);require(cv.wait_for(lock,std::chrono::seconds(30),[&]{return arrived||overflow;}),"actual notification arrived before test deadline");require(arrived&&!overflow,"actual valid barrier arrival");}
 void release(){std::lock_guard lock(mutex);released=true;cv.notify_all();}
 void hold(std::unique_lock<std::mutex>&lock){arrived=true;++arrivals;cv.notify_all();bool ok=cv.wait_for(lock,std::chrono::seconds(30),[&]{return released;});armed=false;if(next_gate_request){gate_request=next_gate_request;next_gate_request.reset();armed=true;arrived=false;released=false;}if(!ok)throw std::runtime_error("test barrier expired");if(throw_after_release){throw_after_release=false;throw std::runtime_error("selected actual observer throw");}}
 void observe(const NativeObservation&o)override {
  std::unique_lock lock(mutex);if(actual_events.fetch_add(1)>=maximum||events.size()>=maximum){overflow=true;throw std::runtime_error("test observation capacity");}events.push_back(o);cv.notify_all();
  if(throw_publish_request&&o.request_ordinal==throw_publish_request&&o.phase==Phase::publish_ack&&o.edge==Edge::before){throw_publish_request=0;throw std::runtime_error("selected actual publish observer throw");}
  if(armed&&o.kind==gate_kind&&o.phase==gate_phase&&o.edge==gate_edge&&(!gate_request||o.request_ordinal==*gate_request))hold(lock);
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
  const auto label=std::string("exact actual state/error at native.cpp:")+std::to_string(site.line())+" kind="+std::string(kind_name(kind))+" expected_state="+std::string(diagnostic_state(state))+" actual_state="+std::string(diagnostic_state(actual_state))+" expected_error="+std::string(diagnostic_error(error))+" actual_error="+std::string(diagnostic_error(actual_error))+" checks="+std::to_string(checks.load()+1);
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
// Validate the directory with the unchanged caller-path grammar, then append
// one closed test-owned enumeration tail. Wildcards never enter Wide::set.
struct FixedEnumerationOperand {
 std::array<wchar_t,4097> value{};
 bool set(std::string_view directory,std::wstring_view tail)noexcept{
  if(tail!=L"\\*"&&tail!=L"\\.fsplayers-*.tmp")return false;
  Wide base;if(!base.set(directory))return false;
  const auto used=static_cast<std::size_t>(base.size);
  if(used+tail.size()+1>value.size())return false;
  std::copy_n(base.value.data(),used,value.data());
  std::copy(tail.begin(),tail.end(),value.data()+used);
  value[used+tail.size()]=L'\0';return true;
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

struct Plan {FixedText<32> nonce;FixedText<64> stage;std::uint64_t service{};std::size_t events{};};
constexpr std::array<std::string_view,19> crash_case_ids={"pre_begin","before_commit","after_commit","publish_ack","wal_schema","interrupt_before_commit","interrupt_after_commit","pre_intent_read","intent_before_write","copy_after_read","copy_after_write","work_before_sqlite","two_partial_limit","export_after_write","export_after_flush","export_after_move","delete_before_row","delete_after_row","delete_after_commit"};
bool crash_stage_name(std::string_view stage);
constexpr std::array<std::string_view,8> service_case_ids={"same_token_create_retry","foreign_owner_inert","fifo_capacity_copy","atomic_delivery_batch","worker_progress_during_owner_barrier","closed_poll_after_join","management_loss_closed_failures","source_bound_terminal_shapes"};
constexpr std::array<std::string_view,8> store_case_ids={"two_players_revisions","typed_audio_signed_zero","source_identifier_admission","exact_tick_history","creation_cursor_archive","selected_export_receipt","prune_delete_isolation","real_close_reopen_recovery"};
[[maybe_unused]] bool plan_from(std::string_view bytes,Plan&out,std::string_view suite)noexcept{
 auto p=parse(bytes);if(!p)return false;auto d=p.value;auto n=d.root;std::uint64_t events{};
 if(closed(d,n,{"schema","nonce","first_service_ordinal","maximum_actual_events","suite","cases"})!=Error::none||!d.string_is(d.member(n,"schema"),"LocalPlayersNativeTestPlan/v1")||!d.string_is(d.member(n,"suite"),suite)||!out.nonce.from(d,d.member(n,"nonce"))||!lower_hex(out.nonce.view(),32)||!positive_int(d,d.member(n,"first_service_ordinal"),suite=="store"?INT64_MAX-12:INT64_MAX-8,out.service)||!positive_int(d,d.member(n,"maximum_actual_events"),16384,events)||events!=16384)return false;
 out.events=static_cast<std::size_t>(events);auto a=d.member(n,"cases");auto c=d.at(a);if(!c||c->kind!=ValueKind::array)return false;auto i=c->first;
 if(suite=="crash")return i!=no_cell&&out.stage.from(d,i)&&d.at(i)->next==no_cell&&crash_stage_name(out.stage.view());auto&ids=suite=="service"?service_case_ids:store_case_ids;
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

// Keep the complete long-path fixture on its own call frame, with one heap
// input buffer. Do not raise the native executable stack reserve.
__declspec(noinline) void long_export_cases(Service* service,const std::string&alice,const std::string&root,const std::string&target,const std::string&ex){
 auto input=std::make_unique<InputFile>();
 // Real service export beyond MAX_PATH, under the existing isolated parent.
 // A single235-character component remains within the NTFS component limit.
 const auto target_slash=target.find_last_of("\\/");require(target_slash!=target.npos,"export fixture has isolated parent");
 const std::string long_leaf=std::string(230,'l')+".json";
 const std::string long_target=target.substr(0,target_slash+1)+long_leaf;
 require(long_leaf.size()<=255&&long_target.size()>MAX_PATH&&long_target.size()<=4096&&valid_local_absolute_path(long_target),"actual canonical long export fixture crosses MAX_PATH");
 auto long_export=job(service,JobKind::export_player,V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("3")},{"target_absolute_path",V::s(long_target)}}),"read");
 std::string long_hash;std::size_t long_bytes{};
 {Raw r(long_export);auto v=value(r);long_hash=field(r.d,v,"sha256");require(field(r.d,v,"outcome")=="saved"&&field(r.d,v,"phase")=="done"&&field(r.d,v,"target_absolute_path")==long_target&&nil(r.d,member(r.d,v,"temporary_absolute_path"))&&r.d.at(member(r.d,v,"installed"))->scalar==1,"long target completed actual create/flush/verify/move/reopen");auto& file=*input;require(load_input(long_target,long_hash,file),"independent full long target SHA");long_bytes=file.size;require(natural(r.d,member(r.d,v,"bytes"),33554432)==long_bytes,"independent long target full length");require(file.handle.close(),"long target read handle retired before collision test");}
 {Raw original_export(ex);require(long_hash==field(original_export.d,value(original_export),"sha256"),"long path preserves same coherent canonical snapshot bytes");}
 auto long_exists=job(service,JobKind::export_player,V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("3")},{"target_absolute_path",V::s(long_target)}}),"failed","target_exists");
 {Raw r(long_exists);auto v=value(r);require(field(r.d,v,"outcome")=="not_saved"&&r.d.at(member(r.d,v,"installed"))->scalar==0,"long no-overwrite receipt reports no install");}
 {auto& file=*input;require(load_input(long_target,long_hash,file)&&file.size==long_bytes,"long existing target entire bytes/hash preserved");require(file.handle.close(),"long collision verification handle retired");}
 const std::string protected_long=root+"\\"+long_leaf;
 require(protected_long.size()>MAX_PATH&&valid_local_absolute_path(protected_long),"long protected canonical fixture");
 job(service,JobKind::export_player,V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("3")},{"target_absolute_path",V::s(protected_long)}}),"failed","path_rejected");
 {Wide path;require(path.set(protected_long),"independent protected long operand");HANDLE denied=CreateFileW(ExtendedFileOperand(path).value.data(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);const DWORD error=denied==INVALID_HANDLE_VALUE?GetLastError():ERROR_SUCCESS;Handle owned(denied);require(owned.close(),"unexpected protected handle retained/closed");require(denied==INVALID_HANDLE_VALUE&&error==ERROR_FILE_NOT_FOUND,"protected long target remains actually absent");}
}

void export_sharing_cases(Service*,Probe&,const std::string&,const std::string&,const std::string&,const std::string&);
void export_range_lock_cases(Service*,Probe&,const std::string&,const std::string&,const std::string&,const std::string&);
void full_record_store_cases(TrustedRoots&,std::string_view,std::string_view,std::uint64_t,std::size_t,const std::string&,const std::string&);
void u64_fixture_setup(const std::string&);
void u64_exhaustion_cases(Service*,Probe&);
void u64_fixture_final(const std::string&);
// Real query-cursor refusals: callbacks observe actual SQLite work only.
void cursor_refusal(Service*service,Probe&p,JobKind kind,V payload,std::string_view error,const std::string&owner,const std::string&existing){
 auto ready=[&]{p.wait_published(p.last_request());auto state=status(service);require(state.state==ServiceState::ready&&state.pending==0&&state.undelivered==0&&state.writer_alive&&p.reserved_bytes()==2097152,"cursor refusal ACK retires all request ownership; worker remains ready");};
 auto snapshot=[&]{std::array<std::string,2> saved;
  {Raw row(job(service,JobKind::load_player,V::o({{"player_id",V::s(owner)}}),"read"));saved[0]=canonical(row.d,value(row));}
  {Raw row(job(service,JobKind::load_practice,V::o({{"player_id",V::s(owner)},{"practice_id",V::s(existing)}}),"read"));saved[1]=canonical(row.d,value(row));}
  ready();return saved;};
 const auto before=snapshot();Capture capture(kind,std::move(payload));auto admission=service->submit(capture);require(admission.accepted,"cursor refusal admitted to actual worker transaction");const auto request=p.last_request();auto rows=receive(service,1);result(rows[0],admission.request_id.view(),kind,"failed",error);{Raw row(rows[0]);require(nil(row.d,value(row)),"known cursor refusal has null value and no commit sequence");}ready();
 {std::array<unsigned,4> counts{};std::lock_guard lock(p.mutex);
  for(const auto&o:p.events)if(o.request_ordinal==request&&o.kind==kind){
   require(o.phase!=Phase::row_write&&o.phase!=Phase::before_commit&&o.phase!=Phase::after_commit&&o.phase!=Phase::postverify,"cursor refusal has no SQL row write/COMMIT/postverify");
   if(o.scope==Scope::original&&(o.phase==Phase::before_begin||o.phase==Phase::rollback)){
    const unsigned at=(o.phase==Phase::rollback?2U:0U)+(o.edge==Edge::after?1U:0U);++counts[at];
    if(o.edge==Edge::after)require(o.has_result&&o.sqlite_result==SQLITE_DONE&&(o.phase==Phase::rollback?(o.autocommit&&o.txn_state==SQLITE_TXN_NONE):(!o.autocommit&&o.txn_state==SQLITE_TXN_WRITE)),"cursor refusal observes actual successful BEGIN/ROLLBACK and exact SQLite transaction state");
   }
  }
  require(counts==std::array<unsigned,4>{1,1,1,1},"cursor refusal performs exactly one real BEGIN and one clean rollback");
 }
 require(snapshot()==before,"cursor refusal preserves whole Player/Preferences and existing Practice bytes");
}
[[maybe_unused]] void store_cases(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,std::uint64_t ordinal,std::size_t cap,const std::string&root,const std::string&target){
 const std::string alice(32,'1'),bob(32,'2'),one(32,'3'),two(32,'4');Probe p(cap);Fixture f(trust,descriptor,digest,p,ordinal++);start(f,false,true);
 auto created=job(f.service,JobKind::create_player,player_seed(alice),"committed","","2");paired(created,alice,"1","Alice");job(f.service,JobKind::create_player,player_seed(alice),"no_change","","2");job(f.service,JobKind::create_player,player_seed(bob,"Bob"),"committed","","3");job(f.service,JobKind::create_player,player_seed(alice,"Other"),"failed","identity_conflict");
 auto unchanged=job(f.service,JobKind::rename_player,rename_seed(alice,"1","Alice"),"no_change","","2");require(unchanged.size()>0,"actual no-change pair exists");auto renamed=job(f.service,JobKind::rename_player,rename_seed(alice,"1","Alice two"),"committed","","4");paired(renamed,alice,"2","Alice two");
 auto saved=job(f.service,JobKind::save_preferences,V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("2")},{"seed",seed_audio(UINT64_C(0x8000000000000000))},{"utc",V::s("2026-10-03T12:04:00Z")}}),"committed","","5");paired(saved,alice,"3","Alice two");{Raw r(saved);auto prefs=member(r.d,value(r),"preferences"),a=member(r.d,prefs,"audio"),gain=member(r.d,a,"engine_gain");require(r.d.at(gain)->kind==ValueKind::object&&r.d.size(gain)==1&&field(r.d,gain,"$binary64_le")=="0000000000000080","actual negative-zero canonical tag exact LE bytes");}
 job(f.service,JobKind::save_preferences,V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("2")},{"seed",seed_audio(UINT64_C(0x8000000000000000))},{"utc",V::s("2026-10-03T12:04:00Z")}}),"failed","revision_conflict");job(f.service,JobKind::save_preferences,V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("3")},{"seed",seed_audio(UINT64_C(0x8000000000000000))},{"utc",V::s("2026-10-03T12:04:00Z")}}),"no_change","","5");paired(job(f.service,JobKind::load_player,V::o({{"player_id",V::s(alice)}}),"read"),alice,"3","Alice two");
 for(const auto&session:std::array<std::string,5>{"Upper","two--separators","trailing-","1leading","nonascii-\xc3\xa9"}){auto seed=begin_seed(one,alice,session);refused(f.service,JobKind::begin_practice,std::move(seed),Error::invalid_record);}auto old=begin_seed(one,alice);old.get("seed").get("source").get("named_start")=V::s("ground-rest");refused(f.service,JobKind::begin_practice,std::move(old),Error::invalid_record);
 auto began=job(f.service,JobKind::begin_practice,begin_seed(one,alice),"committed","","6");{Raw r(began);auto n=practice(r);require(field(r.d,n,"first_tick")=="9007199254740993"&&field(r.d,n,"last_tick")=="9007199254740993"&&field(r.d,n,"observed_ticks")=="0"&&field(r.d,n,"creation_sequence")=="6","exact beyond-binary64 tick seed and immutable creation");}
 cursor_refusal(f.service,p,JobKind::delete_player,V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("3")}}),"active_practice",alice,one);
 job(f.service,JobKind::observe_practice,observe_seed(one,alice,"1","9007199254741000","foreign-session"),"failed","source_mismatch");auto observed=job(f.service,JobKind::observe_practice,observe_seed(one,alice,"1"),"committed","","7");{Raw r(observed);auto n=practice(r);require(field(r.d,n,"observed_ticks")=="7"&&field(r.d,n,"revision")=="2"&&field(r.d,n,"creation_sequence")=="6","exact U64 subtraction and revision");}
 auto equal=observe_seed(one,alice,"2");equal.get("utc")=V::s("2026-10-03T11:00:00Z");auto eq=job(f.service,JobKind::observe_practice,std::move(equal),"no_change","","7");{Raw r(eq);require(field(r.d,practice(r),"last_observed_utc")=="2026-10-03T12:02:00Z","equal tick preserves real observation UTC");}job(f.service,JobKind::observe_practice,observe_seed(one,alice,"1"),"failed","revision_conflict");
 auto ended=job(f.service,JobKind::end_practice,end_seed(one,alice,"2"),"committed","","8");{Raw r(ended);auto n=practice(r);require(field(r.d,n,"status")=="manually_ended"&&field(r.d,n,"end_reason")=="user_end"&&field(r.d,n,"revision")=="3","explicit manually ended history");}job(f.service,JobKind::end_practice,end_seed(one,alice,"3"),"no_change","","8");job(f.service,JobKind::observe_practice,observe_seed(one,alice,"3"),"failed","invalid_transition");auto dup=job(f.service,JobKind::begin_practice,begin_seed(one,alice),"no_change","","8");{Raw r(dup);require(field(r.d,practice(r),"status")=="manually_ended","duplicate seed returns progressed terminal without resetting");}
 cursor_refusal(f.service,p,JobKind::begin_practice,begin_seed(std::string(32,'d'),alice),"identity_conflict",alice,one);
 // Synthetic association is a repository DTO test, not a real Save/recording
 // authority witness. The nonexistent link must remain unopened on queries.
 V archive=V::o({{"type",V::s("ExternalRecordedReview")},{"version",V::i(1)},{"absolute_path",V::s(root+"\\missing-review.json")},{"payload_sha256",V::s(std::string(64,'3'))},{"recording_session_id",V::s("synthetic-service-reference-1")},{"first_tick",V::s("9007199254740993")},{"last_tick",V::s("9007199254741000")},{"linked_utc",V::s("2026-10-03T12:05:00Z")}});
 job(f.service,JobKind::link_archive,V::o({{"practice_id",V::s(one)},{"player_id",V::s(alice)},{"expected_revision",V::s("3")},{"expected_source",source()},{"archive",archive}}),"committed","","9");
 job(f.service,JobKind::begin_practice,begin_seed(two,alice,"synthetic-service-reference-2","0"),"committed","","10");job(f.service,JobKind::end_practice,end_seed(two,alice,"1","5","synthetic-service-reference-2"),"committed","","11");
 auto page=job(f.service,JobKind::list_practice,V::o({{"player_id",V::s(alice)},{"before_creation_sequence",V::null()},{"limit",V::i(1)}}),"read");{Raw r(page);auto v=value(r);auto rows=array(r.d,member(r.d,v,"practice"));require(rows.size()==1&&field(r.d,rows[0],"id")==two&&field(r.d,v,"next_before_creation_sequence")=="10","numeric immutable creation cursor newest row");}
 auto earlier=job(f.service,JobKind::list_practice,V::o({{"player_id",V::s(alice)},{"before_creation_sequence",V::s("10")},{"limit",V::i(1)}}),"read");{Raw r(earlier);auto v=value(r);auto rows=array(r.d,member(r.d,v,"practice"));require(rows.size()==1&&field(r.d,rows[0],"id")==one&&field(r.d,rows[0],"creation_sequence")=="6"&&field(r.d,rows[0],"commit_sequence")=="9"&&nil(r.d,member(r.d,v,"next_before_creation_sequence")),"updated old row remains in its creation page");auto link=member(r.d,rows[0],"archive");require(closed(r.d,link,{"linked"})==Error::none&&r.d.at(member(r.d,link,"linked"))->scalar==1,"summary excludes external path");}

 auto zero_cursor=job(f.service,JobKind::list_practice,V::o({{"player_id",V::s(alice)},{"before_creation_sequence",V::s("0")},{"limit",V::i(1)}}),"read");{Raw r(zero_cursor);auto v=value(r);require(array(r.d,member(r.d,v,"practice")).empty()&&nil(r.d,member(r.d,v,"next_before_creation_sequence")),"canonical zero cursor is admitted and reads an empty page with null continuation");}

 // Actual new selected file is a sibling under Root's isolated proof parent,
 // outside the protected run root. No overwrite or product-path fallback.
 auto ex=job(f.service,JobKind::export_player,V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("3")},{"target_absolute_path",V::s(target)}}),"read");
 {Raw r(ex);auto v=value(r);require(closed(r.d,v,{"operation_id","outcome","phase","target_absolute_path","temporary_absolute_path","installed","bytes","sha256","player_id","preferences_revision","practice_count"})==Error::none,"closed real export receipt");require(field(r.d,v,"operation_id")==field(r.d,r.d.root,"request_id")&&field(r.d,v,"outcome")=="saved"&&field(r.d,v,"phase")=="done"&&field(r.d,v,"target_absolute_path")==target&&nil(r.d,member(r.d,v,"temporary_absolute_path"))&&r.d.at(member(r.d,v,"installed"))->kind==ValueKind::boolean&&r.d.at(member(r.d,v,"installed"))->scalar==1,"actual export install/verification state");require(field(r.d,v,"player_id")==alice&&field(r.d,v,"preferences_revision")=="3"&&natural(r.d,member(r.d,v,"practice_count"),2000)==2,"selected coherent export snapshot metadata");InputFile file;require(load_input(target,field(r.d,v,"sha256"),file),"actual target bytes match observed receipt SHA");require(natural(r.d,member(r.d,v,"bytes"),33554432)==file.size,"actual target length matches receipt");Raw envelope(std::string(file.bytes.data(),file.size));require(closed(envelope.d,envelope.d.root,{"format","version","payload_json","payload_sha256"})==Error::none&&field(envelope.d,envelope.d.root,"format")=="LocalPlayerSummary"&&natural(envelope.d,member(envelope.d,envelope.d.root,"version"),1)==1,"public closed export envelope");auto payload=field(envelope.d,envelope.d.root,"payload_json");require(digest_text(payload)==field(envelope.d,envelope.d.root,"payload_sha256"),"actual payload hash");Raw expanded(payload);require(closed(expanded.d,expanded.d.root,{"player","preferences","practice"})==Error::none&&field(expanded.d,member(expanded.d,expanded.d.root,"player"),"id")==alice,"export contains only selected player");auto rows=array(expanded.d,member(expanded.d,expanded.d.root,"practice"));require(rows.size()==2&&field(expanded.d,rows[0],"id")==two&&field(expanded.d,rows[1],"id")==one,"ALL selected history in numeric creation DESC order");require(payload.find("missing-review.json")==payload.npos&&payload.find("absolute_path")==payload.npos,"public summary excludes archive paths");
  // Bob's synthetic32-hex ID deliberately collides with the64-hex world hash.
  // Privacy checks ownership fields, not substrings of admitted provenance.
  require(field(expanded.d,member(expanded.d,expanded.d.root,"preferences"),"player_id")==alice,"export preferences belong only to selected player");
  for(auto row:rows){
   require(closed(expanded.d,row,{"archive","commit_sequence","creation_sequence","end_reason","first_tick","id","last_observed_utc","last_tick","observed_ticks","player_id","revision","source","started_utc","status","tick_rate_hz","type","version"})==Error::none&&field(expanded.d,row,"player_id")==alice,"closed exported practice belongs only to selected player");
   auto link=member(expanded.d,row,"archive");
   require(closed(expanded.d,link,{"linked"})==Error::none&&expanded.d.at(member(expanded.d,link,"linked"))->kind==ValueKind::boolean,"public archive summary contains only linked BOOL");
   require(field(expanded.d,member(expanded.d,row,"source"),"prepared_world_sha256")==std::string(64,'2'),"public summary preserves exact colliding source provenance");
  }
  require(alice!=bob&&payload.find(bob)!=payload.npos,"synthetic other-player ID collision is exercised without exporting that player's records");require(file.handle.close(),"actual export read handle closed");}
 auto exists=job(f.service,JobKind::export_player,V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("3")},{"target_absolute_path",V::s(target)}}),"failed","target_exists");{Raw r(exists);auto v=value(r);require(field(r.d,v,"outcome")=="not_saved"&&r.d.at(member(r.d,v,"installed"))->scalar==0,"no-overwrite known failure stays file-specific");}

 export_sharing_cases(f.service,p,alice,root,target,ex);
 export_range_lock_cases(f.service,p,alice,root,target,ex);
 long_export_cases(f.service,alice,root,target,ex);
 job(f.service,JobKind::prune_practice,V::o({{"player_id",V::s(alice)},{"practice_ids",V::a({V::s(one),V::s(std::string(32,'f'))})}}),"failed","not_found");{Raw r(job(f.service,JobKind::load_practice,V::o({{"player_id",V::s(alice)},{"practice_id",V::s(one)}}),"read"));require(!nil(r.d,member(r.d,practice(r),"archive")),"failed prune all-or-nothing and full archive retained");}
 job(f.service,JobKind::prune_practice,V::o({{"player_id",V::s(alice)},{"practice_ids",V::a({V::s(one)})}}),"committed","","12");job(f.service,JobKind::delete_player,V::o({{"player_id",V::s(bob)},{"expected_revision",V::s("1")}}),"committed","","13");
 {Raw r(job(f.service,JobKind::list_players,V::o({}),"read"));auto rows=array(r.d,member(r.d,value(r),"players"));require(rows.size()==1&&field(r.d,rows[0],"id")==alice,"selected deletion preserves other player");}
 // Equality must distinguish the two IEEE zero signs, not just 1.0 from zero.
 job(f.service,JobKind::save_preferences,V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("3")},{"seed",seed_audio(0)},{"utc",V::s("2026-10-03T12:06:00Z")}}),"committed","","14");job(f.service,JobKind::save_preferences,V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("4")},{"seed",seed_audio(UINT64_C(0x8000000000000000))},{"utc",V::s("2026-10-03T12:07:00Z")}}),"committed","","15");
 f.close(); // prior fixture remains alive but has relinquished the actual lock
 u64_fixture_setup(root);
 Probe reopened(cap);Fixture again(trust,descriptor,digest,reopened,ordinal++);start(again);paired(job(again.service,JobKind::load_player,V::o({{"player_id",V::s(alice)}}),"read"),alice,"5","Alice two");{Raw r(job(again.service,JobKind::load_practice,V::o({{"player_id",V::s(alice)},{"practice_id",V::s(two)}}),"read"));require(field(r.d,practice(r),"status")=="manually_ended","same-process actual close/reopen preserves durable terminal");}u64_exhaustion_cases(again.service,reopened);again.close();u64_fixture_final(root);
 Probe mp(cap);Fixture management(trust,descriptor,digest,mp,ordinal++);start(management,true);auto snapshots=job(management.service,JobKind::list_recovery,V::o({}),"read");{Raw r(snapshots);auto rows=array(r.d,member(r.d,value(r),"snapshots"));require(!rows.empty()&&rows.size()<=2,"actual reopen retained recovery set visible");std::vector<V> ids;for(auto n:rows){require(closed(r.d,n,{"id","state","created_utc","bytes","manifest_sha256"})==Error::none,"actual closed recovery summary");auto bytes=natural(r.d,member(r.d,n,"bytes"),337U*1024U*1024U);require(bytes>0,"actual retained-only byte observation");ids.push_back(V::s(field(r.d,n,"id")));}auto deleted=job(management.service,JobKind::delete_recovery,V::o({{"snapshot_ids",V::a(std::move(ids))}}),"read");Raw d(deleted);auto v=value(d);require(array(d.d,member(d.d,v,"retained_ids")).empty(),"actual requested recovery sets completely deleted");}management.close();
 full_record_store_cases(trust,descriptor,digest,ordinal,cap,root,target);
}

// Original MIT. Closed crash stages; Root alone authenticates/joins the actor.
// Test-owned bounded observations are not production arena allocations.
const std::string crash_alice(32,'a'),crash_bob(32,'b'),crash_one(32,'c'),crash_two(32,'d');
std::vector<std::string> crash_observations;
std::string crash_quote(std::string_view input){
 std::string out="\"";constexpr char h[]="0123456789abcdef";
 for(unsigned char c:input){if(c=='\"'||c=='\\'){out+='\\';out+=static_cast<char>(c);}else if(c<32){out+="\\u00";out+=h[c>>4];out+=h[c&15];}else out+=static_cast<char>(c);}return out+'\"';
}
std::string crash_identity(const FileIdentity&id){
 require(id.valid&&id.links==1,"actual ordinary single-link file identity");char volume[17]{},file[33]{};constexpr char h[]="0123456789abcdef";
 for(unsigned i=0;i<16;++i){volume[15-i]=h[(id.volume_serial>>(4*i))&15];auto b=std::to_integer<unsigned>(id.file_id[i]);file[2*i]=h[b>>4];file[2*i+1]=h[b&15];}
 return "{\"file_id_hex\":"+crash_quote(file)+",\"volume_serial_hex\":"+crash_quote(volume)+"}";
}
struct CrashRootAdmission {
 Capability cap;
 CrashRootAdmission(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,std::uint64_t ordinal):cap(TestRootFactory::admit_bytes(descriptor,digest,trust,nullptr,ordinal)){require(cap.valid(),"real isolated root authority before test raw reads");}
 ~CrashRootAdmission(){if(!cap.retire_unconsumed())std::terminate();}
};
struct CrashFile {bool present{};std::uint64_t length{};FileIdentity identity{};std::string hash,bytes;};
CrashFile crash_file(const std::string&path,std::uint64_t cap,bool retain=false){
 Wide wide;require(wide.set(path),"closed crash file absolute path");SetLastError(ERROR_SUCCESS);auto attributes=GetFileAttributesW(wide.value.data());
 if(attributes==INVALID_FILE_ATTRIBUTES){require(GetLastError()==ERROR_FILE_NOT_FOUND||GetLastError()==ERROR_PATH_NOT_FOUND,"actual file absence only");return {};}
 require(!(attributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT)),"crash fixture file regular/nonreparse");Handle h;require(open_ordinary(path,h),"read-only ordinary crash file");CrashFile out;out.present=true;
 LARGE_INTEGER size{};require(observe_identity(h.value,false,out.identity)&&GetFileSizeEx(h.value,&size)&&size.QuadPart>=0&&static_cast<std::uint64_t>(size.QuadPart)<=cap,"closed file identity/size cap");out.length=static_cast<std::uint64_t>(size.QuadPart);
 Sha256 hash;std::array<std::byte,65536>chunk{};std::uint64_t total=0;if(retain)out.bytes.reserve(static_cast<std::size_t>(out.length));
 while(total<out.length){DWORD got{};auto wanted=static_cast<DWORD>(std::min<std::uint64_t>(chunk.size(),out.length-total));require(ReadFile(h.value,chunk.data(),wanted,&got,nullptr)&&got&&got<=wanted,"actual bounded crash read");hash.update(std::span<const std::byte>(chunk).first(got));if(retain)out.bytes.append(reinterpret_cast<const char*>(chunk.data()),got);total+=got;}
 DWORD extra{};std::byte byte{};require(ReadFile(h.value,&byte,1,&extra,nullptr)&&extra==0,"actual exact EOF");FileIdentity again;LARGE_INTEGER after{};require(observe_identity(h.value,false,again)&&same_identity(out.identity,again)&&GetFileSizeEx(h.value,&after)&&after.QuadPart==size.QuadPart,"read identity/length stable");auto raw=hash.finish();constexpr char hex[]="0123456789abcdef";out.hash.resize(64);for(unsigned i=0;i<32;++i){auto b=std::to_integer<unsigned>(raw[i]);out.hash[2*i]=hex[b>>4];out.hash[2*i+1]=hex[b&15];}require(h.close(),"actual crash read handle close");return out;
}
// Original MIT. Actual Win32 sharing failures, not injected return codes.
// Only the first already-open Service is used; every path is a proof sibling.
struct ExportGateRetirement {
 Probe& probe;
 ~ExportGateRetirement(){probe.release();}
};
std::vector<std::string> export_owned_temporaries(const std::string&parent){
 FixedEnumerationOperand pattern;require(pattern.set(parent,L"\\.fsplayers-*.tmp"),"bounded literal owned-export temporary wildcard");
 WIN32_FIND_DATAW data{};HANDLE find=FindFirstFileW(pattern.value.data(),&data);std::vector<std::string> names;
 if(find==INVALID_HANDLE_VALUE){require(GetLastError()==ERROR_FILE_NOT_FOUND,"temporary enumeration has only ordinary no-match absence");return names;}
 bool valid=true;do{FixedText<4096> leaf;if(!utf8(std::wstring_view(data.cFileName),leaf)){valid=false;break;}auto name=leaf.view();
  if(name.size()!=47||!name.starts_with(".fsplayers-")||!name.ends_with(".tmp")||!lower_hex(name.substr(11,32),32)||(data.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT))||names.size()>=2){valid=false;break;}
  names.emplace_back(parent+"\\"+std::string(name));
 }while(FindNextFileW(find,&data));const auto error=GetLastError();require(FindClose(find)!=0,"owned temporary enumeration retired");
 require(valid&&error==ERROR_NO_MORE_FILES,"closed at-most-two owned temporary discovery");std::sort(names.begin(),names.end());return names;
}
__declspec(noinline) void export_sharing_cases(Service*service,Probe&p,const std::string&alice,const std::string&root,const std::string&target,const std::string&original_receipt){
 p.wait_published(p.last_request());
 const auto slash=target.find_last_of('\\');require(slash!=target.npos,"owned export proof parent");const auto parent=target.substr(0,slash);
 const auto baseline=crash_file(target,65536,true);Raw original(original_receipt);auto ov=value(original);
 require(baseline.present&&baseline.length==natural(original.d,member(original.d,ov,"bytes"),65536)&&baseline.hash==field(original.d,ov,"sha256"),"reuse independently verified first-Service complete export, not new generated expectations");
 require(field(original.d,ov,"player_id")==alice&&field(original.d,ov,"preferences_revision")=="3"&&natural(original.d,member(original.d,ov,"practice_count"),2)==2,"fault snapshot is exact original selected revision3/two-practice snapshot");
 require(export_owned_temporaries(parent).empty(),"no previous retained export before first sharing failure");
 auto payload=[&](const std::string&path){require(valid_local_absolute_path(path)&&!at_or_within(path,root),"self-owned export proof stays outside protected root");return V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("3")},{"target_absolute_path",V::s(path)}});};
 auto ready=[&]{p.wait_published(p.last_request());auto s=status(service);require(s.state==ServiceState::ready&&s.error==Error::none&&s.writer_alive&&s.pending==0&&s.undelivered==0&&p.reserved_bytes()==2097152,"file failure/ack leaves ready worker and original permanent reservations");};
 auto unchanged=[&](const std::string&path,const FileIdentity&identity){auto file=crash_file(path,65536,true);require(file.present&&file.length==baseline.length&&file.hash==baseline.hash&&file.bytes==baseline.bytes&&same_identity(file.identity,identity),"whole original export bytes/identity retained without overwrite or implicit deletion");};
 auto whole_state=[&]{std::array<std::string,3> rows;Raw pair(job(service,JobKind::load_player,V::o({{"player_id",V::s(alice)}}),"read"));rows[0]=canonical(pair.d,value(pair));
  for(unsigned i=0;i<2;++i){Raw practice_row(job(service,JobKind::load_practice,V::o({{"player_id",V::s(alice)},{"practice_id",V::s(std::string(32,i?'4':'3'))}}),"read"));rows[i+1]=canonical(practice_row.d,value(practice_row));}ready();return rows;};
 const auto selected_before=whole_state();std::string retained_temp;FileIdentity retained_identity;
 for(bool reopen:{false,true}){
  ready();const auto names_before=export_owned_temporaries(parent);require(names_before.size()==(reopen?1U:0U)&&(!reopen||names_before[0]==retained_temp),"only prior owned retained temporary may precede next operation");
  const std::string failed_target=target+(reopen?".reopen-sharing":".move-sharing");require(!crash_file(failed_target,65536).present,"fresh fault target is actually absent");
  const auto events_begin=p.event_count();p.arm(JobKind::export_player,Phase::export_move,reopen?Edge::after:Edge::before);ExportGateRetirement retire{p};
  Capture input(JobKind::export_player,payload(failed_target));auto admission=service->submit(input);require(admission.accepted&&admission.error==Error::none,"fault export accepted by existing first Service");const auto request=p.last_request();p.wait();
  NativeObservation held;{std::lock_guard lock(p.mutex);require(p.events.size()>events_begin,"held actual move notification exists");held=p.events.back();}
  require(held.kind==JobKind::export_player&&held.phase==Phase::export_move&&held.edge==(reopen?Edge::after:Edge::before)&&held.scope==Scope::export_file&&held.role==FileRole::target&&held.request_ordinal==request&&held.owned_handle&&held.identity.valid&&held.identity.links==1,"barrier bound to actual owned move identity and exact admitted request");
  require(reopen?(held.has_win32_error&&held.win32_error==ERROR_SUCCESS&&held.installed==1):(!held.has_win32_error&&held.installed==0),"before/after move distinction reflects actual installation, never guessed from target existence");
  std::string blocked_path=failed_target;
  if(!reopen){auto names=export_owned_temporaries(parent);require(names.size()==1,"discover exactly one actual random owned temporary");blocked_path=names[0];auto temp=crash_file(blocked_path,65536,true);require(temp.present&&same_identity(temp.identity,held.identity)&&temp.bytes==baseline.bytes&&temp.hash==baseline.hash,"actual temp bound to move event identity/full original export");require(!crash_file(failed_target,65536).present,"before move target remains absent");}
  Handle blocker;require(open_ordinary(blocked_path,blocker,reopen?DELETE:GENERIC_READ,reopen?(FILE_SHARE_READ|FILE_SHARE_DELETE):FILE_SHARE_READ),"actual compatible blocker opened while production read guard remains owned");
  FileIdentity blocker_identity;require(observe_identity(blocker.value,false,blocker_identity)&&same_identity(blocker_identity,held.identity),"blocker targets the exact worker-owned file");
  // Temp READ/shareREAD denies rename DELETE. Target DELETE/shareREAD|DELETE
  // coexists with guard READ/shareREAD|DELETE, but denies later READ/shareREAD.
  p.release();auto delivered=receive(service,1);result(delivered[0],admission.request_id.view(),JobKind::export_player,"recovery_required","file_recovery_required");p.wait_published(request);
  {Raw receipt(delivered[0]);auto v=value(receipt);require(field(receipt.d,v,"outcome")=="recovery_required"&&field(receipt.d,v,"phase")== (reopen?"verify_target":"move")&&field(receipt.d,v,"target_absolute_path")==failed_target,"exact file-only recovery outcome/phase/target");
   auto installed=member(receipt.d,v,"installed");require(reopen?(receipt.d.at(installed)->kind==ValueKind::boolean&&receipt.d.at(installed)->scalar==1):nil(receipt.d,installed),"failed move reports unknown installation; failed reopen preserves historical actual successful move");
   require(field(receipt.d,v,"player_id")==alice&&field(receipt.d,v,"preferences_revision")=="3"&&natural(receipt.d,member(receipt.d,v,"practice_count"),2)==2&&natural(receipt.d,member(receipt.d,v,"bytes"),65536)==baseline.length&&field(receipt.d,v,"sha256")==baseline.hash,"completed snapshot/temp verification metadata survives both actual failures");
   auto temporary=field(receipt.d,v,"temporary_absolute_path");const auto temp_slash=temporary.find_last_of('\\');require(temp_slash!=temporary.npos&&temporary.substr(0,temp_slash)==parent,"receipt temporary belongs to exact isolated proof parent");auto leaf=std::string_view(temporary).substr(temp_slash+1);require(leaf.size()==47&&leaf.starts_with(".fsplayers-")&&leaf.ends_with(".tmp")&&lower_hex(leaf.substr(11,32),32),"receipt retains canonical actual random-temporary grammar");
   if(!reopen){require(temporary==blocked_path,"failed move retains the independently discovered exact temporary path");retained_temp=temporary;retained_identity=held.identity;}
   else{require(temporary!=retained_temp&&!crash_file(temporary,65536).present,"reopen receipt's historical temporary was actually moved, not silently erased after failure");}
  }
  {std::lock_guard lock(p.mutex);unsigned before_move=0,after_move=0,before_open=0,after_open=0,commits=0;
   for(std::size_t i=events_begin;i<p.events.size();++i){const auto&o=p.events[i];require(o.request_ordinal==request&&o.service_ordinal==held.service_ordinal&&o.kind==JobKind::export_player,"all operation observations remain exact first-Service/request identity");
    require(o.phase!=Phase::row_write&&o.phase!=Phase::rollback,"file recovery does not inject SQL write/rollback failure");
    if(o.scope==Scope::original&&o.phase==Phase::after_commit){require(o.edge==Edge::after&&o.has_result&&o.sqlite_result==SQLITE_DONE&&o.autocommit&&o.txn_state==SQLITE_TXN_NONE&&before_move==0,"coherent read snapshot actually committed before target fault, no DB uncertainty");++commits;}
    if(o.phase==Phase::export_move){require(o.scope==Scope::export_file&&o.role==FileRole::target&&same_identity(o.identity,held.identity),"paired move observations preserve exact file identity");if(o.edge==Edge::before)++before_move;else{++after_move;require(o.has_win32_error&&o.win32_error==static_cast<std::uint32_t>(reopen?ERROR_SUCCESS:ERROR_SHARING_VIOLATION)&&o.installed==(reopen?1:-1),"actual MoveFileEx result/error32, not simulated IO result");}}
    if(o.phase==Phase::export_verify_target&&o.role==FileRole::target){require(reopen&&o.scope==Scope::export_file&&o.installed==1,"target reopen occurs only after actual successful install");if(o.edge==Edge::before)++before_open;else{++after_open;require(o.has_win32_error&&o.win32_error==ERROR_SHARING_VIOLATION&&!o.owned_handle&&!o.identity.valid,"actual failed target CreateFileW reports32 without fabricated file ownership");}}
   }require(commits==1&&before_move==1&&after_move==1&&before_open==(reopen?1U:0U)&&after_open==(reopen?1U:0U),"exact paired move/reopen and snapshot-commit counts");
  }
  ready();require(blocker.close(),"test-owned blocker explicitly retired after recovery receipt ACK");
  if(reopen){unchanged(failed_target,held.identity);Raw collision(job(service,JobKind::export_player,payload(failed_target),"failed","target_exists"));auto v=value(collision);require(field(collision.d,v,"outcome")=="not_saved"&&collision.d.at(member(collision.d,v,"installed"))->kind==ValueKind::boolean&&collision.d.at(member(collision.d,v,"installed"))->scalar==0&&nil(collision.d,member(collision.d,v,"temporary_absolute_path")),"explicit same-target retry refuses overwrite and creates no new temporary");ready();unchanged(failed_target,held.identity);}
  else require(!crash_file(failed_target,65536).present,"failed move never creates selected target");
  unchanged(retained_temp,retained_identity);
  const std::string fresh=failed_target+".retry";require(!crash_file(fresh,65536).present,"explicit retry chooses separate actually absent proof sibling");Raw retried(job(service,JobKind::export_player,payload(fresh),"read"));auto rv=value(retried);
  require(field(retried.d,rv,"outcome")=="saved"&&field(retried.d,rv,"phase")=="done"&&field(retried.d,rv,"target_absolute_path")==fresh&&retried.d.at(member(retried.d,rv,"installed"))->kind==ValueKind::boolean&&retried.d.at(member(retried.d,rv,"installed"))->scalar==1&&nil(retried.d,member(retried.d,rv,"temporary_absolute_path"))&&field(retried.d,rv,"sha256")==baseline.hash&&natural(retried.d,member(retried.d,rv,"bytes"),65536)==baseline.length,"new target explicit retry actually saved same complete snapshot");
  ready();auto saved_file=crash_file(fresh,65536,true);require(saved_file.present&&saved_file.bytes==baseline.bytes&&saved_file.hash==baseline.hash&&saved_file.length==baseline.length,"whole fresh retry file equals independently checked original export");unchanged(retained_temp,retained_identity);unchanged(target,baseline.identity);
  require(export_owned_temporaries(parent)==std::vector<std::string>{retained_temp},"neither retry/failure silently removes retained temporary or leaks another");
 }
 require(whole_state()==selected_before,"all selected Player/preferences and two full Practice records unchanged by file failures and retries");ready();
}

// Original MIT. Real synchronous byte-range IO failures on the worker's temp.
// This second handle does not replace syscall results or throw from observers.
struct ExportRangeLock {
 Handle handle;
 OVERLAPPED range{};
 bool locked{};
 bool close()noexcept {
  if(locked){if(!UnlockFileEx(handle.value,0,1,0,&range))return false;locked=false;}
  return handle.close();
 }
 ~ExportRangeLock(){if(!close())std::terminate();}
};
__declspec(noinline) void export_range_lock_cases(Service*service,Probe&p,const std::string&alice,const std::string&root,const std::string&target,const std::string&original_receipt){
 p.wait_published(p.last_request());
 const auto slash=target.find_last_of('\\');require(slash!=target.npos,"range-lock isolated export parent");const auto parent=target.substr(0,slash);
 const auto baseline=crash_file(target,65536,true);Raw original(original_receipt);auto ov=value(original);
 require(baseline.present&&baseline.length>0&&baseline.length==natural(original.d,member(original.d,ov,"bytes"),65536)&&baseline.hash==field(original.d,ov,"sha256"),"range-lock uses full independently verified nonempty original export");
 const auto prior_names=export_owned_temporaries(parent);require(prior_names.size()==1,"prior sharing failure's owned temporary is retained");const auto prior=crash_file(prior_names[0],65536,true);
 require(prior.present&&prior.bytes==baseline.bytes&&prior.hash==baseline.hash,"prior sharing temporary remains complete before range-lock cases");
 auto payload=[&](const std::string&path){require(valid_local_absolute_path(path)&&!at_or_within(path,root),"range-lock export stays outside protected root");return V::o({{"player_id",V::s(alice)},{"expected_revision",V::s("3")},{"target_absolute_path",V::s(path)}});};
 auto ready=[&]{p.wait_published(p.last_request());auto state=status(service);require(state.state==ServiceState::ready&&state.error==Error::none&&state.writer_alive&&state.pending==0&&state.undelivered==0&&p.reserved_bytes()==2097152,"range-lock ACK restores permanent-only ready ownership");};
 auto whole_state=[&]{std::array<std::string,3> rows;{Raw pair(job(service,JobKind::load_player,V::o({{"player_id",V::s(alice)}}),"read"));rows[0]=canonical(pair.d,value(pair));}
  for(unsigned i=0;i<2;++i){Raw row(job(service,JobKind::load_practice,V::o({{"player_id",V::s(alice)},{"practice_id",V::s(std::string(32,i?'4':'3'))}}),"read"));rows[i+1]=canonical(row.d,value(row));}ready();return rows;};
 const auto selected_before=whole_state();
 for(bool verify_read:{false,true}){
  ready();require(export_owned_temporaries(parent)==prior_names,"new IO case preserves bounded prior temporary roster");
  const auto phase=verify_read?Phase::export_verify_target:Phase::export_write;const auto kind=verify_read?IoKind::read:IoKind::write;
  const std::string failed_target=target+(verify_read?".temp-read-locked":".temp-write-locked");require(!crash_file(failed_target,65536).present,"fresh range-lock selected target absent");
  const auto events_begin=p.event_count();p.arm(JobKind::export_player,phase,Edge::before);ExportGateRetirement retire{p};
  Capture input(JobKind::export_player,payload(failed_target));auto admission=service->submit(input);require(admission.accepted&&admission.error==Error::none,"range-lock request admitted to existing first Service");const auto request=p.last_request();p.wait();
  NativeObservation held;{std::lock_guard lock(p.mutex);require(p.events.size()>events_begin,"actual held IO observation exists");held=p.events.back();}
  require(held.kind==JobKind::export_player&&held.phase==phase&&held.scope==Scope::export_file&&held.edge==Edge::before&&held.role==FileRole::temp&&held.io_kind==kind&&held.chunk_index==1&&held.request_ordinal==request&&held.owned_handle&&held.identity.valid&&held.identity.links==1&&held.has_requested&&held.requested>0&&held.requested<=65536&&!held.has_completed&&!held.has_win32_error,"exact first synchronous worker temp IO held before syscall");
  const auto names=export_owned_temporaries(parent);std::string temporary;for(const auto&name:names)if(std::find(prior_names.begin(),prior_names.end(),name)==prior_names.end()){require(temporary.empty(),"only one new owned temp");temporary=name;}
  require(names.size()==prior_names.size()+1&&!temporary.empty(),"closed at-most-two discovery identifies only new temp");
  ExportRangeLock blocker;require(open_ordinary(temporary,blocker.handle,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE),"compatible second synchronous READ handle does not deny writer sharing");
  FileIdentity identity;LARGE_INTEGER size{};require(observe_identity(blocker.handle.value,false,identity)&&same_identity(identity,held.identity)&&GetFileSizeEx(blocker.handle.value,&size)&&size.QuadPart==static_cast<LONGLONG>(verify_read?baseline.length:0),"blocker is exact single-link temp; write empty or flushed read complete");
  if(verify_read){std::string bytes(static_cast<std::size_t>(baseline.length),'\0');std::size_t offset=0;while(offset<bytes.size()){DWORD got{};const auto wanted=static_cast<DWORD>(bytes.size()-offset);require(ReadFile(blocker.handle.value,bytes.data()+offset,wanted,&got,nullptr)&&got>0&&got<=wanted,"independent temp read before lock");offset+=got;}DWORD extra{};char byte{};require(ReadFile(blocker.handle.value,&byte,1,&extra,nullptr)&&extra==0&&bytes==baseline.bytes&&digest_text(bytes)==baseline.hash,"full flushed temp bytes/hash/EOF before locking verification read");}
  // Offset zero, length one: first positive worker syscall must overlap.
  // Beyond-EOF locks are valid for the still-empty first-write case.
  const BOOL locked=LockFileEx(blocker.handle.value,LOCKFILE_EXCLUSIVE_LOCK|LOCKFILE_FAIL_IMMEDIATELY,0,1,0,&blocker.range);const DWORD lock_error=locked?ERROR_SUCCESS:GetLastError();blocker.locked=locked!=0;
  require(locked&&lock_error==ERROR_SUCCESS,"actual immediate exclusive one-byte lock acquired on separate owned handle");
  p.release();auto delivered=receive(service,1);result(delivered[0],admission.request_id.view(),JobKind::export_player,"failed",verify_read?"file_verify_failed":"file_write_failed");p.wait_published(request);
  {Raw receipt(delivered[0]);auto v=value(receipt);auto installed=receipt.d.at(member(receipt.d,v,"installed"));
   require(field(receipt.d,v,"operation_id")==admission.request_id.view()&&field(receipt.d,v,"outcome")=="not_saved"&&field(receipt.d,v,"phase")== (verify_read?"verify_temp":"write")&&field(receipt.d,v,"target_absolute_path")==failed_target&&field(receipt.d,v,"temporary_absolute_path")==temporary&&installed&&installed->kind==ValueKind::boolean&&installed->scalar==0,"known pre-move file failure retains exact temp and never claims installation");
   require(nil(receipt.d,member(receipt.d,v,"bytes"))&&nil(receipt.d,member(receipt.d,v,"sha256"))&&field(receipt.d,v,"player_id")==alice&&field(receipt.d,v,"preferences_revision")=="3"&&natural(receipt.d,member(receipt.d,v,"practice_count"),2)==2,"uncompleted digest exposes null verified bytes/hash and unchanged coherent snapshot metadata");
  }
  {std::lock_guard lock(p.mutex);unsigned io_before=0,io_after=0,commits=0,flush_before=0,flush_after=0;
   for(std::size_t i=events_begin;i<p.events.size();++i){const auto&o=p.events[i];require(o.request_ordinal==request&&o.service_ordinal==held.service_ordinal&&o.kind==JobKind::export_player,"range failure trace bound to exact request and Service");
    require(o.phase!=Phase::row_write&&o.phase!=Phase::rollback&&o.phase!=Phase::postverify&&o.phase!=Phase::export_move,"range failure neither SQL mutation/rollback/postverify nor move");
    if(o.scope==Scope::original&&o.phase==Phase::after_commit){require(o.edge==Edge::after&&o.has_result&&o.sqlite_result==SQLITE_DONE&&o.autocommit&&o.txn_state==SQLITE_TXN_NONE&&io_before==0,"real coherent read COMMIT completed before any locked file IO");++commits;}
    if(o.phase==Phase::export_flush){require(verify_read&&o.scope==Scope::export_file&&o.role==FileRole::temp&&same_identity(o.identity,held.identity),"read failure follows actual flush of same temp");if(o.edge==Edge::before)++flush_before;else{++flush_after;require(o.has_win32_error&&o.win32_error==ERROR_SUCCESS,"flush really succeeded; not a flush-failure claim");}}
    if(o.scope==Scope::export_file&&o.phase==phase){require(o.role==FileRole::temp&&o.io_kind==kind&&o.chunk_index==1&&o.occurrence==held.occurrence&&o.has_requested&&o.requested==held.requested&&o.owned_handle&&same_identity(o.identity,held.identity),"exact paired first IO kind/count/file identity");
     if(o.edge==Edge::before){++io_before;require(!o.has_completed&&!o.has_win32_error,"before IO has no fabricated result");}else{++io_after;require(o.has_completed&&o.completed==0&&o.has_win32_error&&o.win32_error==ERROR_LOCK_VIOLATION,"actual synchronous ReadFile/WriteFile denied with Win32 lock violation33 and zero bytes");}}
    if(o.scope==Scope::export_file&&o.io_kind!=IoKind::not_applicable&&o.phase!=phase)require(verify_read&&o.phase==Phase::export_write&&o.io_kind==IoKind::write&&(o.edge==Edge::before||(o.has_completed&&o.completed>0&&o.completed<=o.requested&&o.has_win32_error&&o.win32_error==ERROR_SUCCESS)),"only successful earlier writes may precede temp-read failure");
   }require(commits==1&&io_before==1&&io_after==1&&flush_before==(verify_read?1U:0U)&&flush_after==(verify_read?1U:0U),"one actual failed IO pair, with flush only for verify-read case");
  }
  ready();require(blocker.close(),"explicit exact-range unlock and checked blocker close after failure ACK");
  const auto failed=crash_file(temporary,65536,true);require(failed.present&&same_identity(failed.identity,held.identity)&&failed.length==(verify_read?baseline.length:0)&&failed.bytes==(verify_read?baseline.bytes:std::string{})&&failed.hash==(verify_read?baseline.hash:digest_text("")),"whole failed temp retained unchanged: zero-byte write failure or complete unverified read failure");
  require(!crash_file(failed_target,65536).present,"known pre-move IO failure leaves selected target absent");
  const std::string fresh=failed_target+".retry";require(!crash_file(fresh,65536).present,"explicit fresh retry target absent");Raw retried(job(service,JobKind::export_player,payload(fresh),"read"));auto rv=value(retried);
  require(field(retried.d,rv,"outcome")=="saved"&&field(retried.d,rv,"phase")=="done"&&field(retried.d,rv,"target_absolute_path")==fresh&&retried.d.at(member(retried.d,rv,"installed"))->kind==ValueKind::boolean&&retried.d.at(member(retried.d,rv,"installed"))->scalar==1&&nil(retried.d,member(retried.d,rv,"temporary_absolute_path"))&&field(retried.d,rv,"sha256")==baseline.hash&&natural(retried.d,member(retried.d,rv,"bytes"),65536)==baseline.length,"fresh explicit retry saved complete unchanged snapshot after blocker retired");ready();
  const auto saved=crash_file(fresh,65536,true);require(saved.present&&saved.length==baseline.length&&saved.hash==baseline.hash&&saved.bytes==baseline.bytes,"independent whole retry file verification");
  const auto retained=crash_file(temporary,65536,true);require(retained.present&&same_identity(retained.identity,failed.identity)&&retained.length==failed.length&&retained.bytes==failed.bytes&&retained.hash==failed.hash,"retry does not silently erase or alter failed temp");
  // Test-owned cleanup is explicit, after full retained-byte proof and unlock.
  auto own_temp=std::make_unique<Wide>();require(own_temp->set(temporary),"exact independently discovered owned temp cleanup operand");auto own_operand=std::make_unique<ExtendedFileOperand>(*own_temp);require(DeleteFileW(own_operand->value.data())!=0,"explicit test cleanup of only new failed temp");
  require(!crash_file(temporary,65536).present&&export_owned_temporaries(parent)==prior_names,"cleanup restores unchanged at-most-two enumeration bound; prior temp not deleted");
  const auto old=crash_file(prior_names[0],65536,true),original_file=crash_file(target,65536,true);require(old.present&&same_identity(old.identity,prior.identity)&&old.bytes==prior.bytes&&old.hash==prior.hash&&original_file.present&&same_identity(original_file.identity,baseline.identity)&&original_file.bytes==baseline.bytes&&original_file.hash==baseline.hash,"original export and previous sharing temp retain full bytes and identity");
 }
 require(whole_state()==selected_before,"actual IO failures/retries preserve complete Player/Preferences and both Practice records");ready();
}

void crash_record_file(std::string_view label,const CrashFile&f){
 require(crash_observations.size()<128,"finite observation roster");std::string row="{\"label\":"+crash_quote(label)+",\"present\":"+(f.present?"true":"false")+",\"bytes\":"+(f.present?std::to_string(f.length):"null")+",\"sha256\":"+(f.present?crash_quote(f.hash):"null")+",\"identity\":"+(f.present?crash_identity(f.identity):"null")+"}";crash_observations.push_back(std::move(row));
}
constexpr std::array<std::string_view,4> crash_data_names={"players.sqlite3","players.sqlite3-wal","players.sqlite3-shm","players.sqlite3-journal"};
constexpr std::array<std::string_view,4> crash_roles={"main","wal","shm","journal"};
constexpr std::array<std::uint64_t,4> crash_caps={268435456,67108864,8388608,8388608};
std::array<CrashFile,4> crash_original(const std::string&root,bool retain=false){
 std::array<CrashFile,4> out;for(unsigned i=0;i<4;++i){out[i]=crash_file(root+"\\"+std::string(crash_data_names[i]),crash_caps[i],retain);crash_record_file("original/"+std::string(crash_data_names[i]),out[i]);}return out;
}
std::vector<std::string> crash_directories(const std::string&root){
 const auto directory=root+"\\recovery";Wide path;require(path.set(directory),"recovery path");auto attrs=GetFileAttributesW(path.value.data());if(attrs==INVALID_FILE_ATTRIBUTES){require(GetLastError()==ERROR_PATH_NOT_FOUND||GetLastError()==ERROR_FILE_NOT_FOUND,"actual missing recovery directory");return {};}
 require((attrs&FILE_ATTRIBUTE_DIRECTORY)&&!(attrs&FILE_ATTRIBUTE_REPARSE_POINT),"ordinary recovery directory");FixedEnumerationOperand pattern;require(pattern.set(directory,L"\\*"),"recovery wildcard literal");WIN32_FIND_DATAW data{};HANDLE find=FindFirstFileW(pattern.value.data(),&data);require(find!=INVALID_HANDLE_VALUE,"actual recovery enumeration");std::vector<std::string> out;bool valid=true;
 do{std::wstring_view w(data.cFileName);if(w==L"."||w==L"..")continue;FixedText<4096> name;if(!utf8(w,name)){valid=false;break;}auto s=name.view();bool work=s.starts_with("work-");auto prefix=work?5U:9U;if((!work&&!s.starts_with("recovery-"))||s.size()!=prefix+32||!lower_hex(s.substr(prefix),32)||!(data.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)||(data.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)||out.size()>=3){valid=false;break;}out.emplace_back(s);}while(FindNextFileW(find,&data));auto error=GetLastError();require(FindClose(find)!=0,"actual directory enumeration close");require(valid&&error==ERROR_NO_MORE_FILES,"closed finite recovery/work names");std::sort(out.begin(),out.end());return out;
}
std::string crash_source_json(bool second=false){
 return "{\"angular_integration_method\":null,\"model_identity\":{\"backend_model\":\"original-interactive\",\"id\":\"original-interactive-prototype\",\"version\":\"0.1.0-prototype\"},\"named_start\":\"ground-ready\",\"native_source_fingerprint\":\""+std::string(64,'1')+"\",\"prepared_world_sha256\":\""+std::string(64,'2')+"\",\"session_id\":\"synthetic-service-reference-"+(second?"2":"1")+"\",\"source_variant\":\"jsbsim-1.3.1-upstream\",\"wind_profile\":\"calm\"}";
}
std::string crash_player(bool bob=false,bool renamed=false){
 return "{\"created_utc\":\"2026-10-03T12:00:00Z\",\"id\":"+crash_quote(bob?crash_bob:crash_alice)+",\"name\":"+crash_quote(bob?"Bob":renamed?"Alice After":"Alice")+",\"revision\":"+crash_quote(bob?"1":renamed?"3":"2")+",\"type\":\"LocalPlayer\",\"updated_utc\":"+crash_quote(bob?"2026-10-03T12:00:00Z":renamed?"2026-10-03T12:03:00Z":"2026-10-03T12:04:00Z")+",\"version\":1}";
}
std::string crash_preferences(bool bob=false,bool renamed=false){
 return "{\"audio\":{\"airflow_gain\":{\"$binary64_le\":\"000000000000f03f\"},\"enabled\":true,\"engine_gain\":{\"$binary64_le\":"+crash_quote(bob?"000000000000f03f":"0000000000000080")+"},\"show_panel_captions\":true},\"legacy_input\":null,\"piston_input\":null,\"player_id\":"+crash_quote(bob?crash_bob:crash_alice)+",\"revision\":"+crash_quote(bob?"1":renamed?"3":"2")+",\"type\":\"LocalPlayerPreferences\",\"version\":1}";
}
std::string crash_practice(bool second=false,bool interrupted=false,bool summary=false){
 return "{\"archive\":"+std::string(summary?"{\"linked\":false}":"null")+",\"commit_sequence\":"+crash_quote(second?"8":interrupted?"7":"6")+",\"creation_sequence\":"+crash_quote(second?"7":"5")+",\"end_reason\":"+crash_quote(interrupted?"previous_process_incomplete":"user_end")+",\"first_tick\":"+crash_quote(second?"0":"9007199254740993")+",\"id\":"+crash_quote(second?crash_two:crash_one)+",\"last_observed_utc\":\"2026-10-03T12:02:00Z\",\"last_tick\":"+crash_quote(second?"5":"9007199254741000")+",\"observed_ticks\":"+crash_quote(second?"5":"7")+",\"player_id\":"+crash_quote(crash_alice)+",\"revision\":"+crash_quote(interrupted?"3":"2")+",\"source\":"+crash_source_json(second)+",\"started_utc\":\"2026-10-03T12:01:00Z\",\"status\":"+crash_quote(interrupted?"interrupted":"manually_ended")+",\"tick_rate_hz\":120,\"type\":\"LocalPractice\",\"version\":1}";
}
std::string crash_export_bytes(){
 auto payload="{\"player\":"+crash_player()+",\"practice\":["+crash_practice(true,false,true)+","+crash_practice(false,false,true)+"],\"preferences\":"+crash_preferences()+"}";
 return "{\"format\":\"LocalPlayerSummary\",\"payload_json\":"+crash_quote(payload)+",\"payload_sha256\":"+crash_quote(digest_text(payload))+",\"version\":1}";
}
void crash_pair(Service*s,bool renamed=false){
 for(bool bob:{false,true}){Raw r(job(s,JobKind::load_player,V::o({{"player_id",V::s(bob?crash_bob:crash_alice)}}),"read"));auto v=value(r);require(canonical(r.d,member(r.d,v,"player"))==crash_player(bob,renamed)&&canonical(r.d,member(r.d,v,"preferences"))==crash_preferences(bob,renamed),"whole independent Player/preferences exact including zero sign/revision/UTC");}
 Raw listed(job(s,JobKind::list_players,V::o({}),"read"));auto rows=array(listed.d,member(listed.d,value(listed),"players"));require(rows.size()==2&&field(listed.d,rows[0],"id")==crash_alice&&field(listed.d,rows[1],"id")==crash_bob,"exact two selected-independent player rows");
}
void crash_history(Service*s,bool exported,bool interrupted){
 if(!exported&&!interrupted){Raw r(job(s,JobKind::list_practice,V::o({{"player_id",V::s(crash_alice)},{"before_creation_sequence",V::null()},{"limit",V::i(50)}}),"read"));require(array(r.d,member(r.d,value(r),"practice")).empty()&&nil(r.d,member(r.d,value(r),"next_before_creation_sequence")),"no invented history");return;}
 for(bool second:{false,true}){if(second&&!exported)continue;Raw r(job(s,JobKind::load_practice,V::o({{"player_id",V::s(crash_alice)},{"practice_id",V::s(second?crash_two:crash_one)}}),"read"));require(canonical(r.d,practice(r))==crash_practice(second,interrupted),"full Practice exact source/ticks/observation UTC/revision/creation/commit/status");}
 Raw r(job(s,JobKind::list_practice,V::o({{"player_id",V::s(crash_alice)},{"before_creation_sequence",V::null()},{"limit",V::i(50)}}),"read"));auto rows=array(r.d,member(r.d,value(r),"practice"));require(rows.size()==(exported?2U:1U)&&nil(r.d,member(r.d,value(r),"next_before_creation_sequence")),"ALL exact history in one page");for(std::size_t i=0;i<rows.size();++i)require(canonical(r.d,rows[i])==crash_practice(exported&&i==0,interrupted,true),"numeric immutable creation-desc complete summaries");
}
// Transactional DELETE crash witness. No raw SQL and no actor-death claim.
void crash_delete_reopened(Service*s,bool committed){
 if(!committed){crash_pair(s);crash_history(s,true,false);}
 else {
  job(s,JobKind::load_player,V::o({{"player_id",V::s(crash_alice)}}),"failed","not_found");
  job(s,JobKind::list_practice,V::o({{"player_id",V::s(crash_alice)},{"before_creation_sequence",V::null()},{"limit",V::i(50)}}),"failed","not_found");
  for(const auto&id:{crash_one,crash_two})job(s,JobKind::load_practice,V::o({{"player_id",V::s(crash_alice)},{"practice_id",V::s(id)}}),"failed","not_found");
  Raw bob(job(s,JobKind::load_player,V::o({{"player_id",V::s(crash_bob)}}),"read"));auto v=value(bob);
  require(canonical(bob.d,member(bob.d,v,"player"))==crash_player(true)&&canonical(bob.d,member(bob.d,v,"preferences"))==crash_preferences(true),"deletion preserves complete unrelated Bob/preferences");
  Raw listed(job(s,JobKind::list_players,V::o({}),"read"));auto rows=array(listed.d,member(listed.d,value(listed),"players"));
  require(rows.size()==1&&canonical(listed.d,rows[0])=="{\"id\":\""+crash_bob+"\",\"name\":\"Bob\",\"revision\":\"1\"}","exact sole surviving Bob summary");
 }
 auto renamed=job(s,JobKind::rename_player,V::o({{"player_id",V::s(crash_bob)},{"expected_revision",V::s("1")},{"name",V::s("Bob After")},{"utc",V::s("2026-10-03T12:05:00Z")}}),"committed","",committed?"10":"9");
 Raw rename(renamed);auto v=value(rename);
 auto expected_player=crash_player(true),expected_prefs=crash_preferences(true);
 auto rewrite=[](std::string&bytes,std::string_view old,std::string_view now){auto pos=bytes.find(old);require(pos!=std::string::npos&&bytes.find(old,pos+old.size())==std::string::npos,"unique independent expected field replacement");bytes.replace(pos,old.size(),now);};
 rewrite(expected_player,"\"name\":\"Bob\"","\"name\":\"Bob After\"");rewrite(expected_player,"\"revision\":\"1\"","\"revision\":\"2\"");rewrite(expected_player,"\"updated_utc\":\"2026-10-03T12:00:00Z\"","\"updated_utc\":\"2026-10-03T12:05:00Z\"");rewrite(expected_prefs,"\"revision\":\"1\"","\"revision\":\"2\"");
 require(canonical(rename.d,member(rename.d,v,"player"))==expected_player&&canonical(rename.d,member(rename.d,v,"preferences"))==expected_prefs,"whole surviving pair plus exact next global commit sequence");
 if(committed){
  // Reusing the deleted ID through the ordinary API makes hidden old children
  // observable: fresh preferences must be unity and old practices absent.
  Raw recreated(job(s,JobKind::create_player,player_seed(crash_alice),"committed","","11"));auto rv=value(recreated);
  auto fresh_player=crash_player(),fresh_preferences=crash_preferences();
  rewrite(fresh_player,"\"revision\":\"2\"","\"revision\":\"1\"");rewrite(fresh_player,"\"updated_utc\":\"2026-10-03T12:04:00Z\"","\"updated_utc\":\"2026-10-03T12:00:00Z\"");
  rewrite(fresh_preferences,"\"revision\":\"2\"","\"revision\":\"1\"");rewrite(fresh_preferences,"0000000000000080","000000000000f03f");
  require(canonical(recreated.d,member(recreated.d,rv,"player"))==fresh_player&&canonical(recreated.d,member(recreated.d,rv,"preferences"))==fresh_preferences,"fresh same-ID player/default preferences prove old preference cascade");
  crash_history(s,false,false);
  for(const auto&id:{crash_one,crash_two})job(s,JobKind::load_practice,V::o({{"player_id",V::s(crash_alice)},{"practice_id",V::s(id)}}),"failed","not_found");
 }
}
void crash_start(Fixture&f,bool management=false,bool fresh=false,bool interrupted=false,std::source_location site=std::source_location::current()){
 auto a=f.service->start(management);require(a.accepted&&a.error==Error::none,"real crash-stage start admitted");auto terminal=receive(f.service,1);result(terminal[0],a.request_id.view(),management?JobKind::start_management:JobKind::start,(fresh||interrupted)?"committed":"read","",fresh?"1":interrupted?"7":"",site);
 if(!management){Raw r(terminal[0]);auto v=value(r);require(natural(r.d,member(r.d,v,"interrupted_rows"),1)==static_cast<unsigned>(interrupted)&&r.d.at(member(r.d,v,"created"))->scalar==static_cast<unsigned>(fresh),"actual created/interrupted branches exact");}
}
void crash_no_sqlite(Probe&p){std::lock_guard lock(p.mutex);require(std::none_of(p.events.begin(),p.events.end(),[](const NativeObservation&o){return o.phase==Phase::before_open;}),"no SQLite connection opening on refused/management path");}
void crash_refused_start(Fixture&f,Probe&p,std::string_view expected){auto a=f.service->start();require(a.accepted,"refused open is admitted start job");auto rows=receive(f.service,1);result(rows[0],a.request_id.view(),JobKind::start,"failed",expected);crash_no_sqlite(p);require(status(f.service).state==ServiceState::unavailable,"failed qualification stays unavailable");f.close();}
void crash_prepare(Fixture&f,std::string_view name){
 crash_start(f,false,true);job(f.service,JobKind::create_player,player_seed(crash_alice),"committed","","2");job(f.service,JobKind::create_player,player_seed(crash_bob,"Bob"),"committed","","3");
 job(f.service,JobKind::save_preferences,V::o({{"player_id",V::s(crash_alice)},{"expected_revision",V::s("1")},{"seed",seed_audio(UINT64_C(0x8000000000000000))},{"utc",V::s("2026-10-03T12:04:00Z")}}),"committed","","4");crash_pair(f.service);
 if(name.starts_with("interrupt_")){job(f.service,JobKind::begin_practice,begin_seed(crash_one,crash_alice),"committed","","5");job(f.service,JobKind::observe_practice,observe_seed(crash_one,crash_alice,"1"),"committed","","6");}
 if(name.starts_with("export_")||name.starts_with("delete_")){job(f.service,JobKind::begin_practice,begin_seed(crash_one,crash_alice),"committed","","5");job(f.service,JobKind::end_practice,end_seed(crash_one,crash_alice,"1"),"committed","","6");job(f.service,JobKind::begin_practice,begin_seed(crash_two,crash_alice,"synthetic-service-reference-2","0"),"committed","","7");job(f.service,JobKind::end_practice,end_seed(crash_two,crash_alice,"1","5","synthetic-service-reference-2"),"committed","","8");crash_history(f.service,true,false);}
 f.close();
}
// Metadata auditor deliberately does not use the production filesystem decoder.
// It compares each declared row to the actual ordinary original/copied file.
struct CrashSet {std::string leaf,id;bool work{},valid_intent{},complete{};std::uint64_t total{};CrashFile intent,manifest;std::array<CrashFile,4>data;};
void crash_identity_equal(DocumentView d,std::uint32_t node,const FileIdentity&id){require(closed(d,node,{"file_id_hex","volume_serial_hex"})==Error::none&&canonical(d,node)==crash_identity(id),"declared identity equals independently opened actual file");}
void crash_members(DocumentView d,std::uint32_t n,std::initializer_list<std::string_view> keys){require(closed(d,n,keys)==Error::none,"closed recovery metadata record");}
CrashSet crash_set(const std::string&root,const std::string&leaf,const std::array<CrashFile,4>&original,bool strict_original){
 CrashSet set;set.leaf=leaf;set.work=leaf.starts_with("work-");set.id=leaf.substr(set.work?5:9);const auto dir=root+"\\recovery\\"+leaf;
 set.intent=crash_file(dir+"\\intent.json",65536,true);set.manifest=crash_file(dir+"\\manifest.json",983040,true);crash_record_file(leaf+"/intent.json",set.intent);crash_record_file(leaf+"/manifest.json",set.manifest);set.total=set.intent.length+set.manifest.length;
 for(unsigned i=0;i<4;++i){set.data[i]=crash_file(dir+"\\"+std::string(crash_data_names[i]),crash_caps[i]);set.total+=set.data[i].length;crash_record_file(leaf+"/"+std::string(crash_data_names[i]),set.data[i]);}
 require(set.total<=353370112,"retained finite file-byte cap");
 // Missing/empty CreateNew intent is the deliberate intent-before-WRITE case.
 if(!set.intent.present||set.intent.length==0){require(!set.work&&!set.manifest.present,"missing intent is never complete/work authority");for(auto&f:set.data)require(!f.present,"early intent fixture contains no data copy");return set;}
 Raw intent(set.intent.bytes);auto d=intent.d;auto n=d.root;crash_members(d,n,{"format","version","id","created_utc","source_files"});require(field(d,n,"format")=="LocalPlayersRecoveryIntent"&&natural(d,member(d,n,"version"),1)==1&&field(d,n,"id")==set.id&&valid_utc(field(d,n,"created_utc")),"intent closed identity/version/UTC");auto declared=array(d,member(d,n,"source_files"));require(declared.size()==4,"four ordered intent roles");
 for(unsigned i=0;i<4;++i){auto row=declared[i];crash_members(d,row,{"role","name","present","bytes","source_identity"});require(field(d,row,"role")==crash_roles[i]&&field(d,row,"name")==crash_data_names[i],"ordered literal intent role/name");auto present=d.at(member(d,row,"present"));require(present&&present->kind==ValueKind::boolean&&present->scalar<=1,"intent actual BOOL");if(present->scalar){natural(d,member(d,row,"bytes"),crash_caps[i]);auto identity=member(d,row,"source_identity");crash_members(d,identity,{"file_id_hex","volume_serial_hex"});require(lower_hex(field(d,identity,"file_id_hex"),32)&&lower_hex(field(d,identity,"volume_serial_hex"),16),"closed declared source identity");}else require(nil(d,member(d,row,"bytes"))&&nil(d,member(d,row,"source_identity")),"absent intent null companions");
  if(!set.work&&strict_original){require(present->scalar==static_cast<unsigned>(original[i].present),"intent original roster exact");if(original[i].present){require(natural(d,member(d,row,"bytes"),crash_caps[i])==original[i].length,"intent actual original size");crash_identity_equal(d,member(d,row,"source_identity"),original[i].identity);}else require(nil(d,member(d,row,"bytes"))&&nil(d,member(d,row,"source_identity")),"absent original null companions");}
  else if(set.work){require(present->scalar==static_cast<unsigned>(set.data[i].present),"work copy roster exact");if(set.data[i].present)require(natural(d,member(d,row,"bytes"),crash_caps[i])==set.data[i].length,"work copied length exact");else require(nil(d,member(d,row,"bytes"))&&nil(d,member(d,row,"source_identity")),"absent work fields null");}
 }
 set.valid_intent=true;if(!set.manifest.present){if(set.work)for(unsigned i=0;i<4;++i)require(set.data[i].present==original[i].present&&set.data[i].length==original[i].length&&set.data[i].hash==original[i].hash,"pre-SQLite WORK complete byte-equal original set");return set;}
 require(!set.work,"work may not acquire final manifest");Raw manifest(set.manifest.bytes);d=manifest.d;n=d.root;crash_members(d,n,{"format","version","id","created_utc","intent_sha256","files"});require(field(d,n,"format")=="LocalPlayersRecoveryCopy"&&natural(d,member(d,n,"version"),1)==1&&field(d,n,"id")==set.id&&field(d,n,"created_utc")==field(intent.d,intent.d.root,"created_utc")&&field(d,n,"intent_sha256")==set.intent.hash,"manifest links exact entire actual intent");auto files=array(d,member(d,n,"files"));require(files.size()==4,"four ordered manifest rows");
 for(unsigned i=0;i<4;++i){auto row=files[i];crash_members(d,row,{"role","name","present","bytes","sha256","source_identity","copy_identity"});require(field(d,row,"role")==crash_roles[i]&&field(d,row,"name")==crash_data_names[i],"manifest literal ordered file role");auto present=d.at(member(d,row,"present"));require(present&&present->kind==ValueKind::boolean&&set.data[i].present==static_cast<bool>(present->scalar),"complete manifest exact copied roster");auto declared_row=declared[i];auto source_present=intent.d.at(member(intent.d,declared_row,"present"));require(source_present&&source_present->kind==ValueKind::boolean&&source_present->scalar==present->scalar,"manifest/intent roster equality");
  if(set.data[i].present){require(natural(d,member(d,row,"bytes"),crash_caps[i])==set.data[i].length&&natural(intent.d,member(intent.d,declared_row,"bytes"),crash_caps[i])==set.data[i].length&&field(d,row,"sha256")==set.data[i].hash,"whole copied counts/hash equal manifest and intent");require(canonical(d,member(d,row,"source_identity"))==canonical(intent.d,member(intent.d,declared_row,"source_identity")),"manifest source identity exact intent");crash_identity_equal(d,member(d,row,"copy_identity"),set.data[i].identity);if(strict_original)require(set.data[i].present==original[i].present&&set.data[i].length==original[i].length&&set.data[i].hash==original[i].hash,"whole pre-open copied source matches current original");}
  else for(auto key:{"bytes","sha256","source_identity","copy_identity"})require(nil(d,member(d,row,key)),"absent manifest four null companions");
 }set.complete=true;return set;
}
void crash_closed_set_names(const std::string&root,const CrashSet&set){
 FixedEnumerationOperand wildcard;require(wildcard.set(root+"\\recovery\\"+set.leaf,L"\\*"),"literal set wildcard");WIN32_FIND_DATAW data{};HANDLE find=FindFirstFileW(wildcard.value.data(),&data);require(find!=INVALID_HANDLE_VALUE,"actual set enumeration");bool good=true;std::size_t count=0;
 do{std::wstring_view name(data.cFileName);if(name==L"."||name==L"..")continue;FixedText<4096> utf;bool known=false;if(!utf8(name,utf)){good=false;break;}known=utf.view()=="intent.json"||utf.view()=="manifest.json";for(auto n:crash_data_names)known|=utf.view()==n;if(!known||(data.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT))||++count>6){good=false;break;}}while(FindNextFileW(find,&data));auto error=GetLastError();require(FindClose(find)!=0&&good&&error==ERROR_NO_MORE_FILES,"no unknown/aliased recovery entry");
}
std::vector<CrashSet> crash_sets(const std::string&root,const std::array<CrashFile,4>&original,bool strict_original=false){std::vector<CrashSet>sets;for(const auto&leaf:crash_directories(root)){auto set=crash_set(root,leaf,original,strict_original);crash_closed_set_names(root,set);sets.push_back(std::move(set));}return sets;}
std::string crash_list(Service*s,const std::vector<CrashSet>&sets){
 Capture c(JobKind::list_recovery,V::o({}));auto a=s->submit(c);require(a.accepted&&a.error==Error::none,"real list recovery admitted");auto replies=receive(s,1);Raw r(replies[0]);auto n=r.d.root;crash_members(r.d,n,{"request_id","kind","state","error_code","commit_sequence","value"});require(field(r.d,n,"request_id")==a.request_id.view()&&field(r.d,n,"kind")=="list_recovery"&&field(r.d,n,"state")=="read"&&field(r.d,n,"error_code").empty()&&nil(r.d,member(r.d,n,"commit_sequence")),"closed actual recovery read terminal");auto v=value(r);crash_members(r.d,v,{"snapshots"});auto rows=array(r.d,member(r.d,v,"snapshots"));std::size_t retained=static_cast<std::size_t>(std::count_if(sets.begin(),sets.end(),[](const CrashSet&s){return !s.work;}));require(rows.size()==retained&&retained<=2,"complete finite retained-ID list");for(const auto&set:sets)if(!set.work)require(std::count_if(rows.begin(),rows.end(),[&](auto row){return field(r.d,row,"id")==set.id;})==1,"each independently observed retained ID returned exactly once");
 for(auto row:rows){crash_members(r.d,row,{"id","state","created_utc","bytes","manifest_sha256"});auto id=field(r.d,row,"id");auto set=std::find_if(sets.begin(),sets.end(),[&](const CrashSet&s){return !s.work&&s.id==id;});require(set!=sets.end()&&field(r.d,row,"state")==std::string(set->complete?"complete":"partial")&&natural(r.d,member(r.d,row,"bytes"),353370112)==set->total,"summary equals independently observed retained set only");if(set->valid_intent){Raw intent(set->intent.bytes);require(field(r.d,row,"created_utc")==field(intent.d,intent.d.root,"created_utc"),"actual valid intent UTC");}else require(nil(r.d,member(r.d,row,"created_utc")),"invalid empty intent UTC is null");if(set->complete)require(field(r.d,row,"manifest_sha256")==set->manifest.hash,"whole observed manifest hash");else require(nil(r.d,member(r.d,row,"manifest_sha256")),"partial never promoted to complete hash");}
 return replies[0];
}
void crash_delete(Service*s,const std::vector<CrashSet>&sets,const std::string&root,bool denied=false){std::vector<V>ids;for(const auto&set:sets)if(!set.work)ids.push_back(V::s(set.id));auto row=job(s,JobKind::delete_recovery,V::o({{"snapshot_ids",V::a(std::move(ids))}}),denied?"failed":"read",denied?"snapshot_failed":"");Raw r(row);if(denied){for(const auto&set:sets){auto intent=crash_file(root+"\\recovery\\"+set.leaf+"\\intent.json",65536);require(intent.present==set.intent.present&&intent.hash==set.intent.hash&&same_identity(intent.identity,set.intent.identity),"unowned/invalid intent is never guessed deletable");}return;}auto v=value(r);auto removed=array(r.d,member(r.d,v,"deleted_ids"));require(array(r.d,member(r.d,v,"retained_ids")).empty()&&removed.size()==static_cast<std::size_t>(std::count_if(sets.begin(),sets.end(),[](const CrashSet&s){return !s.work;})),"actual deleted/retained partition");for(const auto&set:sets)if(!set.work)require(std::count_if(removed.begin(),removed.end(),[&](auto id){return text(r.d,id)==set.id;})==1,"each requested retained ID reported deleted exactly once");for(auto id:removed)require(std::any_of(sets.begin(),sets.end(),[&](const CrashSet&s){return !s.work&&s.id==text(r.d,id);}),"every deleted ID requested");require(crash_directories(root).empty(),"BOTH retained and associated WORK actually absent");}
// Actual sharing-denied retained deletion, independent of production decoders.
// Reuse the already authenticated work_before_sqlite fixture and owner: no new
// process, root, service ordinal, SQLite connection or fault-injection event.
void crash_unchanged_file(const CrashFile&actual,const CrashFile&expected){
 require(actual.present==expected.present,"management preserves exact file presence");
 if(expected.present)require(actual.length==expected.length&&actual.hash==expected.hash&&actual.bytes==expected.bytes&&same_identity(actual.identity,expected.identity),"management preserves entire actual bytes/hash/ordinary identity");
}
FileIdentity crash_directory_identity(const std::string&path){
 auto wide=std::make_unique<Wide>();require(wide->set(path)&&ordinary_ancestors(*wide),"owned recovery directory canonical ordinary ancestors");
 auto operand=std::make_unique<ExtendedFileOperand>(*wide);
 Handle h(CreateFileW(operand->value.data(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
 FileIdentity identity;require(h.good()&&observe_identity(h.value,true,identity)&&final_equal(h.value,*wide),"actual owned recovery directory identity");require(h.close(),"checked recovery directory observation close");return identity;
}
void crash_hold_delete_denial(const std::string&path,const CrashFile&expected,Handle&blocker){
 require(open_ordinary(path,blocker,GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE),"hold actual owned recovery file without delete sharing");
 FileIdentity identity;require(observe_identity(blocker.value,false,identity)&&same_identity(identity,expected.identity),"blocking handle pins exact independently audited file");
 auto wide=std::make_unique<Wide>();require(wide->set(path),"fixed owned denial operand");auto operand=std::make_unique<ExtendedFileOperand>(*wide);
 Handle denied(CreateFileW(operand->value.data(),DELETE|FILE_READ_ATTRIBUTES,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
 const DWORD error=GetLastError();const bool opened=denied.good();require(denied.close(),"checked denial-probe handle close");
 require(!opened&&error==ERROR_SHARING_VIOLATION,"actual Win32 DWORD32 denies production-equivalent DELETE open");
}
void crash_delete_sharing_retry(Service*s,Probe&p,const std::vector<CrashSet>&sets,const std::string&root,const std::array<CrashFile,4>&original){
 require(sets.size()==2,"sharing retry uses exactly one retained and one WORK");
 const auto retained=std::find_if(sets.begin(),sets.end(),[](const CrashSet&set){return !set.work;});
 const auto work=std::find_if(sets.begin(),sets.end(),[](const CrashSet&set){return set.work;});
 require(retained!=sets.end()&&work!=sets.end()&&retained->complete&&retained->valid_intent&&work->valid_intent&&work->id==retained->id&&!work->manifest.present&&retained->data[0].present,"predeclared complete retained/linked WORK deletion premise");
 const auto retained_path=root+"\\recovery\\"+retained->leaf,work_path=root+"\\recovery\\"+work->leaf;
 const auto retained_identity=crash_directory_identity(retained_path),work_identity=crash_directory_identity(work_path);
 const auto manifest_path=retained_path+"\\manifest.json";
 Handle work_blocker,blocker;
 require(work->data[0].present,"linked WORK first data file actually present");
 crash_hold_delete_denial(work_path+"\\players.sqlite3",work->data[0],work_blocker);
 crash_hold_delete_denial(manifest_path,retained->manifest,blocker);
 crash_no_sqlite(p);
 Raw work_denied(job(s,JobKind::delete_recovery,V::o({{"snapshot_ids",V::a({V::s(retained->id)})}}),"failed","snapshot_failed"));
 require(nil(work_denied.d,member(work_denied.d,work_denied.d.root,"value")),"WORK-first denial before any actual delete reports null, no invented partition");
 std::vector<std::string> expected_leaves{retained->leaf,work->leaf};std::sort(expected_leaves.begin(),expected_leaves.end());
 require(crash_directories(root)==expected_leaves&&same_identity(crash_directory_identity(retained_path),retained_identity)&&same_identity(crash_directory_identity(work_path),work_identity),"held WORK failure preserves BOTH exact directory identities and closed roster");
 for(const auto*set:{&*retained,&*work}){
  const auto directory=root+"\\recovery\\"+set->leaf;
  crash_unchanged_file(crash_file(directory+"\\intent.json",65536,true),set->intent);
  crash_unchanged_file(crash_file(directory+"\\manifest.json",983040,true),set->manifest);
  for(unsigned i=0;i<4;++i)crash_unchanged_file(crash_file(directory+"\\"+std::string(crash_data_names[i]),crash_caps[i]),set->data[i]);
  crash_closed_set_names(root,*set);
 }
 auto after_work_denial=crash_original(root);for(unsigned i=0;i<4;++i)crash_unchanged_file(after_work_denial[i],original[i]);
 crash_no_sqlite(p);require(work_blocker.close(),"explicitly release held WORK before same-ID retry");
 crash_no_sqlite(p);
 Raw failed(job(s,JobKind::delete_recovery,V::o({{"snapshot_ids",V::a({V::s(retained->id)})}}),"failed","snapshot_failed"));
 auto v=value(failed);crash_members(failed.d,v,{"deleted_ids","retained_ids"});
 auto deleted=array(failed.d,member(failed.d,v,"deleted_ids")),kept=array(failed.d,member(failed.d,v,"retained_ids"));
 require(deleted.empty()&&kept.size()==1&&text(failed.d,kept[0])==retained->id,"failed deletion reports exact empty-deleted/one-retained partition");
 require(crash_directories(root)==std::vector<std::string>{retained->leaf},"partial retained manifest failure leaves retained directory only; linked WORK already absent");
 require(same_identity(crash_directory_identity(retained_path),retained_identity),"mid-delete failure retains exact retained directory identity");
 // WORK is removed first so a failed WORK delete cannot orphan it by removing
 // its retained ownership metadata. Within retained: data, manifest, intent,
 // directory. The held manifest leaves a retryable, truthfully retained ID.
 for(unsigned i=0;i<4;++i)require(!crash_file(retained_path+"\\"+std::string(crash_data_names[i]),crash_caps[i]).present,"actual retained data absent after mid-delete failure");
 crash_unchanged_file(crash_file(manifest_path,983040,true),retained->manifest);
 crash_unchanged_file(crash_file(retained_path+"\\intent.json",65536,true),retained->intent);
 crash_closed_set_names(root,*retained);
 auto after_denial=crash_original(root);for(unsigned i=0;i<4;++i)crash_unchanged_file(after_denial[i],original[i]);
 FileIdentity held_identity;require(observe_identity(blocker.value,false,held_identity)&&same_identity(held_identity,retained->manifest.identity),"denial handle remains same live manifest through failed request");
 crash_no_sqlite(p);require(blocker.close(),"explicitly release real sharing denial before retry");
 // Accepted partial-set ownership must allow this explicit same-ID retry;
 // neither remaining linked WORK nor a stale complete manifest is success.
 crash_delete(s,sets,root);
 auto after_retry=crash_original(root);for(unsigned i=0;i<4;++i)crash_unchanged_file(after_retry[i],original[i]);
 crash_no_sqlite(p);
}
std::uint32_t crash_word(const std::string&b,std::size_t at,bool big=true){require(at+4<=b.size(),"bounded independent header word");std::uint32_t n=0;for(unsigned i=0;i<4;++i){auto x=static_cast<unsigned char>(b[at+i]);if(big)n=(n<<8)|x;else n|=static_cast<std::uint32_t>(x)<<(8*i);}return n;}
void crash_wal_schema(const std::array<CrashFile,4>&files){
 // Independent scalar implementation, no SQLite API. Pinned SQLite amalgamate
 // WAL_MAGIC/format and walChecksumBytes/walDecodeFrame are provenance only.
 const auto&main=files[0].bytes;const auto&wal=files[1].bytes;require(files[0].present&&files[1].present&&main.size()>=100&&wal.size()>=32,"actual main plus WAL required, no skipped witness");auto magic=crash_word(wal,0);require((magic&0xfffffffeU)==0x377f0682U&&crash_word(wal,4)==3007000&&crash_word(wal,8)==4096,"pinned WAL format/page size");bool big=(magic&1)!=0;std::uint32_t s0=0,s1=0;
 auto sum=[&](std::size_t start,std::size_t length){require((length%8)==0&&start+length<=wal.size(),"checksum complete word pairs");for(std::size_t i=start;i<start+length;i+=8){s0+=crash_word(wal,i,big)+s1;s1+=crash_word(wal,i+4,big)+s0;}};sum(0,24);require(s0==crash_word(wal,24)&&s1==crash_word(wal,28),"actual WAL header checksum");require((wal.size()-32)%4120==0,"complete actual WAL frames");std::size_t pending_page1=0,committed_page1=0,commits=0;
 for(std::size_t at=32;at<wal.size();at+=4120){require(crash_word(wal,at)>0&&wal.compare(at+8,8,wal,16,8)==0,"frame positive page and header salts");sum(at,8);sum(at+24,4096);require(s0==crash_word(wal,at+16)&&s1==crash_word(wal,at+20),"every actual WAL frame checksum");if(crash_word(wal,at)==1)pending_page1=at+24;if(crash_word(wal,at+4)){++commits;committed_page1=pending_page1;}}
 require(commits>0&&committed_page1>0,"page1 belongs to actual committed WAL prefix");require(main.compare(0,16,"SQLite format 3\0",16)==0&&wal.compare(committed_page1,16,"SQLite format 3\0",16)==0,"both actual SQLite page1 signatures");auto old_cookie=crash_word(main,40),new_cookie=crash_word(wal,committed_page1+40);require(old_cookie==0&&new_cookie!=0,"stale main schema cookie0/new committed page1 cookie");crash_observations.push_back("{\"kind\":\"wal_schema\",\"frames\":"+std::to_string((wal.size()-32)/4120)+",\"commits\":"+std::to_string(commits)+",\"main_schema_cookie\":"+std::to_string(old_cookie)+",\"committed_schema_cookie\":"+std::to_string(new_cookie)+"}");
}
void crash_partial_prefix(const std::string&root,const CrashSet&set,const std::array<CrashFile,4>&original,bool after_write){
 require(set.valid_intent&&!set.complete&&!set.work&&!set.manifest.present&&set.data[0].present,"valid intent/incomplete retained data set");for(unsigned i=1;i<4;++i)require(!set.data[i].present,"only first copied main created");auto copied=crash_file(root+"\\recovery\\"+set.leaf+"\\players.sqlite3",65536,true);require(copied.length==(after_write?std::min<std::uint64_t>(original[0].length,65536):0),"exact first call copy length");if(after_write){auto main=crash_file(root+"\\players.sqlite3",crash_caps[0],true);require(copied.bytes==main.bytes.substr(0,copied.bytes.size()),"copied bytes equal actual original prefix");}
}
void crash_export_observed(const std::string&parent,const std::string&target,std::string_view name){
 auto expected=crash_export_bytes();auto installed=crash_file(target,33554432,true);crash_record_file("export/target",installed);FixedEnumerationOperand pattern;require(pattern.set(parent,L"\\.fsplayers-*.tmp"),"literal export temp wildcard");WIN32_FIND_DATAW data{};HANDLE find=FindFirstFileW(pattern.value.data(),&data);std::vector<std::string>names;if(find==INVALID_HANDLE_VALUE)require(GetLastError()==ERROR_FILE_NOT_FOUND,"actual no matching temporary");else{bool valid=true;do{std::wstring_view w(data.cFileName);FixedText<4096> file;if(!utf8(w,file)){valid=false;break;}auto s=file.view();if(s.size()!=47||!s.starts_with(".fsplayers-")||!s.ends_with(".tmp")||!lower_hex(s.substr(11,32),32)||(data.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT))||names.size()>=1){valid=false;break;}names.emplace_back(s);}while(FindNextFileW(find,&data));auto error=GetLastError();require(FindClose(find)!=0&&valid&&error==ERROR_NO_MORE_FILES,"exact isolated owned-export temporary roster");}
 if(name=="export_after_move"){require(installed.present&&installed.bytes==expected&&installed.hash==digest_text(expected)&&names.empty(),"actual installed entire canonical export, temp absent");}
 else{require(!installed.present&&names.size()==1,"pre-move target absent/exact one owned temp");auto temp=crash_file(parent+"\\"+names[0],33554432,true);crash_record_file("export/"+names[0],temp);require(temp.present&&temp.bytes==expected&&temp.hash==digest_text(expected),"small fixed export first write/flush whole exact canonical bytes");}
 // Small fixed export fits one65536-byte call. No partial-return or durability
 // claim is inferred: Root independently validates selected successful details.
 require(expected.size()<65536,"frozen small export full-first-call premise");
}
void crash_work_link(const std::vector<CrashSet>&sets){
 for(const auto&work:sets)if(work.work){auto retained=std::find_if(sets.begin(),sets.end(),[&](const CrashSet&s){return !s.work&&s.id==work.id;});require(retained!=sets.end()&&retained->complete&&work.valid_intent&&!work.manifest.present,"WORK linked to one actual complete retained set");Raw intent(work.intent.bytes);auto rows=array(intent.d,member(intent.d,intent.d.root,"source_files"));for(unsigned i=0;i<4;++i)if(retained->data[i].present)crash_identity_equal(intent.d,member(intent.d,rows[i],"source_identity"),retained->data[i].identity);}
}
void crash_retained_shape(const std::vector<CrashSet>&sets,std::size_t retained,std::size_t work){require(std::count_if(sets.begin(),sets.end(),[](const CrashSet&s){return !s.work;})==static_cast<std::ptrdiff_t>(retained)&&sets.size()==retained+work,"exact retained/work directory counts");}
// Frozen accepted D01/SQL_exact projections, extracted independently before runtime.
constexpr std::string_view full_fixture_inserts[]={
R"LPFIX(INSERT INTO meta(singleton,schema_version,schema_fingerprint,codec_fingerprint,store_id,owner_run_id,created_utc,commit_sequence) VALUES(1,1,'cbd00b3fe47b400e79635ed901d195abfe133a4131d5001feac8e3eedeb0562f','47711d41be89e233efe3c42e8f2cedd33f729e6e0e2c9a78a6026454022b0538','77777777777777777777777777777777','88888888888888888888888888888888','2026-10-11T06:00:00Z','12');)LPFIX",
R"LPFIX(INSERT INTO players(commit_sequence,id,revision,record,record_sha256) VALUES('3','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','3',X'7b22637265617465645f757463223a22323030302d30322d32395430303a30303a30305a222c226964223a226161616161616161616161616161616161616161616161616161616161616161222c226e616d65223a22416e61205c22ce945c22205c5c20e9a39be8a18c222c227265766973696f6e223a2233222c2274797065223a224c6f63616c506c61796572222c22757064617465645f757463223a22323032362d31302d31315430363a30303a30305a222c2276657273696f6e223a317d','d57f15f328b0142c3ad6c9a7d0962577ab54431512b7d606d9b5aa275926e82d');)LPFIX",
R"LPFIX(INSERT INTO players(commit_sequence,id,revision,record,record_sha256) VALUES('3','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','1',X'7b22637265617465645f757463223a22323030302d30322d32395430303a30303a30305a222c226964223a226262626262626262626262626262626262626262626262626262626262626262222c226e616d65223a22416e61205c22ce945c22205c5c20e9a39be8a18c222c227265766973696f6e223a2231222c2274797065223a224c6f63616c506c61796572222c22757064617465645f757463223a22323032362d31302d31315430363a30303a30305a222c2276657273696f6e223a317d','fb39dc7307e3070a4445cb10a731b92d5a1f2c55483848aba471a5104d4a5e80');)LPFIX",
R"LPFIX(INSERT INTO preferences(player_id,revision,record,record_sha256) VALUES('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','3',X'7b22666f726d6174223a224c6f63616c506c61796572507265666572656e636573222c227061796c6f61645f6a736f6e223a227b5c22617564696f5c223a7b5c22616972666c6f775f6761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c22656e61626c65645c223a747275652c5c22656e67696e655f6761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c2273686f775f70616e656c5f63617074696f6e735c223a66616c73657d2c5c226c65676163795f696e7075745c223a7b5c22616374696f6e735c223a5b7b5c2269645c223a5c22726563656e7465725c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b38325d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d2c7b5c2269645c223a5c226c6f6f6b5f686f6c645c222c5c22736f75726365735c223a5b7b5c22627574746f6e5c223a322c5c226b696e645c223a5c226d6f7573655f627574746f6e5c227d5d7d2c7b5c2269645c223a5c22766965775f6379636c655c222c5c22736f75726365735c223a5b7b5c22696e6465785c223a3132372c5c226b696e645c223a5c226a6f795f627574746f6e5c222c5c22736c6f745c223a5c22737469636b2d415c227d5d7d5d2c5c22617865735c223a5b7b5c226761696e5c223a312c5c226b696e645c223a5c226b65795f706169725c222c5c226e656761746976655c223a5b36355d2c5c22706f7369746976655c223a5b36385d2c5c22726174655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030313034305c227d2c5c2272657475726e5f746f5f73746172745c223a747275652c5c227461726765745c223a5c22726f6c6c5c227d2c7b5c2263656e7465725c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c22646561647a6f6e655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c22696e6465785c223a302c5c22696e766572745c223a66616c73652c5c226b696e645c223a5c226a6f795f617869735c222c5c226d6178696d756d5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c226d696e696d756d5c223a2d312c5c2272616e67655c223a5c2263656e74657265645c222c5c2273617475726174696f6e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c22736c65775f7065725f735c223a342c5c22736c6f745c223a5c22737469636b2d415c222c5c227461726765745c223a5c2270697463685c227d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c227961775c222c5c2276616c75655c223a2d317d2c7b5c2263656e7465725c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c22646561647a6f6e655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c22696e6465785c223a312c5c22696e766572745c223a66616c73652c5c226b696e645c223a5c226a6f795f617869735c222c5c226d6178696d756d5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c226d696e696d756d5c223a302c5c2272616e67655c223a5c22756e7369676e65645c222c5c2273617475726174696f6e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c22736c65775f7065725f735c223a342c5c22736c6f745c223a5c22737469636b2d415c222c5c227461726765745c223a5c227468726f74746c655c227d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c226d6978747572655c222c5c2276616c75655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d7d2c7b5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c226b696e645c223a5c226b65795f706169725c222c5c226e656761746976655c223a5b37345d2c5c22706f7369746976655c223a5b37355d2c5c22726174655c223a312c5c2272657475726e5f746f5f73746172745c223a66616c73652c5c227461726765745c223a5c226c6566745f6272616b655c227d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c2272696768745f6272616b655c222c5c2276616c75655c223a307d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c227472696d5c222c5c2276616c75655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d7d5d2c5c22646576696365735c223a5b7b5c226c6162656c5c223a5c22596f6b6520ce945c222c5c226d617463685c223a7b5c22677569645c223a5c22666978747572652d677569645c222c5c226e616d655c223a5c2246697874757265206465766963655c5c7530303039e9a39be8a18c5c222c5c2270726f647563745f69645c223a5c22303061625c222c5c2276656e646f725f69645c223a5c22303132335c227d2c5c22736c6f745c223a5c22737469636b2d415c227d5d2c5c226e616d655c223a5c224f726967696e616c205c5c5c22ce945c5c5c22205c5c5c5c20e9a39be8a18c5c222c5c22747970655c223a5c22496e7075745072657365745c222c5c2276657273696f6e5c223a317d2c5c22706973746f6e5f696e7075745c223a7b5c22616374696f6e735c223a5b7b5c2269645c223a5c22726563656e7465725c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b38325d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d2c7b5c2269645c223a5c226c6f6f6b5f686f6c645c222c5c22736f75726365735c223a5b7b5c22627574746f6e5c223a322c5c226b696e645c223a5c226d6f7573655f627574746f6e5c227d5d7d2c7b5c2269645c223a5c22766965775f6379636c655c222c5c22736f75726365735c223a5b7b5c22696e6465785c223a3132372c5c226b696e645c223a5c226a6f795f627574746f6e5c222c5c22736c6f745c223a5c22737469636b2d415c227d5d7d5d2c5c22617865735c223a5b7b5c226761696e5c223a312c5c226b696e645c223a5c226b65795f706169725c222c5c226e656761746976655c223a5b36355d2c5c22706f7369746976655c223a5b36385d2c5c22726174655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030313034305c227d2c5c2272657475726e5f746f5f73746172745c223a747275652c5c227461726765745c223a5c22726f6c6c5c227d2c7b5c2263656e7465725c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c22646561647a6f6e655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c22696e6465785c223a302c5c22696e766572745c223a66616c73652c5c226b696e645c223a5c226a6f795f617869735c222c5c226d6178696d756d5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c226d696e696d756d5c223a2d312c5c2272616e67655c223a5c2263656e74657265645c222c5c2273617475726174696f6e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c22736c65775f7065725f735c223a342c5c22736c6f745c223a5c22737469636b2d415c222c5c227461726765745c223a5c2270697463685c227d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c227961775c222c5c2276616c75655c223a2d317d2c7b5c2263656e7465725c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c22646561647a6f6e655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c22696e6465785c223a312c5c22696e766572745c223a66616c73652c5c226b696e645c223a5c226a6f795f617869735c222c5c226d6178696d756d5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c226d696e696d756d5c223a302c5c2272616e67655c223a5c22756e7369676e65645c222c5c2273617475726174696f6e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c22736c65775f7065725f735c223a342c5c22736c6f745c223a5c22737469636b2d415c222c5c227461726765745c223a5c227468726f74746c655c227d2c7b5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c226b696e645c223a5c226b65795f706169725c222c5c226e656761746976655c223a5b37375d2c5c22706f7369746976655c223a5b37385d2c5c22726174655c223a7b5c222462696e61727936345f6c655c223a5c22303130303030303030303030303030305c227d2c5c2272657475726e5f746f5f73746172745c223a66616c73652c5c227461726765745c223a5c226d6978747572655c227d2c7b5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c226b696e645c223a5c226b65795f706169725c222c5c226e656761746976655c223a5b37345d2c5c22706f7369746976655c223a5b37355d2c5c22726174655c223a312c5c2272657475726e5f746f5f73746172745c223a66616c73652c5c227461726765745c223a5c226c6566745f6272616b655c227d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c2272696768745f6272616b655c222c5c2276616c75655c223a307d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c227472696d5c222c5c2276616c75655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d7d5d2c5c226361706162696c6974795f7265766973696f6e5c223a5c22706973746f6e2d636f6e74726f6c732d76315c222c5c22646576696365735c223a5b7b5c226c6162656c5c223a5c22596f6b6520ce945c222c5c226d617463685c223a7b5c22677569645c223a5c22666978747572652d677569645c222c5c226e616d655c223a5c2246697874757265206465766963655c5c7530303039e9a39be8a18c5c222c5c2270726f647563745f69645c223a5c22303061625c222c5c2276656e646f725f69645c223a5c22303132335c227d2c5c22736c6f745c223a5c22737469636b2d415c227d5d2c5c226e616d655c223a5c224f726967696e616c205c5c5c22ce945c5c5c22205c5c5c5c20e9a39be8a18c5c222c5c2270726f66696c655c223a7b5c226261636b656e645f6d6f64656c5c223a5c226f726967696e616c2d706973746f6e2d70726f705c222c5c2269645c223a5c226f726967696e616c2d706973746f6e2d70726f702d76315c222c5c2276657273696f6e5c223a5c22302e312e302d70726f746f747970655c227d2c5c2273797374656d735c223a5b7b5c2269645c223a5c22656e67696e652e69676e6974696f6e5f6c6566745c222c5c226b696e645c223a5c22746f67676c655c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b37335d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d2c7b5c2269645c223a5c22656e67696e652e69676e6974696f6e5f72696768745c222c5c226b696e645c223a5c22746f67676c655c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b37395d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d2c7b5c2269645c223a5c22656e67696e652e737461727465725c222c5c226b696e645c223a5c226d6f6d656e746172795c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b38335d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d2c7b5c2269645c223a5c226675656c2e666565645c222c5c226b696e645c223a5c22746f67676c655c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b37305d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d5d2c5c22747970655c223a5c22496e7075745072657365745c222c5c2276657273696f6e5c223a327d2c5c22706c617965725f69645c223a5c2261616161616161616161616161616161616161616161616161616161616161615c222c5c227265766973696f6e5c223a5c22335c222c5c22747970655c223a5c224c6f63616c506c61796572507265666572656e6365735c222c5c2276657273696f6e5c223a317d222c227061796c6f61645f736861323536223a2237366231393732383138323437313962353737663965623336316333623938623261656366613666346139373638363538656164326333656363373231363861222c2276657273696f6e223a317d','2571fbaf91a77f23aab9ac00e9707a02943ce9b84b3eef541a9f8b0aba480a24');)LPFIX",
R"LPFIX(INSERT INTO preferences(player_id,revision,record,record_sha256) VALUES('bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','1',X'7b22666f726d6174223a224c6f63616c506c61796572507265666572656e636573222c227061796c6f61645f6a736f6e223a227b5c22617564696f5c223a7b5c22616972666c6f775f6761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c22656e61626c65645c223a747275652c5c22656e67696e655f6761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c2273686f775f70616e656c5f63617074696f6e735c223a66616c73657d2c5c226c65676163795f696e7075745c223a6e756c6c2c5c22706973746f6e5f696e7075745c223a6e756c6c2c5c22706c617965725f69645c223a5c2262626262626262626262626262626262626262626262626262626262626262625c222c5c227265766973696f6e5c223a5c22315c222c5c22747970655c223a5c224c6f63616c506c61796572507265666572656e6365735c222c5c2276657273696f6e5c223a317d222c227061796c6f61645f736861323536223a2234323962333261343363663938646634653832396634363138626435303834323632333963633032616337653836633165633665313364363439373632643531222c2276657273696f6e223a317d','0d11040fd38cf4b7a4aa76487ffb82f5ab5d8a12ca20ef3f99e40292abc5cbfc');)LPFIX",
R"LPFIX(INSERT INTO practices(id,player_id,creation_sequence,commit_sequence,revision,status,source_fingerprint,source_session,record,record_sha256) VALUES('11111111111111111111111111111111','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','9','12','2','manually_ended','4444444444444444444444444444444444444444444444444444444444444444','fixture-session',X'7b2261726368697665223a7b226162736f6c7574655f70617468223a22433a2f666978747572652d6f6e6c792fce942f7265766965772e6a736f6e222c2266697273745f7469636b223a2239303037313939323534373431303030222c226c6173745f7469636b223a2239303037313939323534373431313030222c226c696e6b65645f757463223a22323032362d31302d31315430363a30303a30305a222c227061796c6f61645f736861323536223a2236363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636363636222c227265636f7264696e675f73657373696f6e5f6964223a22666978747572652d73657373696f6e222c2274797065223a2245787465726e616c5265636f72646564526576696577222c2276657273696f6e223a317d2c22636f6d6d69745f73657175656e6365223a223132222c226372656174696f6e5f73657175656e6365223a2239222c22656e645f726561736f6e223a22757365725f656e64222c2266697273745f7469636b223a2239303037313939323534373430393933222c226964223a223131313131313131313131313131313131313131313131313131313131313131222c226c6173745f6f627365727665645f757463223a22323032362d31302d31315430353a35393a35395a222c226c6173745f7469636b223a2239303037313939323534373431313133222c226f627365727665645f7469636b73223a22313230222c22706c617965725f6964223a226161616161616161616161616161616161616161616161616161616161616161222c227265766973696f6e223a2232222c22736f75726365223a7b22616e67756c61725f696e746567726174696f6e5f6d6574686f64223a6e756c6c2c226d6f64656c5f6964656e74697479223a7b226261636b656e645f6d6f64656c223a226f726967696e616c2d696e746572616374697665222c226964223a226f726967696e616c2d696e7465726163746976652d70726f746f74797065222c2276657273696f6e223a22302e312e302d70726f746f74797065227d2c226e616d65645f7374617274223a22616972626f726e652d7072657061726564222c226e61746976655f736f757263655f66696e6765727072696e74223a2234343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434222c2270726570617265645f776f726c645f736861323536223a2235353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535222c2273657373696f6e5f6964223a22666978747572652d73657373696f6e222c22736f757263655f76617269616e74223a226a736273696d2d312e332e312d6576656e742d61776172652d636f75706c65642d6d6964706f696e742d6c6f63616c2d77696e646f772d7632222c2277696e645f70726f66696c65223a2266726f6d2d77657374227d2c22737461727465645f757463223a22323032362d31302d31315430363a30303a30305a222c22737461747573223a226d616e75616c6c795f656e646564222c227469636b5f726174655f687a223a3132302c2274797065223a224c6f63616c5072616374696365222c2276657273696f6e223a317d','144a7fec11464329de1799ad0e427e59dae2d1ec00eb58fd05b5b132952cbdab');)LPFIX",
R"LPFIX(INSERT INTO practices(id,player_id,creation_sequence,commit_sequence,revision,status,source_fingerprint,source_session,record,record_sha256) VALUES('22222222222222222222222222222222','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','10','11','2','manually_ended','4444444444444444444444444444444444444444444444444444444444444444','fixture-session-two',X'7b2261726368697665223a6e756c6c2c22636f6d6d69745f73657175656e6365223a223131222c226372656174696f6e5f73657175656e6365223a223130222c22656e645f726561736f6e223a22757365725f656e64222c2266697273745f7469636b223a2239303037313939323534373430393933222c226964223a223232323232323232323232323232323232323232323232323232323232323232222c226c6173745f6f627365727665645f757463223a22323032362d31302d31315430353a35393a35395a222c226c6173745f7469636b223a2239303037313939323534373431313133222c226f627365727665645f7469636b73223a22313230222c22706c617965725f6964223a226161616161616161616161616161616161616161616161616161616161616161222c227265766973696f6e223a2232222c22736f75726365223a7b22616e67756c61725f696e746567726174696f6e5f6d6574686f64223a6e756c6c2c226d6f64656c5f6964656e74697479223a7b226261636b656e645f6d6f64656c223a226f726967696e616c2d696e746572616374697665222c226964223a226f726967696e616c2d696e7465726163746976652d70726f746f74797065222c2276657273696f6e223a22302e312e302d70726f746f74797065227d2c226e616d65645f7374617274223a22616972626f726e652d7072657061726564222c226e61746976655f736f757263655f66696e6765727072696e74223a2234343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434222c2270726570617265645f776f726c645f736861323536223a2235353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535222c2273657373696f6e5f6964223a22666978747572652d73657373696f6e2d74776f222c22736f757263655f76617269616e74223a226a736273696d2d312e332e312d6576656e742d61776172652d636f75706c65642d6d6964706f696e742d6c6f63616c2d77696e646f772d7632222c2277696e645f70726f66696c65223a2266726f6d2d77657374227d2c22737461727465645f757463223a22323032362d31302d31315430363a30303a30305a222c22737461747573223a226d616e75616c6c795f656e646564222c227469636b5f726174655f687a223a3132302c2274797065223a224c6f63616c5072616374696365222c2276657273696f6e223a317d','1bc5f709e28064647d75ff9f8817ed0cfd4e78639e0ee8b536235ee2b2c7630a');)LPFIX",
R"LPFIX(INSERT INTO practices(id,player_id,creation_sequence,commit_sequence,revision,status,source_fingerprint,source_session,record,record_sha256) VALUES('33333333333333333333333333333333','bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb','8','8','2','manually_ended','4444444444444444444444444444444444444444444444444444444444444444','other-player-session',X'7b2261726368697665223a6e756c6c2c22636f6d6d69745f73657175656e6365223a2238222c226372656174696f6e5f73657175656e6365223a2238222c22656e645f726561736f6e223a22757365725f656e64222c2266697273745f7469636b223a2239303037313939323534373430393933222c226964223a223333333333333333333333333333333333333333333333333333333333333333222c226c6173745f6f627365727665645f757463223a22323032362d31302d31315430353a35393a35395a222c226c6173745f7469636b223a2239303037313939323534373431313133222c226f627365727665645f7469636b73223a22313230222c22706c617965725f6964223a226262626262626262626262626262626262626262626262626262626262626262222c227265766973696f6e223a2232222c22736f75726365223a7b22616e67756c61725f696e746567726174696f6e5f6d6574686f64223a6e756c6c2c226d6f64656c5f6964656e74697479223a7b226261636b656e645f6d6f64656c223a226f726967696e616c2d696e746572616374697665222c226964223a226f726967696e616c2d696e7465726163746976652d70726f746f74797065222c2276657273696f6e223a22302e312e302d70726f746f74797065227d2c226e616d65645f7374617274223a22616972626f726e652d7072657061726564222c226e61746976655f736f757263655f66696e6765727072696e74223a2234343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434343434222c2270726570617265645f776f726c645f736861323536223a2235353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535353535222c2273657373696f6e5f6964223a226f746865722d706c617965722d73657373696f6e222c22736f757263655f76617269616e74223a226a736273696d2d312e332e312d6576656e742d61776172652d636f75706c65642d6d6964706f696e742d6c6f63616c2d77696e646f772d7632222c2277696e645f70726f66696c65223a2266726f6d2d77657374227d2c22737461727465645f757463223a22323032362d31302d31315430363a30303a30305a222c22737461747573223a226d616e75616c6c795f656e646564222c227469636b5f726174655f687a223a3132302c2274797065223a224c6f63616c5072616374696365222c2276657273696f6e223a317d','0d61262c2c0f8c720585e8af601e3d7eae407e562ac35f7222ae6f5667ccdc3f');)LPFIX"
};
struct FullFixtureSchema {std::string_view name,sql;};
constexpr FullFixtureSchema full_fixture_schema[]={
{R"LPFIX(meta)LPFIX",R"LPFIX(CREATE TABLE meta (
  singleton INTEGER PRIMARY KEY CHECK(singleton=1),
  schema_version INTEGER NOT NULL CHECK(schema_version=1),
  schema_fingerprint TEXT NOT NULL CHECK(length(schema_fingerprint)=64 AND schema_fingerprint NOT GLOB '*[^0-9a-f]*'),
  codec_fingerprint TEXT NOT NULL CHECK(length(codec_fingerprint)=64 AND codec_fingerprint NOT GLOB '*[^0-9a-f]*'),
  store_id TEXT NOT NULL CHECK(length(store_id)=32 AND store_id NOT GLOB '*[^0-9a-f]*'),
  owner_run_id TEXT NOT NULL CHECK(length(owner_run_id)=32 AND owner_run_id NOT GLOB '*[^0-9a-f]*'),
  created_utc TEXT NOT NULL CHECK(length(created_utc)=20),
  commit_sequence TEXT NOT NULL CHECK(length(commit_sequence) BETWEEN 1 AND 20 AND commit_sequence NOT GLOB '*[^0-9]*' AND (commit_sequence='0' OR substr(commit_sequence,1,1)!='0') AND (length(commit_sequence)<20 OR commit_sequence COLLATE BINARY<='18446744073709551615'))
) STRICT)LPFIX"},
{R"LPFIX(players)LPFIX",R"LPFIX(CREATE TABLE players (
  commit_sequence TEXT NOT NULL CHECK(length(commit_sequence) BETWEEN 1 AND 20 AND commit_sequence NOT GLOB '*[^0-9]*' AND substr(commit_sequence,1,1) BETWEEN '1' AND '9' AND (length(commit_sequence)<20 OR commit_sequence COLLATE BINARY<='18446744073709551615')),
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=32 AND id NOT GLOB '*[^0-9a-f]*'),
  revision TEXT NOT NULL CHECK(length(revision) BETWEEN 1 AND 20 AND revision NOT GLOB '*[^0-9]*' AND substr(revision,1,1) BETWEEN '1' AND '9' AND (length(revision)<20 OR revision COLLATE BINARY<='18446744073709551615')),
  record BLOB NOT NULL CHECK(length(record) BETWEEN 1 AND 8192),
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256)=64 AND record_sha256 NOT GLOB '*[^0-9a-f]*')
) STRICT)LPFIX"},
{R"LPFIX(preferences)LPFIX",R"LPFIX(CREATE TABLE preferences (
  player_id TEXT PRIMARY KEY NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  revision TEXT NOT NULL CHECK(length(revision) BETWEEN 1 AND 20 AND revision NOT GLOB '*[^0-9]*' AND substr(revision,1,1) BETWEEN '1' AND '9' AND (length(revision)<20 OR revision COLLATE BINARY<='18446744073709551615')),
  record BLOB NOT NULL CHECK(length(record) BETWEEN 1 AND 614400),
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256)=64 AND record_sha256 NOT GLOB '*[^0-9a-f]*')
) STRICT)LPFIX"},
{R"LPFIX(practices)LPFIX",R"LPFIX(CREATE TABLE practices (
  id TEXT PRIMARY KEY NOT NULL CHECK(length(id)=32 AND id NOT GLOB '*[^0-9a-f]*'),
  player_id TEXT NOT NULL REFERENCES players(id) ON DELETE CASCADE,
  source_fingerprint TEXT NOT NULL CHECK(length(source_fingerprint)=64 AND source_fingerprint NOT GLOB '*[^0-9a-f]*'),
  source_session TEXT NOT NULL CHECK(length(source_session) BETWEEN 1 AND 128),
  creation_sequence TEXT NOT NULL UNIQUE CHECK(length(creation_sequence) BETWEEN 1 AND 20 AND creation_sequence NOT GLOB '*[^0-9]*' AND substr(creation_sequence,1,1) BETWEEN '1' AND '9' AND (length(creation_sequence)<20 OR creation_sequence COLLATE BINARY<='18446744073709551615')),
  commit_sequence TEXT NOT NULL CHECK(length(commit_sequence) BETWEEN 1 AND 20 AND commit_sequence NOT GLOB '*[^0-9]*' AND substr(commit_sequence,1,1) BETWEEN '1' AND '9' AND (length(commit_sequence)<20 OR commit_sequence COLLATE BINARY<='18446744073709551615')),
  revision TEXT NOT NULL CHECK(length(revision) BETWEEN 1 AND 20 AND revision NOT GLOB '*[^0-9]*' AND substr(revision,1,1) BETWEEN '1' AND '9' AND (length(revision)<20 OR revision COLLATE BINARY<='18446744073709551615')),
  status TEXT NOT NULL CHECK(status IN ('active','manually_ended','source_ended','interrupted')),
  record BLOB NOT NULL CHECK(length(record) BETWEEN 1 AND 8192),
  record_sha256 TEXT NOT NULL CHECK(length(record_sha256)=64 AND record_sha256 NOT GLOB '*[^0-9a-f]*'),
  UNIQUE(source_fingerprint,source_session)
) STRICT)LPFIX"},
{R"LPFIX(practices_one_active)LPFIX",R"LPFIX(CREATE UNIQUE INDEX practices_one_active ON practices(status) WHERE status='active')LPFIX"},
{R"LPFIX(practices_player_creation)LPFIX",R"LPFIX(CREATE INDEX practices_player_creation ON practices(player_id,length(creation_sequence) DESC,creation_sequence COLLATE BINARY DESC))LPFIX"}
};
constexpr std::string_view full_fixture_trigger=R"LPFIX(CREATE TRIGGER extra AFTER INSERT ON players BEGIN SELECT 1; END;)LPFIX";
struct FullFixturePair {std::string_view id,player,preferences;};
constexpr FullFixturePair full_fixture_pairs[]={
{R"LPFIX(aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)LPFIX",R"LPFIX({"created_utc":"2000-02-29T00:00:00Z","id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","name":"Ana \"Δ\" \\ 飛行","revision":"3","type":"LocalPlayer","updated_utc":"2026-10-11T06:00:00Z","version":1})LPFIX",R"LPFIX({"audio":{"airflow_gain":{"$binary64_le":"000000000000e03f"},"enabled":true,"engine_gain":{"$binary64_le":"0000000000000080"},"show_panel_captions":false},"legacy_input":{"actions":[{"id":"recenter","sources":[{"keys":[82],"kind":"physical_keys"}]},{"id":"look_hold","sources":[{"button":2,"kind":"mouse_button"}]},{"id":"view_cycle","sources":[{"index":127,"kind":"joy_button","slot":"stick-A"}]}],"axes":[{"gain":1,"kind":"key_pair","negative":[65],"positive":[68],"rate":{"$binary64_le":"0000000000001040"},"return_to_start":true,"target":"roll"},{"center":{"$binary64_le":"0000000000000080"},"deadzone":{"$binary64_le":"0000000000000080"},"gain":{"$binary64_le":"000000000000e03f"},"index":0,"invert":false,"kind":"joy_axis","maximum":{"$binary64_le":"000000000000f03f"},"minimum":-1,"range":"centered","saturation":{"$binary64_le":"000000000000f03f"},"slew_per_s":4,"slot":"stick-A","target":"pitch"},{"kind":"fixed","target":"yaw","value":-1},{"center":{"$binary64_le":"0000000000000080"},"deadzone":{"$binary64_le":"0000000000000080"},"gain":{"$binary64_le":"000000000000e03f"},"index":1,"invert":false,"kind":"joy_axis","maximum":{"$binary64_le":"000000000000f03f"},"minimum":0,"range":"unsigned","saturation":{"$binary64_le":"000000000000f03f"},"slew_per_s":4,"slot":"stick-A","target":"throttle"},{"kind":"fixed","target":"mixture","value":{"$binary64_le":"000000000000f03f"}},{"gain":{"$binary64_le":"000000000000e03f"},"kind":"key_pair","negative":[74],"positive":[75],"rate":1,"return_to_start":false,"target":"left_brake"},{"kind":"fixed","target":"right_brake","value":0},{"kind":"fixed","target":"trim","value":{"$binary64_le":"0000000000000080"}}],"devices":[{"label":"Yoke Δ","match":{"guid":"fixture-guid","name":"Fixture device\u0009飛行","product_id":"00ab","vendor_id":"0123"},"slot":"stick-A"}],"name":"Original \"Δ\" \\ 飛行","type":"InputPreset","version":1},"piston_input":{"actions":[{"id":"recenter","sources":[{"keys":[82],"kind":"physical_keys"}]},{"id":"look_hold","sources":[{"button":2,"kind":"mouse_button"}]},{"id":"view_cycle","sources":[{"index":127,"kind":"joy_button","slot":"stick-A"}]}],"axes":[{"gain":1,"kind":"key_pair","negative":[65],"positive":[68],"rate":{"$binary64_le":"0000000000001040"},"return_to_start":true,"target":"roll"},{"center":{"$binary64_le":"0000000000000080"},"deadzone":{"$binary64_le":"0000000000000080"},"gain":{"$binary64_le":"000000000000e03f"},"index":0,"invert":false,"kind":"joy_axis","maximum":{"$binary64_le":"000000000000f03f"},"minimum":-1,"range":"centered","saturation":{"$binary64_le":"000000000000f03f"},"slew_per_s":4,"slot":"stick-A","target":"pitch"},{"kind":"fixed","target":"yaw","value":-1},{"center":{"$binary64_le":"0000000000000080"},"deadzone":{"$binary64_le":"0000000000000080"},"gain":{"$binary64_le":"000000000000e03f"},"index":1,"invert":false,"kind":"joy_axis","maximum":{"$binary64_le":"000000000000f03f"},"minimum":0,"range":"unsigned","saturation":{"$binary64_le":"000000000000f03f"},"slew_per_s":4,"slot":"stick-A","target":"throttle"},{"gain":{"$binary64_le":"000000000000e03f"},"kind":"key_pair","negative":[77],"positive":[78],"rate":{"$binary64_le":"0100000000000000"},"return_to_start":false,"target":"mixture"},{"gain":{"$binary64_le":"000000000000e03f"},"kind":"key_pair","negative":[74],"positive":[75],"rate":1,"return_to_start":false,"target":"left_brake"},{"kind":"fixed","target":"right_brake","value":0},{"kind":"fixed","target":"trim","value":{"$binary64_le":"0000000000000080"}}],"capability_revision":"piston-controls-v1","devices":[{"label":"Yoke Δ","match":{"guid":"fixture-guid","name":"Fixture device\u0009飛行","product_id":"00ab","vendor_id":"0123"},"slot":"stick-A"}],"name":"Original \"Δ\" \\ 飛行","profile":{"backend_model":"original-piston-prop","id":"original-piston-prop-v1","version":"0.1.0-prototype"},"systems":[{"id":"engine.ignition_left","kind":"toggle","sources":[{"keys":[73],"kind":"physical_keys"}]},{"id":"engine.ignition_right","kind":"toggle","sources":[{"keys":[79],"kind":"physical_keys"}]},{"id":"engine.starter","kind":"momentary","sources":[{"keys":[83],"kind":"physical_keys"}]},{"id":"fuel.feed","kind":"toggle","sources":[{"keys":[70],"kind":"physical_keys"}]}],"type":"InputPreset","version":2},"player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","revision":"3","type":"LocalPlayerPreferences","version":1})LPFIX"},
{R"LPFIX(bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb)LPFIX",R"LPFIX({"created_utc":"2000-02-29T00:00:00Z","id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","name":"Ana \"Δ\" \\ 飛行","revision":"1","type":"LocalPlayer","updated_utc":"2026-10-11T06:00:00Z","version":1})LPFIX",R"LPFIX({"audio":{"airflow_gain":{"$binary64_le":"000000000000e03f"},"enabled":true,"engine_gain":{"$binary64_le":"0000000000000080"},"show_panel_captions":false},"legacy_input":null,"piston_input":null,"player_id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","revision":"1","type":"LocalPlayerPreferences","version":1})LPFIX"}
};
struct FullFixturePractice {std::string_view id,owner,record;};
constexpr FullFixturePractice full_fixture_practices[]={
{R"LPFIX(11111111111111111111111111111111)LPFIX",R"LPFIX(aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)LPFIX",R"LPFIX({"archive":{"absolute_path":"C:/fixture-only/Δ/review.json","first_tick":"9007199254741000","last_tick":"9007199254741100","linked_utc":"2026-10-11T06:00:00Z","payload_sha256":"6666666666666666666666666666666666666666666666666666666666666666","recording_session_id":"fixture-session","type":"ExternalRecordedReview","version":1},"commit_sequence":"12","creation_sequence":"9","end_reason":"user_end","first_tick":"9007199254740993","id":"11111111111111111111111111111111","last_observed_utc":"2026-10-11T05:59:59Z","last_tick":"9007199254741113","observed_ticks":"120","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","revision":"2","source":{"angular_integration_method":null,"model_identity":{"backend_model":"original-interactive","id":"original-interactive-prototype","version":"0.1.0-prototype"},"named_start":"airborne-prepared","native_source_fingerprint":"4444444444444444444444444444444444444444444444444444444444444444","prepared_world_sha256":"5555555555555555555555555555555555555555555555555555555555555555","session_id":"fixture-session","source_variant":"jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2","wind_profile":"from-west"},"started_utc":"2026-10-11T06:00:00Z","status":"manually_ended","tick_rate_hz":120,"type":"LocalPractice","version":1})LPFIX"},
{R"LPFIX(22222222222222222222222222222222)LPFIX",R"LPFIX(aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)LPFIX",R"LPFIX({"archive":null,"commit_sequence":"11","creation_sequence":"10","end_reason":"user_end","first_tick":"9007199254740993","id":"22222222222222222222222222222222","last_observed_utc":"2026-10-11T05:59:59Z","last_tick":"9007199254741113","observed_ticks":"120","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","revision":"2","source":{"angular_integration_method":null,"model_identity":{"backend_model":"original-interactive","id":"original-interactive-prototype","version":"0.1.0-prototype"},"named_start":"airborne-prepared","native_source_fingerprint":"4444444444444444444444444444444444444444444444444444444444444444","prepared_world_sha256":"5555555555555555555555555555555555555555555555555555555555555555","session_id":"fixture-session-two","source_variant":"jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2","wind_profile":"from-west"},"started_utc":"2026-10-11T06:00:00Z","status":"manually_ended","tick_rate_hz":120,"type":"LocalPractice","version":1})LPFIX"},
{R"LPFIX(33333333333333333333333333333333)LPFIX",R"LPFIX(bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb)LPFIX",R"LPFIX({"archive":null,"commit_sequence":"8","creation_sequence":"8","end_reason":"user_end","first_tick":"9007199254740993","id":"33333333333333333333333333333333","last_observed_utc":"2026-10-11T05:59:59Z","last_tick":"9007199254741113","observed_ticks":"120","player_id":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","revision":"2","source":{"angular_integration_method":null,"model_identity":{"backend_model":"original-interactive","id":"original-interactive-prototype","version":"0.1.0-prototype"},"named_start":"airborne-prepared","native_source_fingerprint":"4444444444444444444444444444444444444444444444444444444444444444","prepared_world_sha256":"5555555555555555555555555555555555555555555555555555555555555555","session_id":"other-player-session","source_variant":"jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2","wind_profile":"from-west"},"started_utc":"2026-10-11T06:00:00Z","status":"manually_ended","tick_rate_hz":120,"type":"LocalPractice","version":1})LPFIX"}
};

// Setup-only SQLite operations run after real joins, under the still-live
// management Capability's ordinary root/sentinel leases. No product resolver,
// CREATE flag, consumer encoder, fault hook or arbitrary input SQL is used.
struct FullFixtureDb {
 sqlite3* value{};
 ~FullFixtureDb(){if(value&&sqlite3_close(value)!=SQLITE_OK)std::terminate();}
 void close(){require(value&&sqlite3_close(value)==SQLITE_OK,"fixture SQLite actual close");value=nullptr;}
};
void full_fixture_exec(sqlite3*db,std::string_view sql){
 std::string owned(sql);require(owned.size()<65536&&sqlite3_exec(db,owned.c_str(),nullptr,nullptr,nullptr)==SQLITE_OK,"fixed independent fixture SQL executes on actual pinned SQLite");
}
void full_fixture_schema_check(sqlite3*db,bool extra){
 for(const auto&row:full_fixture_schema){
  sqlite3_stmt*statement{};require(sqlite3_prepare_v2(db,"SELECT sql FROM sqlite_schema WHERE name=?1",-1,&statement,nullptr)==SQLITE_OK,"actual fixture sqlite_schema prepare");
  const int bound=sqlite3_bind_text(statement,1,row.name.data(),static_cast<int>(row.name.size()),SQLITE_STATIC);
  const int stepped=bound==SQLITE_OK?sqlite3_step(statement):bound;
  bool exact=stepped==SQLITE_ROW&&sqlite3_column_type(statement,0)==SQLITE_TEXT;
  if(exact){const auto*text=sqlite3_column_text(statement,0);exact=text&&std::string_view(reinterpret_cast<const char*>(text),static_cast<std::size_t>(sqlite3_column_bytes(statement,0)))==row.sql;}
  const int end=exact?sqlite3_step(statement):SQLITE_ERROR;const int retired=sqlite3_finalize(statement);
  require(exact&&end==SQLITE_DONE&&retired==SQLITE_OK,"actual six allocated schema SQL bodies equal frozen SQL_exact");
 }
 sqlite3_stmt*count{};require(sqlite3_prepare_v2(db,"SELECT count(*) FROM sqlite_schema",-1,&count,nullptr)==SQLITE_OK,"actual full schema roster count");
 const bool exact=sqlite3_step(count)==SQLITE_ROW&&sqlite3_column_type(count,0)==SQLITE_INTEGER&&sqlite3_column_int64(count,0)==(extra?12:11);
 const int end=exact?sqlite3_step(count):SQLITE_ERROR;const int retired=sqlite3_finalize(count);
 require(exact&&end==SQLITE_DONE&&retired==SQLITE_OK,"exact user/autoindex roster including explicit extra-trigger negative");
}

// Original test expansion of accepted CAP_full_2000_summary_export; no generated2000-row blob.
constexpr std::string_view full_max_template=R"LPFIX({"archive":null,"commit_sequence":"2","creation_sequence":"2","end_reason":"user_end","first_tick":"9007199254740993","id":"11111111111111111111111111111111","last_observed_utc":"2026-10-11T05:59:59Z","last_tick":"9007199254741113","observed_ticks":"120","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","revision":"2","source":{"angular_integration_method":null,"model_identity":{"backend_model":"original-interactive","id":"original-interactive-prototype","version":"0.1.0-prototype"},"named_start":"airborne-prepared","native_source_fingerprint":"4444444444444444444444444444444444444444444444444444444444444444","prepared_world_sha256":"5555555555555555555555555555555555555555555555555555555555555555","session_id":"saaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0000000","source_variant":"jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2","wind_profile":"from-west"},"started_utc":"2026-10-11T06:00:00Z","status":"manually_ended","tick_rate_hz":120,"type":"LocalPractice","version":1})LPFIX";
constexpr std::string_view full_max_summary=R"LPFIX({"archive":{"linked":false},"commit_sequence":"2","creation_sequence":"2","end_reason":"user_end","first_tick":"9007199254740993","id":"11111111111111111111111111111111","last_observed_utc":"2026-10-11T05:59:59Z","last_tick":"9007199254741113","observed_ticks":"120","player_id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","revision":"2","source":{"angular_integration_method":null,"model_identity":{"backend_model":"original-interactive","id":"original-interactive-prototype","version":"0.1.0-prototype"},"named_start":"airborne-prepared","native_source_fingerprint":"4444444444444444444444444444444444444444444444444444444444444444","prepared_world_sha256":"5555555555555555555555555555555555555555555555555555555555555555","session_id":"saaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa0000000","source_variant":"jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2","wind_profile":"from-west"},"started_utc":"2026-10-11T06:00:00Z","status":"manually_ended","tick_rate_hz":120,"type":"LocalPractice","version":1})LPFIX";
constexpr std::string_view full_max_inserts[]={
R"LPFIX(INSERT INTO meta(singleton,schema_version,schema_fingerprint,codec_fingerprint,store_id,owner_run_id,created_utc,commit_sequence) VALUES(1,1,'cbd00b3fe47b400e79635ed901d195abfe133a4131d5001feac8e3eedeb0562f','47711d41be89e233efe3c42e8f2cedd33f729e6e0e2c9a78a6026454022b0538','77777777777777777777777777777777','88888888888888888888888888888888','2026-10-11T06:00:00Z','2001');)LPFIX",
R"LPFIX(INSERT INTO players(commit_sequence,id,revision,record,record_sha256) VALUES('6','aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','3',X'7b22637265617465645f757463223a22323030302d30322d32395430303a30303a30305a222c226964223a226161616161616161616161616161616161616161616161616161616161616161222c226e616d65223a22f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880f09f9880222c227265766973696f6e223a2233222c2274797065223a224c6f63616c506c61796572222c22757064617465645f757463223a22323032362d31302d31315430363a30303a30305a222c2276657273696f6e223a317d','e9c920758a6cd7cef46f222c2637809819522845b777198bb44d3753003436e0');)LPFIX",
R"LPFIX(INSERT INTO preferences(player_id,revision,record,record_sha256) VALUES('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa','3',X'7b22666f726d6174223a224c6f63616c506c61796572507265666572656e636573222c227061796c6f61645f6a736f6e223a227b5c22617564696f5c223a7b5c22616972666c6f775f6761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c22656e61626c65645c223a747275652c5c22656e67696e655f6761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c2273686f775f70616e656c5f63617074696f6e735c223a66616c73657d2c5c226c65676163795f696e7075745c223a7b5c22616374696f6e735c223a5b7b5c2269645c223a5c22726563656e7465725c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b38325d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d2c7b5c2269645c223a5c226c6f6f6b5f686f6c645c222c5c22736f75726365735c223a5b7b5c22627574746f6e5c223a322c5c226b696e645c223a5c226d6f7573655f627574746f6e5c227d5d7d2c7b5c2269645c223a5c22766965775f6379636c655c222c5c22736f75726365735c223a5b7b5c22696e6465785c223a3132372c5c226b696e645c223a5c226a6f795f627574746f6e5c222c5c22736c6f745c223a5c22737469636b2d415c227d5d7d5d2c5c22617865735c223a5b7b5c226761696e5c223a312c5c226b696e645c223a5c226b65795f706169725c222c5c226e656761746976655c223a5b36355d2c5c22706f7369746976655c223a5b36385d2c5c22726174655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030313034305c227d2c5c2272657475726e5f746f5f73746172745c223a747275652c5c227461726765745c223a5c22726f6c6c5c227d2c7b5c2263656e7465725c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c22646561647a6f6e655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c22696e6465785c223a302c5c22696e766572745c223a66616c73652c5c226b696e645c223a5c226a6f795f617869735c222c5c226d6178696d756d5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c226d696e696d756d5c223a2d312c5c2272616e67655c223a5c2263656e74657265645c222c5c2273617475726174696f6e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c22736c65775f7065725f735c223a342c5c22736c6f745c223a5c22737469636b2d415c222c5c227461726765745c223a5c2270697463685c227d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c227961775c222c5c2276616c75655c223a2d317d2c7b5c2263656e7465725c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c22646561647a6f6e655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c22696e6465785c223a312c5c22696e766572745c223a66616c73652c5c226b696e645c223a5c226a6f795f617869735c222c5c226d6178696d756d5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c226d696e696d756d5c223a302c5c2272616e67655c223a5c22756e7369676e65645c222c5c2273617475726174696f6e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c22736c65775f7065725f735c223a342c5c22736c6f745c223a5c22737469636b2d415c222c5c227461726765745c223a5c227468726f74746c655c227d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c226d6978747572655c222c5c2276616c75655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d7d2c7b5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c226b696e645c223a5c226b65795f706169725c222c5c226e656761746976655c223a5b37345d2c5c22706f7369746976655c223a5b37355d2c5c22726174655c223a312c5c2272657475726e5f746f5f73746172745c223a66616c73652c5c227461726765745c223a5c226c6566745f6272616b655c227d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c2272696768745f6272616b655c222c5c2276616c75655c223a307d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c227472696d5c222c5c2276616c75655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d7d5d2c5c22646576696365735c223a5b7b5c226c6162656c5c223a5c22596f6b6520ce945c222c5c226d617463685c223a7b5c22677569645c223a5c22666978747572652d677569645c222c5c226e616d655c223a5c2246697874757265206465766963655c5c7530303039e9a39be8a18c5c222c5c2270726f647563745f69645c223a5c22303061625c222c5c2276656e646f725f69645c223a5c22303132335c227d2c5c22736c6f745c223a5c22737469636b2d415c227d5d2c5c226e616d655c223a5c224f726967696e616c205c5c5c22ce945c5c5c22205c5c5c5c20e9a39be8a18c5c222c5c22747970655c223a5c22496e7075745072657365745c222c5c2276657273696f6e5c223a317d2c5c22706973746f6e5f696e7075745c223a7b5c22616374696f6e735c223a5b7b5c2269645c223a5c22726563656e7465725c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b38325d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d2c7b5c2269645c223a5c226c6f6f6b5f686f6c645c222c5c22736f75726365735c223a5b7b5c22627574746f6e5c223a322c5c226b696e645c223a5c226d6f7573655f627574746f6e5c227d5d7d2c7b5c2269645c223a5c22766965775f6379636c655c222c5c22736f75726365735c223a5b7b5c22696e6465785c223a3132372c5c226b696e645c223a5c226a6f795f627574746f6e5c222c5c22736c6f745c223a5c22737469636b2d415c227d5d7d5d2c5c22617865735c223a5b7b5c226761696e5c223a312c5c226b696e645c223a5c226b65795f706169725c222c5c226e656761746976655c223a5b36355d2c5c22706f7369746976655c223a5b36385d2c5c22726174655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030313034305c227d2c5c2272657475726e5f746f5f73746172745c223a747275652c5c227461726765745c223a5c22726f6c6c5c227d2c7b5c2263656e7465725c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c22646561647a6f6e655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c22696e6465785c223a302c5c22696e766572745c223a66616c73652c5c226b696e645c223a5c226a6f795f617869735c222c5c226d6178696d756d5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c226d696e696d756d5c223a2d312c5c2272616e67655c223a5c2263656e74657265645c222c5c2273617475726174696f6e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c22736c65775f7065725f735c223a342c5c22736c6f745c223a5c22737469636b2d415c222c5c227461726765745c223a5c2270697463685c227d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c227961775c222c5c2276616c75655c223a2d317d2c7b5c2263656e7465725c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c22646561647a6f6e655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d2c5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c22696e6465785c223a312c5c22696e766572745c223a66616c73652c5c226b696e645c223a5c226a6f795f617869735c222c5c226d6178696d756d5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c226d696e696d756d5c223a302c5c2272616e67655c223a5c22756e7369676e65645c222c5c2273617475726174696f6e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030663033665c227d2c5c22736c65775f7065725f735c223a342c5c22736c6f745c223a5c22737469636b2d415c222c5c227461726765745c223a5c227468726f74746c655c227d2c7b5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c226b696e645c223a5c226b65795f706169725c222c5c226e656761746976655c223a5b37375d2c5c22706f7369746976655c223a5b37385d2c5c22726174655c223a7b5c222462696e61727936345f6c655c223a5c22303130303030303030303030303030305c227d2c5c2272657475726e5f746f5f73746172745c223a66616c73652c5c227461726765745c223a5c226d6978747572655c227d2c7b5c226761696e5c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030653033665c227d2c5c226b696e645c223a5c226b65795f706169725c222c5c226e656761746976655c223a5b37345d2c5c22706f7369746976655c223a5b37355d2c5c22726174655c223a312c5c2272657475726e5f746f5f73746172745c223a66616c73652c5c227461726765745c223a5c226c6566745f6272616b655c227d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c2272696768745f6272616b655c222c5c2276616c75655c223a307d2c7b5c226b696e645c223a5c2266697865645c222c5c227461726765745c223a5c227472696d5c222c5c2276616c75655c223a7b5c222462696e61727936345f6c655c223a5c22303030303030303030303030303038305c227d7d5d2c5c226361706162696c6974795f7265766973696f6e5c223a5c22706973746f6e2d636f6e74726f6c732d76315c222c5c22646576696365735c223a5b7b5c226c6162656c5c223a5c22596f6b6520ce945c222c5c226d617463685c223a7b5c22677569645c223a5c22666978747572652d677569645c222c5c226e616d655c223a5c2246697874757265206465766963655c5c7530303039e9a39be8a18c5c222c5c2270726f647563745f69645c223a5c22303061625c222c5c2276656e646f725f69645c223a5c22303132335c227d2c5c22736c6f745c223a5c22737469636b2d415c227d5d2c5c226e616d655c223a5c224f726967696e616c205c5c5c22ce945c5c5c22205c5c5c5c20e9a39be8a18c5c222c5c2270726f66696c655c223a7b5c226261636b656e645f6d6f64656c5c223a5c226f726967696e616c2d706973746f6e2d70726f705c222c5c2269645c223a5c226f726967696e616c2d706973746f6e2d70726f702d76315c222c5c2276657273696f6e5c223a5c22302e312e302d70726f746f747970655c227d2c5c2273797374656d735c223a5b7b5c2269645c223a5c22656e67696e652e69676e6974696f6e5f6c6566745c222c5c226b696e645c223a5c22746f67676c655c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b37335d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d2c7b5c2269645c223a5c22656e67696e652e69676e6974696f6e5f72696768745c222c5c226b696e645c223a5c22746f67676c655c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b37395d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d2c7b5c2269645c223a5c22656e67696e652e737461727465725c222c5c226b696e645c223a5c226d6f6d656e746172795c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b38335d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d2c7b5c2269645c223a5c226675656c2e666565645c222c5c226b696e645c223a5c22746f67676c655c222c5c22736f75726365735c223a5b7b5c226b6579735c223a5b37305d2c5c226b696e645c223a5c22706879736963616c5f6b6579735c227d5d7d5d2c5c22747970655c223a5c22496e7075745072657365745c222c5c2276657273696f6e5c223a327d2c5c22706c617965725f69645c223a5c2261616161616161616161616161616161616161616161616161616161616161615c222c5c227265766973696f6e5c223a5c22335c222c5c22747970655c223a5c224c6f63616c506c61796572507265666572656e6365735c222c5c2276657273696f6e5c223a317d222c227061796c6f61645f736861323536223a2237366231393732383138323437313962353737663965623336316333623938623261656366613666346139373638363538656164326333656363373231363861222c2276657273696f6e223a317d','2571fbaf91a77f23aab9ac00e9707a02943ce9b84b3eef541a9f8b0aba480a24');)LPFIX"
};

std::string full_max_id(unsigned n){require(n>=1&&n<=2000,"fixed maximum reference ID domain");std::string out(32,'0');constexpr char hex[]="0123456789abcdef";for(unsigned at=32;n;){require(at!=0,"fixed lowerhex32 width");out[--at]=hex[n&15];n>>=4;}return out;}
std::string full_max_session(unsigned i){require(i<2000,"fixed maximum reference session domain");auto digits=std::to_string(i);return "s"+std::string(120,'a')+std::string(7-digits.size(),'0')+digits;}
void full_max_replace(std::string&record,std::string_view old,std::string_view next){auto at=record.find(old);require(at!=record.npos&&record.find(old,at+old.size())==record.npos,"exact unique frozen template field");record.replace(at,old.size(),next);}
std::string full_max_record(unsigned i,bool summary){
 require(i<2000,"fixed maximum reference row domain");std::string out(summary?full_max_summary:full_max_template);
 full_max_replace(out,"\"id\":\"11111111111111111111111111111111\"","\"id\":\""+full_max_id(i+1)+"\"");
 full_max_replace(out,"\"creation_sequence\":\"2\"","\"creation_sequence\":\""+std::to_string(i+2)+"\"");
 full_max_replace(out,"\"commit_sequence\":\"2\"","\"commit_sequence\":\""+std::to_string(i+2)+"\"");
 full_max_replace(out,"\"session_id\":\"s"+std::string(120,'a')+"0000000\"","\"session_id\":\""+full_max_session(i)+"\"");return out;
}
void full_max_insert_practices(sqlite3*db){
 sqlite3_stmt*statement{};require(sqlite3_prepare_v2(db,"INSERT INTO practices(id,player_id,source_fingerprint,source_session,creation_sequence,commit_sequence,revision,status,record,record_sha256) VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10)",-1,&statement,nullptr)==SQLITE_OK,"one bounded prepared maximum-fixture statement");
 for(unsigned i=0;i<2000;++i){
  auto id=full_max_id(i+1),session=full_max_session(i),sequence=std::to_string(i+2),record=full_max_record(i,false),hash=digest_text(record);
  auto text=[&](int at,std::string_view value){require(value.size()<=8192&&sqlite3_bind_text(statement,at,value.data(),static_cast<int>(value.size()),SQLITE_STATIC)==SQLITE_OK,"exact fixture column bind");};
  text(1,id);text(2,"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");text(3,"4444444444444444444444444444444444444444444444444444444444444444");text(4,session);text(5,sequence);text(6,sequence);text(7,"2");text(8,"manually_ended");
  require(record.size()<=8192&&sqlite3_bind_blob(statement,9,record.data(),static_cast<int>(record.size()),SQLITE_STATIC)==SQLITE_OK,"exact independently expanded canonical record BLOB");text(10,hash);
  require(sqlite3_step(statement)==SQLITE_DONE&&sqlite3_reset(statement)==SQLITE_OK&&sqlite3_clear_bindings(statement)==SQLITE_OK,"all2000 real SQLite rows inserted before consumer opens");
 }
 require(sqlite3_finalize(statement)==SQLITE_OK,"maximum fixture prepared statement retired");
 sqlite3_stmt*count{};require(sqlite3_prepare_v2(db,"SELECT count(*) FROM practices",-1,&count,nullptr)==SQLITE_OK,"maximum fixture actual SQL count");
 require(sqlite3_step(count)==SQLITE_ROW&&sqlite3_column_type(count,0)==SQLITE_INTEGER&&sqlite3_column_int64(count,0)==2000&&sqlite3_step(count)==SQLITE_DONE&&sqlite3_finalize(count)==SQLITE_OK,"exact2000 SQL rows, no count proxy");
}

void full_fixture_setup(const std::string&root,bool bad_revision,bool extra_trigger,bool maximum=false){
 // The file must already exist as the joined synthetic store. No SQLite CREATE.
 auto before=crash_file(root+"\\players.sqlite3",33554432);require(before.present,"existing isolated main before independent row setup");
 std::string uri="file:";constexpr char hex[]="0123456789ABCDEF";
 for(unsigned char c:root+"\\players.sqlite3"){
  if(c=='\\')uri+='/';else if((c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='/'||c==':'||c=='-'||c=='_'||c=='.')uri+=static_cast<char>(c);
  else{uri+='%';uri+=hex[c>>4];uri+=hex[c&15];}
 }
 uri+="?exclusive=1";FullFixtureDb db;
 require(sqlite3_open_v2(uri.c_str(),&db.value,SQLITE_OPEN_READWRITE|SQLITE_OPEN_URI|SQLITE_OPEN_NOMUTEX,nullptr)==SQLITE_OK,"actual existing-only test SQLite open");
 full_fixture_exec(db.value,"PRAGMA locking_mode=EXCLUSIVE;PRAGMA foreign_keys=ON;BEGIN IMMEDIATE;DELETE FROM practices;DELETE FROM preferences;DELETE FROM players;DELETE FROM meta;");
 if(maximum){for(auto sql:full_max_inserts)full_fixture_exec(db.value,sql);full_max_insert_practices(db.value);}else for(auto sql:full_fixture_inserts)full_fixture_exec(db.value,sql);
 if(bad_revision)full_fixture_exec(db.value,"UPDATE players SET revision='4' WHERE id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';");
 if(extra_trigger)full_fixture_exec(db.value,full_fixture_trigger);
 full_fixture_exec(db.value,"COMMIT;");full_fixture_schema_check(db.value,extra_trigger);if(!maximum)full_fixture_exec(db.value,"VACUUM;");db.close();
 auto after=crash_file(root+"\\players.sqlite3",33554432);require(after.present&&same_identity(before.identity,after.identity)&&(!maximum?after.length<=524288:after.length<=6291456),"fixture setup keeps main identity and explicitly shrinks reset D01 for bounded failure copies");
 for(unsigned i=1;i<4;++i)require(!crash_file(root+"\\"+std::string(crash_data_names[i]),crash_caps[i]).present,"fully closed fixed fixture leaves no SQLite sidecar before qualification");
}

// Independent valid-state U64 boundary fixture. The contract cross-checks paired
// revisions and latest<=meta; this does not claim replaying 2^64 historical jobs.
constexpr std::string_view u64_high_player=R"U64FIX({"created_utc":"2026-10-03T12:00:00Z","id":"22222222222222222222222222222222","name":"Maximum revision","revision":"18446744073709551615","type":"LocalPlayer","updated_utc":"2026-10-03T12:00:00Z","version":1})U64FIX";
constexpr std::string_view u64_high_preferences=R"U64FIX({"format":"LocalPlayerPreferences","payload_json":"{\"audio\":{\"airflow_gain\":{\"$binary64_le\":\"000000000000f03f\"},\"enabled\":true,\"engine_gain\":{\"$binary64_le\":\"000000000000f03f\"},\"show_panel_captions\":true},\"legacy_input\":null,\"piston_input\":null,\"player_id\":\"22222222222222222222222222222222\",\"revision\":\"18446744073709551615\",\"type\":\"LocalPlayerPreferences\",\"version\":1}","payload_sha256":"1345d6b862182785adadbc73f49827f7825ec05a362a7fcd024dddd18b17abd9","version":1})U64FIX";
constexpr std::string_view u64_almost_player=R"U64FIX({"created_utc":"2026-10-03T12:00:00Z","id":"cccccccccccccccccccccccccccccccc","name":"Before maximum","revision":"18446744073709551614","type":"LocalPlayer","updated_utc":"2026-10-03T12:00:00Z","version":1})U64FIX";
constexpr std::string_view u64_almost_preferences=R"U64FIX({"format":"LocalPlayerPreferences","payload_json":"{\"audio\":{\"airflow_gain\":{\"$binary64_le\":\"000000000000f03f\"},\"enabled\":true,\"engine_gain\":{\"$binary64_le\":\"000000000000f03f\"},\"show_panel_captions\":true},\"legacy_input\":null,\"piston_input\":null,\"player_id\":\"cccccccccccccccccccccccccccccccc\",\"revision\":\"18446744073709551614\",\"type\":\"LocalPlayerPreferences\",\"version\":1}","payload_sha256":"e3b900c07883e07dcfa3ec93926752b23dd662d02459bdc6f178456ff22c774d","version":1})U64FIX";
constexpr std::string_view u64_high_pair=R"U64FIX({"player":{"created_utc":"2026-10-03T12:00:00Z","id":"22222222222222222222222222222222","name":"Maximum revision","revision":"18446744073709551615","type":"LocalPlayer","updated_utc":"2026-10-03T12:00:00Z","version":1},"preferences":{"audio":{"airflow_gain":{"$binary64_le":"000000000000f03f"},"enabled":true,"engine_gain":{"$binary64_le":"000000000000f03f"},"show_panel_captions":true},"legacy_input":null,"piston_input":null,"player_id":"22222222222222222222222222222222","revision":"18446744073709551615","type":"LocalPlayerPreferences","version":1}})U64FIX";
constexpr std::string_view u64_changed_pair=R"U64FIX({"player":{"created_utc":"2026-10-03T12:00:00Z","id":"cccccccccccccccccccccccccccccccc","name":"Now maximum","revision":"18446744073709551615","type":"LocalPlayer","updated_utc":"2026-10-03T12:03:00Z","version":1},"preferences":{"audio":{"airflow_gain":{"$binary64_le":"000000000000f03f"},"enabled":true,"engine_gain":{"$binary64_le":"000000000000f03f"},"show_panel_captions":true},"legacy_input":null,"piston_input":null,"player_id":"cccccccccccccccccccccccccccccccc","revision":"18446744073709551615","type":"LocalPlayerPreferences","version":1}})U64FIX";
constexpr std::string_view u64_alice_pair=R"U64FIX({"player":{"created_utc":"2026-10-03T12:00:00Z","id":"11111111111111111111111111111111","name":"Counter final","revision":"6","type":"LocalPlayer","updated_utc":"2026-10-03T12:03:00Z","version":1},"preferences":{"audio":{"airflow_gain":{"$binary64_le":"000000000000f03f"},"enabled":true,"engine_gain":{"$binary64_le":"0000000000000080"},"show_panel_captions":true},"legacy_input":null,"piston_input":null,"player_id":"11111111111111111111111111111111","revision":"6","type":"LocalPlayerPreferences","version":1}})U64FIX";
void u64_fixture_open(const std::string&root,FullFixtureDb&db){
 std::string uri="file:";constexpr char digits[]="0123456789ABCDEF";
 for(unsigned char c:root+"\\players.sqlite3"){
  if(c=='\\')uri+='/';else if((c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='/'||c==':'||c=='-'||c=='_'||c=='.')uri+=static_cast<char>(c);
  else{uri+='%';uri+=digits[c>>4];uri+=digits[c&15];}
 }
 uri+="?exclusive=1";
 require(sqlite3_open_v2(uri.c_str(),&db.value,SQLITE_OPEN_READWRITE|SQLITE_OPEN_URI|SQLITE_OPEN_NOMUTEX,nullptr)==SQLITE_OK,"existing-only fixed U64 fixture SQLite open after join");
}
__declspec(noinline) void u64_fixture_setup(const std::string&root){
 auto before=crash_file(root+"\\players.sqlite3",33554432);require(before.present,"U64 fixture preserves existing joined store");FullFixtureDb db;u64_fixture_open(root,db);
 full_fixture_exec(db.value,"PRAGMA locking_mode=EXCLUSIVE;PRAGMA foreign_keys=ON;BEGIN IMMEDIATE;");
 struct Row {std::string_view id,revision,player,preferences;};
 const Row rows[]={{"22222222222222222222222222222222","18446744073709551615",u64_high_player,u64_high_preferences},{"cccccccccccccccccccccccccccccccc","18446744073709551614",u64_almost_player,u64_almost_preferences}};
 for(const auto&row:rows){
  for(bool preferences:{false,true}){
   sqlite3_stmt*statement{};const auto sql=preferences?"INSERT INTO preferences(player_id,revision,record,record_sha256) VALUES(?1,?2,?3,?4)":"INSERT INTO players(id,revision,record,record_sha256,commit_sequence) VALUES(?1,?2,?3,?4,'18446744073709551613')";
   require(sqlite3_prepare_v2(db.value,sql,-1,&statement,nullptr)==SQLITE_OK,"fixed U64 paired insert prepares");const auto record=preferences?row.preferences:row.player;const auto hash=digest_text(record);
   require(sqlite3_bind_text(statement,1,row.id.data(),static_cast<int>(row.id.size()),SQLITE_STATIC)==SQLITE_OK&&sqlite3_bind_text(statement,2,row.revision.data(),static_cast<int>(row.revision.size()),SQLITE_STATIC)==SQLITE_OK&&sqlite3_bind_blob(statement,3,record.data(),static_cast<int>(record.size()),SQLITE_STATIC)==SQLITE_OK&&sqlite3_bind_text(statement,4,hash.data(),static_cast<int>(hash.size()),SQLITE_STATIC)==SQLITE_OK,"fixed independent U64 BLOB and hash binds");
   require(sqlite3_step(statement)==SQLITE_DONE&&sqlite3_finalize(statement)==SQLITE_OK,"exact U64 row inserted and statement retired");
  }
 }
 full_fixture_exec(db.value,"UPDATE meta SET commit_sequence='18446744073709551613' WHERE singleton=1;COMMIT;");full_fixture_schema_check(db.value,false);db.close();
 auto after=crash_file(root+"\\players.sqlite3",33554432);require(after.present&&same_identity(before.identity,after.identity),"U64 fixture retains original MAIN identity");
 for(unsigned i=1;i<4;++i)require(!crash_file(root+"\\"+std::string(crash_data_names[i]),crash_caps[i]).present,"closed U64 fixture has no sidecar before real reopen");
}
void u64_pair(std::string bytes,std::string_view expected){Raw row(std::move(bytes));require(canonical(row.d,value(row))==expected,"whole U64 paired player/options equals independent frozen bytes");}
void u64_refusal(Service*service,Probe&p,JobKind kind,V payload){
 p.wait_published(p.last_request());Capture capture(kind,std::move(payload));auto admission=service->submit(capture);require(admission.accepted,"U64 boundary request accepted before real SQLite refusal");const auto request=p.last_request();auto rows=receive(service,1);result(rows[0],admission.request_id.view(),kind,"failed","counter_exhausted");{Raw row(rows[0]);require(nil(row.d,value(row)),"counter exhaustion has null value and sequence");}p.wait_published(request);
 std::array<unsigned,4> counts{};std::lock_guard lock(p.mutex);
 for(const auto&o:p.events)if(o.request_ordinal==request&&o.kind==kind){
  require(o.phase!=Phase::row_write&&o.phase!=Phase::before_commit&&o.phase!=Phase::after_commit&&o.phase!=Phase::postverify,"exhausted mutation performs no row write/COMMIT/postverify");
  if(o.scope==Scope::original&&(o.phase==Phase::before_begin||o.phase==Phase::rollback)){
   const unsigned at=(o.phase==Phase::rollback?2U:0U)+(o.edge==Edge::after?1U:0U);++counts[at];
   if(o.edge==Edge::after)require(o.has_result&&o.sqlite_result==SQLITE_DONE&&(o.phase==Phase::rollback?(o.autocommit&&o.txn_state==SQLITE_TXN_NONE):(!o.autocommit&&o.txn_state==SQLITE_TXN_WRITE)),"actual BEGIN/ROLLBACK results and autocommit/transaction states");
  }
 }
 require(counts==std::array<unsigned,4>{1,1,1,1},"one real BEGIN and one successful real rollback for exact exhausted request");
}
__declspec(noinline) void u64_exhaustion_cases(Service*service,Probe&p){
 const std::string high(32,'2'),almost(32,'c'),alice(32,'1');
 u64_pair(job(service,JobKind::load_player,V::o({{"player_id",V::s(high)}}),"read"),u64_high_pair);
 u64_refusal(service,p,JobKind::rename_player,rename_seed(high,"18446744073709551615","Refused revision"));
 u64_refusal(service,p,JobKind::save_preferences,V::o({{"player_id",V::s(high)},{"expected_revision",V::s("18446744073709551615")},{"seed",seed_audio(0)},{"utc",V::s("2026-10-03T12:04:00Z")}}));
 u64_pair(job(service,JobKind::rename_player,rename_seed(almost,"18446744073709551614","Now maximum"),"committed","","18446744073709551614"),u64_changed_pair);
 u64_pair(job(service,JobKind::rename_player,rename_seed(alice,"5","Counter final"),"committed","","18446744073709551615"),u64_alice_pair);
 u64_pair(job(service,JobKind::rename_player,rename_seed(high,"18446744073709551615","Maximum revision"),"no_change","","18446744073709551613"),u64_high_pair);
 u64_pair(job(service,JobKind::rename_player,rename_seed(alice,"6","Counter final"),"no_change","","18446744073709551615"),u64_alice_pair);
 u64_refusal(service,p,JobKind::rename_player,rename_seed(alice,"6","Refused global counter"));
 u64_refusal(service,p,JobKind::save_preferences,V::o({{"player_id",V::s(almost)},{"expected_revision",V::s("18446744073709551615")},{"seed",seed_audio(0)},{"utc",V::s("2026-10-03T12:04:00Z")}}));
 u64_refusal(service,p,JobKind::delete_player,V::o({{"player_id",V::s(high)},{"expected_revision",V::s("18446744073709551615")}}));
 u64_pair(job(service,JobKind::load_player,V::o({{"player_id",V::s(high)}}),"read"),u64_high_pair);
 u64_pair(job(service,JobKind::load_player,V::o({{"player_id",V::s(almost)}}),"read"),u64_changed_pair);
 u64_pair(job(service,JobKind::load_player,V::o({{"player_id",V::s(alice)}}),"read"),u64_alice_pair);
 p.wait_published(p.last_request());require(status(service).state==ServiceState::ready&&p.reserved_bytes()==2097152,"exhaustion preserves ready reads and retires all transient reservations");
}
__declspec(noinline) void u64_fixture_final(const std::string&root){
 FullFixtureDb db;u64_fixture_open(root,db);sqlite3_stmt*statement{};require(sqlite3_prepare_v2(db.value,"SELECT commit_sequence FROM meta WHERE singleton=1",-1,&statement,nullptr)==SQLITE_OK,"closed actual U64 final meta read");
 require(sqlite3_step(statement)==SQLITE_ROW&&sqlite3_column_type(statement,0)==SQLITE_TEXT,"actual final meta has TEXT U64");const auto*bytes=sqlite3_column_text(statement,0);require(bytes&&std::string_view(reinterpret_cast<const char*>(bytes),static_cast<std::size_t>(sqlite3_column_bytes(statement,0)))=="18446744073709551615","actual final meta stays MAX without wrapping or hidden increments");
 require(sqlite3_step(statement)==SQLITE_DONE&&sqlite3_finalize(statement)==SQLITE_OK,"final U64 meta reader retires");db.close();
}

void full_fixture_preserve(const std::string&root,const std::string&target,const std::array<CrashFile,4>&original){
 require(original[0].present&&original[0].length<=524288&&!at_or_within(target,root),"bounded synthetic failure preservation outside protected root");
 for(unsigned i=1;i<4;++i)require(!original[i].present,"failure fixture source has explicit absent sidecars");
 auto input=std::make_unique<InputFile>();require(load_input(root+"\\players.sqlite3",original[0].hash,*input),"entire failed original pinned before preservation");
 auto wide=std::make_unique<Wide>();require(wide->set(target)&&ordinary_ancestors(*wide),"fixed proof sibling ordinary ancestors");auto operand=std::make_unique<ExtendedFileOperand>(*wide);
 Handle output(CreateFileW(operand->value.data(),GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ,nullptr,CREATE_NEW,FILE_FLAG_OPEN_REPARSE_POINT,nullptr));FileIdentity identity;
 require(output.good()&&observe_identity(output.value,false,identity)&&final_equal(output.value,*wide),"new ordinary single-link evidence file, never overwrite");
 std::size_t done=0;while(done<input->size){DWORD n{};const auto want=static_cast<DWORD>(std::min<std::size_t>(65536,input->size-done));require(WriteFile(output.value,input->bytes.data()+done,want,&n,nullptr)&&n&&n<=want,"bounded complete raw failure evidence write");done+=n;}
 require(FlushFileBuffers(output.value)!=0&&output.close()&&input->handle.close(),"actual failure-copy flush and checked handle closes");
 require(load_input(target,original[0].hash,*input)&&input->size==original[0].length&&input->handle.close(),"preserved failure evidence full bytes/hash/length verified");
}
void full_fixture_management_cleanup(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,std::uint64_t&ordinal,std::size_t cap,const std::string&root,std::size_t expected_count=1){
 require(expected_count==1||expected_count==2,"closed test retained count choice");auto original=crash_original(root);Probe p(cap);Fixture f(trust,descriptor,digest,p,ordinal++);crash_start(f,true);
 Raw listed(job(f.service,JobKind::list_recovery,V::o({}),"read"));auto rows=array(listed.d,member(listed.d,value(listed),"snapshots"));require(rows.size()==expected_count,"exact fixture retained ID count, linked WORK included by management ownership");
 std::vector<std::string> requested;std::vector<V> request_ids;for(auto row:rows){const auto id=field(listed.d,row,"id");require(lower_hex(id,32)&&std::find(requested.begin(),requested.end(),id)==requested.end(),"unique displayed fixed retained ID");requested.push_back(id);request_ids.push_back(V::s(id));}
 Raw deleted(job(f.service,JobKind::delete_recovery,V::o({{"snapshot_ids",V::a(std::move(request_ids))}}),"read"));auto value_node=value(deleted);
 auto ids=array(deleted.d,member(deleted.d,value_node,"deleted_ids"));require(ids.size()==expected_count&&array(deleted.d,member(deleted.d,value_node,"retained_ids")).empty()&&crash_directories(root).empty(),"fixture cleanup exact partition and BOTH known directories absent");for(const auto&id:requested)require(std::count_if(ids.begin(),ids.end(),[&](auto n){return text(deleted.d,n)==id;})==1,"every requested retained ID deleted exactly once");
 crash_no_sqlite(p);f.close();crash_no_sqlite(p);auto after=crash_original(root);for(unsigned i=0;i<4;++i)crash_unchanged_file(after[i],original[i]);
}
void full_fixture_failed_start(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,std::uint64_t&ordinal,std::size_t cap,const std::string&root,const std::string&proof,std::string_view error){
 auto original=crash_original(root);Probe p(cap);Fixture f(trust,descriptor,digest,p,ordinal++);
 auto a=f.service->start();require(a.accepted,"malformed complete fixture starts real qualification job");auto replies=receive(f.service,1);result(replies[0],a.request_id.view(),JobKind::start,"failed",error);require(status(f.service).state==ServiceState::unavailable,"malformed fixture remains unavailable");f.close();
 {std::lock_guard lock(p.mutex);require(std::any_of(p.events.begin(),p.events.end(),[](const NativeObservation&o){return o.phase==Phase::before_open&&o.scope==Scope::qualification_copy;}),"negative actually opens disposable qualification WORK");require(std::none_of(p.events.begin(),p.events.end(),[](const NativeObservation&o){return o.phase==Phase::before_open&&o.scope==Scope::original;}),"negative never opens original SQLite");}
 auto after=crash_original(root);for(unsigned i=0;i<4;++i)crash_unchanged_file(after[i],original[i]);
 auto leaves=crash_directories(root);require(leaves.size()==2&&std::count_if(leaves.begin(),leaves.end(),[](const std::string&s){return s.starts_with("recovery-");})==1&&std::count_if(leaves.begin(),leaves.end(),[](const std::string&s){return s.starts_with("work-");})==1,"refused source keeps finite retained and WORK artifacts");
 full_fixture_preserve(root,proof,original);
}

// Test-owned operands are heap backed by std::string/vector. No new inline
// raw-input buffer and no executable stack-reserve change.

// L08/L12/L13: two actual complete frozen exports plus ordinary queued work.
// This is maximum ROW COUNT, not maximum encoded wire size or arbitrary
// Win32 partial-progress throughput. Existing16384 gate still fails overflow.
__declspec(noinline) void shared_maximum_exports(Service*service,Probe&p,const std::string&owner,const std::string&target){
 p.wait_published(p.last_request());
 const std::array<std::string,2> targets={target+".shared-one",target+".shared-two"};
 auto payload=[&](const std::string&t){return V::o({{"player_id",V::s(owner)},{"expected_revision",V::s("3")},{"target_absolute_path",V::s(t)}});};
 auto check_export=[&](const std::string&bytes,const std::string&id,const std::string&t){result(bytes,id,JobKind::export_player,"read");Raw r(bytes);auto v=value(r);require(field(r.d,v,"outcome")=="saved"&&field(r.d,v,"phase")=="done"&&r.d.at(member(r.d,v,"installed"))->scalar==1&&nil(r.d,member(r.d,v,"temporary_absolute_path")),"shared maximum export fully installed and verified");require(field(r.d,v,"target_absolute_path")==t&&field(r.d,v,"player_id")==owner&&field(r.d,v,"preferences_revision")=="3"&&natural(r.d,member(r.d,v,"practice_count"),2000)==2000,"shared export exact coherent selected snapshot");require(natural(r.d,member(r.d,v,"bytes"),33554432)==2387415&&field(r.d,v,"sha256")=="c07ca164caffac111c5b7e3724dc00eed439502fe7bfc17523be4fa01cab74fc","unchanged independent CAP_full_2000_summary_export");auto actual=crash_file(t,33554432);require(actual.present&&actual.length==2387415&&actual.hash=="c07ca164caffac111c5b7e3724dc00eed439502fe7bfc17523be4fa01cab74fc","entire second real export independently streamed and hashed");};
 require(p.reserved_bytes()==2097152,"before shared exports no old result/credit retained");
 p.arm(JobKind::export_player,Phase::export_create,Edge::before);Capture one(JobKind::export_player,payload(targets[0]));auto first=service->submit(one);require(first.accepted,"first complete export admitted");p.wait_arrival(1);
 Capture two(JobKind::export_player,payload(targets[1]));auto second=service->submit(two);require(second.accepted,"second complete export shares credit while first held");auto second_request=p.last_request();p.follow_request(second_request);
 std::vector<std::string> reads;for(unsigned i=0;i<7;++i){Capture c(JobKind::list_players,V::o({}));auto a=service->submit(c);require(a.accepted,"seven ordinary reads coexist with two shared exports");reads.emplace_back(a.request_id.view());}
 require(status(service).pending==9&&status(service).undelivered==0&&p.reserved_bytes()==32804864,"L08 nine actual small slots plus one E leave749568bytes");
 {std::lock_guard lock(p.mutex);unsigned requests=0;for(const auto&o:p.allocations)if(o.request_ordinal>=second_request-1&&o.category==AllocationCategory::request){require(o.rounded==4096,"literal fixture request plus128byte header rounds to one actual page");++requests;}require(requests==9,"all nine actual request charges observed");}
 p.shared_spool(1,2,0,0);auto no_effects=p.event_count();refused(service,JobKind::list_players,V::o({}),Error::out_of_memory);p.no_effects_since(no_effects);require(p.reserved_bytes()==32804864,"insufficient capacity releases provisional extents exactly");
 p.release();p.wait_arrival(2);require(status(service).pending==8&&status(service).undelivered==1,"first terminal before second target IO, seven reads still queued");
 require(p.reserved_bytes()==32800768,"first request borrower retired, its T/D and shared E remain");p.shared_spool(1,2,1,0);
 std::array<DeliveryView,1> views{};std::uint8_t count{};auto allocations=p.allocation_count();require(service->peek(1,views,count)&&count==1,"owner copies first complete receipt into prepaid D");std::string owned(views[0].bytes);require(p.allocation_count()==allocations&&p.reserved_bytes()==32800768,"peek overlap retains independent T/D without new allocation");auto original=owned;owned[0]=owned[0]=='{'?'[':'{';require(views[0].bytes==original,"caller copied receipt mutation cannot affect native delivery");owned=original;
 std::array<std::uint64_t,1> lease={views[0].lease};require(service->acknowledge(lease)&&p.reserved_bytes()==31490048,"successful transfer alone frees first T/D1310720bytes");
 Capture retry(JobKind::list_players,V::o({}));auto retried=service->submit(retry);require(retried.accepted&&p.reserved_bytes()==32804864,"explicit retry now fits from poll-freed credit without releasing E");auto last_request=p.last_request();p.shared_spool(1,2,1,0);
 check_export(owned,std::string(first.request_id.view()),targets[0]);p.release();wait_done(service,9);p.wait_published(last_request);auto rows=receive(service,9);check_export(rows[0],std::string(second.request_id.view()),targets[1]);for(unsigned i=0;i<7;++i)result(rows[i+1],reads[i],JobKind::list_players,"read");result(rows[8],retried.request_id.view(),JobKind::list_players,"read");
 p.shared_spool(1,2,2,1);require(p.reserved_bytes()==2097152,"last active export/terminal borrowers fully retired");
}

__declspec(noinline) void full_maximum_cases(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,std::uint64_t&ordinal,std::size_t cap,const std::string&root,const std::string&target){
 full_fixture_setup(root,false,false,true);
 Probe p(cap);Fixture f(trust,descriptor,digest,p,ordinal++);crash_start(f);
 const std::string owner(32,'a'),extra(32,'f');
 unsigned remaining=2000;V cursor=V::null();
 for(unsigned page=0;page<40;++page){
  Raw r(job(f.service,JobKind::list_practice,V::o({{"player_id",V::s(owner)},{"before_creation_sequence",cursor},{"limit",V::i(50)}}),"read"));auto v=value(r);auto rows=array(r.d,member(r.d,v,"practice"));require(rows.size()==50,"all40 pages have50 actual summaries");
  for(auto n:rows){require(remaining!=0,"exact maximum page count");--remaining;require(canonical(r.d,n)==full_max_record(remaining,true),"whole frozen maximum summary in numeric creation DESC order");}
  auto next=member(r.d,v,"next_before_creation_sequence");if(remaining){require(text(r.d,next)==std::to_string(remaining+2),"exact strict numeric continuation after50 rows");cursor=V::s(text(r.d,next));}else require(nil(r.d,next),"2000th summary ends with null continuation");
 }
 require(remaining==0,"no omitted or duplicate maximum summary");
 {Raw r(job(f.service,JobKind::list_practice,V::o({{"player_id",V::s(owner)},{"before_creation_sequence",V::s("0")},{"limit",V::i(50)}}),"read"));auto v=value(r);require(array(r.d,member(r.d,v,"practice")).empty()&&nil(r.d,member(r.d,v,"next_before_creation_sequence")),"maximum numeric zero cursor remains empty");}
 shared_maximum_exports(f.service,p,owner,target);
 const auto export_target=target+".maximum";
 {Raw r(job(f.service,JobKind::export_player,V::o({{"player_id",V::s(owner)},{"expected_revision",V::s("3")},{"target_absolute_path",V::s(export_target)}}),"read"));auto v=value(r);
  require(field(r.d,v,"outcome")=="saved"&&field(r.d,v,"phase")=="done"&&r.d.at(member(r.d,v,"installed"))->scalar==1&&nil(r.d,member(r.d,v,"temporary_absolute_path")),"maximum export actual installed and verified");
  require(natural(r.d,member(r.d,v,"practice_count"),2000)==2000&&field(r.d,v,"preferences_revision")=="3"&&field(r.d,v,"player_id")==owner,"coherent maximum snapshot receipt");
  require(natural(r.d,member(r.d,v,"bytes"),33554432)==2387415&&field(r.d,v,"sha256")=="c07ca164caffac111c5b7e3724dc00eed439502fe7bfc17523be4fa01cab74fc","receipt equals independently frozen whole2000 export bytes/hash");
  auto actual=crash_file(export_target,33554432);require(actual.present&&actual.length==2387415&&actual.hash=="c07ca164caffac111c5b7e3724dc00eed439502fe7bfc17523be4fa01cab74fc","independent entire2387415-byte streaming read/hash, not512KiB prefix");
 }
 job(f.service,JobKind::begin_practice,begin_seed(extra,owner,"maximum-replacement"),"failed","history_limit");
 {Raw r(job(f.service,JobKind::load_practice,V::o({{"player_id",V::s(owner)},{"practice_id",V::s(full_max_id(2000))}}),"read"));require(canonical(r.d,practice(r))==full_max_record(1999,false),"2001st refusal preserves whole existing last record");}
 job(f.service,JobKind::prune_practice,V::o({{"player_id",V::s(owner)},{"practice_ids",V::a({V::s(full_max_id(1))})}}),"committed","","2002");
 {Raw r(job(f.service,JobKind::begin_practice,begin_seed(extra,owner,"maximum-replacement"),"committed","","2003"));require(field(r.d,practice(r),"creation_sequence")=="2003","no hidden counter increment on2001st refusal; removed count credit admits replacement");}
 {Raw r(job(f.service,JobKind::list_practice,V::o({{"player_id",V::s(owner)},{"before_creation_sequence",V::null()},{"limit",V::i(2)}}),"read"));auto v=value(r);auto rows=array(r.d,member(r.d,v,"practice"));require(rows.size()==2&&field(r.d,rows[0],"id")==extra&&field(r.d,rows[0],"creation_sequence")=="2003"&&canonical(r.d,rows[1])==full_max_record(1999,true)&&text(r.d,member(r.d,v,"next_before_creation_sequence"))=="2001","insert/delete keeps immutable numeric creation page and strict cursor");}
 job(f.service,JobKind::begin_practice,begin_seed(std::string(32,'e'),owner,"maximum-still-full"),"failed","history_limit");
 f.close();require(actual_events.load()<=cap,"maximum path retains original16384 actual-event ceiling");
}

// Original independent dense-valid fixture. Exact oracle is private expected.json;
// no MAX_R, device availability, calibration or Godot conversion-OOM claim.
std::string dense_slot(unsigned index){require(index<8,"dense declared slot index");return std::string("Slot")+static_cast<char>('A'+index)+std::string(27,'a');}
V dense_sources(unsigned first){
 std::vector<V> out;for(unsigned i=first;i<first+4;++i)out.push_back(V::o({{"kind",V::s("joy_button")},{"slot",V::s(dense_slot(i%8))},{"index",V::i(i/8)}}));return V::a(std::move(out));
}
V dense_preset(unsigned version){
 require(version==1||version==2,"dense closed preset version");
 constexpr std::string_view targets[]={"roll","pitch","yaw","throttle","mixture","left_brake","right_brake","trim"};
 constexpr std::string_view actions[]={"pause_menu","restart","start_ground","start_airborne","idle","left_brake","right_brake","both_brakes","brake_hold","view_cycle","view_cockpit","view_chase","view_orbit","view_panel","map_toggle","runway_toggle","map_zoom_in","map_zoom_out","look_hold","view_zoom_in","view_zoom_out","recenter","help","overlay","controller_select","audio","fullscreen","speed_down","speed_up","controls_panel"};
 constexpr std::string_view systems[]={"engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"};
 std::vector<V> devices,axes,bindings,held;
 for(unsigned i=0;i<8;++i)devices.push_back(V::o({{"slot",V::s(dense_slot(i))},{"label",V::s(std::string(64,'\1'))},{"match",V::o({{"guid",V::s(std::string(128,'\1'))},{"name",V::s(std::string(128,'\1'))},{"vendor_id",V::s(std::string(16,'\1'))},{"product_id",V::s(std::string(16,'\1'))}})}}));
 for(unsigned i=0;i<8;++i){
  if(version==1&&i==4){axes.push_back(V::o({{"target",V::s("mixture")},{"kind",V::s("fixed")},{"value",V::f(UINT64_C(0x3ff0000000000000))}}));continue;}
  const bool centered=i<3||i==7;
  axes.push_back(V::o({{"target",V::s(std::string(targets[i]))},{"kind",V::s("joy_axis")},{"slot",V::s(dense_slot(i))},{"index",V::i(i)},{"range",V::s(centered?"centered":"unsigned")},
   {"minimum",V::f(centered?UINT64_C(0xbff0000000000000):UINT64_C(0))},{"center",V::f(UINT64_C(0x8000000000000000))},{"maximum",V::f(UINT64_C(0x3ff0000000000000))},
   {"invert",V::b(false)},{"deadzone",V::f(UINT64_C(0x8000000000000000))},{"saturation",V::f(UINT64_C(0x3ff0000000000000))},{"gain",V::f(UINT64_C(0x3ff0000000000000))},{"slew_per_s",V::f(UINT64_C(1))}}));
 }
 for(unsigned i=0;i<std::size(actions);++i)bindings.push_back(V::o({{"id",V::s(std::string(actions[i]))},{"sources",dense_sources(4*i)}}));
 V out=V::o({{"type",V::s("InputPreset")},{"version",V::i(version)},{"name",V::s(std::string(64,'\1'))},{"devices",V::a(std::move(devices))},{"axes",V::a(std::move(axes))},{"actions",V::a(std::move(bindings))}});
 if(version==2){
  for(unsigned i=0;i<std::size(systems);++i)held.push_back(V::o({{"id",V::s(std::string(systems[i]))},{"kind",V::s(i==2?"momentary":"toggle")},{"sources",dense_sources(120+4*i)}}));
  out.fields.emplace_back("profile",V::o({{"id",V::s("original-piston-prop-v1")},{"version",V::s("0.1.0-prototype")},{"backend_model",V::s("original-piston-prop")}}));
  out.fields.emplace_back("capability_revision",V::s("piston-controls-v1"));out.fields.emplace_back("systems",V::a(std::move(held)));
 }
 return out;
}
__declspec(noinline) void dense_dual_preset_cases(Service* service,Probe& probe){
 const std::string owner(32,'c');
 V seed=V::o({{"legacy_input",dense_preset(1)},{"piston_input",dense_preset(2)},{"audio",V::o({{"enabled",V::b(true)},{"engine_gain",V::f(UINT64_C(0x8000000000000000))},{"airflow_gain",V::f(UINT64_C(1))},{"show_panel_captions",V::b(false)}})}});
 Capture input(JobKind::save_preferences,V::o({{"player_id",V::s(owner)},{"expected_revision",V::s("2")},{"seed",std::move(seed)},{"utc",V::s("2026-10-03T12:05:00Z")}}));
 // Constructor versus independently authored exact oracle, before admission.
 {std::vector<JsonCell> cells(8192);std::vector<char> text_buffer(max_message),encoded(max_message);DocumentView document;RequestView request;
  require(input.capture(cells,text_buffer,document)==Error::none,"dense constructor bounded capture");
  require(validate_capture(document,Limits{max_message,30000,12,4096,4096})==Error::none&&validate_request(document,request,false,cells)==Error::none,"dense full closed Controls/Audio record validation before queue");
  Writer writer(encoded);require(writer.value(document,document.root)&&writer.bytes().size()==65078&&digest_text(writer.bytes())=="c1a10be4bc7076abdf78672ecadf756a46bc95a24539cd7e39a2bc1095962545","whole independent dense canonical request exact size/hash");
  auto actual_seed=member(document,member(document,document.root,"payload"),"seed");
  require(digest_text(canonical(document,actual_seed))=="fe8ea7c187d4965ac0b87e70ea07f632a34334271924e7a7e61449e3e51d5f02","whole independent dense seed exact bits and fields");
 }
 probe.wait_published(probe.last_request()); // Prior rename ACK may precede its R-release notification.
 require(probe.reserved_bytes()==2097152,"dense fixture starts with only permanent arena ownership");
 probe.arm(JobKind::save_preferences,Phase::before_begin,Edge::before);
 auto admitted=service->submit(input);require(admitted.accepted&&admitted.error==Error::none,"dense valid request admitted");const auto request=probe.last_request();probe.wait();
 require(probe.reserved_bytes()==3473408,"dense actual R65536 plus T/D655360 each and permanent arena");
 {std::lock_guard lock(probe.mutex);std::array<unsigned,3> found{};
  for(const auto& observation:probe.allocations)if(observation.request_ordinal==request){
   if(observation.category==AllocationCategory::request){require(observation.requested==65206&&observation.rounded==65536,"dense R65078 plus128 header rounds to sixteen actual pages");++found[0];}
   else if(observation.category==AllocationCategory::terminal){require(observation.requested==655360&&observation.rounded==655360,"dense full real T reservation");++found[1];}
   else if(observation.category==AllocationCategory::delivery){require(observation.requested==655360&&observation.rounded==655360,"dense full real D reservation");++found[2];}
   else require(false,"dense request has no export credit or replacement arena allocation");
  }
  require(found==std::array<unsigned,3>{1,1,1},"exact three dense admission allocation observations");
 }
 input.value=V::null(); // Destroy caller tree while worker is held before BEGIN.
 probe.release();probe.wait_published(request);
 require(probe.reserved_bytes()==3407872,"dense completed R released while full T/D remain");
 auto check_pair=[&](const std::string& bytes,JobKind kind,std::string_view id){
  result(bytes,id,kind,kind==JobKind::save_preferences?"committed":"read","",kind==JobKind::save_preferences?"20":"");
  require(bytes.size()==(kind==JobKind::save_preferences?65396u:65386u),"dense entire terminal encoded length includes complete fixed envelope");
  Raw actual(bytes);auto pair=value(actual);auto canonical_pair=canonical(actual.d,pair);
  require(canonical_pair.size()==65253&&digest_text(canonical_pair)=="27227b52665b91b44266fa48584e6fa56c6527c22b2a3a8efcc137f3bb147a55","whole dense player and preferences frozen oracle equality");
  auto preferences=member(actual.d,pair,"preferences");auto canonical_preferences=canonical(actual.d,preferences);
  require(canonical_preferences.size()==65037&&digest_text(canonical_preferences)=="616055be5c185a11f3f2352b32d3cd93a0abb0631395066cb67c2af5316dc71b","all dense preference fields and exact FLOAT tags preserved");
  require(validate_preferences(actual.d,preferences,true,actual.cells)==Error::none,"dense restored full typed preferences");
  std::vector<char> payload(max_message),storage(max_preferences);Writer envelope(storage);
  require(encode_preferences(actual.d,preferences,envelope,payload)==Error::none&&envelope.bytes().size()==75354&&digest_text(envelope.bytes())=="c3ad783f81be754456094fe992ca7a9d29a906c5cc37e492bceadd6a7d401d7c","dense reconstructed canonical storage envelope exact independent size/hash");
 };
 std::array<DeliveryView,1> views{};std::uint8_t count{};const auto allocations=probe.allocation_count();
 require(service->peek(1,views,count)&&count==1,"dense owner peeks entire prepaid delivery");std::string owned(views[0].bytes);const auto saved_hash=digest_text(owned);const auto old_lease=views[0].lease;
 check_pair(owned,JobKind::save_preferences,admitted.request_id.view());
 require(probe.allocation_count()==allocations&&probe.reserved_bytes()==3407872,"dense peek retains T/D and requires no new native allocation");
 std::array<std::uint64_t,1> leases={old_lease};require(service->abandon(leases),"dense caller deliberately declines delivery; no manufactured engine OOM");
 require(status(service).pending==0&&status(service).undelivered==1&&probe.reserved_bytes()==3407872,"dense abandon preserves queued terminal and T/D");
 require(service->peek(1,views,count)&&count==1&&views[0].lease!=old_lease&&views[0].bytes==owned,"dense exact bytes reacquired under a fresh delivery lease");
 require(probe.allocation_count()==allocations&&probe.reserved_bytes()==3407872,"dense retry still uses original T/D");
 leases[0]=views[0].lease;require(service->acknowledge(leases)&&probe.reserved_bytes()==2097152,"dense successful transfer releases exactly original T/D");
 Capture load(JobKind::load_player,V::o({{"player_id",V::s(owner)}}));auto read=service->submit(load);require(read.accepted&&read.error==Error::none,"dense SQL-backed reload admitted after delivery retirement");const auto load_request=probe.last_request();
 auto rows=receive(service,1);require(rows.size()==1,"dense one complete SQL-backed load result");check_pair(rows[0],JobKind::load_player,read.request_id.view());
 probe.wait_published(load_request); // Wait for the exact reload R-release notification, beyond ACK.
 require(digest_text(owned)==saved_hash&&probe.reserved_bytes()==2097152,"dense returned copy survives subsequent native slot reuse and exact release");
}

// Original MIT. Exact DN_hash_mismatch and DN_shared_revision frozen inputs.
// expected-v1.json SHA164aad9b74de33b04a6a69734116eab899dceaf696135137b9963f679968b722.
constexpr std::string_view rejected_shared_player=R"LPREJECT({"created_utc":"2000-02-29T00:00:00Z","id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","name":"Ana \"Δ\" \\ 飛行","revision":"4","type":"LocalPlayer","updated_utc":"2026-10-11T06:00:00Z","version":1})LPREJECT";
constexpr std::string_view rejected_shared_hash="8beae7b38e81159de0590449182d41cc766e80528da90f425cfa2b4e2dbde870";
void full_rejected_record_mutation(sqlite3*db,bool shared_revision){
 const std::string zero_hash(64,'0');sqlite3_stmt*raw{};
 const char*sql=shared_revision?"UPDATE players SET revision='4',record=?1,record_sha256=?2 WHERE id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'":"UPDATE practices SET record_sha256=?1 WHERE id='11111111111111111111111111111111'";
 const int prepared=sqlite3_prepare_v2(db,sql,-1,&raw,nullptr);std::unique_ptr<sqlite3_stmt,decltype(&sqlite3_finalize)> statement(raw,sqlite3_finalize);
 require(prepared==SQLITE_OK&&statement,"closed exact frozen mutant statement");
 if(shared_revision){
  require(sqlite3_bind_blob(statement.get(),1,rejected_shared_player.data(),static_cast<int>(rejected_shared_player.size()),SQLITE_STATIC)==SQLITE_OK&&sqlite3_bind_text(statement.get(),2,rejected_shared_hash.data(),static_cast<int>(rejected_shared_hash.size()),SQLITE_STATIC)==SQLITE_OK,"exact frozen internally coherent Player BLOB/hash");
 }else require(sqlite3_bind_text(statement.get(),1,zero_hash.data(),static_cast<int>(zero_hash.size()),SQLITE_STATIC)==SQLITE_OK,"frozen all-zero Practice hash conflict");
 require(sqlite3_step(statement.get())==SQLITE_DONE&&sqlite3_changes(db)==1,"exactly one selected row changed");require(sqlite3_finalize(statement.release())==SQLITE_OK,"mutant statement retired before inspection");
 raw=nullptr;sql=shared_revision?"SELECT record,record_sha256,revision FROM players WHERE id='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'":"SELECT record,record_sha256,revision FROM practices WHERE id='11111111111111111111111111111111'";
 const int checked=sqlite3_prepare_v2(db,sql,-1,&raw,nullptr);statement.reset(raw);
 require(checked==SQLITE_OK&&statement&&sqlite3_step(statement.get())==SQLITE_ROW&&sqlite3_column_type(statement.get(),0)==SQLITE_BLOB&&sqlite3_column_type(statement.get(),1)==SQLITE_TEXT&&sqlite3_column_type(statement.get(),2)==SQLITE_TEXT,"actual selected mutant BLOB/TEXT branches");
 const auto*blob=static_cast<const char*>(sqlite3_column_blob(statement.get(),0));const auto*hash=sqlite3_column_text(statement.get(),1);const auto*revision=sqlite3_column_text(statement.get(),2);
 const auto expected_record=shared_revision?rejected_shared_player:full_fixture_practices[0].record;const auto expected_hash=shared_revision?rejected_shared_hash:std::string_view(zero_hash);
 require(blob&&hash&&revision&&std::string_view(blob,static_cast<std::size_t>(sqlite3_column_bytes(statement.get(),0)))==expected_record&&std::string_view(reinterpret_cast<const char*>(hash),static_cast<std::size_t>(sqlite3_column_bytes(statement.get(),1)))==expected_hash&&std::string_view(reinterpret_cast<const char*>(revision),static_cast<std::size_t>(sqlite3_column_bytes(statement.get(),2)))==(shared_revision?"4":"2"),"exact frozen selected row BLOB/hash/revision");
 require(sqlite3_step(statement.get())==SQLITE_DONE&&sqlite3_finalize(statement.release())==SQLITE_OK,"one exact selected row inspection retired");
}
__declspec(noinline) void full_rejected_record_setup(const std::string&root,bool shared_revision){
 // The file must already exist as the joined synthetic store. No SQLite CREATE.
 auto before=crash_file(root+"\\players.sqlite3",33554432);require(before.present,"existing isolated main before independent row setup");
 std::string uri="file:";constexpr char hex[]="0123456789ABCDEF";
 for(unsigned char c:root+"\\players.sqlite3"){
  if(c=='\\')uri+='/';else if((c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='/'||c==':'||c=='-'||c=='_'||c=='.')uri+=static_cast<char>(c);
  else{uri+='%';uri+=hex[c>>4];uri+=hex[c&15];}
 }
 uri+="?exclusive=1";FullFixtureDb db;
 require(sqlite3_open_v2(uri.c_str(),&db.value,SQLITE_OPEN_READWRITE|SQLITE_OPEN_URI|SQLITE_OPEN_NOMUTEX,nullptr)==SQLITE_OK,"actual existing-only test SQLite open");
 full_fixture_schema_check(db.value,!shared_revision); // first follows exact SQLN_extra_trigger; second follows SQL_exact
 full_fixture_exec(db.value,"PRAGMA locking_mode=EXCLUSIVE;PRAGMA foreign_keys=ON;BEGIN IMMEDIATE;");
 if(!shared_revision)full_fixture_exec(db.value,"DROP TRIGGER extra;");
 full_fixture_exec(db.value,"DELETE FROM practices;DELETE FROM preferences;DELETE FROM players;DELETE FROM meta;");
 for(auto sql:full_fixture_inserts)full_fixture_exec(db.value,sql);
 full_rejected_record_mutation(db.value,shared_revision);
 full_fixture_exec(db.value,"COMMIT;");full_fixture_schema_check(db.value,false);full_fixture_exec(db.value,"VACUUM;");db.close();
 auto after=crash_file(root+"\\players.sqlite3",33554432);require(after.present&&same_identity(before.identity,after.identity)&&after.length<=524288,"fixture setup keeps main identity and explicitly shrinks reset D01 for bounded failure copies");
 for(unsigned i=1;i<4;++i)require(!crash_file(root+"\\"+std::string(crash_data_names[i]),crash_caps[i]).present,"fully closed fixed fixture leaves no SQLite sidecar before qualification");
}

__declspec(noinline) void full_record_store_cases(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,std::uint64_t ordinal,std::size_t cap,const std::string&root,const std::string&target){
 require(crash_directories(root).empty(),"existing joined fixture management cleanup finished");
 full_fixture_setup(root,false,false);
 {Probe p(cap);Fixture f(trust,descriptor,digest,p,ordinal++);crash_start(f);
  for(const auto&expected:full_fixture_pairs){Raw loaded(job(f.service,JobKind::load_player,V::o({{"player_id",V::s(std::string(expected.id))}}),"read"));auto pair=value(loaded);require(canonical(loaded.d,member(loaded.d,pair,"player"))==expected.player&&canonical(loaded.d,member(loaded.d,pair,"preferences"))==expected.preferences,"whole accepted D01 player/preferences bytes, all rich numeric families preserved");}
  for(const auto&expected:full_fixture_practices){Raw loaded(job(f.service,JobKind::load_practice,V::o({{"player_id",V::s(std::string(expected.owner))},{"practice_id",V::s(std::string(expected.id))}}),"read"));require(canonical(loaded.d,practice(loaded))==expected.record,"whole accepted D01 Practice/source/archive/U64 bytes preserved");}
  // D01 has two players. Six ordinary creates reach eight; ninth must fail
  // without advancing global sequence18 or changing any existing player.
  constexpr char additional[]="cdef01";for(unsigned i=0;i<6;++i){const std::string id(32,additional[i]);paired(job(f.service,JobKind::create_player,player_seed(id,"Boundary"+std::to_string(i)),"committed","",std::to_string(13+i)),id,"1","Boundary"+std::to_string(i));}
  auto before=job(f.service,JobKind::list_players,V::o({}),"read");job(f.service,JobKind::create_player,player_seed(std::string(32,'2'),"Ninth"),"failed","player_limit");auto after=job(f.service,JobKind::list_players,V::o({}),"read");
  Raw b(before),a(after);require(canonical(b.d,value(b))==canonical(a.d,value(a))&&array(a.d,member(a.d,value(a),"players")).size()==8,"ninth-player refusal preserves exact eight-player summaries");
  job(f.service,JobKind::create_player,player_seed(std::string(32,'c'),"Boundary0"),"no_change","","13");
  paired(job(f.service,JobKind::rename_player,rename_seed(std::string(32,'c'),"1","Boundary0 renamed"),"committed","","19"),std::string(32,'c'),"2","Boundary0 renamed");dense_dual_preset_cases(f.service,p);f.close();
 }
 full_maximum_cases(trust,descriptor,digest,ordinal,cap,root,target);
 full_fixture_management_cleanup(trust,descriptor,digest,ordinal,cap,root,2);
 full_fixture_setup(root,true,false);
 full_fixture_failed_start(trust,descriptor,digest,ordinal,cap,root,target+".dn","corrupt_store");
 full_fixture_management_cleanup(trust,descriptor,digest,ordinal,cap,root);
 full_fixture_setup(root,false,true);
 full_fixture_failed_start(trust,descriptor,digest,ordinal,cap,root,target+".schema","foreign_store");
 require(actual_events.load()<=cap,"unchanged16384 aggregate actual-event ceiling for expanded store driver");
 // Final malformed original + recovery/WORK and both verified sibling raw
 // failure copies remain for Root inspection. No repair or cleanup is a pass.
 // Original .dn/.schema proof copies above stay byte-exact. Explicit management
 // retires each known linked retained/WORK pair before restoring the next
 // closed reference input; only the last new rejected set stays retained.
 full_fixture_management_cleanup(trust,descriptor,digest,ordinal,cap,root);
 full_rejected_record_setup(root,false);
 full_fixture_failed_start(trust,descriptor,digest,ordinal,cap,root,target+".dn-hash","corrupt_store");
 full_fixture_management_cleanup(trust,descriptor,digest,ordinal,cap,root);
 full_rejected_record_setup(root,true);
 full_fixture_failed_start(trust,descriptor,digest,ordinal,cap,root,target+".dn-shared","corrupt_store");
 require(actual_events.load()<=cap,"two appended full-record negatives retain unchanged16384 actual-event ceiling");
}
void crash_postverify_scopes(Probe&p){std::lock_guard lock(p.mutex);for(auto scope:{Scope::qualification_copy,Scope::original})require(std::any_of(p.events.begin(),p.events.end(),[&](const NativeObservation&o){return o.kind==JobKind::start&&o.scope==scope&&o.phase==Phase::postverify&&o.edge==Edge::after;}),"actual WORK and original full postverify notifications");}
bool crash_stage_name(std::string_view stage){
 for(auto name:crash_case_ids){auto suffix=(name=="intent_before_write"||name=="copy_after_read"||name=="copy_after_write"||name=="work_before_sqlite"||name=="two_partial_limit"||name.starts_with("export_"))?"_inspect":"_reopen";if(stage==std::string(name)+"_prepare"||stage==std::string(name)+suffix)return true;}return false;
}
void crash_stage(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,const Plan&plan,const std::string&root,const std::string&parent){
 const std::string stage(plan.stage.view());const bool preparing=stage.ends_with("_prepare");auto split=stage.rfind('_');require(split!=stage.npos,"fixed crash stage suffix");const std::string name=stage.substr(0,split);require(std::find(crash_case_ids.begin(),crash_case_ids.end(),name)!=crash_case_ids.end(),"fixed scenario ID");std::uint64_t ordinal=plan.service;CrashRootAdmission root_admission(trust,descriptor,digest,ordinal++);
 if(preparing){
  Probe p(plan.events);{Fixture f(trust,descriptor,digest,p,ordinal++);auto before=crash_original(root);for(const auto&file:before)require(!file.present,"fresh preparation has no preexisting database files");require(crash_directories(root).empty(),"fresh preparation has no retained/work sets");if(name=="wal_schema"){f.close();crash_no_sqlite(p);}else crash_prepare(f,name);}
  crash_original(root);require(crash_directories(root).empty(),"ordinary joined preparation created no recovery sets");crash_observations.push_back("{\"kind\":\"quiescence\",\"ever_worker\":"+std::string(name=="wal_schema"?"false":"true")+",\"actual_join\":true}");return;
 }
 // Root MUST have independently observed the actual actor86 and drained its
 // authenticated pipes BEFORE this distinct-process invocation. This driver
 // has no previous-process handle/input and never asserts that fact itself.
 auto original=crash_original(root,name=="wal_schema");require(original[0].present,"existing ordinary original main required");
 const bool copy_case=name=="intent_before_write"||name=="copy_after_read"||name=="copy_after_write"||name=="work_before_sqlite"||name=="two_partial_limit";
 auto sets=crash_sets(root,original,copy_case);crash_work_link(sets);
 if(name=="wal_schema"){
  require(sets.empty(),"fresh schema crash preceded any snapshot");crash_wal_schema(original);Probe p(plan.events);Fixture f(trust,descriptor,digest,p,ordinal++);crash_start(f);Raw players(job(f.service,JobKind::list_players,V::o({}),"read"));require(array(players.d,member(players.d,value(players),"players")).empty(),"committed fresh schema has no invented player");crash_postverify_scopes(p);f.close();auto completed=crash_sets(root,original,true);crash_retained_shape(completed,1,0);require(completed[0].complete,"actual pre-open source preserved in immutable complete manifest");return;
 }
 if(copy_case){
  if(name=="intent_before_write"){crash_retained_shape(sets,1,0);require(!sets[0].valid_intent&&!sets[0].complete&&sets[0].intent.present&&sets[0].intent.length==0,"actual empty CreateNew intent remnant");}
  if(name=="copy_after_read"||name=="copy_after_write"){crash_retained_shape(sets,1,0);crash_partial_prefix(root,sets[0],original,name=="copy_after_write");}
  if(name=="work_before_sqlite"){crash_retained_shape(sets,1,1);require(std::any_of(sets.begin(),sets.end(),[](const CrashSet&s){return !s.work&&s.complete;}),"complete retained before qualification-copy SQLite");}
  if(name=="two_partial_limit"){crash_retained_shape(sets,2,0);for(const auto&set:sets)crash_partial_prefix(root,set,original,true);}
  if(name=="work_before_sqlite"||name=="two_partial_limit"){Probe p(plan.events);Fixture f(trust,descriptor,digest,p,ordinal++);crash_refused_start(f,p,name=="two_partial_limit"?"recovery_limit":"recovery_required");}
  {Probe p(plan.events);Fixture f(trust,descriptor,digest,p,ordinal++);crash_start(f,true);crash_list(f.service,sets);crash_no_sqlite(p);if(name=="work_before_sqlite")crash_delete_sharing_retry(f.service,p,sets,root,original);else crash_delete(f.service,sets,root,name=="intent_before_write");crash_no_sqlite(p);f.close();crash_no_sqlite(p);}
  if(name=="intent_before_write"){
   auto still=crash_sets(root,original,true);crash_retained_shape(still,1,0);require(still[0].intent.hash==sets[0].intent.hash&&same_identity(still[0].intent.identity,sets[0].intent.identity),"external-management remnant retained unchanged");return;
  }
  {Probe p(plan.events);Fixture f(trust,descriptor,digest,p,ordinal++);crash_start(f);crash_pair(f.service);crash_history(f.service,false,false);crash_postverify_scopes(p);f.close();}return;
 }
 if(name=="pre_intent_read")require(sets.empty(),"header-only crash leaves no created recovery set");
 else {crash_retained_shape(sets,1,0);require(sets[0].complete,"actor initial start had actual complete retained original");}
 if(name.starts_with("export_"))crash_export_observed(parent,parent+"\\local-players-crash-export-"+std::string(plan.nonce.view())+".json",name);
 Probe p(plan.events);Fixture f(trust,descriptor,digest,p,ordinal++);const bool interrupted=name=="interrupt_before_commit";crash_start(f,false,false,interrupted);if(name.starts_with("delete_"))crash_delete_reopened(f.service,name=="delete_after_commit");else{crash_pair(f.service,name=="after_commit"||name=="publish_ack");crash_history(f.service,name.starts_with("export_"),name.starts_with("interrupt_"));}crash_postverify_scopes(p);f.close();
}
std::string crash_receipt(const Plan&plan,const Arguments&args){
 require(crash_observations.size()<=128,"closed bounded observations count");std::string observations="[";for(const auto&row:crash_observations){if(observations.size()>1)observations+=',';observations+=row;}observations+=']';
 require(observations.size()<=131072,"finite stage observation JSON bytes");
 return "{\"schema\":\"LocalPlayersCrashStageReceipt/v1\",\"stage\":"+crash_quote(plan.stage.view())+",\"stage_only\":true,\"pid\":"+std::to_string(GetCurrentProcessId())+",\"nonce\":"+crash_quote(plan.nonce.view())+",\"descriptor_sha256\":"+crash_quote(args.descriptor_sha.view())+",\"plan_sha256\":"+crash_quote(args.plan_sha.view())+",\"checks\":"+std::to_string(checks.load())+",\"actual_events\":"+std::to_string(actual_events.load())+",\"joined\":true,\"observations\":"+observations+"}";
}

} // namespace
#endif

#if defined(_WIN32)
int wmain(int argc,wchar_t**argv){
 try{Arguments args;require(arguments(argc,argv,args,true),"closed argv");auto&cf=inputs.context;auto&pf=inputs.plan;auto&df=inputs.descriptor;Context ctx;Plan plan;FixedText<4096>root;
 require(load_input(args.context.view(),args.context_sha.view(),cf)&&context_from({cf.bytes.data(),cf.size},ctx,args.suite),"actual immutable context input");require(ctx.capability_sha.view()==args.descriptor_sha.view()&&ctx.plan_sha.view()==args.plan_sha.view(),"context binds both supplied raw input hashes");
 require(load_input(args.plan.view(),args.plan_sha.view(),pf)&&plan_from({pf.bytes.data(),pf.size},plan,args.suite),"closed ordered source-frozen test plan");require(load_input(args.descriptor.view(),args.descriptor_sha.view(),df)&&descriptor_root({df.bytes.data(),df.size},plan,root),"bound root descriptor and nonce");
 require(!at_or_within(args.context.view(),root.view())&&!at_or_within(args.plan.view(),root.view())&&!at_or_within(args.descriptor.view(),root.view())&&module_hash(ctx.actor_sha.view()),"inputs outside selected root and actual executable hash");Handle parent;require(actual_parent(ctx.parent_pid)&&parent_from(ctx,parent),"actual direct parent PID plus creation/liveness");

 auto trust=TestRootFactory::prepare_prerequisite(ctx.source.view(),ctx.parent.view());require(trust.valid(),"actual read-only source/proof/KnownFolder prerequisite");
 if(args.suite=="crash")crash_stage(trust,{df.bytes.data(),df.size},args.descriptor_sha.view(),plan,std::string(root.view()),std::string(ctx.parent.view()));
 else store_cases(trust,{df.bytes.data(),df.size},args.descriptor_sha.view(),plan.service,plan.events,std::string(root.view()),std::string(ctx.parent.view())+"\\local-players-"+std::string(plan.nonce.view())+"-export.json");
 require(WaitForSingleObject(parent.value,0)==WAIT_TIMEOUT,"actual supervisor still alive at final result");require(trust.retire()&&cf.handle.close()&&pf.handle.close()&&df.handle.close()&&parent.close(),"explicit prerequisite/input/parent retirement");
 if(args.suite=="crash"){require(actual_events.load()<=plan.events,"bounded actual stage event count");std::cout<<crash_receipt(plan,args)<<"\n";}
 else std::cout<<"LocalPlayers focused "<<args.suite<<" checks="<<checks.load()<<" actual_events="<<actual_events.load()<<" PASS\n";return 0;
 }catch(const std::exception&e){std::cerr<<"LocalPlayers focused failure: "<<e.what()<<"\n";return 1;}catch(...){std::cerr<<"LocalPlayers focused unknown failure\n";return 1;}
}
#else
int main(){std::cerr<<"Windows-only real storage test; Linux codec has its separate allocated executable\n";return 2;}
#endif
