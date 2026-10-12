// Original MIT. Test-only injected process death in SAME Service/SQLite callback.
#include "test_capability.hpp"
#include "flight/local_players/service.hpp"
#include <algorithm>
#include <array>
#include <charconv>
#include <cstring>
#include <cstdio>
#include <limits>
#include <string_view>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <tlhelp32.h>
#include <atomic>
#include <cstdlib>
#include <exception>
#include <mutex>
#include <optional>
#include <stdexcept>
#include <thread>
#include <tuple>
#include <vector>

namespace {
using namespace flight::local_players;
using namespace flight::local_players::testing;
constexpr DWORD startup_ms=45000,held_ms=120000,close_ms=10000;
constexpr std::size_t input_cap=65536,frame_cap=4096;
// Failure-only private stderr: fixed literals and numeric codes, never input values.
int actor_failure(const char*stage,int code,DWORD win32=ERROR_SUCCESS,bool has_win32=false)noexcept{
 std::fprintf(stderr,"LOCAL_PLAYERS_ACTOR_FAILURE role=crash_actor stage=%s code=%d win32_available=%d win32=%lu\n",
              stage,code,has_win32?1:0,static_cast<unsigned long>(win32));
 std::fflush(stderr);return code;
}
bool actor_reject(const char*stage,DWORD win32=ERROR_SUCCESS,bool has_win32=false)noexcept{
 actor_failure(stage,3,win32,has_win32);return false;
}
// Single-thread actor-only fixed parsing storage. No hidden variable allocation.
struct ParsingStorage {std::array<JsonCell,30000> cells{};std::array<std::byte,524288> duplicate{};};
ParsingStorage parsing;
struct Handle {
 HANDLE value{INVALID_HANDLE_VALUE};
 Handle()=default;explicit Handle(HANDLE h):value(h){}
 Handle(const Handle&)=delete;Handle& operator=(const Handle&)=delete;
 ~Handle(){if(good()&&!close())std::terminate();}
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
bool utf8(std::wstring_view in,FixedText<4096>& out)noexcept{
 if(in.empty()||in.size()>32767)return false;
 int n=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,in.data(),static_cast<int>(in.size()),out.data.data(),4096,nullptr,nullptr);
 if(n<1)return false;out.size=static_cast<std::uint32_t>(n);out.data[n]=0;return true;
}
bool observe_identity(HANDLE h,bool directory,FileIdentity& out)noexcept{
 FILE_ID_INFO id{};FILE_STANDARD_INFO standard{};FILE_ATTRIBUTE_TAG_INFO tag{};
 if(!GetFileInformationByHandleEx(h,FileIdInfo,&id,sizeof(id))||
    !GetFileInformationByHandleEx(h,FileStandardInfo,&standard,sizeof(standard))||
    !GetFileInformationByHandleEx(h,FileAttributeTagInfo,&tag,sizeof(tag))||
    bool(standard.Directory)!=directory||(tag.FileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)||
    (!directory&&standard.NumberOfLinks!=1))return false;
 out={};out.valid=true;out.volume_serial=id.VolumeSerialNumber;out.links=standard.NumberOfLinks;
 std::memcpy(out.file_id.data(),id.FileId.Identifier,16);return true;
}
bool final_equal(HANDLE h,const Wide&w)noexcept{
 std::array<wchar_t,4097> final{};
 auto n=GetFinalPathNameByHandleW(h,final.data(),static_cast<DWORD>(final.size()),FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
 return n>4&&n<final.size()&&std::wstring_view(final.data(),4)==L"\\\\?\\"&&
  CompareStringOrdinal(final.data()+4,static_cast<int>(n-4),w.value.data(),w.size,TRUE)==CSTR_EQUAL;
}
bool at_or_within(std::string_view path,std::string_view root)noexcept{
 if(path.size()<root.size()||(path.size()>root.size()&&path[root.size()]!='\\'))return false;
 Wide a,b;if(!a.set(path.substr(0,root.size()))||!b.set(root))return false;
 return CompareStringOrdinal(a.value.data(),a.size,b.value.data(),b.size,TRUE)==CSTR_EQUAL;
}
bool ordinary_ancestors(const Wide&w)noexcept{
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
bool open_ordinary(std::string_view path,Handle& h,DWORD access=GENERIC_READ,DWORD share=FILE_SHARE_READ)noexcept{
 Wide w;if(!w.set(path)||!ordinary_ancestors(w))return false;
 h.value=CreateFileW(ExtendedFileOperand(w).value.data(),access,share,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
 if(!h.good()){const auto error=GetLastError();return actor_reject("ordinary_file_open",error,true);}
 FileIdentity id;return observe_identity(h.value,false,id)&&final_equal(h.value,w);
}
struct InputFile {Handle handle;std::array<char,input_cap> bytes{};std::size_t size{};};
// Keep the three bounded inputs off the Windows thread stack. These handles
// remain retained through injected death; no graceful CLOSED is asserted.
struct InputStorage {InputFile context,plan,descriptor;};
InputStorage inputs;
bool load_input(std::string_view path,std::string_view expected,InputFile& out)noexcept{
 if(!lower_hex(expected,64)||!open_ordinary(path,out.handle))return false;
 LARGE_INTEGER length{};
 if(!GetFileSizeEx(out.handle.value,&length)||length.QuadPart<1||length.QuadPart>input_cap)return false;
 out.size=static_cast<std::size_t>(length.QuadPart);std::size_t done=0;
 while(done<out.size){DWORD n{};if(!ReadFile(out.handle.value,out.bytes.data()+done,
  static_cast<DWORD>(out.size-done),&n,nullptr)||!n||n>out.size-done)return false;done+=n;}
 char extra;DWORD n{};if(!ReadFile(out.handle.value,&extra,1,&n,nullptr)||n)return false;
 auto hash=sha256_hex({out.bytes.data(),out.size});return std::string_view(hash.data(),hash.size())==expected;
}
bool module_hash(std::string_view expected)noexcept{
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
ParseResult parse(std::string_view bytes)noexcept{
 return parse_json(bytes,parsing.cells,parsing.duplicate,Limits{max_message,30000,12,4096,262144});
}
bool positive_int(DocumentView d,std::uint32_t n,std::uint64_t max,std::uint64_t& out)noexcept{
 auto c=d.at(n);if(!c||c->kind!=ValueKind::integer||!c->scalar||c->scalar>max)return false;out=c->scalar;return true;
}
bool decimal(DocumentView d,std::uint32_t n,std::uint64_t& out,bool positive=false)noexcept{
 FixedText<20> text;U64 parsed;if(!text.from(d,n)||!U64::parse(text.view(),parsed,positive))return false;
 out=0;for(char c:text.view())out=out*10+static_cast<unsigned>(c-'0');return true;
}
bool decimal_text(Writer&w,std::uint64_t value)noexcept{
 std::array<char,20> b{};auto result=std::to_chars(b.data(),b.data()+b.size(),value);
 return result.ec==std::errc{}&&w.string({b.data(),static_cast<std::size_t>(result.ptr-b.data())});
}
struct Context {
 FixedText<4096> source,parent;FixedText<128> stdin_pipe,stdout_pipe;FixedText<64> actor_sha,capability_sha,plan_sha;
 DWORD parent_pid{};std::uint64_t creation{};
};
bool context_from(std::string_view bytes,Context&out)noexcept{
 auto p=parse(bytes);if(!p)return false;auto d=p.value;auto n=d.root;
 if(closed(d,n,{"schema","role","source_root","proof_parent","parent_pid","parent_creation_filetime",
                "actor_sha256","capability_sha256","plan_sha256","stdin_pipe","stdout_pipe"})!=Error::none||
    !d.string_is(d.member(n,"schema"),"LocalPlayersCrashActorContext/v1")||
    !d.string_is(d.member(n,"role"),"crash_actor"))return false;
 std::uint64_t pid{};
 if(!out.source.from(d,d.member(n,"source_root"))||!out.parent.from(d,d.member(n,"proof_parent"))||
    !out.stdin_pipe.from(d,d.member(n,"stdin_pipe"))||!out.stdout_pipe.from(d,d.member(n,"stdout_pipe"))||
    !out.actor_sha.from(d,d.member(n,"actor_sha256"))||!out.capability_sha.from(d,d.member(n,"capability_sha256"))||
    !out.plan_sha.from(d,d.member(n,"plan_sha256"))||!positive_int(d,d.member(n,"parent_pid"),MAXDWORD,pid)||
    !decimal(d,d.member(n,"parent_creation_filetime"),out.creation,true))return false;
 out.parent_pid=static_cast<DWORD>(pid);
 return valid_local_absolute_path(out.source.view())&&valid_local_absolute_path(out.parent.view())&&
  lower_hex(out.actor_sha.view(),64)&&lower_hex(out.capability_sha.view(),64)&&lower_hex(out.plan_sha.view(),64);
}

constexpr std::array<std::string_view,15> phases={"before_open","before_begin","row_write","before_commit","after_commit","rollback","postverify","publish_ack","checkpoint","export_create","export_write","export_flush","export_move","export_verify_target","recovery_copy"};
constexpr std::array<std::string_view,5> scopes={"service","qualification_copy","original","export","recovery"};
constexpr std::array<std::string_view,6> categories={"control","request","terminal","delivery","workspace","export_spool"};
struct Job {JobKind kind{};FixedText<32> id;FixedText<20> revision;FixedText<512> name;FixedText<64> utc;};
struct Plan {
 FixedText<32> nonce;std::uint64_t service{};std::uint32_t action{1},maximum{};
 std::array<OperationSite,256> sites{};std::size_t site_count{};
 std::array<Job,8> jobs{};std::size_t job_count{};Selector crash;
 FaultPlan fault()const noexcept {FaultPlan p;p.count=1;p.actions[0]={crash,ActionKind::hold};p.maximum_actual_events=maximum;p.sites={sites.data(),site_count};return p;}
};
template<std::size_t N> bool token(DocumentView d,std::uint32_t n,const std::array<std::string_view,N>&names,unsigned&out)noexcept{
 for(unsigned i=0;i<N;++i)if(d.string_is(n,names[i])){out=i;return true;}return false;
}
bool recipe_kind(JobKind k)noexcept{return k==JobKind::start||k==JobKind::create_player||k==JobKind::rename_player||k==JobKind::load_player||k==JobKind::export_player||k==JobKind::delete_player;}
bool kind_from(DocumentView d,std::uint32_t n,JobKind&out)noexcept{FixedText<32>s;return s.from(d,n)&&parse_kind(s.view(),out)&&recipe_kind(out);}
bool site_from(DocumentView d,std::uint32_t n,OperationSite&out)noexcept{
 unsigned p{},s{};FixedText<8> edge;
 if(closed(d,n,{"kind","scope","phase","edge"})!=Error::none||!kind_from(d,d.member(n,"kind"),out.kind)||
    !token(d,d.member(n,"phase"),phases,p)||!token(d,d.member(n,"scope"),scopes,s)||!edge.from(d,d.member(n,"edge")))return false;
 if(edge.view()!="before"&&edge.view()!="after")return false;
 out.phase=static_cast<Phase>(p);out.scope=static_cast<Scope>(s);out.edge=edge.view()=="before"?Edge::before:Edge::after;return true;
}
bool job_from(DocumentView d,std::uint32_t n,Job&j)noexcept{
 if(!kind_from(d,d.member(n,"kind"),j.kind))return false;
 if(j.kind==JobKind::start)return closed(d,n,{"kind"})==Error::none;
 if(j.kind==JobKind::create_player){
  if(closed(d,n,{"kind","id","name","utc"})!=Error::none||!j.id.from(d,d.member(n,"id")))return false;
 }else{
  if(j.kind==JobKind::rename_player){if(closed(d,n,{"kind","player_id","expected_revision","name","utc"})!=Error::none)return false;}
  else if(j.kind==JobKind::load_player){if(closed(d,n,{"kind","player_id"})!=Error::none)return false;}
  else if(closed(d,n,{"kind","player_id","expected_revision"})!=Error::none)return false;
  if(!j.id.from(d,d.member(n,"player_id")))return false;
 }
 if(!lower_hex(j.id.view(),32))return false;
 if(j.kind==JobKind::rename_player||j.kind==JobKind::export_player||j.kind==JobKind::delete_player){U64 rev;if(!j.revision.from(d,d.member(n,"expected_revision"))||!U64::parse(j.revision.view(),rev,true))return false;}
 if(j.kind==JobKind::create_player||j.kind==JobKind::rename_player)
  return j.name.from(d,d.member(n,"name"))&&valid_player_name(j.name.view())&&j.utc.from(d,d.member(n,"utc"))&&valid_utc(j.utc.view());
 return true;
}
bool plan_from(std::string_view bytes,Plan&out)noexcept{
 auto p=parse(bytes);if(!p)return false;auto d=p.value;auto n=d.root;std::uint64_t maximum{},code{};
 if(closed(d,n,{"schema","nonce","service_ordinal","maximum_actual_events","sites","jobs","crash_selector","exit_code"})!=Error::none||
  !d.string_is(d.member(n,"schema"),"LocalPlayersCrashActorPlan/v1")||!out.nonce.from(d,d.member(n,"nonce"))||!lower_hex(out.nonce.view(),32)||
  !positive_int(d,d.member(n,"service_ordinal"),INT64_MAX,out.service)||!positive_int(d,d.member(n,"maximum_actual_events"),max_events,maximum)||
  !positive_int(d,d.member(n,"exit_code"),86,code)||code!=86)return false;
 out.maximum=static_cast<std::uint32_t>(maximum);
 auto sites=d.at(d.member(n,"sites"));auto jobs=d.at(d.member(n,"jobs"));
 if(!sites||sites->kind!=ValueKind::array||!jobs||jobs->kind!=ValueKind::array)return false;
 for(auto at=sites->first;at!=no_cell;at=d.at(at)->next){if(out.site_count==out.sites.size()||!site_from(d,at,out.sites[out.site_count]))return false;
  for(std::size_t i=0;i<out.site_count;++i)if(out.sites[i]==out.sites[out.site_count])return false;++out.site_count;}
 for(auto at=jobs->first;at!=no_cell;at=d.at(at)->next){if(out.job_count==out.jobs.size()||!job_from(d,at,out.jobs[out.job_count]))return false;
  if((out.job_count==0)!=(out.jobs[out.job_count].kind==JobKind::start))return false;++out.job_count;}
 if(!out.site_count||!out.job_count)return false;
 auto c=d.member(n,"crash_selector");OperationSite selected;std::uint64_t service{},request{},occurrence{};
 if(closed(d,c,{"service_ordinal","request_ordinal","kind","scope","phase","edge","occurrence"})!=Error::none||
  !positive_int(d,d.member(c,"service_ordinal"),INT64_MAX,service)||service!=out.service||
  !positive_int(d,d.member(c,"request_ordinal"),out.job_count,request)||
  !positive_int(d,d.member(c,"occurrence"),INT64_MAX,occurrence))return false;
 // The selected object has seven keys rather than the four-key site shape.
 unsigned phase{},scope{};FixedText<8> edge;
 if(!kind_from(d,d.member(c,"kind"),selected.kind)||selected.kind!=out.jobs[request-1].kind||
  !token(d,d.member(c,"phase"),phases,phase)||!token(d,d.member(c,"scope"),scopes,scope)||!edge.from(d,d.member(c,"edge"))||
  (edge.view()!="before"&&edge.view()!="after"))return false;
 selected.phase=static_cast<Phase>(phase);selected.scope=static_cast<Scope>(scope);selected.edge=edge.view()=="before"?Edge::before:Edge::after;
 if(std::find(out.sites.begin(),out.sites.begin()+out.site_count,selected)==out.sites.begin()+out.site_count)return false;
 out.crash.service=service;out.crash.request=request;out.crash.kind=selected.kind;out.crash.scope=selected.scope;out.crash.phase=selected.phase;out.crash.edge=selected.edge;out.crash.occurrence=occurrence;
 return valid_plan(out.fault());
}
bool descriptor_root(std::string_view bytes,const Plan&plan,FixedText<4096>&root)noexcept{
 auto p=parse(bytes);if(!p)return false;auto d=p.value;auto n=d.root;FixedText<4096>parent;FixedText<32>rid,pid;FixedText<64>hash;std::uint64_t rv{},pv{};
 return closed(d,n,{"schema","root","parent","nonce","root_volume_serial","root_file_id","parent_volume_serial","parent_file_id","sentinel_sha256"})==Error::none&&
  d.string_is(d.member(n,"schema"),"LocalPlayersTestRootDescriptor/v1")&&d.string_is(d.member(n,"nonce"),plan.nonce.view())&&
  root.from(d,d.member(n,"root"))&&valid_local_absolute_path(root.view())&&parent.from(d,d.member(n,"parent"))&&valid_local_absolute_path(parent.view())&&
  decimal(d,d.member(n,"root_volume_serial"),rv)&&decimal(d,d.member(n,"parent_volume_serial"),pv)&&
  rid.from(d,d.member(n,"root_file_id"))&&lower_hex(rid.view(),32)&&pid.from(d,d.member(n,"parent_file_id"))&&lower_hex(pid.view(),32)&&
  hash.from(d,d.member(n,"sentinel_sha256"))&&lower_hex(hash.view(),64);
}
std::uint64_t filetime(FILETIME t)noexcept{return(static_cast<std::uint64_t>(t.dwHighDateTime)<<32)|t.dwLowDateTime;}
bool parent_from(const Context&ctx,Handle&parent)noexcept{
 if(ctx.parent_pid==GetCurrentProcessId())return false;
 Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0));if(!snapshot.good())return false;
 PROCESSENTRY32W entry{};entry.dwSize=sizeof entry;bool direct=false;
 if(Process32FirstW(snapshot.value,&entry))do{if(entry.th32ProcessID==GetCurrentProcessId()){direct=entry.th32ParentProcessID==ctx.parent_pid;break;}}while(Process32NextW(snapshot.value,&entry));
 if(!snapshot.close()||!direct)return false;
 parent.value=OpenProcess(SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION,FALSE,ctx.parent_pid);
 FILETIME c{},e{},k{},u{};return parent.good()&&GetProcessTimes(parent.value,&c,&e,&k,&u)&&
  filetime(c)==ctx.creation&&WaitForSingleObject(parent.value,0)==WAIT_TIMEOUT;
}
// Only these exact per-nonce local names are admitted. Neither a general
// UNC filesystem path nor an inherited standard handle can select transport.
bool pipe_name(std::string_view name,const Plan&plan,std::string_view suffix)noexcept{
 constexpr std::string_view prefix=R"(\\.\pipe\flight-local-players-)";
 return name.size()==prefix.size()+32+suffix.size()&&
  name.substr(0,prefix.size())==prefix&&name.substr(prefix.size(),32)==plan.nonce.view()&&
  name.substr(prefix.size()+32)==suffix;
}
bool open_pipe(std::string_view name,DWORD access,Handle&client)noexcept{
 if(name.empty()||name.size()>128)return false;
 std::array<wchar_t,129> wide{};
 int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,name.data(),static_cast<int>(name.size()),wide.data(),128);
 if(n<1)return false;wide[n]=0;
 // Root must already own this fresh single-instance byte-mode server. Failure
 // is retained; no name retry, inherited-handle or synchronous fallback exists.
 client.value=CreateFileW(wide.data(),access,0,nullptr,OPEN_EXISTING,
                        FILE_FLAG_OVERLAPPED|SECURITY_SQOS_PRESENT|SECURITY_IDENTIFICATION,nullptr);
 if(!client.good()){const auto error=GetLastError();return actor_reject("pipe_open",error,true);}
 DWORD flags{};if(!GetHandleInformation(client.value,&flags)){const auto error=GetLastError();return actor_reject("pipe_handle_info",error,true);}
 return !(flags&HANDLE_FLAG_INHERIT)||actor_reject("pipe_inheritance");
}
bool transport(HANDLE input,HANDLE output,DWORD parent_pid)noexcept{
 if(!input||!output||input==INVALID_HANDLE_VALUE||output==INVALID_HANDLE_VALUE||input==output)return actor_reject("transport_handles");
 for(auto h:{input,output}){ULONG pid{};DWORD flags{};
  const auto type=GetFileType(h);
  if(type!=FILE_TYPE_PIPE){const auto error=type==FILE_TYPE_UNKNOWN?GetLastError():ERROR_SUCCESS;return actor_reject("transport_file_type",error,type==FILE_TYPE_UNKNOWN&&error!=ERROR_SUCCESS);}
  if(!GetNamedPipeInfo(h,&flags,nullptr,nullptr,nullptr)){const auto error=GetLastError();return actor_reject("transport_pipe_info",error,true);}
  if((flags&PIPE_SERVER_END)||(flags&PIPE_TYPE_MESSAGE))return actor_reject("transport_flags");
  if(!GetNamedPipeServerProcessId(h,&pid)){const auto error=GetLastError();return actor_reject("transport_server_pid",error,true);}
  if(pid!=parent_pid)return actor_reject("transport_server_identity");}
 // These clients were opened by this actor with FILE_FLAG_OVERLAPPED.
 // Root independently checks both server-side client PIDs against this child;
 // it never accepts inherited opener PID or readiness text as that proof.
 return true;
}
enum class Io {ok,parent_eof,lease_expired,actor_error};
DWORD remaining(ULONGLONG deadline)noexcept{
 auto now=GetTickCount64();return now>=deadline?0:static_cast<DWORD>(std::min<ULONGLONG>(deadline-now,MAXDWORD-1));
}
// Every pending operation owns its buffer/OVERLAPPED/event until observed
// completion, including cancellation. No deadline frees pending kernel memory.
Io transfer(HANDLE pipe,HANDLE parent,bool write,std::span<char> bytes,ULONGLONG deadline)noexcept{
 std::size_t done=0;
 while(done<bytes.size()){
  DWORD wait=remaining(deadline);if(!wait){actor_failure("transfer_deadline",6);return Io::lease_expired;}
  Handle event(CreateEventW(nullptr,TRUE,FALSE,nullptr));if(!event.good()){const auto error=GetLastError();actor_failure("transfer_event",6,error,true);return Io::actor_error;}
  OVERLAPPED ov{};ov.hEvent=event.value;DWORD count{};
  BOOL immediate=write?WriteFile(pipe,bytes.data()+done,static_cast<DWORD>(bytes.size()-done),&count,&ov):
                        ReadFile(pipe,bytes.data()+done,static_cast<DWORD>(bytes.size()-done),&count,&ov);
  DWORD error=immediate?ERROR_SUCCESS:GetLastError();Io status=Io::ok;
  bool pending=!immediate&&error==ERROR_IO_PENDING;
  if(pending){
   HANDLE watches[2]={event.value,parent};DWORD n=parent?2:1;
   DWORD observed=WaitForMultipleObjects(n,watches,FALSE,remaining(deadline));
   if(observed!=WAIT_OBJECT_0){
    status=observed==WAIT_TIMEOUT?Io::lease_expired:observed==WAIT_OBJECT_0+1?Io::parent_eof:Io::actor_error;
    // ERROR_NOT_FOUND may be a legitimate completion race, never permission
    // to discard the OVERLAPPED; GetOverlappedResult still drains it below.
    CancelIoEx(pipe,&ov);
    BOOL complete=GetOverlappedResult(pipe,&ov,&count,TRUE);
    error=complete?ERROR_SUCCESS:GetLastError();
    while(!complete&&error==ERROR_IO_INCOMPLETE){
     complete=GetOverlappedResult(pipe,&ov,&count,TRUE);error=complete?ERROR_SUCCESS:GetLastError();
    }
    pending=false;
   }else if(!GetOverlappedResult(pipe,&ov,&count,FALSE))error=GetLastError();
   else {pending=false;error=ERROR_SUCCESS;}
  }else if(immediate&&!GetOverlappedResult(pipe,&ov,&count,FALSE))error=GetLastError();
  // Defensive completion path: even an unexpected incomplete event cannot
  // release live OVERLAPPED storage. Failure is never converted to success.
  if((pending||immediate)&&error==ERROR_IO_INCOMPLETE){
   status=Io::actor_error;CancelIoEx(pipe,&ov);
   BOOL complete=GetOverlappedResult(pipe,&ov,&count,TRUE);
   error=complete?ERROR_SUCCESS:GetLastError();
   while(!complete&&error==ERROR_IO_INCOMPLETE){
    complete=GetOverlappedResult(pipe,&ov,&count,TRUE);error=complete?ERROR_SUCCESS:GetLastError();
   }
   pending=false;
  }
  if(error!=ERROR_SUCCESS&&status==Io::ok)
   status=(error==ERROR_BROKEN_PIPE||error==ERROR_PIPE_NOT_CONNECTED)?Io::parent_eof:Io::actor_error;
  bool event_closed=event.close();if(!event_closed){const auto close_error=GetLastError();actor_failure("transfer_event_close",6,close_error,true);return Io::actor_error;}
  if(status!=Io::ok){actor_failure(write?"transfer_write":"transfer_read",6,error,error!=ERROR_SUCCESS);return status;}
  if(!count||count>bytes.size()-done){actor_failure("transfer_count",6);return Io::actor_error;}
  if(parent){const auto observed=WaitForSingleObject(parent,0);if(observed!=WAIT_TIMEOUT){const auto wait_error=observed==WAIT_FAILED?GetLastError():ERROR_SUCCESS;actor_failure("transfer_parent",6,wait_error,observed==WAIT_FAILED);return Io::parent_eof;}}
  done+=count;
 }
 return Io::ok;
}
Io send_frame(HANDLE pipe,HANDLE parent,std::string_view payload,ULONGLONG deadline)noexcept{
 if(payload.empty()||payload.size()>frame_cap||!valid_utf8(payload))return Io::actor_error;
 std::array<char,frame_cap+4> frame{};auto n=static_cast<std::uint32_t>(payload.size());
 for(unsigned i=0;i<4;++i)frame[i]=static_cast<char>((n>>(8*i))&255);
 std::memcpy(frame.data()+4,payload.data(),payload.size());
 return transfer(pipe,parent,true,std::span(frame).first(payload.size()+4),deadline);
}
Io receive_release(HANDLE input,HANDLE parent,const Plan&plan,DWORD actor_pid,ULONGLONG deadline,std::array<char,frame_cap>&bytes,std::size_t&size)noexcept{
 std::array<char,4> prefix{};auto result=transfer(input,parent,false,prefix,deadline);if(result!=Io::ok)return result;
 std::uint32_t n=0;for(unsigned i=0;i<4;++i)n|=static_cast<std::uint32_t>(static_cast<unsigned char>(prefix[i]))<<(8*i);
 if(!n||n>frame_cap)return Io::actor_error;
 size=n;result=transfer(input,parent,false,std::span(bytes).first(n),deadline);if(result!=Io::ok)return result;
 auto parsed=parse({bytes.data(),n});if(!parsed)return Io::actor_error;auto d=parsed.value;auto root=d.root;std::uint64_t pid{},action{};
 if(closed(d,root,{"type","nonce","pid","action_ordinal"})!=Error::none||
  !d.string_is(d.member(root,"type"),"RELEASE")||!d.string_is(d.member(root,"nonce"),plan.nonce.view())||
  !positive_int(d,d.member(root,"pid"),MAXDWORD,pid)||pid!=actor_pid||
  !positive_int(d,d.member(root,"action_ordinal"),32,action)||action!=plan.action)return Io::actor_error;
 DWORD extra{};if(!PeekNamedPipe(input,nullptr,0,nullptr,&extra,nullptr)||extra)return Io::actor_error;
 return Io::ok;
}
bool ready(Writer&w,const Plan&p,DWORD pid,const Context&ctx)noexcept{
 return w.raw("{\"type\":\"READY\",\"nonce\":")&&w.string(p.nonce.view())&&w.raw(",\"pid\":")&&w.integer(pid)&&
  w.raw(",\"role\":\"crash_actor\",\"capability_sha256\":")&&w.string(ctx.capability_sha.view())&&
  w.raw(",\"plan_sha256\":")&&w.string(ctx.plan_sha.view())&&w.character('}');
}
struct Arguments {FixedText<4096> context,descriptor,plan;FixedText<64> context_sha,descriptor_sha,plan_sha;};
bool arguments(int argc,wchar_t**argv,Arguments&out)noexcept{
 if(argc!=13)return false;unsigned seen=0;
 for(int i=1;i<argc;i+=2){std::wstring_view key(argv[i]);unsigned bit{};FixedText<4096> text;
  if(!utf8(argv[i+1],text))return false;
  if(key==L"--context"){bit=1;out.context=text;}
  else if(key==L"--descriptor"){bit=2;out.descriptor=text;}
  else if(key==L"--plan"){bit=4;out.plan=text;}
  else if(key==L"--context-sha256"){bit=8;if(!out.context_sha.assign(text.view()))return false;}
  else if(key==L"--descriptor-sha256"){bit=16;if(!out.descriptor_sha.assign(text.view()))return false;}
  else if(key==L"--plan-sha256"){bit=32;if(!out.plan_sha.assign(text.view()))return false;}
  else return false;if(seen&bit)return false;seen|=bit;
 }
 return seen==63&&lower_hex(out.context_sha.view(),64)&&lower_hex(out.descriptor_sha.view(),64)&&lower_hex(out.plan_sha.view(),64);
}

Selector selected(const NativeObservation&o)noexcept{Selector s;s.service=o.service_ordinal;s.request=o.request_ordinal;s.kind=o.kind;s.scope=o.scope;s.phase=o.phase;s.edge=o.edge;s.occurrence=o.occurrence;return s;}
Selector selected(const AllocationObservation&o)noexcept{Selector s;s.type=SelectorKind::allocation;s.service=o.service_ordinal;s.request=o.request_ordinal;s.category=o.category;s.ordinal=o.ordinal;return s;}
auto key(const Selector&s)noexcept{return std::tuple(s.type,s.service,s.request,s.kind,s.scope,s.phase,s.edge,s.occurrence,s.category,s.ordinal);}
struct Order {bool reservation{};Selector selector;ReservationObservation charge;std::uint64_t reservation_sequence{};};
struct CrashObserver final:QualificationObserver {
 const Plan&plan;TestController controller;std::vector<Order> order;std::mutex mutex;
 std::atomic_bool failed{},permitted{};std::uint64_t reservations{};
 CrashObserver(const Plan&p,std::span<ObservedEvent>events,std::span<CounterState>counters):plan(p),controller(p.nonce.view(),p.fault(),events,counters){order.reserve(p.maximum);}
 void enter_locked(Order row){if(failed||order.size()>=plan.maximum){failed=true;throw std::runtime_error("crash event capacity");}order.push_back(row);}
 void observe(const NativeObservation&o)override{
  if(selected(o)!=plan.crash){
   // No other action exists, so this call cannot hold. Serialize entry and
   // controller numbering together, including concurrent owner admissions.
   std::lock_guard lock(mutex);enter_locked({false,selected(o),{},0});controller.observe(o);
   if(failed||controller.error()!=TestError::none)throw std::runtime_error("invalid actual crash observation");return;
  }
  {std::lock_guard lock(mutex);enter_locked({false,selected(o),{},0});}
  // Selected submit's owner-side allocation callbacks already completed. The
  // owner waits rather than submitting again; allow history reads while held.
  controller.observe(o);
  if(failed||controller.error()!=TestError::none)throw std::runtime_error("invalid actual crash observation");
  if(selected(o)==plan.crash){if(!permitted.load(std::memory_order_acquire))throw std::runtime_error("selected hold returned without valid Root release");
   // Intentional injected process crash ONLY from this selected real callback.
   // No destructors, graceful join, next SQLite/OS operation or synthetic ACK.
   std::_Exit(86);
  }
 }
 bool allow_allocation(const AllocationObservation&o)override{std::lock_guard lock(mutex);enter_locked({false,selected(o),{},0});return !failed&&controller.allow_allocation(o);}
 void observe_reservation(const ReservationObservation&o)override{
  if(static_cast<unsigned>(o.action)>3||static_cast<unsigned>(o.category)>5||o.service_ordinal!=plan.service||o.request_ordinal>INT64_MAX||
   !o.allocation_ordinal||o.allocation_ordinal>INT64_MAX||o.requested>33554432||o.rounded>33554432||o.rounded<o.requested||o.rounded%4096||o.reserved_pages>8192||o.live_pages>8192){failed=true;throw std::runtime_error("invalid actual reservation");}
  std::lock_guard lock(mutex);if(failed||order.size()>=plan.maximum||reservations==UINT64_MAX){failed=true;throw std::runtime_error("crash reservation capacity");}
  Order row;row.reservation=true;row.charge=o;row.reservation_sequence=++reservations;order.push_back(row);
 }
 bool take_sqlite_interrupt_request()noexcept override{return controller.take_sqlite_interrupt_request();}
};
struct Capture final:AdmissionSource {
 const Job&job;std::string_view target;
 Capture(const Job&j,std::string_view t):job(j),target(t){}
 Error outer_kind(JobKind&out)const noexcept override {out=job.kind;return recipe_kind(job.kind)&&job.kind!=JobKind::start?Error::none:Error::invalid_request;}
 Error capture(std::span<JsonCell>cells,std::span<char>bytes,DocumentView&out)const noexcept override{
  std::size_t used=0,count=0;bool good=true;
  auto add=[&](ValueKind kind,std::string_view k,std::string_view value)->std::uint32_t{
   if(!good||count>=cells.size()||k.size()>UINT16_MAX||k.size()+value.size()>bytes.size()-used){good=false;return no_cell;}
   auto n=static_cast<std::uint32_t>(count++);JsonCell c;c.kind=kind;c.flags=1;c.key_offset=static_cast<std::uint32_t>(used);c.key_length=static_cast<std::uint16_t>(k.size());
   if(!k.empty())std::memcpy(bytes.data()+used,k.data(),k.size());used+=k.size();c.offset=static_cast<std::uint32_t>(used);c.length=static_cast<std::uint32_t>(value.size());
   if(!value.empty())std::memcpy(bytes.data()+used,value.data(),value.size());used+=value.size();cells[n]=c;return n;
  };
  auto root=add(ValueKind::object,{},{}),kind=add(ValueKind::string,"kind",kind_name(job.kind)),payload=add(ValueKind::object,"payload",{});
  if(!good)return Error::payload_limit;cells[root].first=kind;cells[kind].next=payload;std::uint32_t prior=no_cell;
  auto field=[&](std::string_view k,std::string_view v){auto at=add(ValueKind::string,k,v);if(at==no_cell)return;if(prior==no_cell)cells[payload].first=at;else cells[prior].next=at;prior=at;};
  field(job.kind==JobKind::create_player?"id":"player_id",job.id.view());
  if(job.kind==JobKind::rename_player||job.kind==JobKind::export_player||job.kind==JobKind::delete_player)field("expected_revision",job.revision.view());
  if(job.kind==JobKind::create_player||job.kind==JobKind::rename_player){field("name",job.name.view());field("utc",job.utc.view());}
  if(job.kind==JobKind::export_player)field("target_absolute_path",target);
  if(!good)return Error::payload_limit;out={{bytes.data(),used},cells.first(count),root};return Error::none;
 }
};
struct ServiceOwner {
 Capability&cap;CrashObserver&observer;Service*service{};
 ~ServiceOwner(){
  observer.controller.abort();if(service){if(!service->begin_shutdown())std::terminate();
   // Failure retains real owners until actual join. Root watchdog is failure,
   // never a fabricated close or success exit. No native handle is freed live.
   while(!service->try_join())std::this_thread::yield();
   if(!Service::destroy(service))std::terminate();service=nullptr;
  }
  cap.release_leases_after_join(); // void release is NOT a checked CLOSED claim
 }
};
bool successful_terminal(std::string_view bytes,const Job&job,const Admission&a)noexcept{
 auto parsed=parse(bytes);if(!parsed)return false;auto d=parsed.value;auto n=d.root;FixedText<20>sequence;U64 u;
 if(closed(d,n,{"request_id","kind","state","error_code","commit_sequence","value"})!=Error::none||
  !d.string_is(d.member(n,"request_id"),a.request_id.view())||!d.string_is(d.member(n,"kind"),kind_name(job.kind))||!d.string_is(d.member(n,"error_code"),""))return false;
 auto value=d.at(d.member(n,"value"));if(!value||value->kind!=ValueKind::object)return false;
 bool committed=d.string_is(d.member(n,"state"),"committed"),read=d.string_is(d.member(n,"state"),"read"),unchanged=d.string_is(d.member(n,"state"),"no_change");
 bool legal=job.kind==JobKind::start?(committed||read):(job.kind==JobKind::create_player||job.kind==JobKind::rename_player)?(committed||unchanged):job.kind==JobKind::delete_player?committed:read;
 if(!legal)return false;auto seq=d.member(n,"commit_sequence");
 if(committed)return sequence.from(d,seq)&&U64::parse(sequence.view(),u,true);
 return d.at(seq)&&d.at(seq)->kind==ValueKind::null;
}
// Sequential FAILURE-ONLY snapshots, not an atomic history or success gate.
// No profile/value/root/path/nonce/request text is emitted. peek borrows one
// immutable terminal and abandon returns it unacknowledged before teardown.
int arrival_failure(Service*s,CrashObserver&o,const Arrival&arrived,const Job&job,const Admission&a,std::uint32_t pid)noexcept{
 const auto error=o.controller.error();const auto count=o.controller.event_count();
 ObservedEvent last{},checkpoint{};bool has_last=count&&o.controller.copy_event(count-1,last),has_checkpoint=false;
 for(auto i=count;i>0;--i){ObservedEvent event{};if(o.controller.copy_event(i-1,event)&&!event.allocation){checkpoint=event;has_checkpoint=true;break;}}
 std::fprintf(stderr,"LOCAL_PLAYERS_ACTOR_ARRIVAL controller_error=%u observer_failed=%d arrival_present=%d pid_match=%d action_ordinal=%u selector_match=%d event_count=%zu last_present=%d last_sequence=%llu last_allocation=%d last_admitted=%d\n",
  static_cast<unsigned>(error),o.failed.load()?1:0,arrived.present?1:0,arrived.pid==pid?1:0,arrived.action_ordinal,arrived.selector==o.plan.crash?1:0,count,has_last?1:0,
  static_cast<unsigned long long>(last.sequence),last.allocation?1:0,last.admitted?1:0);
 const auto&c=checkpoint.operation;
 std::fprintf(stderr,"LOCAL_PLAYERS_ACTOR_CHECKPOINT present=%d sequence=%llu admitted=%d service=%llu request=%llu kind=%u scope=%u phase=%u edge=%u occurrence=%llu sqlite_available=%d sqlite_result=%d win32_available=%d win32=%u\n",
  has_checkpoint?1:0,static_cast<unsigned long long>(checkpoint.sequence),checkpoint.admitted?1:0,static_cast<unsigned long long>(c.service_ordinal),static_cast<unsigned long long>(c.request_ordinal),
  static_cast<unsigned>(c.kind),static_cast<unsigned>(c.scope),static_cast<unsigned>(c.phase),static_cast<unsigned>(c.edge),static_cast<unsigned long long>(c.occurrence),c.has_result?1:0,c.sqlite_result,c.has_win32_error?1:0,c.win32_error);
 Status status{};const bool has_status=s->status(status);
 std::fprintf(stderr,"LOCAL_PLAYERS_ACTOR_STATUS available=%d state=%u error=%u pending=%u undelivered=%u writer_alive=%d has_root=%d has_store_version=%d\n",
  has_status?1:0,static_cast<unsigned>(status.state),static_cast<unsigned>(status.error),static_cast<unsigned>(status.pending),static_cast<unsigned>(status.undelivered),status.writer_alive?1:0,status.has_root?1:0,status.has_store_version?1:0);
 std::array<DeliveryView,1>views{};std::uint8_t terminals{};const bool peeked=s->peek(1,views,terminals);
 int parse_error=-1,state=-1,terminal_error=-1;bool shape=false,request_match=false,kind_match=false,abandoned=false;
 if(peeked&&terminals==1){
  auto parsed=parse(views[0].bytes);parse_error=static_cast<int>(parsed.error);
  if(parsed){const auto d=parsed.value;const auto n=d.root;
   shape=closed(d,n,{"request_id","kind","state","error_code","commit_sequence","value"})==Error::none;
   request_match=d.string_is(d.member(n,"request_id"),a.request_id.view());kind_match=d.string_is(d.member(n,"kind"),kind_name(job.kind));
   constexpr std::array<std::string_view,6>states={"read","committed","no_change","failed","uncertain","recovery_required"};
   for(std::size_t i=0;i<states.size();++i)if(d.string_is(d.member(n,"state"),states[i]))state=static_cast<int>(i);
   for(unsigned i=0;i<=static_cast<unsigned>(Error::file_recovery_required);++i)if(d.string_is(d.member(n,"error_code"),error_name(static_cast<Error>(i))))terminal_error=static_cast<int>(i);
  }
  std::array<std::uint64_t,1>leases={views[0].lease};abandoned=s->abandon(leases);
 }
 std::fprintf(stderr,"LOCAL_PLAYERS_ACTOR_TERMINAL peek_available=%d count=%u parse_error=%d closed_shape=%d request_match=%d kind_match=%d state=%d error=%d abandoned=%d\n",
  peeked?1:0,static_cast<unsigned>(terminals),parse_error,shape?1:0,request_match?1:0,kind_match?1:0,state,terminal_error,abandoned?1:0);
 return actor_failure("wait_arrived",8);
}
bool finish_job(Service*s,CrashObserver&o,HANDLE parent,const Job&job,const Admission&a)noexcept{
 auto deadline=GetTickCount64()+startup_ms;
 while(remaining(deadline)&&WaitForSingleObject(parent,0)==WAIT_TIMEOUT&&!o.failed&&o.controller.error()==TestError::none){
  std::array<DeliveryView,16>views{};std::uint8_t count{};if(!s->peek(16,views,count)||count>1)return false;
  if(count){std::array<std::uint64_t,1>leases={views[0].lease};if(!successful_terminal(views[0].bytes,job,a)){s->abandon(leases);return false;}return s->acknowledge(leases);}
  std::this_thread::yield();
 }
 return false;
}
bool reservation_record(Writer&w,const Plan&p,DWORD pid,const Order&r)noexcept{
 const auto&o=r.charge;constexpr std::array<std::string_view,4>actions={"claim","release","share","unshare"};
 return w.raw("{\"type\":\"RESERVATION\",\"nonce\":")&&w.string(p.nonce.view())&&w.raw(",\"pid\":")&&w.integer(pid)&&
  w.raw(",\"reservation_sequence\":")&&decimal_text(w,r.reservation_sequence)&&w.raw(",\"action\":")&&w.string(actions[static_cast<unsigned>(o.action)])&&
  w.raw(",\"category\":")&&w.string(categories[static_cast<unsigned>(o.category)])&&w.raw(",\"service_ordinal\":")&&w.integer(static_cast<std::int64_t>(o.service_ordinal))&&
  w.raw(",\"request_ordinal\":")&&w.integer(static_cast<std::int64_t>(o.request_ordinal))&&w.raw(",\"allocation_ordinal\":")&&w.integer(static_cast<std::int64_t>(o.allocation_ordinal))&&
  w.raw(",\"requested\":")&&w.integer(o.requested)&&w.raw(",\"rounded\":")&&w.integer(o.rounded)&&w.raw(",\"reserved_pages\":")&&w.integer(o.reserved_pages)&&
  w.raw(",\"live_pages\":")&&w.integer(o.live_pages)&&w.character('}');
}
struct Indexed {Selector selector;std::size_t index{};};
bool stream_history(CrashObserver&o,const Plan&p,HANDLE output,HANDLE parent,DWORD pid,std::uint64_t&selected_sequence) {
 // Selected controller hold has recorded/validated the final event. No owner
 // submits another job while streaming; the worker remains actually held.
 auto count=o.controller.event_count();std::vector<Indexed>index;index.reserve(count);
 for(std::size_t i=0;i<count;++i){ObservedEvent e;if(!o.controller.copy_event(i,e)||!e.admitted||e.sequence!=i+1)return false;
  index.push_back({e.allocation?selected(e.charge):selected(e.operation),i});}
 std::sort(index.begin(),index.end(),[](const Indexed&a,const Indexed&b){return key(a.selector)<key(b.selector);});
 for(std::size_t i=1;i<index.size();++i)if(index[i-1].selector==index[i].selector)return false;
 std::lock_guard lock(o.mutex);std::size_t emitted{};std::uint64_t reservations{};selected_sequence=0;
 if(o.failed||o.order.size()>p.maximum||o.order.size()!=count+o.reservations)return false;
 auto deadline=GetTickCount64()+held_ms;std::array<char,frame_cap>buffer{};
 for(const auto&r:o.order){Writer w(buffer);
  if(r.reservation){if(r.reservation_sequence!=++reservations||!reservation_record(w,p,pid,r))return false;}
  else {auto at=std::lower_bound(index.begin(),index.end(),r.selector,[](const Indexed&i,const Selector&s){return key(i.selector)<key(s);});
   if(at==index.end()||at->selector!=r.selector||at->index!=emitted)return false;++emitted;
   if(r.selector==p.crash){if(selected_sequence)return false;selected_sequence=at->index+1;}
   if(!w.raw("{\"type\":\"EVENT\",\"nonce\":")||!w.string(p.nonce.view())||!w.raw(",\"pid\":")||!w.integer(pid)||!w.raw(",\"event\":")||
    !o.controller.write_event(at->index,w)||!w.character('}'))return false;
  }
  if(send_frame(output,parent,w.bytes(),deadline)!=Io::ok)return false;
 }
 return emitted==count&&reservations==o.reservations&&selected_sequence!=0&&!o.failed&&o.controller.error()==TestError::none;
}
bool arrived_record(Writer&w,const Plan&p,DWORD pid,std::uint64_t sequence)noexcept{
 return w.raw("{\"type\":\"ARRIVED\",\"nonce\":")&&w.string(p.nonce.view())&&w.raw(",\"pid\":")&&w.integer(pid)&&
  w.raw(",\"action_ordinal\":1,\"event_sequence\":")&&decimal_text(w,sequence)&&w.character('}');
}
bool derived_target(const Context&c,const Plan&p,FixedText<4096>&out)noexcept{
 std::array<char,4096>b{};Writer w(b);
 if(!w.raw(c.parent.view())||!w.raw("\\local-players-crash-export-")||!w.raw(p.nonce.view())||!w.raw(".json")||!out.assign(w.bytes()))return false;
 Wide wide;if(!wide.set(out.view()))return false;
 // Do not overwrite/predelete an old target. Root separately pins fresh-parent
 // fixtures. Exactly missing FILE is required, not an inaccessible parent.
 SetLastError(ERROR_SUCCESS);auto attributes=GetFileAttributesW(wide.value.data());
 return attributes==INVALID_FILE_ATTRIBUTES&&GetLastError()==ERROR_FILE_NOT_FOUND;
}
int actor(int argc,wchar_t**argv){
 auto startup_deadline=GetTickCount64()+startup_ms;Arguments args;if(!arguments(argc,argv,args))return 2;
 auto&cf=inputs.context;auto&pf=inputs.plan;auto&df=inputs.descriptor;Context context;Plan plan;FixedText<4096>root,target;
 if(!load_input(args.context.view(),args.context_sha.view(),cf)||!context_from({cf.bytes.data(),cf.size},context)||
  context.capability_sha.view()!=args.descriptor_sha.view()||context.plan_sha.view()!=args.plan_sha.view()||
  !load_input(args.plan.view(),args.plan_sha.view(),pf)||!plan_from({pf.bytes.data(),pf.size},plan)||
  !load_input(args.descriptor.view(),args.descriptor_sha.view(),df)||!descriptor_root({df.bytes.data(),df.size},plan,root)||
  at_or_within(args.context.view(),root.view())||at_or_within(args.plan.view(),root.view())||at_or_within(args.descriptor.view(),root.view())||!module_hash(context.actor_sha.view()))return 3;
 Handle parent;if(!parent_from(context,parent))return actor_failure("parent_admission",3);Handle input,output;
 if(!pipe_name(context.stdin_pipe.view(),plan,"-stdin")||!pipe_name(context.stdout_pipe.view(),plan,"-stdout")||
  !open_pipe(context.stdin_pipe.view(),GENERIC_READ,input)||!open_pipe(context.stdout_pipe.view(),GENERIC_WRITE|FILE_READ_ATTRIBUTES,output)||
  !transport(input.value,output.value,context.parent_pid))return actor_failure("transport_admission",3);
 const auto parent_state=WaitForSingleObject(parent.value,0);
 if(parent_state!=WAIT_TIMEOUT){const auto error=parent_state==WAIT_FAILED?GetLastError():ERROR_SUCCESS;return actor_failure("startup_parent",3,error,parent_state==WAIT_FAILED);}
 if(!remaining(startup_deadline))return actor_failure("startup_deadline",3);
 bool export_job=false;for(std::size_t i=0;i<plan.job_count;++i)export_job=export_job||plan.jobs[i].kind==JobKind::export_player;
 if(export_job&&!derived_target(context,plan,target))return 3;
 auto trust=TestRootFactory::prepare_prerequisite(context.source.view(),context.parent.view());if(!trust.valid())return actor_failure("prerequisite",4);
 std::vector<ObservedEvent>events(plan.maximum);std::vector<CounterState>counters(plan.maximum);CrashObserver observer(plan,events,counters);
 if(observer.controller.error()!=TestError::none)return actor_failure("controller",4);
 auto cap=TestRootFactory::admit_file(args.descriptor.view(),args.descriptor_sha.view(),trust,&observer,plan.service);
 if(!cap.valid()||cap.nonce()!=plan.nonce.view())return actor_failure("capability",4);
 auto token=cap.take_access();if(!token||!token->isolated_test())return actor_failure("sealed_token",4);
 ServiceOwner owner{cap,observer};owner.service=Service::create(std::move(*token));
 if(!owner.service){token.reset();return actor_failure("service_create",5);}token.reset();
 std::array<char,frame_cap>buffer{};Writer w(buffer);DWORD pid=GetCurrentProcessId();
 if(!ready(w,plan,pid,context))return actor_failure("ready_encode",6);
 if(send_frame(output.value,parent.value,w.bytes(),startup_deadline)!=Io::ok)return actor_failure("ready_send",6);
 for(std::size_t i=0;i<plan.job_count;++i){const auto&job=plan.jobs[i];Capture capture(job,target.view());
  Admission a=job.kind==JobKind::start?owner.service->start():owner.service->submit(capture);
  if(!a.accepted||a.error!=Error::none)return 7;
  if(i+1!=plan.crash.request){if(!finish_job(owner.service,observer,parent.value,job,a))return 7;continue;}
  auto arrived=observer.controller.wait_arrived(1,startup_ms);
  if(!arrived.present||arrived.pid!=pid||arrived.action_ordinal!=1||arrived.selector!=plan.crash||observer.failed||
   WaitForSingleObject(parent.value,0)!=WAIT_TIMEOUT)return arrival_failure(owner.service,observer,arrived,job,a,pid);
  std::uint64_t sequence{};if(!stream_history(observer,plan,output.value,parent.value,pid,sequence))return 8;
  w.reset();if(!arrived_record(w,plan,pid,sequence)||send_frame(output.value,parent.value,w.bytes(),GetTickCount64()+close_ms)!=Io::ok)return 8;
  std::size_t size{};if(receive_release(input.value,parent.value,plan,pid,GetTickCount64()+held_ms,buffer,size)!=Io::ok||
   observer.failed||observer.controller.error()!=TestError::none||WaitForSingleObject(parent.value,0)!=WAIT_TIMEOUT)return 9;
  // Arm before release; acquire in the held worker callback. The exact raw
  // authenticated frame is admitted again by the existing controller.
  observer.permitted.store(true,std::memory_order_release);
  if(!observer.controller.release_bytes({buffer.data(),size})){observer.permitted=false;return 9;}
  // No return/next job/positive CLOSED exists. If the callback fails to execute
  // the injected exit, this process remains a failed retained owner for Root.
  for(;;)std::this_thread::yield();
 }
 return 10; // an unmatched selector is failure, never an UNAVAILABLE pass
}
} // namespace
int wmain(int argc,wchar_t**argv){try{return actor(argc,argv);}catch(...){return 20;}}
#else
int main(){return 77;} // unsupported platform is not a passed crash fixture
#endif
