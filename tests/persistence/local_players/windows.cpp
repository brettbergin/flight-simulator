// Original MIT. Windows qualification source; no runtime evidence inferred.
// Closed context/typed capture/terminal helpers are mechanically retained from
// the separately pinned focused native v2 source. Windows cases below are new.
// Test-owned buffers/fixtures are not service arena or production factories.
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
#include <winioctl.h>
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
 explicit Probe(std::size_t cap):maximum(cap){events.reserve(cap);allocations.reserve(cap);}
 void arm(JobKind k,Phase p,Edge e,bool throws=false){std::lock_guard lock(mutex);require(!armed,"one actual test barrier");gate_kind=k;gate_phase=p;gate_edge=e;armed=true;arrived=false;released=false;throw_after_release=throws;allocation_gate.reset();}
 void arm_allocation(AllocationCategory c){std::lock_guard lock(mutex);require(!allocation_armed,"one allocation barrier");allocation_armed=true;allocation_arrived=false;allocation_released=false;allocation_gate=c;}
 void wait_allocation(){std::unique_lock lock(mutex);require(cv.wait_for(lock,std::chrono::seconds(30),[&]{return allocation_arrived||overflow;}),"actual allocation notification arrived");require(allocation_arrived&&!overflow,"valid allocation arrival");}
 void release_allocation(){std::lock_guard lock(mutex);allocation_released=true;cv.notify_all();}
 void wait(){std::unique_lock lock(mutex);require(cv.wait_for(lock,std::chrono::seconds(30),[&]{return arrived||overflow;}),"actual notification arrived before test deadline");require(arrived&&!overflow,"actual valid barrier arrival");}
 void release(){std::lock_guard lock(mutex);released=true;cv.notify_all();}
 void hold(std::unique_lock<std::mutex>&lock){arrived=true;cv.notify_all();bool ok=cv.wait_for(lock,std::chrono::seconds(30),[&]{return released;});armed=false;if(!ok)throw std::runtime_error("test barrier expired");if(throw_after_release){throw_after_release=false;throw std::runtime_error("selected actual observer throw");}}
 void observe(const NativeObservation&o)override {
  std::unique_lock lock(mutex);if(actual_events.fetch_add(1)>=maximum||events.size()>=maximum){overflow=true;throw std::runtime_error("test observation capacity");}events.push_back(o);cv.notify_all();
  if(armed&&o.kind==gate_kind&&o.phase==gate_phase&&o.edge==gate_edge)hold(lock);
 }
 bool allow_allocation(const AllocationObservation&o)override {
  std::unique_lock lock(mutex);if(actual_events.fetch_add(1)>=maximum||allocations.size()>=maximum){overflow=true;return false;}allocations.push_back(o);cv.notify_all();
  if(allocation_armed&&allocation_gate&&o.category==*allocation_gate){allocation_arrived=true;cv.notify_all();bool ok=cv.wait_for(lock,std::chrono::seconds(30),[&]{return allocation_released;});allocation_armed=false;if(!ok)throw std::runtime_error("allocation test barrier expired");}
  if(refuse_next){refuse_next=false;return false;}return true;
 }
 void observe_reservation(const ReservationObservation&)override {std::lock_guard lock(mutex);++claims;if(actual_events.fetch_add(1)>=maximum){overflow=true;throw std::runtime_error("reservation event capacity");}if(throw_claim){throw_claim=false;throw std::runtime_error("selected create claim throw");}}
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
[[maybe_unused]] void result(std::string_view raw,std::string_view id,JobKind kind,std::string_view state,std::string_view error="",std::string_view sequence={}){
 Raw r{std::string(raw)};require(closed(r.d,r.d.root,{"request_id","kind","state","error_code","commit_sequence","value"})==Error::none,"closed actual terminal including value");
 require(field(r.d,r.d.root,"request_id")==id&&field(r.d,r.d.root,"kind")==kind_name(kind),"exact accepted ID/kind FIFO");
 require(field(r.d,r.d.root,"state")==state&&field(r.d,r.d.root,"error_code")==error,"exact actual state/error");auto seq=member(r.d,r.d.root,"commit_sequence");
 require(sequence.empty()?nil(r.d,seq):text(r.d,seq)==sequence,"exact commit sequence branch/value");
 terminal_value(r,kind,state);
}
[[maybe_unused]] std::string job(Service*s,JobKind kind,V payload,std::string_view state,std::string_view error="",std::string_view sequence={}){
 Capture input(kind,std::move(payload));auto a=s->submit(input);require(a.accepted&&a.error==Error::none,"actual accepted request");auto rows=receive(s,1);result(rows[0],a.request_id.view(),kind,state,error,sequence);return rows[0];
}
[[maybe_unused]] void start(Fixture&f,bool management=false,bool fresh=false){auto a=f.service->start(management);require(a.accepted,"actual worker start accepted");auto rows=receive(f.service,1);result(rows[0],a.request_id.view(),management?JobKind::start_management:JobKind::start,fresh?"committed":"read","",fresh?"1":"");Raw r(rows[0]);auto value=member(r.d,r.d.root,"value");if(management)require(closed(r.d,value,{"management_only"})==Error::none,"closed management result");else require(closed(r.d,value,{"store_version","interrupted_rows","created"})==Error::none,"closed start result");}

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

enum class WindowsMode {standalone,contention,post_release};
struct Plan {FixedText<32> nonce;std::uint64_t service{};std::size_t events{};WindowsMode mode{WindowsMode::standalone};};
constexpr std::array<std::string_view,8> windows_case_ids={
 "descriptor_rejection_no_store_effects","physical_ntfs_identity_and_reparse",
 "sentinel_content_and_lease_retirement","mint_move_and_monotone_identity",
 "foreign_owner_no_effects","share_zero_lock_refusal_and_retry",
 "untrusted_source_files_preserved","actual_sqlite_export_and_move_race"};
