// Original MIT. Fixed Windows KnownFolder/NTFS policy, actual no-overwrite IO.
#include "flight/local_players/windows_filesystem.hpp"
#include <algorithm>
#include <cstring>
#include <limits>
#include <new>
#include <thread>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <shlobj.h>
#include <bcrypt.h>
#endif
namespace flight::local_players {
std::uint64_t NativeContext::next(Phase phase,Scope scope) noexcept {if(!occurrences)return 0;auto& n=(*occurrences)[static_cast<unsigned>(phase)*5+static_cast<unsigned>(scope)];if(n==UINT64_MAX)std::terminate();return ++n;}
void NativeContext::event(NativeObservation o) const {if(observer){o.service_ordinal=service;o.request_ordinal=request;o.kind=kind;observer->observe(o);}}
namespace {thread_local NativeOperationScope* active_operation{};}
NativeOperationScope::NativeOperationScope(NativeContext& c,std::span<char> storage,FileSystem& fs) noexcept:previous_(active_operation),context_(&c),filesystem_(&fs),storage_(storage){active_operation=this;}
NativeOperationScope::~NativeOperationScope(){active_operation=previous_;}
NativeOperationScope* NativeOperationScope::current() noexcept{return active_operation;}
void* NativeOperationScope::push(std::size_t bytes,std::size_t alignment){
 if(!alignment||(alignment&(alignment-1))||used_>storage_.size())throw std::bad_alloc{};
 auto base=reinterpret_cast<std::uintptr_t>(storage_.data());auto address=base+used_;
 if(address<base||address>UINTPTR_MAX-(alignment-1))throw std::bad_alloc{};
 auto aligned=(address+alignment-1)&~(alignment-1);auto offset=aligned-base;
 if(offset>storage_.size()||bytes>storage_.size()-offset)throw std::bad_alloc{};
 used_=offset+bytes;return storage_.data()+offset;
}
void NativeOperationScope::pop(std::size_t mark) noexcept{if(mark<=used_)used_=mark;}
StoreAccess::StoreAccess(StoreAccess&& a) noexcept {if(a.filesystem_){filesystem_=a.filesystem_->relocate(platform_.data());a.filesystem_=nullptr;}observer_=a.observer_;origin_=a.origin_;service_ordinal_=a.service_ordinal_;allocation_ordinals_=a.allocation_ordinals_;a.observer_=nullptr;}
StoreAccess& StoreAccess::operator=(StoreAccess&& a) noexcept {if(this==&a)return *this;if(filesystem_)filesystem_->~FileSystem();filesystem_=a.filesystem_?a.filesystem_->relocate(platform_.data()):nullptr;a.filesystem_=nullptr;observer_=a.observer_;origin_=a.origin_;service_ordinal_=a.service_ordinal_;allocation_ordinals_=a.allocation_ordinals_;a.observer_=nullptr;return *this;}
StoreAccess::~StoreAccess(){if(filesystem_)filesystem_->~FileSystem();}
bool StoreAccess::valid()const noexcept {return filesystem_!=nullptr;}
bool write_export_receipt(Writer& w,const ExportReceipt& r) noexcept {
 constexpr std::string_view phases[]={"read","encode","create","write","flush","verify_temp","move","verify_target","done"};
 w.raw("{\"bytes\":");if(r.has_bytes_hash)w.integer(static_cast<std::int64_t>(r.bytes));else w.raw("null");w.raw(",\"installed\":");w.raw(r.installed<0?"null":r.installed?"true":"false");w.raw(",\"operation_id\":");w.string(r.operation_id.view());w.raw(",\"outcome\":");w.string(r.outcome==ExportReceipt::Outcome::saved?"saved":r.outcome==ExportReceipt::Outcome::recovery_required?"recovery_required":"not_saved");w.raw(",\"phase\":");w.string(phases[static_cast<unsigned>(r.phase)]);w.raw(",\"player_id\":");if(r.has_snapshot)w.string(r.player_id.view());else w.raw("null");w.raw(",\"practice_count\":");if(r.has_snapshot)w.integer(r.practice_count);else w.raw("null");w.raw(",\"preferences_revision\":");if(r.has_snapshot)w.string(r.preferences_revision.view());else w.raw("null");w.raw(",\"sha256\":");if(r.has_bytes_hash)w.string({r.sha256.data(),64});else w.raw("null");w.raw(",\"target_absolute_path\":");w.string(r.target.view());w.raw(",\"temporary_absolute_path\":");if(r.temporary.size)w.string(r.temporary.view());else w.raw("null");return w.character('}')&&w.good();
}
#if defined(_WIN32)
namespace {
constexpr wchar_t hexw[]=L"0123456789abcdef";constexpr char hex[]="0123456789abcdef";
constexpr std::string_view roles[]={"main","wal","shm","journal"};
// Only scalar ownership links are automatic; payload backing is charged.
template<class T> class Scratch {
 NativeOperationScope* scope_{};std::size_t mark_{};T* value_{};
 public:
 Scratch():scope_(NativeOperationScope::current()){
  if(!scope_)throw std::bad_alloc{};mark_=scope_->mark();value_=new(scope_->push(sizeof(T),alignof(T)))T{};
 }
 ~Scratch(){if(value_)value_->~T();if(scope_)scope_->pop(mark_);}
 T& get() noexcept{return *value_;}
 Scratch(const Scratch&)=delete;Scratch& operator=(const Scratch&)=delete;
};
struct Handle {
 HANDLE value{INVALID_HANDLE_VALUE};bool find{};
 Handle()=default;explicit Handle(HANDLE h,bool f=false):value(h),find(f){}
 ~Handle(){close();}
 bool close()noexcept{if(!*this)return true;BOOL ok=find?FindClose(value):CloseHandle(value);if(ok){value=INVALID_HANDLE_VALUE;return true;}
  if(auto* op=NativeOperationScope::current()){op->filesystem().retain_failed_handle(value,find);value=INVALID_HANDLE_VALUE;}return false;
 }
 Handle(const Handle&)=delete;Handle&operator=(const Handle&)=delete;
 HANDLE release()noexcept{auto h=value;value=INVALID_HANDLE_VALUE;return h;}
 explicit operator bool()const noexcept{return value!=INVALID_HANDLE_VALUE&&value!=nullptr;}
};
// Canonical DOS identity stays separate from the syscall-only extended prefix.
// One charged buffer holds at most4096 UTF16 characters plus prefix and NUL.
struct Wide {
 std::array<wchar_t,4101> text{};int size{};
 wchar_t* canonical()noexcept{return text.data()+4;}
 const wchar_t* canonical()const noexcept{return text.data()+4;}
 bool set(std::string_view value)noexcept{return valid_local_absolute_path(value)&&convert(value);}
 bool set_pattern(std::string_view value,std::string_view tail)noexcept{
  if((tail!="\\*"&&tail!="\\players.sqlite3*")||!value.ends_with(tail)||!valid_local_absolute_path(value.substr(0,value.size()-tail.size())))return false;
  return convert(value);
 }
 private:
 bool convert(std::string_view value)noexcept{
  if(value.empty()||value.size()>4096||!valid_utf8(value))return false;
  size=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,value.data(),static_cast<int>(value.size()),canonical(),4096);if(size<=0)return false;
  canonical()[size]=0;for(int i=0;i<size;++i)if(canonical()[i]==L'/')canonical()[i]=L'\\';
  text[0]=L'\\';text[1]=L'\\';text[2]=L'?';text[3]=L'\\';return true;
 }
};
bool utf8(const wchar_t* p,std::size_t n,FixedText<4096>& out)noexcept {if(n>4096)return false;int z=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,p,static_cast<int>(n),out.data.data(),4096,nullptr,nullptr);if(z<=0)return false;out.size=static_cast<std::uint32_t>(z);out.data[z]=0;return true;}
bool joined(std::string_view parent,std::string_view leaf,FixedText<4096>& out)noexcept {if(parent.empty()||leaf.empty()||parent.size()+leaf.size()+1>4096)return false;out.assign(parent);out.data[out.size++]='\\';for(char c:leaf)out.data[out.size++]=c;out.data[out.size]=0;return true;}
HANDLE open_file(std::string_view path,DWORD access,DWORD share,DWORD creation,DWORD extra=0) {Scratch<Wide> w_storage;auto& w=w_storage.get();if(!w.set(path))return INVALID_HANDLE_VALUE;return CreateFileW(w.text.data(),access,share,nullptr,creation,FILE_FLAG_OPEN_REPARSE_POINT|extra,nullptr);}
bool file_identity(HANDLE h,FileIdentity& out,bool directory=false)noexcept {FILE_ID_INFO id{};FILE_STANDARD_INFO standard{};FILE_ATTRIBUTE_TAG_INFO attrs{};if(!GetFileInformationByHandleEx(h,FileIdInfo,&id,sizeof(id))||!GetFileInformationByHandleEx(h,FileStandardInfo,&standard,sizeof(standard))||!GetFileInformationByHandleEx(h,FileAttributeTagInfo,&attrs,sizeof(attrs)))return false;if((attrs.FileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)!=0||standard.Directory!=static_cast<BOOLEAN>(directory)||(!directory&&standard.NumberOfLinks!=1))return false;out.volume_serial=id.VolumeSerialNumber;std::memcpy(out.file_id.data(),id.FileId.Identifier,16);out.links=standard.NumberOfLinks;out.valid=true;return true;}
bool same_identity(const FileIdentity& a,const FileIdentity& b)noexcept{return a.valid&&b.valid&&a.volume_serial==b.volume_serial&&a.file_id==b.file_id&&a.links==b.links;}
bool file_size(HANDLE h,std::uint64_t& bytes)noexcept {LARGE_INTEGER n;if(!GetFileSizeEx(h,&n)||n.QuadPart<0)return false;bytes=static_cast<std::uint64_t>(n.QuadPart);return true;}
Error path_guard(std::string_view path,FileIdentity* last=nullptr,bool include_leaf=false) {
 Scratch<Wide> w_storage;auto& w=w_storage.get();if(!valid_local_absolute_path(path)||!w.set(path))return Error::path_rejected;
 Scratch<std::array<wchar_t,4101>> volume_storage;auto& volume=volume_storage.get();std::array<wchar_t,64> filesystem{};if(!GetVolumePathNameW(w.text.data(),volume.data(),4101)||GetDriveTypeW(volume.data())!=DRIVE_FIXED||!GetVolumeInformationW(volume.data(),nullptr,0,nullptr,nullptr,nullptr,filesystem.data(),64)||CompareStringOrdinal(filesystem.data(),-1,L"NTFS",-1,TRUE)!=CSTR_EQUAL)return Error::path_rejected;
 for(int i=3;i<=w.size;++i)if((i<w.size&&w.canonical()[i]==L'\\')||(include_leaf&&i==w.size)){wchar_t saved=w.canonical()[i];w.canonical()[i]=0;Handle h(CreateFileW(w.text.data(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,nullptr,OPEN_EXISTING,FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));FileIdentity identity;
  if(!h||!file_identity(h.value,identity,true)){w.canonical()[i]=saved;return Error::path_rejected;}
  // Reject aliases (including short DOS names) by the actual opened directory,
  // not only a lexical prefix. Reparse points were rejected above. This remains
  // an observed guard, not adversarial atomic parent-path security.
  Scratch<std::array<wchar_t,4101>> resolved_storage;auto& resolved=resolved_storage.get();DWORD n=GetFinalPathNameByHandleW(h.value,resolved.data(),4101,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
  bool canonical=n>4&&n<4101&&resolved[0]==L'\\'&&resolved[1]==L'\\'&&resolved[2]==L'?'&&resolved[3]==L'\\'&&CompareStringOrdinal(resolved.data()+4,static_cast<int>(n-4),w.canonical(),i,TRUE)==CSTR_EQUAL;
  w.canonical()[i]=saved;if(!canonical)return Error::path_rejected;if(last)*last=identity;}
 return Error::none;
}
// Read-only observation on the supplied creation or borrowed SQLite MAIN
// handle. No second main handle is opened; temporary directory guards retain
// their existing checked-close/failed-handle ownership policy.
bool reserved_main_matches(HANDLE handle,const FileIdentity& expected,
                           std::string_view root,const FileIdentity& root_identity,
                           const FileIdentity& parent_identity) {
 FileIdentity actual;std::uint64_t bytes{};
 if(GetFileType(handle)!=FILE_TYPE_DISK||!file_identity(handle,actual)||!same_identity(actual,expected)||!file_size(handle,bytes)||bytes!=0)return false;
 Scratch<FixedText<4096>> path_storage;auto& path=path_storage.get();if(!joined(root,store_file_names[0],path))return false;
 Scratch<Wide> wanted_storage;auto& wanted=wanted_storage.get();if(!wanted.set(path.view()))return false;
 Scratch<std::array<wchar_t,4101>> resolved_storage;auto& resolved=resolved_storage.get();
 DWORD n=GetFinalPathNameByHandleW(handle,resolved.data(),4101,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
 if(n<=4||n>=4101||resolved[0]!=L'\\'||resolved[1]!=L'\\'||resolved[2]!=L'?'||resolved[3]!=L'\\'||CompareStringOrdinal(resolved.data()+4,static_cast<int>(n-4),wanted.canonical(),wanted.size,TRUE)!=CSTR_EQUAL)return false;
 FileIdentity current_root,current_parent;
 return path_guard(root,&current_root,true)==Error::none&&same_identity(current_root,root_identity)&&path_guard(root,&current_parent)==Error::none&&same_identity(current_parent,parent_identity);
}
bool make_directory(std::string_view path) {Scratch<Wide> w_storage;auto& w=w_storage.get();if(!w.set(path)||path_guard(path)!=Error::none)return false;if(!CreateDirectoryW(w.text.data(),nullptr)&&GetLastError()!=ERROR_ALREADY_EXISTS)return false;FileIdentity id;return path_guard(path,&id,true)==Error::none;}
bool exists(std::string_view path,bool& present) {Scratch<Wide> w_storage;auto& w=w_storage.get();if(!w.set(path))return false;auto attrs=GetFileAttributesW(w.text.data());if(attrs==INVALID_FILE_ATTRIBUTES){auto e=GetLastError();present=false;return e==ERROR_FILE_NOT_FOUND||e==ERROR_PATH_NOT_FOUND;}present=true;return (attrs&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY))==0;}
bool seek_start(HANDLE h)noexcept {LARGE_INTEGER zero{};return SetFilePointerEx(h,zero,nullptr,FILE_BEGIN)!=0;}
void encode_identity(Writer& w,const FileIdentity& id)noexcept {char volume[16],file[32];for(unsigned i=0;i<16;++i)volume[15-i]=hex[(id.volume_serial>>(4*i))&15];for(unsigned i=0;i<16;++i){auto b=std::to_integer<unsigned>(id.file_id[i]);file[i*2]=hex[b>>4];file[i*2+1]=hex[b&15];}w.raw("{\"file_id_hex\":");w.string({file,32});w.raw(",\"volume_serial_hex\":");w.string({volume,16});w.character('}');}
bool decode_identity(DocumentView d,std::uint32_t node,FileIdentity& id)noexcept {if(closed(d,node,{"volume_serial_hex","file_id_hex"})!=Error::none)return false;FixedText<32> volume,file;if(!volume.from(d,d.member(node,"volume_serial_hex"))||!file.from(d,d.member(node,"file_id_hex"))||!lower_hex(volume.view(),16)||!lower_hex(file.view(),32))return false;auto nibble=[](char c){return c<='9'?c-'0':c-'a'+10;};id={};for(char c:volume.view())id.volume_serial=id.volume_serial*16+static_cast<unsigned>(nibble(c));for(unsigned i=0;i<16;++i)id.file_id[i]=static_cast<std::byte>(nibble(file.data[i*2])*16+nibble(file.data[i*2+1]));id.links=1;id.valid=true;return true;}
NativeObservation io_observation(Phase phase,Scope scope,Edge edge,std::uint64_t occurrence,FileRole role,IoKind kind,std::uint32_t chunk,std::uint32_t requested)noexcept {NativeObservation o;o.phase=phase;o.scope=scope;o.edge=edge;o.occurrence=occurrence;o.role=role;o.io_kind=kind;o.chunk_index=chunk;o.has_requested=true;o.requested=requested;return o;}
bool read_actual(HANDLE h,std::span<std::byte> bytes,DWORD& count,NativeContext* c,FileRole role,std::uint32_t chunk,Phase phase=Phase::recovery_copy,Scope scope=Scope::recovery) {
 if(!c){auto* active=NativeOperationScope::current();if(!active)throw std::bad_alloc{};c=&active->context();}
 auto n=c->next(phase,scope);auto o=io_observation(phase,scope,Edge::before,n,role,IoKind::read,chunk,static_cast<std::uint32_t>(bytes.size()));o.owned_handle=h!=INVALID_HANDLE_VALUE&&h!=nullptr;if(o.owned_handle)file_identity(h,o.identity);if(c)c->event(o);BOOL ok=ReadFile(h,bytes.data(),static_cast<DWORD>(bytes.size()),&count,nullptr);auto error=ok?ERROR_SUCCESS:GetLastError();o.edge=Edge::after;o.has_completed=true;o.completed=count;o.has_win32_error=true;o.win32_error=error;if(c)c->event(o);return ok!=0;
}
bool write_actual(HANDLE h,std::span<const std::byte> bytes,DWORD& count,NativeContext* c,FileRole role,std::uint32_t chunk,Phase phase=Phase::recovery_copy,Scope scope=Scope::recovery) {
 if(!c){auto* active=NativeOperationScope::current();if(!active)throw std::bad_alloc{};c=&active->context();}
 auto n=c->next(phase,scope);auto o=io_observation(phase,scope,Edge::before,n,role,IoKind::write,chunk,static_cast<std::uint32_t>(bytes.size()));o.owned_handle=h!=INVALID_HANDLE_VALUE&&h!=nullptr;if(o.owned_handle)file_identity(h,o.identity);if(c)c->event(o);BOOL ok=WriteFile(h,bytes.data(),static_cast<DWORD>(bytes.size()),&count,nullptr);auto error=ok?ERROR_SUCCESS:GetLastError();o.edge=Edge::after;o.has_completed=true;o.completed=count;o.has_win32_error=true;o.win32_error=error;if(c)c->event(o);return ok!=0;
}
bool write_all(HANDLE h,std::string_view bytes,NativeContext* c=nullptr,FileRole role=FileRole::temp,Phase phase=Phase::recovery_copy,Scope scope=Scope::recovery) {std::size_t offset=0;std::uint32_t chunk=0;while(offset<bytes.size()){auto n=std::min<std::size_t>(65536,bytes.size()-offset);DWORD done{};if(!write_actual(h,std::as_bytes(std::span(bytes.data()+offset,n)),done,c,role,++chunk,phase,scope)||!done||done>n)return false;offset+=done;}return true;}
bool digest(HANDLE h,std::span<std::byte> io,std::uint64_t bytes,std::array<char,64>& output,FileRole role=FileRole::temp,Phase phase=Phase::recovery_copy,Scope scope=Scope::recovery) {
 if(io.empty()||!seek_start(h))return false;Sha256 hash;std::uint32_t chunk=0;std::uint64_t done=0;while(done<bytes){DWORD n{};auto need=static_cast<DWORD>(std::min<std::uint64_t>(io.size(),bytes-done));if(!read_actual(h,io.first(need),n,nullptr,role,++chunk,phase,scope)||!n||n>need)return false;hash.update(io.first(n));done+=n;}DWORD extra{};std::byte byte;if(!read_actual(h,{&byte,1},extra,nullptr,role,++chunk,phase,scope)||extra!=0)return false;auto d=hash.finish();for(unsigned i=0;i<32;++i){auto b=std::to_integer<unsigned>(d[i]);output[i*2]=hex[b>>4];output[i*2+1]=hex[b&15];}return true;
}
struct WorkspaceLease {std::atomic_flag* flag;explicit WorkspaceLease(CodecWorkspace m):flag(m.lease){while(flag&&flag->test_and_set(std::memory_order_acquire))std::this_thread::yield();}~WorkspaceLease(){if(flag)flag->clear(std::memory_order_release);}};
struct Metadata {FixedText<32> id;FixedText<20> utc;FileSet source,copy,observed_copy;std::array<std::array<char,64>,4> hashes{};std::array<char,64> intent_hash{},manifest_hash{};bool manifest{},manifest_present{},manifest_valid{},intent_valid{};std::uint64_t total{};FileIdentity directory_identity{},intent_identity{},manifest_identity{};};
static_assert(sizeof(Wide)<=8208&&sizeof(Metadata)<=2048&&sizeof(FileSet)<=512);
static_assert(sizeof(FixedText<4096>)<=4112&&sizeof(WIN32_FIND_DATAW)<=640);
static_assert(sizeof(std::array<RecoverySummary,2>)<=512);
// Strip only RFC8259 inter-token whitespace while reading bounded metadata.
// Raw-byte SHA remains over the original entire file. Closed fields then prove
// the compact form fits this charged platform buffer, including long escapes.
bool read_metadata(std::string_view path,std::uint64_t cap,std::span<char> output,std::span<std::byte> io,std::size_t& used,std::array<char,64>& hash,FileIdentity& identity) {
 Handle h(open_file(path,GENERIC_READ,FILE_SHARE_READ,OPEN_EXISTING,FILE_FLAG_SEQUENTIAL_SCAN));std::uint64_t size{};if(!h||!file_identity(h.value,identity)||!file_size(h.value,size)||size==0||size>cap)return false;Sha256 sha;used=0;std::uint64_t consumed=0;std::uint32_t chunk=0;bool string=false,escape=false;while(consumed<size){DWORD n{};auto want=static_cast<DWORD>(std::min<std::uint64_t>(io.size(),size-consumed));if(!read_actual(h.value,io.first(want),n,nullptr,FileRole::temp,++chunk)||!n||n>want)return false;sha.update(io.first(n));for(DWORD i=0;i<n;++i){char ch=static_cast<char>(std::to_integer<unsigned char>(io[i]));bool whitespace=ch==' '||ch=='\r'||ch=='\n'||ch=='\t';if(string||!whitespace){if(used==output.size())return false;output[used++]=ch;}if(string){if(escape)escape=false;else if(ch=='\\')escape=true;else if(ch=='"')string=false;}else if(ch=='"')string=true;}consumed+=n;}if(string||escape)return false;auto bytes=sha.finish();for(unsigned i=0;i<32;++i){auto b=std::to_integer<unsigned>(bytes[i]);hash[i*2]=hex[b>>4];hash[i*2+1]=hex[b&15];}std::uint64_t end{};FileIdentity after;return file_size(h.value,end)&&end==size&&file_identity(h.value,after)&&same_identity(identity,after);
}
bool parse_metadata(std::string_view compact,CodecWorkspace workspace,bool manifest,Metadata& m) {
 WorkspaceLease lease(workspace);auto p=parse_json(compact,workspace.cells,std::as_writable_bytes(workspace.text),Limits{24576,512,12,4096,4096});if(!p)return false;auto d=p.value;auto root=d.root;auto e=manifest?closed(d,root,{"format","version","id","created_utc","intent_sha256","files"}):closed(d,root,{"format","version","id","created_utc","source_files"});if(e!=Error::none||!d.string_is(d.member(root,"format"),manifest?"LocalPlayersRecoveryCopy":"LocalPlayersRecoveryIntent")||d.at(d.member(root,"version"))->kind!=ValueKind::integer||d.at(d.member(root,"version"))->scalar!=1)return false;FixedText<32> id;FixedText<20> utc;if(!id.from(d,d.member(root,"id"))||!lower_hex(id.view(),32)||!utc.from(d,d.member(root,"created_utc"))||!valid_utc(utc.view()))return false;if(manifest&&(id.view()!=m.id.view()||utc.view()!=m.utc.view()||!d.string_is(d.member(root,"intent_sha256"),{m.intent_hash.data(),64})))return false;if(!manifest){m.id=id;m.utc=utc;}
 auto array=d.member(root,manifest?"files":"source_files");if(d.at(array)->kind!=ValueKind::array||d.size(array)!=4)return false;auto row=d.at(array)->first;
 for(unsigned i=0;i<4;++i,row=d.at(row)->next){e=manifest?closed(d,row,{"role","name","present","bytes","sha256","source_identity","copy_identity"}):closed(d,row,{"role","name","present","bytes","source_identity"});if(e!=Error::none||!d.string_is(d.member(row,"role"),roles[i])||!d.string_is(d.member(row,"name"),store_file_names[i]))return false;auto present=d.at(d.member(row,"present"));if(!present||present->kind!=ValueKind::boolean)return false;bool yes=present->scalar!=0;auto& f=manifest?m.copy.files[i]:m.source.files[i];f.present=yes;
  if(!yes){for(auto key:{"bytes","source_identity"})if(d.at(d.member(row,key))->kind!=ValueKind::null)return false;if(manifest)for(auto key:{"sha256","copy_identity"})if(d.at(d.member(row,key))->kind!=ValueKind::null)return false;if(manifest&&m.source.files[i].present)return false;continue;}
  auto bytes=d.at(d.member(row,"bytes"));if(bytes->kind!=ValueKind::integer||std::bit_cast<std::int64_t>(bytes->scalar)<0||bytes->scalar>store_file_caps[i])return false;f.bytes=bytes->scalar;FileIdentity source;if(!decode_identity(d,d.member(row,"source_identity"),source))return false;
  if(manifest){FixedText<64> hash;if(!m.source.files[i].present||f.bytes!=m.source.files[i].bytes||!same_identity(source,m.source.files[i].identity)||!decode_identity(d,d.member(row,"copy_identity"),f.identity)||!hash.from(d,d.member(row,"sha256"))||!lower_hex(hash.view(),64))return false;std::memcpy(m.hashes[i].data(),hash.data.data(),64);}else f.identity=source;
 }
 m.manifest=manifest;return true;
}
} // namespace
StoreAccess WindowsFileSystem::production()noexcept {static_assert(sizeof(WindowsFileSystem)<=49152);StoreAccess access;access.filesystem_=new(access.platform_.data())WindowsFileSystem;return access;}
FileSystem* WindowsFileSystem::relocate(void* to)noexcept {auto* moved=new(to)WindowsFileSystem(std::move(*this));guards_.fill(nullptr);failed_handles_.fill(nullptr);unretained_handle_=false;lock_=nullptr;new_database_=nullptr;this->~WindowsFileSystem();return moved;}
WindowsFileSystem::~WindowsFileSystem(){close_worker_handles();if(lock_){CloseHandle(static_cast<HANDLE>(lock_));lock_=nullptr;}}
Error WindowsFileSystem::resolve_known_folder(FixedText<4096>& out)noexcept {
 PWSTR location{};HRESULT hr=SHGetKnownFolderPath(FOLDERID_LocalAppData,0,nullptr,&location);
 if(FAILED(hr)||!location){if(location)CoTaskMemFree(location);return Error::root_unavailable;}
 std::size_t n=0;while(n<=4096&&location[n])++n;bool ok=n<=4096&&utf8(location,n,out);CoTaskMemFree(location);
 constexpr std::string_view suffix="\\FlightSimulator\\Players";
 if(!ok||suffix.size()>4096-out.size)return Error::root_unavailable;
 for(char c:suffix)out.data[out.size++]=c;out.data[out.size]=0;return Error::none;
}
Error WindowsFileSystem::random_id(FixedText<32>& out)noexcept {std::array<unsigned char,16> bytes;if(BCryptGenRandom(nullptr,bytes.data(),16,BCRYPT_USE_SYSTEM_PREFERRED_RNG)!=0)return Error::io_error;for(unsigned i=0;i<16;++i){out.data[i*2]=hex[bytes[i]>>4];out.data[i*2+1]=hex[bytes[i]&15];}out.size=32;out.data[32]=0;return Error::none;}
std::string_view WindowsFileSystem::owner_run_id()const noexcept {struct Run {FixedText<32> id;Run()noexcept{std::array<unsigned char,16> bytes{};if(BCryptGenRandom(nullptr,bytes.data(),16,BCRYPT_USE_SYSTEM_PREFERRED_RNG)==0){for(unsigned i=0;i<16;++i){id.data[i*2]=hex[bytes[i]>>4];id.data[i*2+1]=hex[bytes[i]&15];}id.size=32;}}};static const Run run;return run.id.view();}
Error WindowsFileSystem::utc(FixedText<20>& out)noexcept {SYSTEMTIME t;GetSystemTime(&t);if(t.wYear<2000||t.wYear>9999)return Error::io_error;auto two=[&](unsigned at,unsigned n){out.data[at]=static_cast<char>('0'+n/10);out.data[at+1]=static_cast<char>('0'+n%10);};out.assign("0000-00-00T00:00:00Z");two(0,t.wYear/100);two(2,t.wYear%100);two(5,t.wMonth);two(8,t.wDay);two(11,t.wHour);two(14,t.wMinute);two(17,t.wSecond);return Error::none;}
Error WindowsFileSystem::acquire_root(bool management,NativeContext&) {
 if(lock_)return Error::invalid_state;
 if(isolated_){
  // The separately linked factory already admitted existing native identities.
  // Preserve them: a new directory at the same string is never equivalent.
  if(!lower_hex(test_nonce_.view(),32)||test_parent_.size==0||!root_identity_.valid||!parent_identity_.valid||!test_sentinel_identity_.valid||!lower_hex({test_sentinel_sha256_.data(),64},64))return Error::root_unavailable;
  Scratch<FixedText<4096>> leaf_storage;auto& leaf=leaf_storage.get();Scratch<FixedText<4096>> expected_root_storage;auto& expected_root=expected_root_storage.get();leaf.assign("local-players-test-");for(char c:test_nonce_.view())leaf.data[leaf.size++]=c;leaf.data[leaf.size]=0;
  if(!joined(test_parent_.view(),leaf.view(),expected_root)||root_.view()!=expected_root.view())return Error::root_unavailable;
  FileIdentity actual_root,actual_parent;if(path_guard(root_.view(),&actual_root,true)!=Error::none||path_guard(test_parent_.view(),&actual_parent,true)!=Error::none||!same_identity(actual_root,root_identity_)||!same_identity(actual_parent,parent_identity_))return Error::root_unavailable;
  Scratch<FixedText<4096>> sentinel_storage;auto& sentinel=sentinel_storage.get();joined(root_.view(),".local-players-test-root.json",sentinel);Handle h(open_file(sentinel.view(),GENERIC_READ,FILE_SHARE_READ,OPEN_EXISTING));FileIdentity actual;std::uint64_t bytes{};
  Writer expected(metadata_);expected.raw("{\"schema\":\"LocalPlayersTestRootSentinel/v1\",\"nonce\":\"");expected.raw(test_nonce_.view());expected.raw("\"}\n");
  DWORD read{};
  if(!h||!file_identity(h.value,actual)||!same_identity(actual,test_sentinel_identity_)||!file_size(h.value,bytes)||bytes!=expected.size()||bytes>1024||!read_actual(h.value,std::span(metadata_io_).first(static_cast<std::size_t>(bytes)),read,nullptr,FileRole::temp,1)||read!=bytes)return Error::root_unavailable;
  std::string_view actual_bytes(reinterpret_cast<const char*>(metadata_io_.data()),read);if(actual_bytes!=expected.bytes()||sha256_hex(actual_bytes)!=test_sentinel_sha256_)return Error::root_unavailable;
 }else{
  auto e=resolve_known_folder(root_);if(e!=Error::none)return e;auto split=root_.view().find_last_of("\\/");if(split==std::string_view::npos)return Error::root_unavailable;auto app=root_.view().substr(0,split);
  if(!make_directory(app)||!make_directory(root_.view())||path_guard(root_.view(),&root_identity_,true)!=Error::none||path_guard(root_.view(),&parent_identity_)!=Error::none)return Error::root_unavailable;
 }
 if(owner_run_id().size()!=32)return Error::root_unavailable;
 Scratch<FixedText<4096>> name_storage;auto& name=name_storage.get();if(!joined(root_.view(),"players.lock",name))return Error::root_unavailable;
 Handle lock(open_file(name.view(),GENERIC_READ|GENERIC_WRITE,0,OPEN_ALWAYS));FileIdentity identity;
 if(!lock)return GetLastError()==ERROR_SHARING_VIOLATION?Error::store_locked:Error::root_unavailable;if(!file_identity(lock.value,identity))return Error::root_unavailable;
 lock_=lock.release();management_origin_=management;return Error::none;
}
Error WindowsFileSystem::inspect_sources(FileSet& out) {
 if(!lock_)return Error::invalid_state;for(unsigned i=0;i<4;++i){if(guards_[i]){if(!CloseHandle(static_cast<HANDLE>(guards_[i])))return Error::io_error;guards_[i]=nullptr;}Scratch<FixedText<4096>> path_storage;auto& path=path_storage.get();if(!joined(root_.view(),store_file_names[i],path))return Error::path_rejected;Handle h(open_file(path.view(),GENERIC_READ,FILE_SHARE_READ,OPEN_EXISTING,FILE_FLAG_SEQUENTIAL_SCAN));if(!h){auto e=GetLastError();if(e==ERROR_FILE_NOT_FOUND){out.files[i]={};continue;}return Error::recovery_required;}auto& f=out.files[i];f.present=true;if(!file_identity(h.value,f.identity)||!file_size(h.value,f.bytes)||f.bytes>store_file_caps[i])return Error::recovery_required;if(i==0){if(f.bytes<100)return Error::foreign_store;auto header=std::span(metadata_io_).first(100);DWORD n{};if(!read_actual(h.value,header,n,nullptr,FileRole::main,1)||n!=100||std::memcmp(header.data(),"SQLite format 3\0",16)!=0||header[16]!=std::byte{0x10}||header[17]!=std::byte{0})return Error::foreign_store;}guards_[i]=h.release();}
 if(!out.files[0].present)for(unsigned i=1;i<4;++i)if(out.files[i].present)return Error::foreign_store;
 // Refuse unowned journal/super-journal variants rather than guessing cleanup.
 Scratch<FixedText<4096>> wildcard_storage;auto& wildcard=wildcard_storage.get();joined(root_.view(),"players.sqlite3*",wildcard);Scratch<Wide> w_storage;auto& w=w_storage.get();if(!w.set_pattern(wildcard.view(),"\\players.sqlite3*"))return Error::path_rejected;Scratch<WIN32_FIND_DATAW> data_storage;auto& data=data_storage.get();Handle find_handle(FindFirstFileW(w.text.data(),&data),true);HANDLE find=find_handle.value;if(find!=INVALID_HANDLE_VALUE){bool bad=false;do{Scratch<FixedText<4096>> name_storage;auto& name=name_storage.get();std::size_t n=0;while(data.cFileName[n])++n;if(!utf8(data.cFileName,n,name)){bad=true;break;}bool known=false;for(auto x:store_file_names)known|=name.view()==x;if(!known||(data.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT)))bad=true;}while(FindNextFileW(find,&data));auto error=GetLastError();if(!find_handle.close())return Error::recovery_required;if(bad||error!=ERROR_NO_MORE_FILES)return Error::recovery_required;}else if(GetLastError()!=ERROR_FILE_NOT_FOUND)return Error::recovery_required;
 return Error::none;
}

