// Original MIT. Test-only real ownership/share0 actor; no SQLite or Service.
#include "../test_capability.hpp"
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

namespace {
using namespace flight::local_players;
using namespace flight::local_players::testing;
constexpr DWORD startup_ms=45000,held_ms=120000,close_ms=10000;
constexpr std::size_t input_cap=65536,frame_cap=4096;
// Failure-only private stderr: fixed literals and numeric codes, never input values.
int actor_failure(const char*stage,int code,DWORD win32=ERROR_SUCCESS,bool has_win32=false)noexcept{
 std::fprintf(stderr,"LOCAL_PLAYERS_ACTOR_FAILURE role=lock_holder stage=%s code=%d win32_available=%d win32=%lu\n",
              stage,code,has_win32?1:0,static_cast<unsigned long>(win32));
 std::fflush(stderr);return code;
}
bool actor_reject(const char*stage,DWORD win32=ERROR_SUCCESS,bool has_win32=false)noexcept{
 actor_failure(stage,3,win32,has_win32);return false;
}
// Single-thread actor-only fixed parsing storage. No hidden variable allocation.
struct ParsingStorage {std::array<JsonCell,32> cells{};std::array<std::byte,524288> duplicate{};};
ParsingStorage parsing;
struct Handle {
 HANDLE value{INVALID_HANDLE_VALUE};
 Handle()=default;explicit Handle(HANDLE h):value(h){}
 Handle(const Handle&)=delete;Handle& operator=(const Handle&)=delete;
 ~Handle(){if(value&&value!=INVALID_HANDLE_VALUE)CloseHandle(value);}
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
bool same_identity(const FileIdentity&a,const FileIdentity&b)noexcept{
 return a.valid&&b.valid&&a.volume_serial==b.volume_serial&&a.file_id==b.file_id;
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
// are explicitly checked/retired before positive CLOSED, not by static teardown.
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
 return parse_json(bytes,parsing.cells,parsing.duplicate,Limits{input_cap,32,2,4096,4096});
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
bool decode_id(std::string_view s,FileIdentity& id)noexcept{
 if(!lower_hex(s,32))return false;
 auto digit=[](char c){return static_cast<unsigned>(c<='9'?c-'0':c-'a'+10);};
 for(std::size_t i=0;i<16;++i)id.file_id[i]=static_cast<std::byte>((digit(s[2*i])<<4)|digit(s[2*i+1]));return true;
}
bool id_text(Writer&w,const FileIdentity&id)noexcept{
 constexpr char digits[]="0123456789abcdef";std::array<char,32> out{};
 for(std::size_t i=0;i<16;++i){auto b=std::to_integer<unsigned>(id.file_id[i]);out[2*i]=digits[b>>4];out[2*i+1]=digits[b&15];}
 return w.string({out.data(),out.size()});
}
struct Context {
 FixedText<4096> source,parent;FixedText<128> stdin_pipe,stdout_pipe;FixedText<64> actor_sha,capability_sha,plan_sha;
 DWORD parent_pid{};std::uint64_t creation{};
};
bool context_from(std::string_view bytes,Context&out)noexcept{
 auto p=parse(bytes);if(!p)return false;auto d=p.value;auto n=d.root;
 if(closed(d,n,{"schema","role","source_root","proof_parent","parent_pid","parent_creation_filetime",
                "actor_sha256","capability_sha256","plan_sha256","stdin_pipe","stdout_pipe"})!=Error::none||
    !d.string_is(d.member(n,"schema"),"LocalPlayersLockActorContext/v2")||
    !d.string_is(d.member(n,"role"),"lock_holder"))return false;
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
struct Plan {FixedText<32> nonce;std::uint64_t service{};std::uint32_t action{};FileIdentity target;};
bool plan_from(std::string_view bytes,Plan&out)noexcept{
 auto p=parse(bytes);if(!p)return false;auto d=p.value;auto n=d.root;
 if(closed(d,n,{"schema","nonce","service_ordinal","action_ordinal","target","volume_serial","file_id"})!=Error::none||
    !d.string_is(d.member(n,"schema"),"LocalPlayersLockActorPlan/v1")||
    !d.string_is(d.member(n,"target"),"ownership_lock"))return false;
 FixedText<32> id;std::uint64_t action{};
 if(!out.nonce.from(d,d.member(n,"nonce"))||!lower_hex(out.nonce.view(),32)||
    !positive_int(d,d.member(n,"service_ordinal"),INT64_MAX,out.service)||
    !positive_int(d,d.member(n,"action_ordinal"),32,action)||
    !decimal(d,d.member(n,"volume_serial"),out.target.volume_serial)||
    !id.from(d,d.member(n,"file_id"))||!decode_id(id.view(),out.target))return false;
 out.action=static_cast<std::uint32_t>(action);out.target.valid=true;return true;
}
bool descriptor_root(std::string_view bytes,const Plan&plan,FixedText<4096>&root)noexcept{
 auto p=parse(bytes);if(!p)return false;auto d=p.value;auto n=d.root;
 return closed(d,n,{"schema","root","parent","nonce","root_volume_serial","root_file_id",
  "parent_volume_serial","parent_file_id","sentinel_sha256"})==Error::none&&
  d.string_is(d.member(n,"schema"),"LocalPlayersTestRootDescriptor/v1")&&
  d.string_is(d.member(n,"nonce"),plan.nonce.view())&&root.from(d,d.member(n,"root"));
}
std::uint64_t filetime(FILETIME t)noexcept{return(static_cast<std::uint64_t>(t.dwHighDateTime)<<32)|t.dwLowDateTime;}
bool parent_from(const Context&ctx,Handle&parent)noexcept{
 if(ctx.parent_pid==GetCurrentProcessId())return false;
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
Io receive_release(HANDLE input,HANDLE parent,const Plan&plan,DWORD actor_pid,ULONGLONG deadline)noexcept{
 std::array<char,4> prefix{};auto result=transfer(input,parent,false,prefix,deadline);if(result!=Io::ok)return result;
 std::uint32_t n=0;for(unsigned i=0;i<4;++i)n|=static_cast<std::uint32_t>(static_cast<unsigned char>(prefix[i]))<<(8*i);
 if(!n||n>frame_cap)return Io::actor_error;
 std::array<char,frame_cap> bytes{};result=transfer(input,parent,false,std::span(bytes).first(n),deadline);if(result!=Io::ok)return result;
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
  w.raw(",\"role\":\"lock_holder\",\"capability_sha256\":")&&w.string(ctx.capability_sha.view())&&
  w.raw(",\"plan_sha256\":")&&w.string(ctx.plan_sha.view())&&w.character('}');
}
bool held(Writer&w,const Plan&p,DWORD pid,const FileIdentity&id)noexcept{
 return w.raw("{\"type\":\"HELD\",\"nonce\":")&&w.string(p.nonce.view())&&w.raw(",\"pid\":")&&w.integer(pid)&&
  w.raw(",\"action_ordinal\":")&&w.integer(p.action)&&w.raw(",\"volume_serial\":")&&decimal_text(w,id.volume_serial)&&
  w.raw(",\"file_id\":")&&id_text(w,id)&&w.raw(",\"held\":true}");
}
bool closed_record(Writer&w,const Plan&p,DWORD pid,Io reason,bool handles_closed)noexcept{
 auto text=reason==Io::ok?"released":reason==Io::parent_eof?"parent_eof":reason==Io::lease_expired?"lease_expired":"actor_error";
 return w.raw("{\"type\":\"CLOSED\",\"nonce\":")&&w.string(p.nonce.view())&&w.raw(",\"pid\":")&&w.integer(pid)&&
  w.raw(",\"reason\":")&&w.string(text)&&w.raw(",\"handles_closed\":")&&w.raw(handles_closed?"true":"false")&&w.character('}');
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
int actor(int argc,wchar_t**argv)noexcept{
 auto startup_deadline=GetTickCount64()+startup_ms;Arguments args;if(!arguments(argc,argv,args))return 2;
 auto&context_file=inputs.context;auto&plan_file=inputs.plan;auto&descriptor_file=inputs.descriptor;
 Context context;Plan plan;FixedText<4096> root;
 if(!load_input(args.context.view(),args.context_sha.view(),context_file)||
    !context_from({context_file.bytes.data(),context_file.size},context)||
    context.capability_sha.view()!=args.descriptor_sha.view()||context.plan_sha.view()!=args.plan_sha.view()||
    !load_input(args.plan.view(),args.plan_sha.view(),plan_file)||!plan_from({plan_file.bytes.data(),plan_file.size},plan)||
    !load_input(args.descriptor.view(),args.descriptor_sha.view(),descriptor_file)||
    !descriptor_root({descriptor_file.bytes.data(),descriptor_file.size},plan,root)||
    at_or_within(args.context.view(),root.view())||at_or_within(args.plan.view(),root.view())||
    at_or_within(args.descriptor.view(),root.view())||!module_hash(context.actor_sha.view()))return 3;
 Handle parent;if(!parent_from(context,parent))return actor_failure("parent_admission",3);
 Handle input_client,output_client;
 if(!pipe_name(context.stdin_pipe.view(),plan,"-stdin")||!pipe_name(context.stdout_pipe.view(),plan,"-stdout")||
    !open_pipe(context.stdin_pipe.view(),GENERIC_READ,input_client)||
    !open_pipe(context.stdout_pipe.view(),GENERIC_WRITE|FILE_READ_ATTRIBUTES,output_client)||
    !transport(input_client.value,output_client.value,context.parent_pid))return actor_failure("transport_admission",3);
 const auto parent_state=WaitForSingleObject(parent.value,0);
 if(parent_state!=WAIT_TIMEOUT){const auto error=parent_state==WAIT_FAILED?GetLastError():ERROR_SUCCESS;return actor_failure("startup_parent",3,error,parent_state==WAIT_FAILED);}
 if(!remaining(startup_deadline))return actor_failure("startup_deadline",3);
 HANDLE input=input_client.value,output=output_client.value;
 // Only after actual parent/channel/EXE/context admission: separate readonly
 // KnownFolder prerequisite, then exact native descriptor admission. No worker.
 auto trust=TestRootFactory::prepare_prerequisite(context.source.view(),context.parent.view());
 if(!trust.valid())return actor_failure("prerequisite",4);
 auto capability=TestRootFactory::admit_file(args.descriptor.view(),args.descriptor_sha.view(),trust,nullptr,plan.service);
 if(!capability.valid()||capability.nonce()!=plan.nonce.view())return actor_failure("capability",4);
 FixedText<4096> target;if(root.size+13>4096||!target.assign(root.view()))return 5;
 constexpr std::string_view leaf="\\players.lock";for(char c:leaf)target.data[target.size++]=c;target.data[target.size]=0;
 Handle owner;FileIdentity actual;
 if(!open_ordinary(target.view(),owner,GENERIC_READ|GENERIC_WRITE,0)||
    !observe_identity(owner.value,false,actual)||!same_identity(actual,plan.target)||
    WaitForSingleObject(parent.value,0)!=WAIT_TIMEOUT||!remaining(startup_deadline))return actor_failure("lock_target_admission",5);
 std::array<char,frame_cap> payload{};Writer writer(payload);DWORD pid=GetCurrentProcessId();
 if(!ready(writer,plan,pid,context))return actor_failure("ready_encode",6);
 if(send_frame(output,parent.value,writer.bytes(),startup_deadline)!=Io::ok)return actor_failure("ready_send",6);
 writer.reset();if(!held(writer,plan,pid,actual))return actor_failure("held_encode",6);
 if(send_frame(output,parent.value,writer.bytes(),startup_deadline)!=Io::ok)return actor_failure("held_send",6);
 // Lease starts only once actual HELD has completed, never while unobserved startup runs.
 Io reason=receive_release(input,parent.value,plan,pid,GetTickCount64()+held_ms);
 bool owned_closed=owner.close();
 bool capability_closed=capability.retire_unconsumed();
 bool prerequisite_closed=trust.retire();
 bool context_closed=context_file.handle.close();bool plan_closed=plan_file.handle.close();
 bool descriptor_closed=descriptor_file.handle.close();bool parent_closed=parent.close();
 bool input_closed=input_client.close();
 bool all_closed=owned_closed&&capability_closed&&prerequisite_closed&&context_closed&&plan_closed&&descriptor_closed&&parent_closed&&input_closed;
 if(!all_closed)reason=Io::actor_error;
 writer.reset();if(!closed_record(writer,plan,pid,reason,all_closed)||
    send_frame(output,nullptr,writer.bytes(),GetTickCount64()+close_ms)!=Io::ok)return 9;
 // The output client must remain live until CLOSED write completion. Only its
 // checked close followed by actual exit0 completes the positive transport gate.
 if(!output_client.close())return 9;
 return reason==Io::ok&&all_closed?0:reason==Io::parent_eof?7:reason==Io::lease_expired?8:9;
}
} // namespace
int wmain(int argc,wchar_t**argv){return actor(argc,argv);}
#else
// Windows actors are not replaced by a Linux positive stub.
int main(){return 77;}
#endif