[[maybe_unused]] bool plan_from(std::string_view bytes,Plan&out,std::string_view role)noexcept{
 auto p=parse(bytes);if(!p)return false;auto d=p.value;auto n=d.root;std::uint64_t events{};FixedText<32> suite;
 if(role!="windows"||closed(d,n,{"schema","nonce","first_service_ordinal","maximum_actual_events","suite","cases"})!=Error::none||!d.string_is(d.member(n,"schema"),"LocalPlayersNativeTestPlan/v1")||!suite.from(d,d.member(n,"suite"))||!out.nonce.from(d,d.member(n,"nonce"))||!lower_hex(out.nonce.view(),32)||!positive_int(d,d.member(n,"first_service_ordinal"),INT64_MAX-32,out.service)||!positive_int(d,d.member(n,"maximum_actual_events"),16384,events)||events!=16384)return false;
 out.events=static_cast<std::size_t>(events);auto a=d.member(n,"cases");auto c=d.at(a);if(!c||c->kind!=ValueKind::array)return false;auto i=c->first;
 if(suite.view()=="windows"){out.mode=WindowsMode::standalone;for(auto name:windows_case_ids){if(i==no_cell||!d.string_is(i,name))return false;i=d.at(i)->next;}return i==no_cell;}
 std::string_view required;
 if(suite.view()=="windows_contention"){out.mode=WindowsMode::contention;required="external_lock_refusal";}
 else if(suite.view()=="windows_post_release"){out.mode=WindowsMode::post_release;required="external_lock_retry";}
 else return false;
 return i!=no_cell&&d.string_is(i,required)&&d.at(i)->next==no_cell;
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
 }if(!native)out.suite="windows";return seen==(native?127U:63U)&&lower_hex(out.context_sha.view(),64)&&lower_hex(out.descriptor_sha.view(),64)&&lower_hex(out.plan_sha.view(),64);
}