namespace {
bool enumerate_known(std::string_view directory,bool& manifest,std::uint64_t& total) {
 Scratch<FixedText<4096>> pattern_storage;auto& pattern=pattern_storage.get();if(!joined(directory,"*",pattern))return false;Scratch<Wide> w_storage;auto& w=w_storage.get();if(!w.set_pattern(pattern.view(),"\\*"))return false;Scratch<WIN32_FIND_DATAW> data_storage;auto& data=data_storage.get();Handle find_handle(FindFirstFileW(w.text.data(),&data),true);HANDLE find=find_handle.value;if(find==INVALID_HANDLE_VALUE)return false;bool good=true;unsigned entries=0;manifest=false;total=0;
 do {std::wstring_view name(data.cFileName);if(name==L"."||name==L"..")continue;Scratch<FixedText<4096>> utf_storage;auto& utf=utf_storage.get();if(++entries>6||!utf8(name.data(),name.size(),utf)||(data.dwFileAttributes&(FILE_ATTRIBUTE_DIRECTORY|FILE_ATTRIBUTE_REPARSE_POINT))){good=false;break;}bool known=utf.view()=="intent.json"||utf.view()=="manifest.json";for(auto n:store_file_names)known|=utf.view()==n;if(!known){good=false;break;}manifest|=utf.view()=="manifest.json";std::uint64_t size=(static_cast<std::uint64_t>(data.nFileSizeHigh)<<32)|data.nFileSizeLow;if(size>UINT64_MAX-total){good=false;break;}total+=size;
 if((utf.view()=="intent.json"&&size>65536)||(utf.view()=="manifest.json"&&size>983040)||total>353370112){good=false;break;}
 }while(FindNextFileW(find,&data));auto error=GetLastError();if(!find_handle.close())return false;return good&&error==ERROR_NO_MORE_FILES;
}
bool audit_set(std::string_view directory,std::string_view id,Metadata& m,std::span<char> metadata,std::span<std::byte> io,CodecWorkspace workspace,bool work=false,bool allow_partial=false) {
 if(path_guard(directory,&m.directory_identity,true)!=Error::none)return false;bool manifest{};if(!enumerate_known(directory,manifest,m.total)||(work&&manifest))return false;m.manifest_present=manifest;Scratch<FixedText<4096>> path_storage;auto& path=path_storage.get();joined(directory,"intent.json",path);std::size_t length{};FileIdentity identity;
 m.intent_valid=read_metadata(path.view(),65536,metadata,io,length,m.intent_hash,m.intent_identity)&&parse_metadata({metadata.data(),length},workspace,false,m)&&m.id.view()==id;
 if(!m.intent_valid){
  if(!allow_partial||work)return false;
  // A failed CreateNew/intent leaves inspectable bounded remnants, never an
  // invented deletion capability or complete recovery copy.
  m.id.assign(id);m.utc={};manifest=false;
 }
 if(manifest){joined(directory,"manifest.json",path);if(!read_metadata(path.view(),983040,metadata,io,length,m.manifest_hash,m.manifest_identity)||!parse_metadata({metadata.data(),length},workspace,true,m)){
  if(!allow_partial||work)return false;manifest=false;
 }}
 // A valid manifest remains the immutable WORK ownership link even after a
 // management deletion removed a declared copy. Only observed files are deleted.
 m.manifest_valid=manifest;bool complete=manifest;
 for(unsigned i=0;i<4;++i){joined(directory,store_file_names[i],path);Handle h(open_file(path.view(),GENERIC_READ,FILE_SHARE_READ,OPEN_EXISTING,FILE_FLAG_SEQUENTIAL_SCAN));if(!h){if(GetLastError()!=ERROR_FILE_NOT_FOUND)return false;if(manifest&&m.copy.files[i].present){if(!allow_partial)return false;complete=false;}continue;}
  FileIdentity actual;std::uint64_t bytes{};if(!file_identity(h.value,actual)||!file_size(h.value,bytes)||bytes>store_file_caps[i])return false;if(m.intent_valid&&!work&&!m.source.files[i].present)return false;if(manifest){std::array<char,64> hash;if(!m.copy.files[i].present||bytes!=m.copy.files[i].bytes||!same_identity(actual,m.copy.files[i].identity)||!digest(h.value,io,bytes,hash,static_cast<FileRole>(i+2))||hash!=m.hashes[i])return false;}
  // Keep actual ordinary identities even for partial/work sets; source intent
  // never proves that a different pathname occupant may be removed.
  m.copy.files[i]={true,bytes,actual};m.observed_copy.files[i]={true,bytes,actual};
 }
 m.manifest=complete;return true;
}
bool remove_exact(std::string_view path,const FileIdentity& expected,bool& any_action,bool directory=false) {
 Handle h(open_file(path,DELETE|FILE_READ_ATTRIBUTES,FILE_SHARE_READ,OPEN_EXISTING,directory?FILE_FLAG_BACKUP_SEMANTICS:0));FileIdentity actual;
 if(!h||!file_identity(h.value,actual,directory)||!same_identity(actual,expected))return false;
 FILE_DISPOSITION_INFO disposition{};disposition.DeleteFile=TRUE;
 // Delete the exact identity held by this handle. No check-then-DeleteFile path
 // substitution, recursive traversal or unknown filename is accepted.
 any_action=true;if(!SetFileInformationByHandle(h.value,FileDispositionInfo,&disposition,sizeof(disposition)))return false;
 return h.close();
}
bool remove_audited_set(std::string_view directory,const Metadata& expected,bool& any_action) {
 FileIdentity current;if(path_guard(directory,&current,true)!=Error::none||!same_identity(current,expected.directory_identity))return false;
 for(unsigned i=0;i<4;++i)if(expected.observed_copy.files[i].present){Scratch<FixedText<4096>> path_storage;auto& path=path_storage.get();if(!joined(directory,store_file_names[i],path))return false;if(!remove_exact(path.view(),expected.observed_copy.files[i].identity,any_action))return false;}
 Scratch<FixedText<4096>> path_storage;auto& path=path_storage.get();if(expected.manifest_present){if(!joined(directory,"manifest.json",path))return false;if(!remove_exact(path.view(),expected.manifest_identity,any_action))return false;}
 if(!joined(directory,"intent.json",path))return false;if(!remove_exact(path.view(),expected.intent_identity,any_action))return false;
 if(!remove_exact(directory,expected.directory_identity,any_action,true))return false;
 Scratch<Wide> absent_storage;auto& absent=absent_storage.get();if(!absent.set(directory))return false;return GetFileAttributesW(absent.text.data())==INVALID_FILE_ATTRIBUTES&&GetLastError()==ERROR_FILE_NOT_FOUND;
}
bool write_new_verified(std::string_view path,std::string_view bytes,std::span<std::byte> io,FileIdentity* identity=nullptr) {
 Handle h(open_file(path,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ,CREATE_NEW));FileIdentity actual;std::array<char,64> hash;if(!h||!file_identity(h.value,actual)||!write_all(h.value,bytes)||!FlushFileBuffers(h.value)||!digest(h.value,io,bytes.size(),hash)||hash!=sha256_hex(bytes))return false;if(identity)*identity=actual;return true;
}
bool write_intent(Writer& w,const RecoverySet& set,const FileSet& source) noexcept {
 w.raw("{\"created_utc\":");w.string(set.created_utc.view());w.raw(",\"format\":\"LocalPlayersRecoveryIntent\",\"id\":");w.string(set.id.view());w.raw(",\"source_files\":[");for(unsigned i=0;i<4;++i){if(i)w.character(',');auto f=source.files[i];w.raw("{\"bytes\":");if(f.present)w.integer(static_cast<std::int64_t>(f.bytes));else w.raw("null");w.raw(",\"name\":");w.string(store_file_names[i]);w.raw(",\"present\":");w.raw(f.present?"true":"false");w.raw(",\"role\":");w.string(roles[i]);w.raw(",\"source_identity\":");if(f.present)encode_identity(w,f.identity);else w.raw("null");w.character('}');}return w.raw("],\"version\":1}")&&w.good();
}
bool copy_file(HANDLE source,std::string_view destination,const FileInfo& original,FileInfo& copied,std::array<char,64>& source_hash,std::span<std::byte> io,NativeContext& context,FileRole role) {
 Handle target(open_file(destination,GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ,CREATE_NEW));if(!target||!file_identity(target.value,copied.identity)||!seek_start(source))return false;Sha256 sha;std::uint64_t done=0;std::uint32_t chunk=0;
 while(done<original.bytes){auto need=static_cast<std::size_t>(std::min<std::uint64_t>(io.size(),original.bytes-done));DWORD read{};if(!read_actual(source,io.first(need),read,&context,role,++chunk)||!read||read>need)return false;sha.update(io.first(read));std::size_t written=0;while(written<read){DWORD part{};if(!write_actual(target.value,io.subspan(written,read-written),part,&context,role,chunk)||!part||part>read-written)return false;written+=part;}done+=read;}
 auto hash=sha.finish();for(unsigned i=0;i<32;++i){auto b=std::to_integer<unsigned>(hash[i]);source_hash[i*2]=hex[b>>4];source_hash[i*2+1]=hex[b&15];}
 if(!FlushFileBuffers(target.value))return false;copied.present=true;copied.bytes=done;std::array<char,64> target_hash,after_source;std::uint64_t end{};FileIdentity actual;
 return file_size(target.value,end)&&end==done&&digest(target.value,io,done,target_hash,role)&&target_hash==source_hash&&file_size(source,end)&&end==original.bytes&&file_identity(source,actual)&&same_identity(actual,original.identity)&&digest(source,io,original.bytes,after_source,role)&&after_source==source_hash;
}
bool create_directory_new(std::string_view name) {Scratch<Wide> w_storage;auto& w=w_storage.get();return w.set(name)&&path_guard(name)==Error::none&&CreateDirectoryW(w.text.data(),nullptr)!=0;}
}
Error WindowsFileSystem::snapshot(const FileSet& files,RecoverySet& set,std::span<std::byte> io,CodecWorkspace workspace,NativeContext& c) {
 worker_codec_=workspace;if(!lock_||io.empty())return Error::invalid_state;Scratch<FixedText<4096>> recovery_storage;auto& recovery=recovery_storage.get();if(!joined(root_.view(),"recovery",recovery)||!make_directory(recovery.view()))return Error::snapshot_failed;
 Scratch<std::array<RecoverySummary,2>> existing_storage;auto& existing=existing_storage.get();std::size_t count{};auto e=list_recovery(existing,count,workspace);if(e!=Error::none)return e;if(count>=2)return Error::recovery_limit;
 Scratch<Wide> root_storage;auto& root=root_storage.get();if(!root.set(root_.view()))return Error::path_rejected;ULARGE_INTEGER free{};if(!GetDiskFreeSpaceExW(root.text.data(),&free,nullptr,nullptr)||free.QuadPart<705691648)return Error::storage_full;
 if(random_id(set.id)!=Error::none||utc(set.created_utc)!=Error::none)return Error::snapshot_failed;Scratch<FixedText<4096>> leaf_storage;auto& leaf=leaf_storage.get();leaf.assign("recovery-");for(char ch:set.id.view())leaf.data[leaf.size++]=ch;leaf.data[leaf.size]=0;if(!joined(recovery.view(),leaf.view(),set.retained_root)||!create_directory_new(set.retained_root.view()))return Error::snapshot_failed;
 set.source=files;Writer intent(metadata_);if(!write_intent(intent,set,files))return Error::snapshot_failed;auto intent_hash=sha256_hex(intent.bytes());Scratch<FixedText<4096>> path_storage;auto& path=path_storage.get();joined(set.retained_root.view(),"intent.json",path);if(!write_new_verified(path.view(),intent.bytes(),io))return Error::snapshot_failed;
 Scratch<FileSet> copies_storage;auto& copies=copies_storage.get();for(unsigned i=0;i<4;++i)if(files.files[i].present){if(!guards_[i])return Error::snapshot_failed;joined(set.retained_root.view(),store_file_names[i],path);if(!copy_file(static_cast<HANDLE>(guards_[i]),path.view(),files.files[i],copies.files[i],set.hashes[i],io,c,static_cast<FileRole>(i+2)))return Error::snapshot_failed;}
 // Roster/identity checks on held source handles and current names precede the
 // immutable complete manifest. No prefix hash is promoted to a complete copy.
 for(unsigned i=0;i<4;++i){joined(root_.view(),store_file_names[i],path);bool present{};if(!exists(path.view(),present)||present!=files.files[i].present)return Error::snapshot_failed;if(present){Handle h(open_file(path.view(),GENERIC_READ,FILE_SHARE_READ,OPEN_EXISTING));FileIdentity id;std::uint64_t bytes{};if(!h||!file_identity(h.value,id)||!same_identity(id,files.files[i].identity)||!file_size(h.value,bytes)||bytes!=files.files[i].bytes)return Error::snapshot_failed;}}
 Writer manifest(metadata_);manifest.raw("{\"created_utc\":");manifest.string(set.created_utc.view());manifest.raw(",\"files\":[");for(unsigned i=0;i<4;++i){if(i)manifest.character(',');auto f=files.files[i];manifest.raw("{\"bytes\":");if(f.present)manifest.integer(static_cast<std::int64_t>(f.bytes));else manifest.raw("null");manifest.raw(",\"copy_identity\":");if(f.present)encode_identity(manifest,copies.files[i].identity);else manifest.raw("null");manifest.raw(",\"name\":");manifest.string(store_file_names[i]);manifest.raw(",\"present\":");manifest.raw(f.present?"true":"false");manifest.raw(",\"role\":");manifest.string(roles[i]);manifest.raw(",\"sha256\":");if(f.present)manifest.string({set.hashes[i].data(),64});else manifest.raw("null");manifest.raw(",\"source_identity\":");if(f.present)encode_identity(manifest,f.identity);else manifest.raw("null");manifest.character('}');}manifest.raw("],\"format\":\"LocalPlayersRecoveryCopy\",\"id\":");manifest.string(set.id.view());manifest.raw(",\"intent_sha256\":");manifest.string({intent_hash.data(),64});manifest.raw(",\"version\":1}");if(!manifest.good())return Error::snapshot_failed;joined(set.retained_root.view(),"manifest.json",path);if(!write_new_verified(path.view(),manifest.bytes(),io))return Error::snapshot_failed;
 Scratch<Metadata> audit_storage;auto& audit=audit_storage.get();if(!audit_set(set.retained_root.view(),set.id.view(),audit,metadata_,metadata_io_,workspace)||!audit.manifest)return Error::snapshot_failed;
 // Retained original guards protect only the copying interval. Release them
 // before any SQLite original RW open; the lifetime owner lock stays retained.
 for(auto& h:guards_)if(h){if(!CloseHandle(static_cast<HANDLE>(h)))return Error::io_error;h=nullptr;}
 leaf.assign("work-");for(char ch:set.id.view())leaf.data[leaf.size++]=ch;leaf.data[leaf.size]=0;if(!joined(recovery.view(),leaf.view(),set.work_root)||!create_directory_new(set.work_root.view()))return Error::snapshot_failed;
 Writer work_intent(metadata_);if(!write_intent(work_intent,set,copies))return Error::snapshot_failed;work_intent_hash_=sha256_hex(work_intent.bytes());joined(set.work_root.view(),"intent.json",path);if(!write_new_verified(path.view(),work_intent.bytes(),io,&work_intent_identity_)||path_guard(set.work_root.view(),&work_directory_identity_,true)!=Error::none)return Error::snapshot_failed;
 for(unsigned i=0;i<4;++i)if(copies.files[i].present){Scratch<FixedText<4096>> original_storage;auto& original=original_storage.get();joined(set.retained_root.view(),store_file_names[i],original);Handle h(open_file(original.view(),GENERIC_READ,FILE_SHARE_READ,OPEN_EXISTING,FILE_FLAG_SEQUENTIAL_SCAN));FileIdentity actual;if(!h||!file_identity(h.value,actual)||!same_identity(actual,copies.files[i].identity))return Error::snapshot_failed;joined(set.work_root.view(),store_file_names[i],path);FileInfo copy;std::array<char,64> hash;if(!copy_file(h.value,path.view(),copies.files[i],copy,hash,io,c,static_cast<FileRole>(i+2))||hash!=set.hashes[i])return Error::snapshot_failed;}
 set.complete=true;return Error::none;
}
Error WindowsFileSystem::recheck_original(const RecoverySet& set,std::span<std::byte> io) {
 if(!set.complete)return Error::snapshot_failed;FileIdentity root,parent;if(path_guard(root_.view(),&root,true)!=Error::none||!same_identity(root,root_identity_)||path_guard(root_.view(),&parent)!=Error::none||!same_identity(parent,parent_identity_))return Error::recovery_required;
 for(unsigned i=0;i<4;++i){Scratch<FixedText<4096>> path_storage;auto& path=path_storage.get();joined(root_.view(),store_file_names[i],path);Handle h(open_file(path.view(),GENERIC_READ,FILE_SHARE_READ,OPEN_EXISTING,FILE_FLAG_SEQUENTIAL_SCAN));if(!h){if(!set.source.files[i].present&&GetLastError()==ERROR_FILE_NOT_FOUND)continue;return Error::recovery_required;}FileIdentity actual;std::uint64_t bytes{};std::array<char,64> hash;if(!set.source.files[i].present||!file_identity(h.value,actual)||!same_identity(actual,set.source.files[i].identity)||!file_size(h.value,bytes)||bytes!=set.source.files[i].bytes||!digest(h.value,io,bytes,hash,static_cast<FileRole>(i+2))||hash!=set.hashes[i])return Error::recovery_required;}
 return Error::none;
}
Error WindowsFileSystem::remove_work(RecoverySet& set) {
 if(!set.complete||set.work_root.size==0||worker_codec_.cells.empty())return Error::snapshot_failed;
 Scratch<FixedText<4096>> recovery_storage;auto& recovery=recovery_storage.get();Scratch<FixedText<4096>> leaf_storage;auto& leaf=leaf_storage.get();Scratch<FixedText<4096>> expected_root_storage;auto& expected_root=expected_root_storage.get();if(!joined(root_.view(),"recovery",recovery)||!leaf.assign("work-"))return Error::snapshot_failed;
 for(char c:set.id.view())leaf.data[leaf.size++]=c;leaf.data[leaf.size]=0;
 if(!joined(recovery.view(),leaf.view(),expected_root)||expected_root.view()!=set.work_root.view())return Error::snapshot_failed;
 Scratch<Metadata> audit_storage;auto& audit=audit_storage.get();if(!audit_set(set.work_root.view(),set.id.view(),audit,metadata_,metadata_io_,worker_codec_,true)||audit.manifest||!same_identity(audit.directory_identity,work_directory_identity_)||!same_identity(audit.intent_identity,work_intent_identity_)||audit.intent_hash!=work_intent_hash_)return Error::snapshot_failed;
 bool any=false;if(!remove_audited_set(set.work_root.view(),audit,any))return Error::snapshot_failed;
 set.work_root.size=0;work_directory_identity_={};work_intent_identity_={};return Error::none;
}
Error WindowsFileSystem::reserve_new_database(FileIdentity& out) {
 out={};if(!lock_||new_database_)return Error::invalid_state;for(auto name:store_file_names){Scratch<FixedText<4096>> path_storage;auto& path=path_storage.get();joined(root_.view(),name,path);bool present{};if(!exists(path.view(),present)||present)return Error::foreign_store;}
 Scratch<FixedText<4096>> path_storage;auto& path=path_storage.get();if(!joined(root_.view(),store_file_names[0],path))return Error::io_error;
 Handle h(open_file(path.view(),GENERIC_READ|GENERIC_WRITE,0,CREATE_NEW));if(!h)return Error::io_error;
 // Keep ownership even when the actual metadata observation refuses admission.
 new_database_=h.release();FileIdentity observed;
 if(!file_identity(static_cast<HANDLE>(new_database_),observed)||!reserved_main_matches(static_cast<HANDLE>(new_database_),observed,root_.view(),root_identity_,parent_identity_))return Error::io_error;
 out=observed;return Error::none;
}
Error WindowsFileSystem::release_reserved_database_for_sqlite(const FileIdentity& expected) {
 if(!lock_||!new_database_||!expected.valid||expected.links!=1)return Error::io_error;
 if(!reserved_main_matches(static_cast<HANDLE>(new_database_),expected,root_.view(),root_identity_,parent_identity_))return Error::recovery_required;
 if(!CloseHandle(static_cast<HANDLE>(new_database_)))return Error::io_error;
 new_database_=nullptr;return Error::none;
}
Error WindowsFileSystem::verify_reserved_database(const FileIdentity& expected,void* borrowed_sqlite_main_handle) {
 if(!lock_||new_database_||!expected.valid||expected.links!=1||!borrowed_sqlite_main_handle||borrowed_sqlite_main_handle==INVALID_HANDLE_VALUE)return Error::io_error;
 return reserved_main_matches(static_cast<HANDLE>(borrowed_sqlite_main_handle),expected,root_.view(),root_identity_,parent_identity_)?Error::none:Error::recovery_required;
}
Error WindowsFileSystem::sqlite_uri(std::string_view physical,FixedText<12288>& output) {
 if(!valid_local_absolute_path(physical)||path_guard(physical,nullptr,true)!=Error::none)return Error::path_rejected;output.assign("file:");for(unsigned char c:physical){if(c=='\\')c='/';if((c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='/'||c==':'||c=='-'||c=='_'||c=='.'){if(output.size==12288)return Error::payload_limit;output.data[output.size++]=static_cast<char>(c);}else{if(output.size>12285)return Error::payload_limit;output.data[output.size++]='%';output.data[output.size++]=hex[c>>4];output.data[output.size++]=hex[c&15];}}
 constexpr std::string_view suffix="/players.sqlite3?exclusive=1";if(output.size+suffix.size()>12288)return Error::payload_limit;for(char c:suffix)output.data[output.size++]=c;output.data[output.size]=0;return Error::none;
}
Error WindowsFileSystem::list_recovery(std::span<RecoverySummary> output,std::size_t& count,CodecWorkspace workspace) {
 worker_codec_=workspace;count=0;if(!lock_)return Error::root_unavailable;if(output.size()<2)return Error::io_error;
 Scratch<FixedText<4096>> recovery_storage;auto& recovery=recovery_storage.get();joined(root_.view(),"recovery",recovery);Scratch<Wide> root_storage;auto& root=root_storage.get();if(!root.set(recovery.view()))return Error::snapshot_failed;
 DWORD attributes=GetFileAttributesW(root.text.data());if(attributes==INVALID_FILE_ATTRIBUTES)return GetLastError()==ERROR_FILE_NOT_FOUND?Error::none:Error::snapshot_failed;
 if(path_guard(recovery.view(),nullptr,true)!=Error::none)return Error::snapshot_failed;
 Scratch<FixedText<4096>> pattern_storage;auto& pattern=pattern_storage.get();joined(recovery.view(),"*",pattern);Scratch<Wide> w_storage;auto& w=w_storage.get();if(!w.set_pattern(pattern.view(),"\\*"))return Error::snapshot_failed;Scratch<WIN32_FIND_DATAW> data_storage;auto& data=data_storage.get();Handle find_handle(FindFirstFileW(w.text.data(),&data),true);HANDLE find=find_handle.value;if(find==INVALID_HANDLE_VALUE)return Error::snapshot_failed;
 std::array<FixedText<32>,2> retained;FixedText<32> work_id;bool has_work=false;Error error=Error::none;
 do{
  std::wstring_view name(data.cFileName);if(name==L"."||name==L"..")continue;Scratch<FixedText<4096>> utf_storage;auto& utf=utf_storage.get();
  if(!utf8(name.data(),name.size(),utf)||(data.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)||!(data.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)){error=Error::snapshot_failed;break;}
  bool work=utf.view().starts_with("work-");auto prefix=work?5U:9U;
  if((!work&&!utf.view().starts_with("recovery-"))||utf.size!=prefix+32||!lower_hex(utf.view().substr(prefix),32)){error=Error::snapshot_failed;break;}
  if(work){if(has_work){error=Error::recovery_limit;break;}has_work=true;work_id.assign(utf.view().substr(prefix));}
  else{if(count==2){error=Error::recovery_limit;break;}retained[count++].assign(utf.view().substr(prefix));}
 }while(FindNextFileW(find,&data));auto native_error=GetLastError();if(!find_handle.close())return Error::snapshot_failed;
 if(error!=Error::none)return error;if(native_error!=ERROR_NO_MORE_FILES)return Error::snapshot_failed;
 if(count==2&&retained[1].view()<retained[0].view())std::swap(retained[0],retained[1]);
 bool associated=!has_work;
 for(std::size_t i=0;i<count;++i){Scratch<FixedText<4096>> leaf_storage;auto& leaf=leaf_storage.get();Scratch<FixedText<4096>> directory_storage;auto& directory=directory_storage.get();leaf.assign("recovery-");for(char c:retained[i].view())leaf.data[leaf.size++]=c;leaf.data[leaf.size]=0;joined(recovery.view(),leaf.view(),directory);
  Scratch<Metadata> audit_storage;auto& audit=audit_storage.get();if(!audit_set(directory.view(),retained[i].view(),audit,metadata_,metadata_io_,workspace,false,true))return Error::snapshot_failed;
  if(has_work&&work_id.view()==retained[i].view()){
   // Summary counts only this retained directory. The associated work copy is
   // separately owned; its current bytes are not an invented combined DTO cap.
   if(!audit.manifest_valid)return Error::snapshot_failed;
   leaf.assign("work-");for(char c:work_id.view())leaf.data[leaf.size++]=c;leaf.data[leaf.size]=0;joined(recovery.view(),leaf.view(),directory);
   Scratch<Metadata> work_storage;auto& work=work_storage.get();if(!audit_set(directory.view(),work_id.view(),work,metadata_,metadata_io_,workspace,true))return Error::snapshot_failed;
   for(unsigned f=0;f<4;++f)if(work.source.files[f].present!=audit.copy.files[f].present||(work.source.files[f].present&&(work.source.files[f].bytes!=audit.copy.files[f].bytes||!same_identity(work.source.files[f].identity,audit.copy.files[f].identity))))return Error::snapshot_failed;
   associated=true;
  }
  auto& summary=output[i];summary.id=retained[i];summary.complete=audit.manifest;summary.has_utc=audit.intent_valid;summary.created_utc=audit.utc;summary.bytes=audit.total;summary.has_manifest_hash=audit.manifest;summary.manifest_hash=audit.manifest_hash;
 }
 if(!associated)return Error::snapshot_failed;
 // Management must expose a legitimate retained ID for explicit deletion of
 // BOTH sets. Ordinary opening cannot create another disposable work copy.
 return has_work&&!management_origin_?Error::recovery_required:Error::none;
}
Error WindowsFileSystem::delete_recovery(std::span<const FixedText<32>> ids,Writer& terminal,CodecWorkspace workspace,std::span<std::byte>,NativeContext&) {
 if(!lock_||has_worker_handles()||ids.empty()||ids.size()>2)return Error::io_error;
 std::array<bool,2> deleted{};std::array<std::array<bool,2>,2> present{};Scratch<std::array<std::array<Metadata,2>,2>> expected_storage;auto& expected=expected_storage.get();bool any_action=false;
 Scratch<FixedText<4096>> recovery_storage;auto& recovery=recovery_storage.get();joined(root_.view(),"recovery",recovery);
 try {
 // Validate every selected retained/work set before the first delete. Then each
 // actual DELETE is bound to that exact audited file/directory identity.
 for(std::size_t i=0;i<ids.size();++i){bool found=false;
  for(unsigned k=0;k<2;++k){Scratch<FixedText<4096>> leaf_storage;auto& leaf=leaf_storage.get();Scratch<FixedText<4096>> directory_storage;auto& directory=directory_storage.get();leaf.assign(k?"work-":"recovery-");for(char c:ids[i].view())leaf.data[leaf.size++]=c;leaf.data[leaf.size]=0;joined(recovery.view(),leaf.view(),directory);Scratch<Wide> w_storage;auto& w=w_storage.get();w.set(directory.view());auto attrs=GetFileAttributesW(w.text.data());
   if(attrs==INVALID_FILE_ATTRIBUTES){if(GetLastError()==ERROR_FILE_NOT_FOUND)continue;return Error::snapshot_failed;}
   if(!audit_set(directory.view(),ids[i].view(),expected[i][k],metadata_,metadata_io_,workspace,k!=0,true)||!expected[i][k].intent_valid||(expected[i][k].manifest_present&&!expected[i][k].manifest_valid))return Error::snapshot_failed;present[i][k]=true;found=true;
  }if(!found)return Error::snapshot_failed;
  if(present[i][1]){
   if(!present[i][0]||!expected[i][0].manifest_valid)return Error::snapshot_failed;
   for(unsigned f=0;f<4;++f){const auto& retained=expected[i][0].copy.files[f];const auto& source=expected[i][1].source.files[f];if(retained.present!=source.present||(source.present&&(retained.bytes!=source.bytes||!same_identity(retained.identity,source.identity))))return Error::snapshot_failed;}
  }
 }
 // Remove linked WORK first: a denied WORK deletion must not orphan it by
 // destroying the retained manifest which proves its source ownership.
 for(std::size_t i=0;i<ids.size();++i){bool all=true;
  for(unsigned order=0;order<2;++order){unsigned k=1-order;if(present[i][k]){Scratch<FixedText<4096>> leaf_storage;auto& leaf=leaf_storage.get();Scratch<FixedText<4096>> directory_storage;auto& directory=directory_storage.get();leaf.assign(k?"work-":"recovery-");for(char c:ids[i].view())leaf.data[leaf.size++]=c;leaf.data[leaf.size]=0;joined(recovery.view(),leaf.view(),directory);if(!remove_audited_set(directory.view(),expected[i][k],any_action)){all=false;break;}}}
  deleted[i]=all;
 }
 }catch(...){
  // The actual deleted-ID ledger survives an observer/IO exception. A selected
  // ID is deleted only after BOTH audited directories were proven absent.
  if(!any_action){terminal.reset();return Error::snapshot_failed;}
 }
 if(!any_action){terminal.reset();return Error::snapshot_failed;}
 terminal.reset();terminal.raw("{\"deleted_ids\":[");bool first=true;for(std::size_t i=0;i<ids.size();++i)if(deleted[i]){if(!first)terminal.character(',');first=false;terminal.string(ids[i].view());}
 terminal.raw("],\"retained_ids\":[");first=true;bool all=true;for(std::size_t i=0;i<ids.size();++i)if(!deleted[i]){all=false;if(!first)terminal.character(',');first=false;terminal.string(ids[i].view());}terminal.raw("]}");return all?Error::none:Error::snapshot_failed;
}

Error WindowsFileSystem::export_new(std::string_view target,std::string_view payload,ExportReceipt& receipt,std::span<std::byte> io,NativeContext& c) {
 bool move_attempted=false;
 try {
 receipt.target.assign(target);receipt.phase=ExportReceipt::Step::encode;receipt.outcome=ExportReceipt::Outcome::not_saved;receipt.installed=0;
 if(!receipt.has_snapshot||!lower_hex(receipt.operation_id.view(),32)||io.size()<65536)return Error::file_verify_failed;
 // Pre-count the complete outer stream before any target/temp mutation. Inner
 // bytes are canonical validated UTF8; quote/backslash escape to exactly2 bytes.
 constexpr std::string_view prefix="{\"format\":\"LocalPlayerSummary\",\"payload_json\":\"";
 constexpr std::string_view suffix_a="\",\"payload_sha256\":\"",suffix_b="\",\"version\":1}";
 if(!valid_utf8(payload))return Error::file_verify_failed;
 std::uint64_t length=prefix.size()+suffix_a.size()+64+suffix_b.size();for(unsigned char byte:payload){std::uint64_t n=(byte=='"'||byte=='\\')?2:byte<32?6:1;if(length>33554432-n)return Error::storage_full;length+=n;}if(length>33554432)return Error::storage_full;
 if(!valid_local_absolute_path(target)||path_guard(target)!=Error::none)return Error::path_rejected;
 Scratch<Wide> target_w_storage;auto& target_w=target_w_storage.get();Scratch<Wide> root_w_storage;auto& root_w=root_w_storage.get();if(!target_w.set(target)||!root_w.set(root_.view()))return Error::path_rejected;
 if(target_w.size>=root_w.size&&CompareStringOrdinal(target_w.canonical(),root_w.size,root_w.canonical(),root_w.size,TRUE)==CSTR_EQUAL&&(target_w.size==root_w.size||target_w.canonical()[root_w.size]==L'\\'))return Error::path_rejected;
 auto slash=target.find_last_of("\\/");if(slash==std::string_view::npos)return Error::path_rejected;auto parent=target.substr(0,slash);FileIdentity parent_identity;if(path_guard(parent,&parent_identity,true)!=Error::none||same_identity(parent_identity,root_identity_))return Error::path_rejected;
 bool present{};if(!exists(target,present))return Error::path_rejected;if(present)return Error::target_exists;
 FixedText<32> temp_id;if(random_id(temp_id)!=Error::none)return Error::file_create_failed;char leaf[48];Writer leaf_writer(leaf);leaf_writer.raw(".fsplayers-");leaf_writer.raw(temp_id.view());leaf_writer.raw(".tmp");Scratch<FixedText<4096>> temporary_storage;auto& temporary=temporary_storage.get();if(!joined(parent,leaf_writer.bytes(),temporary))return Error::path_rejected;
 receipt.phase=ExportReceipt::Step::create;auto occurrence=c.next(Phase::export_create,Scope::export_file);NativeObservation event;event.phase=Phase::export_create;event.scope=Scope::export_file;event.edge=Edge::before;event.occurrence=occurrence;event.role=FileRole::temp;c.event(event);
 Handle file(open_file(temporary.view(),GENERIC_READ|GENERIC_WRITE,FILE_SHARE_READ,CREATE_NEW,FILE_FLAG_SEQUENTIAL_SCAN));auto create_error=file?ERROR_SUCCESS:GetLastError();
 // Ownership/path exists as soon as actual CreateNew succeeds, independently
 // of later identity qualification or observer delivery.
 if(file)receipt.temporary=temporary;
 FileIdentity identity;bool qualified=file&&file_identity(file.value,identity);event.edge=Edge::after;event.has_win32_error=true;event.win32_error=create_error;event.owned_handle=static_cast<bool>(file);event.identity=identity;c.event(event);if(!qualified)return Error::file_create_failed;
 receipt.phase=ExportReceipt::Step::write;Sha256 intended;std::size_t used=0;std::uint64_t written=0;std::uint32_t chunk=0;
 auto flush_chunk=[&](){std::size_t offset=0;while(offset<used){DWORD done{};if(!write_actual(file.value,io.subspan(offset,used-offset),done,&c,FileRole::temp,++chunk,Phase::export_write,Scope::export_file)||!done||done>used-offset)return false;offset+=done;}intended.update(io.first(used));written+=used;used=0;return true;};
 auto emit=[&](std::string_view bytes){for(unsigned char byte:bytes){if(used==io.size()&&!flush_chunk())return false;io[used++]=static_cast<std::byte>(byte);}return true;};
 if(!emit(prefix))return Error::file_write_failed;for(unsigned char byte:payload){char escape[6];if(byte=='"'||byte=='\\'){escape[0]='\\';escape[1]=static_cast<char>(byte);if(!emit({escape,2}))return Error::file_write_failed;}else if(byte<32){escape[0]='\\';escape[1]='u';escape[2]='0';escape[3]='0';escape[4]=hex[byte>>4];escape[5]=hex[byte&15];if(!emit({escape,6}))return Error::file_write_failed;}else{char ch=static_cast<char>(byte);if(!emit({&ch,1}))return Error::file_write_failed;}}
 auto payload_hash=sha256_hex(payload);if(!emit(suffix_a)||!emit({payload_hash.data(),64})||!emit(suffix_b)||!flush_chunk()||written!=length)return Error::file_write_failed;
 auto intended_bytes=intended.finish();std::array<char,64> expected;for(unsigned i=0;i<32;++i){auto b=std::to_integer<unsigned>(intended_bytes[i]);expected[i*2]=hex[b>>4];expected[i*2+1]=hex[b&15];}
 receipt.phase=ExportReceipt::Step::flush;event={};event.phase=Phase::export_flush;event.scope=Scope::export_file;event.edge=Edge::before;event.occurrence=c.next(event.phase,event.scope);event.role=FileRole::temp;event.owned_handle=true;event.identity=identity;c.event(event);
 // Only the sealed isolated factory installs an observer. Default false/null
 // preserves the actual OS operation and its immediate DWORD below.
 if(c.observer&&c.observer->take_export_flush_refusal_request()){event.edge=Edge::after;c.event(event);return Error::file_flush_failed;}
 BOOL flushed=FlushFileBuffers(file.value);auto flush_error=flushed?ERROR_SUCCESS:GetLastError();event.edge=Edge::after;event.has_win32_error=true;event.win32_error=flush_error;c.event(event);if(!flushed)return Error::file_flush_failed;
 receipt.phase=ExportReceipt::Step::verify_temp;std::array<char,64> observed;std::uint64_t size{};FileIdentity checked;if(!file_size(file.value,size)||size!=length||!file_identity(file.value,checked)||!same_identity(identity,checked)||!digest(file.value,io,length,observed,FileRole::temp,Phase::export_verify_target,Scope::export_file)||observed!=expected)return Error::file_verify_failed;receipt.has_bytes_hash=true;receipt.bytes=length;receipt.sha256=observed;
 // Close the writer before rename, retaining an identity-checked read guard
 // which permits DELETE/rename but still denies another writer.
 if(!file.close())return Error::file_verify_failed;Handle guard(open_file(temporary.view(),GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_DELETE,OPEN_EXISTING));if(!guard||!file_identity(guard.value,checked)||!same_identity(identity,checked))return Error::file_verify_failed;
 FileIdentity parent_now;if(path_guard(parent,&parent_now,true)!=Error::none||!same_identity(parent_identity,parent_now)||!exists(target,present))return Error::path_rejected;if(present)return Error::target_exists;
 Scratch<Wide> temp_w_storage;auto& temp_w=temp_w_storage.get();if(!temp_w.set(temporary.view()))return Error::path_rejected;receipt.phase=ExportReceipt::Step::move;event={};event.phase=Phase::export_move;event.scope=Scope::export_file;event.edge=Edge::before;event.occurrence=c.next(event.phase,event.scope);event.role=FileRole::target;event.identity=identity;event.owned_handle=true;event.installed=0;c.event(event);
 // Flags0 is the actual same-volume no-replace primitive. An existence check
 // alone is never used as collision protection.
 move_attempted=true;BOOL moved=MoveFileExW(temp_w.text.data(),target_w.text.data(),0);auto move_error=moved?ERROR_SUCCESS:GetLastError();
 receipt.installed=moved?1:-1;receipt.outcome=ExportReceipt::Outcome::recovery_required;
 event.edge=Edge::after;event.has_win32_error=true;event.win32_error=move_error;event.installed=receipt.installed;c.event(event);if(!moved)return Error::file_recovery_required;
 receipt.phase=ExportReceipt::Step::verify_target;event={};event.phase=Phase::export_verify_target;event.scope=Scope::export_file;event.edge=Edge::before;event.occurrence=c.next(event.phase,event.scope);event.role=FileRole::target;event.installed=1;c.event(event);
 Handle target_file(open_file(target,GENERIC_READ,FILE_SHARE_READ,OPEN_EXISTING,FILE_FLAG_SEQUENTIAL_SCAN));auto target_open_error=target_file?ERROR_SUCCESS:GetLastError();event.edge=Edge::after;event.owned_handle=static_cast<bool>(target_file);if(target_file)file_identity(target_file.value,event.identity);event.has_win32_error=true;event.win32_error=target_open_error;c.event(event);
 // The opening call and each verification read are separately paired. A temp
 // verification read never claims target installation; only the actual move did.
 bool verified=target_file&&file_identity(target_file.value,checked)&&same_identity(identity,checked)&&file_size(target_file.value,size)&&size==length&&digest(target_file.value,io,length,observed,FileRole::target,Phase::export_verify_target,Scope::export_file)&&observed==expected&&path_guard(parent,&parent_now,true)==Error::none&&same_identity(parent_identity,parent_now);if(!verified){receipt.outcome=ExportReceipt::Outcome::recovery_required;return Error::file_recovery_required;}
 receipt.outcome=ExportReceipt::Outcome::saved;receipt.phase=ExportReceipt::Step::done;receipt.temporary={};return Error::none;
 }catch(...){
  // Never erase an actual owned temporary, completed hash/byte verification or
  // known install observation. A failed callback is not a DB COMMIT failure.
  if(move_attempted){receipt.outcome=ExportReceipt::Outcome::recovery_required;return Error::file_recovery_required;}
  receipt.outcome=ExportReceipt::Outcome::not_saved;return Error::file_verify_failed;
 }
}
Error WindowsFileSystem::wal_pressure(std::uint64_t& bytes) {Scratch<FixedText<4096>> path_storage;auto& path=path_storage.get();joined(root_.view(),store_file_names[1],path);Handle h(open_file(path.view(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE,OPEN_EXISTING));if(!h){if(GetLastError()==ERROR_FILE_NOT_FOUND){bytes=0;return Error::none;}return Error::io_error;}FileIdentity id;return file_identity(h.value,id)&&file_size(h.value,bytes)&&bytes<=67108864?Error::none:Error::storage_full;}
void WindowsFileSystem::retain_failed_handle(void* handle,bool find)noexcept {
 for(std::size_t i=0;i<failed_handles_.size();++i)if(!failed_handles_[i]){failed_handles_[i]=handle;failed_find_[i]=find;return;}
 unretained_handle_=true;
}
bool WindowsFileSystem::close_worker_handles()noexcept {
 bool ok=!unretained_handle_;
 for(auto& h:guards_)if(h){if(CloseHandle(static_cast<HANDLE>(h)))h=nullptr;else ok=false;}
 if(new_database_){if(CloseHandle(static_cast<HANDLE>(new_database_)))new_database_=nullptr;else ok=false;}
 for(std::size_t i=0;i<failed_handles_.size();++i)if(failed_handles_[i]){
  BOOL closed=failed_find_[i]?FindClose(static_cast<HANDLE>(failed_handles_[i])):CloseHandle(static_cast<HANDLE>(failed_handles_[i]));
  if(closed)failed_handles_[i]=nullptr;else ok=false;
 }return ok;
}
bool WindowsFileSystem::has_worker_handles()const noexcept {
 if(new_database_||unretained_handle_)return true;for(auto h:guards_)if(h)return true;for(auto h:failed_handles_)if(h)return true;return false;
}
bool WindowsFileSystem::release_lock_after_join()noexcept {if(has_worker_handles())return false;if(!lock_)return true;if(!CloseHandle(static_cast<HANDLE>(lock_)))return false;lock_=nullptr;return true;}
#else
// Windows adapter is not a Linux storage implementation. Reusable codecs and
// repository tests supply separately linked opaque test access on that platform.
StoreAccess WindowsFileSystem::production() noexcept{return {};}
FileSystem* WindowsFileSystem::relocate(void*)noexcept{return nullptr;}
WindowsFileSystem::~WindowsFileSystem()=default;
Error WindowsFileSystem::resolve_known_folder(FixedText<4096>&)noexcept{return Error::root_unavailable;}
Error WindowsFileSystem::acquire_root(bool,NativeContext&){return Error::root_unavailable;}
Error WindowsFileSystem::random_id(FixedText<32>&)noexcept{return Error::root_unavailable;}
Error WindowsFileSystem::utc(FixedText<20>&)noexcept{return Error::root_unavailable;}
std::string_view WindowsFileSystem::owner_run_id()const noexcept{return {};}
Error WindowsFileSystem::inspect_sources(FileSet&){return Error::root_unavailable;}
Error WindowsFileSystem::snapshot(const FileSet&,RecoverySet&,std::span<std::byte>,CodecWorkspace,NativeContext&){return Error::root_unavailable;}
Error WindowsFileSystem::recheck_original(const RecoverySet&,std::span<std::byte>){return Error::root_unavailable;}
Error WindowsFileSystem::remove_work(RecoverySet&){return Error::root_unavailable;}
Error WindowsFileSystem::reserve_new_database(FileIdentity&){return Error::root_unavailable;}
Error WindowsFileSystem::release_reserved_database_for_sqlite(const FileIdentity&){return Error::root_unavailable;}
Error WindowsFileSystem::verify_reserved_database(const FileIdentity&,void*){return Error::root_unavailable;}
Error WindowsFileSystem::sqlite_uri(std::string_view,FixedText<12288>&){return Error::root_unavailable;}
Error WindowsFileSystem::list_recovery(std::span<RecoverySummary>,std::size_t&,CodecWorkspace){return Error::root_unavailable;}
Error WindowsFileSystem::delete_recovery(std::span<const FixedText<32>>,Writer&,CodecWorkspace,std::span<std::byte>,NativeContext&){return Error::root_unavailable;}
Error WindowsFileSystem::export_new(std::string_view,std::string_view,ExportReceipt&,std::span<std::byte>,NativeContext&){return Error::root_unavailable;}
Error WindowsFileSystem::wal_pressure(std::uint64_t&){return Error::root_unavailable;}
void WindowsFileSystem::retain_failed_handle(void*,bool)noexcept{}
bool WindowsFileSystem::close_worker_handles()noexcept{return true;}
bool WindowsFileSystem::release_lock_after_join()noexcept{return true;}
bool WindowsFileSystem::has_worker_handles()const noexcept{return false;}
#endif
} // namespace flight::local_players