// All fixture mutation below is explicit test-owned Win32 work, after Root's
// authenticated admission. No product path is ever opened, redirected or written.
std::string root_path,proof_parent,run_nonce;
[[maybe_unused]] Wide path(std::string_view value){Wide w;require(w.set(value),"canonical fixture path");return w;}
[[maybe_unused]] bool exists(std::string_view name){auto w=path(name);auto a=GetFileAttributesW(w.value.data());if(a!=INVALID_FILE_ATTRIBUTES)return true;auto e=GetLastError();require(e==ERROR_FILE_NOT_FOUND||e==ERROR_PATH_NOT_FOUND,"actual missing-path code");return false;}
[[maybe_unused]] void fixture_path(std::string_view name){
 require(at_or_within(name,root_path)||(name==proof_parent+"\\local-players-"+run_nonce+"-windows-export.json")||(name==proof_parent+"\\local-players-"+run_nonce+"-windows-race.json")||(name==proof_parent+"\\local-players-"+run_nonce+"-windows-hardlink"),"fixed Root-owned fixture name only");
}
[[maybe_unused]] void write_fixture(std::string_view name,std::string_view bytes,bool replace=false){
 fixture_path(name);auto w=path(name);require(ordinary_ancestors(w),"ordinary fixture ancestors");
 Handle h(CreateFileW(ExtendedFileOperand(w).value.data(),GENERIC_WRITE,FILE_SHARE_READ,nullptr,replace?OPEN_EXISTING:CREATE_NEW,FILE_FLAG_OPEN_REPARSE_POINT,nullptr));FileIdentity id;
 require(h.good()&&observe_identity(h.value,false,id)&&final_equal(h.value,w),"actual ordinary single-link fixture write");
 std::size_t used=0;while(used<bytes.size()){DWORD n{};require(WriteFile(h.value,bytes.data()+used,static_cast<DWORD>(bytes.size()-used),&n,nullptr)&&n&&n<=bytes.size()-used,"actual fixture write completed");used+=n;}
 require(SetEndOfFile(h.value)&&FlushFileBuffers(h.value)&&h.close(),"fixture truncation/flush/checked close");
}
[[maybe_unused]] std::string read_fixture(std::string_view name){
 fixture_path(name);Handle h;require(open_ordinary(name,h),"actual ordinary fixture read");LARGE_INTEGER n{};
 require(GetFileSizeEx(h.value,&n)&&n.QuadPart>=0&&n.QuadPart<=655360,"finite fixture length");std::string out(static_cast<std::size_t>(n.QuadPart),'\0');std::size_t used=0;
 while(used<out.size()){DWORD got{};require(ReadFile(h.value,out.data()+used,static_cast<DWORD>(out.size()-used),&got,nullptr)&&got&&got<=out.size()-used,"actual fixture read completed");used+=got;}
 char extra{};DWORD got{};require(ReadFile(h.value,&extra,1,&got,nullptr)&&got==0&&h.close(),"fixture EOF and checked close");return out;
}
[[maybe_unused]] void delete_fixture(std::string_view name){fixture_path(name);auto w=path(name);require(DeleteFileW(w.value.data()),"delete only explicit test-owned ordinary fixture");}
[[maybe_unused]] std::vector<std::string> names(std::string_view root){
 // Validate ONLY the canonical absolute base using the unchanged general grammar.
 // The wildcard is a fixed Win32 enumeration operand, never caller path data.
 auto base=path(root);std::array<wchar_t,4099> pattern{};
 const auto used=static_cast<std::size_t>(base.size);
 require(used+3<=pattern.size(),"bounded fixed enumeration operand");
 std::copy_n(base.value.data(),used,pattern.data());
 pattern[used]=L'\\';pattern[used+1]=L'*';pattern[used+2]=L'\0';
 WIN32_FIND_DATAW item{};HANDLE h=FindFirstFileW(pattern.data(),&item);require(h!=INVALID_HANDLE_VALUE,"actual isolated roster enumeration");std::vector<std::string> out;DWORD end{};
 do{std::wstring_view leaf(item.cFileName);if(leaf==L"."||leaf==L"..")continue;FixedText<4096> u;require(utf8(leaf,u),"actual fixture name UTF8");out.emplace_back(u.view());require(out.size()<=64,"bounded isolated fixture roster");}while(FindNextFileW(h,&item));end=GetLastError();require(FindClose(h)&&end==ERROR_NO_MORE_FILES,"actual roster complete/checked close");std::sort(out.begin(),out.end());return out;
}
[[maybe_unused]] FileIdentity directory_identity(std::string_view value){auto w=path(value);require(ordinary_ancestors(w),"actual fixed NTFS and ordinary ancestors");Handle h(CreateFileW(ExtendedFileOperand(w).value.data(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));FileIdentity id;require(h.good()&&observe_identity(h.value,true,id)&&final_equal(h.value,w)&&h.close(),"actual native directory identity/nonreparse/final name");return id;}
[[maybe_unused]] std::string descriptor_change(std::string_view raw,std::string_view key,std::string_view literal){
 Raw r{std::string(raw)};constexpr std::array<std::string_view,9> keys={"schema","root","parent","nonce","root_volume_serial","root_file_id","parent_volume_serial","parent_file_id","sentinel_sha256"};std::vector<char> b(65536);Writer w(b);w.raw("{");bool first=true;
 for(auto name:keys){if(!first)w.raw(",");first=false;w.string(name);w.raw(":");if(name==key)w.raw(literal);else w.raw(canonical(r.d,member(r.d,r.d.root,name)));}
 if(key=="extra"){w.raw(",\"unknown\":null");}w.raw("}");require(w.good(),"bounded independent descriptor mutation");return std::string(w.bytes());
}
[[maybe_unused]] std::string quote(std::string_view s){std::vector<char>b(16384);Writer w(b);w.string(s);require(w.good(),"bounded test String literal");return std::string(w.bytes());}
[[maybe_unused]] void rejected(TrustedRoots&trust,std::string_view bytes,std::string_view hash,Probe&p,std::uint64_t ordinal,TestError error){
 auto before=names(root_path);auto sentinel=read_fixture(root_path+"\\.local-players-test-root.json");std::size_t events{},allocations{},claims{};{std::lock_guard lock(p.mutex);events=p.events.size();allocations=p.allocations.size();claims=p.claims;}
 auto c=TestRootFactory::admit_bytes(bytes,hash,trust,&p,ordinal);require(!c.valid()&&c.error()==error&&!c.take_access(),"exact factory rejection; no token");require(c.retire_unconsumed(),"failed capability checked retirement");
 {std::lock_guard lock(p.mutex);require(p.events.size()==events&&p.allocations.size()==allocations&&p.claims==claims,"no Service/SQLite/worker notifications or arena reservation on descriptor rejection");}
 require(names(root_path)==before&&read_fixture(root_path+"\\.local-players-test-root.json")==sentinel,"descriptor refusal leaves actual root roster/sentinel unchanged");
}
struct RootSwap {
 std::string original,backup;bool moved{},replacement{};
 explicit RootSwap(std::string root):original(std::move(root)),backup(original+"-preserved-original"){
  require(original==root_path&&at_or_within(backup,proof_parent)&&!at_or_within(backup,root_path),"only admitted root and fixed same-parent preservation sibling");auto a=path(original),b=path(backup);require(!exists(backup)&&MoveFileExW(a.value.data(),b.value.data(),0),"move actual isolated root to one fixed preserved sibling");moved=true;
  if(!CreateDirectoryW(a.value.data(),nullptr)){if(!MoveFileExW(b.value.data(),a.value.data(),0))std::terminate();moved=false;throw std::runtime_error("create explicit replacement directory");}replacement=true;
 }
 void restore(){if(!moved)return;auto a=path(original),b=path(backup);if(replacement){require(RemoveDirectoryW(a.value.data()),"remove only empty replacement or junction itself");replacement=false;}require(MoveFileExW(b.value.data(),a.value.data(),0),"restore exact original root directory");moved=false;}
 ~RootSwap(){if(moved){try{restore();}catch(...){std::terminate();}}}
 void junction(){
  // Native mount-point reparse at an empty test-owned directory. No symlink
  // privilege fallback, external target, arbitrary path or recursive deletion.
  auto a=path(original),b=path(backup);std::wstring substitute=L"\\??\\"+std::wstring(b.value.data(),static_cast<std::size_t>(b.size));std::wstring print(b.value.data(),static_cast<std::size_t>(b.size));
  std::size_t sb=substitute.size()*sizeof(wchar_t),pb=print.size()*sizeof(wchar_t);require(sb+pb+20<=16384,"bounded junction record");std::vector<std::byte> data(20+sb+pb);DWORD tag=IO_REPARSE_TAG_MOUNT_POINT;WORD size=static_cast<WORD>(12+sb+pb),zero=0,sl=static_cast<WORD>(sb),po=static_cast<WORD>(sb+2),pl=static_cast<WORD>(pb);
  std::memcpy(data.data(),&tag,4);std::memcpy(data.data()+4,&size,2);std::memcpy(data.data()+6,&zero,2);std::memcpy(data.data()+8,&zero,2);std::memcpy(data.data()+10,&sl,2);std::memcpy(data.data()+12,&po,2);std::memcpy(data.data()+14,&pl,2);std::memcpy(data.data()+16,substitute.data(),sb);std::memcpy(data.data()+18+sb,print.data(),pb);
  Handle h(CreateFileW(ExtendedFileOperand(a).value.data(),GENERIC_WRITE,0,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));DWORD returned{};require(h.good()&&DeviceIoControl(h.value,FSCTL_SET_REPARSE_POINT,data.data(),static_cast<DWORD>(data.size()),nullptr,0,&returned,nullptr)&&h.close(),"actual test junction construction and checked close");
 }
};
struct CaseRow {std::string id;std::size_t checks{},events{};};
std::vector<CaseRow> completed;
std::string active_case;std::vector<std::pair<std::string,std::string>> terminals;DWORD observed_move_error{};
template<class F> void run_case(std::string_view id,F&&f){active_case=id;auto a=checks.load(),b=actual_events.load();f();require(checks.load()>a,"case performs assertions");completed.push_back({std::string(id),checks.load()-a,actual_events.load()-b});}
[[maybe_unused]] void start_failure(Fixture&f,std::string_view expected){auto a=f.service->start();require(a.accepted&&a.error==Error::none,"actual start enqueued");auto rows=receive(f.service,1);result(rows[0],a.request_id.view(),JobKind::start,"failed",expected);terminals.emplace_back(active_case,rows[0]);auto s=status(f.service);require(s.state==ServiceState::unavailable&&!s.has_store_version,"failed startup never qualifies a store");f.close();}
[[maybe_unused]] void same_file(std::string_view name,std::string_view bytes){require(read_fixture(name)==bytes,"original malformed/source/target bytes retained exactly");}
[[maybe_unused]] void assert_no_database(){for(auto n:{"players.sqlite3","players.sqlite3-wal","players.sqlite3-shm","players.sqlite3-journal"})require(!exists(root_path+"\\"+n),"no SQLite file created by pre-open cases");}
struct ReleaseGate {Probe& p;~ReleaseGate(){p.release();}};
[[maybe_unused]] void publication_finished(Probe&p,std::uint64_t service,std::uint64_t request){std::unique_lock lock(p.mutex);require(p.cv.wait_for(lock,std::chrono::seconds(15),[&]{return std::any_of(p.events.begin(),p.events.end(),[&](const auto&e){return e.service_ordinal==service&&e.request_ordinal==request&&e.phase==Phase::publish_ack&&e.scope==Scope::service&&e.edge==Edge::after;});}),"previous actual publication AFTER observed before next event-range witness");}

[[maybe_unused]] void windows_cases(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,Plan&plan){
 std::uint64_t ordinal=plan.service;Probe p(plan.events);
 // Establish the opaque isolated origin BEFORE any test-owned root read/write.
 // Root-supplied strings alone never authorize touching a selected directory.
 auto baseline=TestRootFactory::admit_bytes(descriptor,digest,trust,&p,ordinal++);require(baseline.valid()&&baseline.retire_unconsumed(),"baseline physical isolated descriptor admitted and checked retired before fixture access");
 const auto sentinel_path=root_path+"\\.local-players-test-root.json";const auto sentinel=read_fixture(sentinel_path);
 require(names(root_path)==std::vector<std::string>{".local-players-test-root.json"},"Root must supply fresh sentinel-only root, not owner data or stale test files");
 run_case(windows_case_ids[0],[&]{
  rejected(trust,descriptor,std::string(64,'0'),p,ordinal,TestError::descriptor_hash);
  for(auto literal:{"null","true","1","[]","{}"}){auto raw=descriptor_change(descriptor,"root",literal);rejected(trust,raw,digest_text(raw),p,ordinal,TestError::invalid_descriptor);}
  for(auto key:{"schema","nonce","root_file_id","parent_file_id","sentinel_sha256"}){auto raw=descriptor_change(descriptor,key,quote("not-canonical"));rejected(trust,raw,digest_text(raw),p,ordinal,TestError::invalid_descriptor);}
  auto extra=descriptor_change(descriptor,"extra","null");rejected(trust,extra,digest_text(extra),p,ordinal,TestError::invalid_descriptor);
  for(auto key:{"root_volume_serial","parent_volume_serial"}){auto raw=descriptor_change(descriptor,key,"1");rejected(trust,raw,digest_text(raw),p,ordinal,TestError::invalid_descriptor);}
  auto outside=descriptor_change(descriptor,"root",quote(proof_parent));rejected(trust,outside,digest_text(outside),p,ordinal,TestError::path);
  auto source=descriptor_change(descriptor,"root",quote(root_path+"-other"));rejected(trust,source,digest_text(source),p,ordinal,TestError::path);
  assert_no_database();
 });
 run_case(windows_case_ids[1],[&]{
  auto root_id=directory_identity(root_path),parent_id=directory_identity(proof_parent);require(root_id.valid&&parent_id.valid&&!same_identity(root_id,parent_id),"actual root is distinct physical fixed-NTFS child");
  Raw d{std::string(descriptor)};FileIdentity expected_root,expected_parent;require(decode_id(field(d.d,d.d.root,"root_file_id"),expected_root)&&decode_id(field(d.d,d.d.root,"parent_file_id"),expected_parent),"descriptor native FILE_ID_INFO hex");
  expected_root.valid=expected_parent.valid=true;auto number=[](std::string_view s){std::uint64_t n{};auto r=std::from_chars(s.data(),s.data()+s.size(),n);require(r.ec==std::errc{}&&r.ptr==s.data()+s.size(),"canonical actual volume serial");return n;};
  expected_root.volume_serial=number(field(d.d,d.d.root,"root_volume_serial"));expected_parent.volume_serial=number(field(d.d,d.d.root,"parent_volume_serial"));require(same_identity(root_id,expected_root)&&same_identity(parent_id,expected_parent),"actual native volume/file IDs equal Root descriptor");
  auto bad=field(d.d,d.d.root,"root_file_id");bad[0]=bad[0]=='0'?'1':'0';auto raw=descriptor_change(descriptor,"root_file_id",quote(bad));rejected(trust,raw,digest_text(raw),p,ordinal,TestError::identity);
  {RootSwap swap(root_path);auto cap=TestRootFactory::admit_bytes(descriptor,digest,trust,&p,ordinal);require(!cap.valid()&&cap.error()==TestError::identity&&cap.retire_unconsumed(),"same path replacement native identity refused");swap.restore();}
  require(same_identity(directory_identity(root_path),root_id),"original native root restored");
  {RootSwap swap(root_path);swap.junction();auto cap=TestRootFactory::admit_bytes(descriptor,digest,trust,&p,ordinal);require(!cap.valid()&&cap.error()==TestError::path&&cap.retire_unconsumed(),"actual junction refused rather than followed");swap.restore();}
  require(same_identity(directory_identity(root_path),root_id)&&read_fixture(sentinel_path)==sentinel,"junction test restores exact original root/sentinel");assert_no_database();
 });
 run_case(windows_case_ids[2],[&]{
  auto changed=sentinel;changed.back()=' ';write_fixture(sentinel_path,changed,true);rejected(trust,descriptor,digest,p,ordinal,TestError::sentinel);same_file(sentinel_path,changed);write_fixture(sentinel_path,sentinel,true);
  auto cap=TestRootFactory::admit_bytes(descriptor,digest,trust,&p,ordinal++);require(cap.valid(),"actual sentinel recovered and admitted");auto w=path(sentinel_path);Handle write(CreateFileW(ExtendedFileOperand(w).value.data(),GENERIC_WRITE,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr));auto error=GetLastError();require(!write.good()&&error==ERROR_SHARING_VIOLATION,"actual retained sentinel lease denies writer");
  require(cap.retire_unconsumed()&&!cap.valid()&&!cap.take_access(),"checked unconsumed retirement invalidates token");Handle reopened;require(open_ordinary(sentinel_path,reopened,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ)&&reopened.close(),"actual writer opens only after checked lease retirement");same_file(sentinel_path,sentinel);assert_no_database();
 });
 run_case(windows_case_ids[3],[&]{
  auto first=ordinal++;auto a=TestRootFactory::admit_bytes(descriptor,digest,trust,&p,first);require(a.valid(),"real capability minted");Capability b(std::move(a));require(!a.valid()&&b.valid()&&b.nonce()==run_nonce&&b.descriptor_sha256()==digest,"move transfers sealed identity and leases exactly");require(b.retire_unconsumed(),"moved token retired checked");
  rejected(trust,descriptor,digest,p,first,TestError::out_of_order);TrustedRoots moved(std::move(trust));require(!trust.valid()&&moved.valid(),"actual prerequisite move transfers retained handles");trust=std::move(moved);require(trust.valid()&&!moved.valid(),"prerequisite move back preserves high-water");rejected(trust,descriptor,digest,p,first,TestError::out_of_order);auto next=TestRootFactory::admit_bytes(descriptor,digest,trust,&p,ordinal++);require(next.valid()&&next.retire_unconsumed(),"new genuinely monotone service ordinal admitted after disposal");assert_no_database();
 });
 run_case(windows_case_ids[4],[&]{
  Fixture f(trust,descriptor,digest,p,ordinal++);auto before=status(f.service);auto files=names(root_path);auto event_count=actual_events.load();Capture c(JobKind::list_players,V::o({}));bool wrong=false;
  std::thread foreign([&]{Status unused;std::array<DeliveryView,1>v{};std::uint8_t count=99;std::array<std::uint64_t,1>lease{1};auto a=f.service->start();auto b=f.service->submit(c);wrong=!a.accepted&&a.error==Error::wrong_thread&&!b.accepted&&b.error==Error::wrong_thread&&!f.service->status(unused)&&!f.service->peek(1,v,count)&&!f.service->acknowledge(lease)&&!f.service->abandon(lease)&&!f.service->begin_shutdown()&&!f.service->try_join()&&!Service::destroy(f.service);});foreign.join();
  require(wrong&&c.captures==0&&same_status(before,status(f.service)),"actual foreign owner methods all reject before deep capture/state mutation");require(actual_events.load()==event_count&&names(root_path)==files,"wrong owner causes zero observer/arena/worker/SQLite effects and no fixture mutation");assert_no_database();f.close();
 });
 run_case(windows_case_ids[5],[&]{
  auto lock_path=root_path+"\\players.lock";write_fixture(lock_path,"");auto w=path(lock_path);Handle held(CreateFileW(ExtendedFileOperand(w).value.data(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr));FileIdentity id;require(held.good()&&observe_identity(held.value,false,id),"actual test-owned share-zero lock held");
  {Fixture f(trust,descriptor,digest,p,ordinal++);start_failure(f,"store_locked");require(WaitForSingleObject(GetCurrentProcess(),0)==WAIT_TIMEOUT,"same-process test explicitly not external actor proof");}
  require(held.close(),"actual held lock checked close");{Fixture f(trust,descriptor,digest,p,ordinal++);start(f,true);require(status(f.service).has_root&&!status(f.service).has_store_version,"management acquired same preserved root after real lock release");f.close();}
  assert_no_database();
 });
 run_case(windows_case_ids[6],[&]{
  auto main=root_path+"\\players.sqlite3",wal=root_path+"\\players.sqlite3-wal",unknown=root_path+"\\players.sqlite3-journal-extra";std::string malformed(100,'x');
  write_fixture(main,malformed);{Fixture f(trust,descriptor,digest,p,ordinal++);start_failure(f,"foreign_store");}same_file(main,malformed);delete_fixture(main);
  write_fixture(wal,"orphan-wal");{Fixture f(trust,descriptor,digest,p,ordinal++);start_failure(f,"foreign_store");}same_file(wal,"orphan-wal");delete_fixture(wal);
  write_fixture(unknown,"unknown-original-journal");{Fixture f(trust,descriptor,digest,p,ordinal++);start_failure(f,"recovery_required");}same_file(unknown,"unknown-original-journal");delete_fixture(unknown);
  write_fixture(main,malformed);auto linked=proof_parent+"\\local-players-"+run_nonce+"-windows-hardlink";auto a=path(main),b=path(linked);require(CreateHardLinkW(b.value.data(),a.value.data(),nullptr),"actual second hard link test fixture");
  {Fixture f(trust,descriptor,digest,p,ordinal++);start_failure(f,"recovery_required");}delete_fixture(linked);same_file(main,malformed);delete_fixture(main);assert_no_database();
 });
 run_case(windows_case_ids[7],[&]{
  const auto id=std::string(32,'6'),target=proof_parent+"\\local-players-"+run_nonce+"-windows-export.json",race=proof_parent+"\\local-players-"+run_nonce+"-windows-race.json";
  require(!exists(target)&&!exists(race),"fresh fixed no-overwrite export targets");const auto this_service=ordinal++;Fixture f(trust,descriptor,digest,p,this_service);start(f,false,true);auto s=status(f.service);require(s.has_root&&s.has_store_version&&s.resolved_root.view()==root_path&&s.state==ServiceState::ready,"real production Windows adapter/SQLite qualified only isolated root");
  job(f.service,JobKind::create_player,player_seed(id,"Windows owner"),"committed","","2");auto out=job(f.service,JobKind::export_player,V::o({{"player_id",V::s(id)},{"expected_revision",V::s("1")},{"target_absolute_path",V::s(target)}}),"read");
  terminals.emplace_back(active_case,out);Raw receipt(out);auto v=member(receipt.d,receipt.d.root,"value");auto bytes=read_fixture(target);require(field(receipt.d,v,"outcome")=="saved"&&field(receipt.d,v,"phase")=="done"&&receipt.d.at(member(receipt.d,v,"installed"))->scalar==1&&field(receipt.d,v,"sha256")==digest_text(bytes)&&natural(receipt.d,member(receipt.d,v,"bytes"),33554432)==bytes.size(),"actual exported file bytes/hash/known install equal closed receipt");
  Raw envelope(bytes);require(closed(envelope.d,envelope.d.root,{"format","version","payload_json","payload_sha256"})==Error::none&&field(envelope.d,envelope.d.root,"format")=="LocalPlayerSummary"&&natural(envelope.d,member(envelope.d,envelope.d.root,"version"),1)==1,"actual canonical summary envelope");auto payload=field(envelope.d,envelope.d.root,"payload_json");require(digest_text(payload)==field(envelope.d,envelope.d.root,"payload_sha256"),"actual export inner hash");Raw inner(payload);auto player=member(inner.d,inner.d.root,"player"),preferences=member(inner.d,inner.d.root,"preferences");require(closed(inner.d,inner.d.root,{"player","preferences","practice"})==Error::none&&validate_player(inner.d,player)==Error::none&&validate_preferences(inner.d,preferences,true,inner.cells)==Error::none&&field(inner.d,player,"id")==id&&field(inner.d,preferences,"player_id")==id&&field(inner.d,player,"revision")==field(inner.d,preferences,"revision")&&array(inner.d,member(inner.d,inner.d.root,"practice")).empty(),"actual empty-history complete selected record/preferences snapshot");
  job(f.service,JobKind::export_player,V::o({{"player_id",V::s(id)},{"expected_revision",V::s("1")},{"target_absolute_path",V::s(target)}}),"failed","target_exists");same_file(target,bytes);publication_finished(p,this_service,4);
  std::size_t event_begin{};{std::lock_guard lock(p.mutex);event_begin=p.events.size();}p.arm(JobKind::export_player,Phase::export_move,Edge::before);ReleaseGate release{p};Capture request(JobKind::export_player,V::o({{"player_id",V::s(id)},{"expected_revision",V::s("1")},{"target_absolute_path",V::s(race)}}));auto accepted=f.service->submit(request);require(accepted.accepted,"actual race export accepted");p.wait();write_fixture(race,"independent-no-replace-competitor\n");p.release();auto rows=receive(f.service,1);result(rows[0],accepted.request_id.view(),JobKind::export_player,"recovery_required","file_recovery_required");terminals.emplace_back(active_case,rows[0]);Raw failed(rows[0]);auto fv=member(failed.d,failed.d.root,"value");
  require(field(failed.d,fv,"outcome")=="recovery_required"&&field(failed.d,fv,"phase")=="move"&&nil(failed.d,member(failed.d,fv,"installed")),"failed actual no-replace move retains unknown install, not DB commit uncertainty");same_file(race,"independent-no-replace-competitor\n");auto temporary=field(failed.d,fv,"temporary_absolute_path");require(at_or_within(temporary,proof_parent)&&!at_or_within(temporary,root_path),"owned temporary stays in independently declared proof parent");
  require(temporary.starts_with(proof_parent+"\\.fsplayers-")&&temporary.ends_with(".tmp")&&temporary.size()==proof_parent.size()+1+11+32+4,"retained temporary exact generated name under same parent");
  InputFile temp;require(load_input(temporary,field(failed.d,fv,"sha256"),temp),"retained temporary actual bytes match completed pre-move verification hash");require(natural(failed.d,member(failed.d,fv,"bytes"),33554432)==temp.size&&temp.handle.close(),"retained temporary actual bytes/checked close equal receipt");
  bool moved_error=false,wrote=false,flushed=false;{std::lock_guard lock(p.mutex);for(std::size_t i=event_begin;i<p.events.size();++i){auto&e=p.events[i];require(e.service_ordinal==this_service&&e.request_ordinal==5&&e.kind==JobKind::export_player,"observed events bind this actual fifth request/service, not prior successful export");if(e.phase==Phase::export_move&&e.edge==Edge::after&&e.has_win32_error&&e.win32_error!=ERROR_SUCCESS&&e.installed==-1){moved_error=true;observed_move_error=e.win32_error;}if(e.phase==Phase::export_write&&e.edge==Edge::after&&e.has_win32_error&&e.win32_error==ERROR_SUCCESS&&e.has_requested&&e.has_completed&&e.requested==e.completed&&e.completed>0)wrote=true;if(e.phase==Phase::export_flush&&e.edge==Edge::after&&e.has_win32_error&&e.win32_error==ERROR_SUCCESS)flushed=true;}}
  require(moved_error&&wrote&&flushed,"actual production Win32 write/flush/error observations, never substituted return code");job(f.service,JobKind::list_players,V::o({}),"read");require(status(f.service).state==ServiceState::ready,"file move recovery does not poison qualified database");f.close();
  Handle lock;require(open_ordinary(root_path+"\\players.lock",lock,GENERIC_READ|GENERIC_WRITE,0)&&lock.close(),"actual SAME Service join releases ownership lock");
 });
 require(!p.overflow&&completed.size()==windows_case_ids.size(),"all fixed Windows cases completed without observation overflow");same_file(sentinel_path,sentinel);require(actual_events.load()>0,"actual native operations were observed");
}
// These modes do not launch/connect/release an actor. Root's independent
// authenticated HELD/exit/transport evidence is indispensable and external.
DWORD contention_open_error{};bool mode_quiescent{},mode_worker_joined{};
std::string mode_start_terminal,mode_list_terminal;
[[maybe_unused]] void mode_root(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,Probe&p,std::uint64_t ordinal){
 auto cap=TestRootFactory::admit_bytes(descriptor,digest,trust,&p,ordinal);require(cap.valid()&&cap.retire_unconsumed(),"isolated real root admitted before separate-mode fixture observations");
 require(names(root_path)==std::vector<std::string>{".local-players-test-root.json","players.lock"},"separate mode uses SAME preserved fresh sentinel/ownership-lock root only");assert_no_database();
}
[[maybe_unused]] void contention_case(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,Plan&plan){
 Probe p(plan.events);mode_root(trust,descriptor,digest,p,plan.service);
 run_case("external_lock_refusal",[&]{
  const auto lock_name=root_path+"\\players.lock";auto w=path(lock_name);require(ordinary_ancestors(w),"actual isolated fixed-NTFS lock ancestors");
  Handle denied(CreateFileW(ExtendedFileOperand(w).value.data(),GENERIC_READ|GENERIC_WRITE,0,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr));contention_open_error=GetLastError();
  require(!denied.good()&&contention_open_error==ERROR_SHARING_VIOLATION,"actual fixed-lock OPEN_EXISTING refuses with sharing violation");
  {Fixture f(trust,descriptor,digest,p,plan.service+1);auto admitted=f.service->start();require(admitted.accepted&&admitted.error==Error::none,"actual production startup request enqueued while external actor held");auto rows=receive(f.service,1);result(rows[0],admitted.request_id.view(),JobKind::start,"failed","store_locked");mode_start_terminal=rows[0];
   auto s=status(f.service);require(s.state==ServiceState::unavailable&&!s.has_store_version,"external lock cannot qualify store");assert_no_database();f.close();require(f.joined,"SAME Service actual safe shutdown/join completed");mode_quiescent=true;}
  require(names(root_path)==std::vector<std::string>{".local-players-test-root.json","players.lock"}&&!p.overflow,"refused external-lock startup preserves root and bounded observations");
 });
 // A successful test exit is meaningful only when Root verifies actor HELD and
 // actual process liveness through that exit. This driver cannot certify it.
}
[[maybe_unused]] void post_release_case(TrustedRoots&trust,std::string_view descriptor,std::string_view digest,Plan&plan){
 Probe p(plan.events);mode_root(trust,descriptor,digest,p,plan.service);
 run_case("external_lock_retry",[&]{
  const auto lock_name=root_path+"\\players.lock";Handle probe;require(open_ordinary(lock_name,probe,GENERIC_READ|GENERIC_WRITE,0)&&probe.close(),"actual fixed ownership lock now opens after Root-confirmed actor release/exit");
  {Fixture f(trust,descriptor,digest,p,plan.service+1);auto admitted=f.service->start();require(admitted.accepted&&admitted.error==Error::none,"actual normal startup accepted on SAME preserved root");auto rows=receive(f.service,1);result(rows[0],admitted.request_id.view(),JobKind::start,"committed","","1");mode_start_terminal=rows[0];Raw r(rows[0]);auto v=member(r.d,r.d.root,"value");
   require(natural(r.d,member(r.d,v,"store_version"),1)==1&&natural(r.d,member(r.d,v,"interrupted_rows"),0)==0&&r.d.at(member(r.d,v,"created"))->kind==ValueKind::boolean&&r.d.at(member(r.d,v,"created"))->scalar==1,"actual fresh schema initialization, not existing-store or recovery result");
   auto s=status(f.service);require(s.state==ServiceState::ready&&s.has_root&&s.has_store_version&&s.resolved_root.view()==root_path,"actual successful retry qualified the exact isolated root");mode_list_terminal=job(f.service,JobKind::list_players,V::o({}),"read");Raw listed(mode_list_terminal);auto value=member(listed.d,listed.d.root,"value");require(array(listed.d,member(listed.d,value,"players")).empty(),"actual SQLite list read on new store returns no invented players");
   f.close();require(f.joined,"SAME actually started production worker exited/joined before success");mode_worker_joined=true;}
  Handle after;require(open_ordinary(lock_name,after,GENERIC_READ|GENERIC_WRITE,0)&&after.close()&&!p.overflow,"actual joined retry released same lock and no observation overflow");
 });
}
[[maybe_unused]] void print_mode_receipt(const Arguments&a,WindowsMode mode){
 std::array<char,16384> b{};Writer w(b);w.raw("{\"schema\":");w.string(mode==WindowsMode::contention?"LocalPlayersWindowsContentionChecks/v1":"LocalPlayersWindowsPostReleaseChecks/v1");w.raw(",\"passed\":true,\"context_sha256\":");w.string(a.context_sha.view());w.raw(",\"descriptor_sha256\":");w.string(a.descriptor_sha.view());w.raw(",\"plan_sha256\":");w.string(a.plan_sha.view());w.raw(",\"checks\":");w.integer(static_cast<std::int64_t>(checks.load()));
 if(mode==WindowsMode::contention){if(!mode_quiescent||contention_open_error!=ERROR_SHARING_VIOLATION||mode_start_terminal.empty())throw std::runtime_error("contention receipt missing actual outcome");w.raw(",\"open_win32_error\":");w.integer(contention_open_error);w.raw(",\"start_terminal_json\":");w.string(mode_start_terminal);w.raw(",\"service_quiescent\":true}");}
 else{if(!mode_worker_joined||mode_start_terminal.empty()||mode_list_terminal.empty())throw std::runtime_error("retry receipt missing actual worker/read outcome");w.raw(",\"start_terminal_json\":");w.string(mode_start_terminal);w.raw(",\"list_terminal_json\":");w.string(mode_list_terminal);w.raw(",\"worker_joined\":true}");}
 if(!w.good())throw std::runtime_error("separate mode receipt capacity");std::cout<<w.bytes()<<"\n";
}

[[maybe_unused]] void print_receipt(const Arguments&a){
 std::array<char,131072>b{};Writer w(b);w.raw("{\"schema\":\"LocalPlayersWindowsChecks/v1\",\"passed\":true,\"context_sha256\":");w.string(a.context_sha.view());w.raw(",\"descriptor_sha256\":");w.string(a.descriptor_sha.view());w.raw(",\"plan_sha256\":");w.string(a.plan_sha.view());w.raw(",\"checks\":");w.integer(static_cast<std::int64_t>(checks.load()));w.raw(",\"actual_events\":");w.integer(static_cast<std::int64_t>(actual_events.load()));w.raw(",\"cases\":[");bool first=true;for(auto&r:completed){if(!first)w.raw(",");first=false;w.raw("{\"id\":");w.string(r.id);w.raw(",\"checks\":");w.integer(static_cast<std::int64_t>(r.checks));w.raw(",\"actual_events\":");w.integer(static_cast<std::int64_t>(r.events));w.raw("}");}w.raw("],\"export_move_error\":");w.integer(observed_move_error);w.raw(",\"terminal_witnesses\":[");first=true;for(auto&t:terminals){if(!first)w.raw(",");first=false;w.raw("{\"case_id\":");w.string(t.first);w.raw(",\"terminal_json\":");w.string(t.second);w.raw("}");}w.raw("],\"two_process_contention\":false}");if(!w.good())throw std::runtime_error("closed standalone receipt capacity");std::cout<<w.bytes()<<"\n";
}
} // namespace
#endif
#if defined(_WIN32)
int wmain(int argc,wchar_t**argv){
 try{Arguments args;require(arguments(argc,argv,args,false),"closed six-pair Windows argv");auto&cf=inputs.context;auto&pf=inputs.plan;auto&df=inputs.descriptor;Context ctx;Plan plan;FixedText<4096>root;
  require(load_input(args.context.view(),args.context_sha.view(),cf)&&context_from({cf.bytes.data(),cf.size},ctx,"windows"),"actual immutable role-windows context");require(ctx.capability_sha.view()==args.descriptor_sha.view()&&ctx.plan_sha.view()==args.plan_sha.view(),"context binds supplied descriptor/plan raw hashes");
  require(load_input(args.plan.view(),args.plan_sha.view(),pf)&&plan_from({pf.bytes.data(),pf.size},plan,"windows"),"exact closed ordered Windows plan");require(load_input(args.descriptor.view(),args.descriptor_sha.view(),df)&&descriptor_root({df.bytes.data(),df.size},plan,root),"bound root descriptor/nonce");
  require(!at_or_within(args.context.view(),root.view())&&!at_or_within(args.plan.view(),root.view())&&!at_or_within(args.descriptor.view(),root.view())&&module_hash(ctx.actor_sha.view()),"immutable inputs outside test root and actual self EXE SHA");Handle parent;require(actual_parent(ctx.parent_pid)&&parent_from(ctx,parent),"actual direct Root PID/creation/liveness");
  root_path=root.view();proof_parent=ctx.parent.view();run_nonce=plan.nonce.view();auto trust=TestRootFactory::prepare_prerequisite(ctx.source.view(),ctx.parent.view());require(trust.valid(),"read-only actual source/proof/KnownFolder prerequisite");
  if(plan.mode==WindowsMode::standalone)windows_cases(trust,{df.bytes.data(),df.size},args.descriptor_sha.view(),plan);
  else if(plan.mode==WindowsMode::contention)contention_case(trust,{df.bytes.data(),df.size},args.descriptor_sha.view(),plan);
  else post_release_case(trust,{df.bytes.data(),df.size},args.descriptor_sha.view(),plan);
  require(WaitForSingleObject(parent.value,0)==WAIT_TIMEOUT,"actual Root supervisor still alive");require(trust.retire()&&cf.handle.close()&&pf.handle.close()&&df.handle.close()&&parent.close(),"checked trust/input/parent retirement before standalone success");if(plan.mode==WindowsMode::standalone)print_receipt(args);else print_mode_receipt(args,plan.mode);return 0;
 }catch(const std::exception&e){std::cerr<<"LocalPlayers Windows test failure: "<<e.what()<<"\n";return 1;}catch(...){std::cerr<<"LocalPlayers Windows unknown failure\n";return 1;}
}
#else
int main(){std::cerr<<"Windows adapter qualification requires actual Windows; Linux codec is separately allocated\n";return 2;}
#endif
