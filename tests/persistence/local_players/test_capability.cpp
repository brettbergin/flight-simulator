// Original MIT. Actual Win32 admission and bounded qualification-only observer.
#include "test_capability.hpp"
#include <algorithm>
#include <chrono>
#include <cstring>
#include <exception>
#include <memory>
#include <new>
#include <utility>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <tlhelp32.h>
#endif

namespace flight::local_players::testing {
namespace {
constexpr std::size_t descriptor_cap=65536;
bool hex(std::string_view s,std::size_t n) noexcept {
 return s.size()==n&&std::all_of(s.begin(),s.end(),[](char c){return(c>='0'&&c<='9')||(c>='a'&&c<='f');});
}
bool eqhash(std::string_view input,std::string_view expected) noexcept {
 auto h=sha256_hex(input);return hex(expected,64)&&std::string_view(h.data(),h.size())==expected;
}
void close_native(void*& p) noexcept {
#if defined(_WIN32)
 if(p&&p!=INVALID_HANDLE_VALUE)CloseHandle(static_cast<HANDLE>(p));
#endif
 p=nullptr;
}
// Checked actor retirement never erases an unsuccessfully closed lease.
bool close_native_checked(void*& p) noexcept {
 if(!p)return true;
#if defined(_WIN32)
 if(!CloseHandle(static_cast<HANDLE>(p)))return false;
 p=nullptr;return true;
#else
 return false;
#endif
}
struct Descriptor {
 FixedText<4096> root,parent;FixedText<32> nonce,root_id,parent_id;
 FixedText<64> sentinel_hash;std::uint64_t root_volume{},parent_volume{};
};
bool decimal(DocumentView d,std::uint32_t node,std::uint64_t& result) noexcept {
 FixedText<20> text;U64 u;if(!text.from(d,node)||!U64::parse(text.view(),u))return false;
 result=0;for(char c:text.view())result=result*10+static_cast<unsigned>(c-'0');return true;
}
bool parse_descriptor(std::string_view bytes,Descriptor& out) noexcept {
 if(bytes.empty()||bytes.size()>descriptor_cap)return false;
 std::array<JsonCell,16> cells{};
 std::unique_ptr<std::byte[]> duplicate(new(std::nothrow)std::byte[524288]{});
 if(!duplicate)return false;
 auto parsed=parse_json(bytes,cells,std::span<std::byte>(duplicate.get(),524288),Limits{descriptor_cap,16,2,4096,4096});
 if(!parsed)return false;auto d=parsed.value;auto n=d.root;
 if(closed(d,n,{"schema","root","parent","nonce","root_volume_serial","root_file_id",
               "parent_volume_serial","parent_file_id","sentinel_sha256"})!=Error::none)return false;
 if(!d.string_is(d.member(n,"schema"),"LocalPlayersTestRootDescriptor/v1"))return false;
 if(!out.root.from(d,d.member(n,"root"))||!out.parent.from(d,d.member(n,"parent"))||
    !out.nonce.from(d,d.member(n,"nonce"))||!out.root_id.from(d,d.member(n,"root_file_id"))||
    !out.parent_id.from(d,d.member(n,"parent_file_id"))||!out.sentinel_hash.from(d,d.member(n,"sentinel_sha256"))||
    !decimal(d,d.member(n,"root_volume_serial"),out.root_volume)||
    !decimal(d,d.member(n,"parent_volume_serial"),out.parent_volume))return false;
 return hex(out.nonce.view(),32)&&hex(out.root_id.view(),32)&&hex(out.parent_id.view(),32)&&hex(out.sentinel_hash.view(),64);
}
bool selector_valid(const Selector& s) noexcept {
 if(!s.service||s.service>INT64_MAX||s.request>INT64_MAX||static_cast<unsigned>(s.type)>1)return false;
 if(s.type==SelectorKind::allocation)
  return s.ordinal&&s.ordinal<=INT64_MAX&&static_cast<unsigned>(s.category)<=static_cast<unsigned>(AllocationCategory::export_spool)&&
         s.kind==JobKind::start&&s.scope==Scope::service&&s.phase==Phase::before_open&&s.edge==Edge::before&&!s.occurrence;
 return s.occurrence&&s.occurrence<=INT64_MAX&&static_cast<unsigned>(s.kind)<=static_cast<unsigned>(JobKind::delete_recovery)&&
  static_cast<unsigned>(s.scope)<=static_cast<unsigned>(Scope::recovery)&&
  static_cast<unsigned>(s.phase)<=static_cast<unsigned>(Phase::recovery_copy)&&static_cast<unsigned>(s.edge)<=1&&
  s.category==AllocationCategory::control&&!s.ordinal;
}
Selector selector(const NativeObservation& o) noexcept {
 Selector s;s.service=o.service_ordinal;s.request=o.request_ordinal;s.kind=o.kind;s.scope=o.scope;
 s.phase=o.phase;s.edge=o.edge;s.occurrence=o.occurrence;return s;
}
Selector selector(const AllocationObservation& o) noexcept {
 Selector s;s.type=SelectorKind::allocation;s.service=o.service_ordinal;s.request=o.request_ordinal;
 s.category=o.category;s.ordinal=o.ordinal;return s;
}
bool sql_interrupt_site(const Selector& s) noexcept {
 return s.type==SelectorKind::operation&&s.edge==Edge::before&&
  (s.phase==Phase::before_begin||s.phase==Phase::row_write||s.phase==Phase::before_commit||
   s.phase==Phase::rollback||s.phase==Phase::postverify||s.phase==Phase::checkpoint);
}
bool site_valid(const OperationSite& s) noexcept {
 Selector x;x.service=1;x.kind=s.kind;x.scope=s.scope;x.phase=s.phase;x.edge=s.edge;x.occurrence=1;
 if(!selector_valid(x))return false;
 if(s.phase==Phase::publish_ack)return s.scope==Scope::service;
 if(s.phase==Phase::recovery_copy)return s.scope==Scope::recovery;
 if(s.phase>=Phase::export_create)return s.scope==Scope::export_file;
 if(s.phase==Phase::after_commit&&s.edge!=Edge::after)return false;
 return s.scope==Scope::original||s.scope==Scope::qualification_copy;
}
bool detail_valid(const NativeObservation& o) noexcept {
 if(o.txn_state>2||o.verified_rows>2017||o.pending>16||o.undelivered>16||o.pending+o.undelivered>16||
    o.chunk_index>524288||static_cast<unsigned>(o.role)>5||static_cast<unsigned>(o.io_kind)>2||o.installed< -1||o.installed>1||
    (o.has_requested&&o.requested>65536)||(o.has_completed&&o.completed>65536)||
    (o.has_requested&&o.has_completed&&o.completed>o.requested))return false;
 if(o.phase<=Phase::checkpoint){
  if(o.has_win32_error||o.has_requested||o.has_completed||o.owned_handle||o.installed!=-1||o.identity.valid||o.chunk_index||o.io_kind!=IoKind::not_applicable)return false;
  if(o.phase==Phase::publish_ack)return !o.has_result&&o.verified_rows==0;
  if(o.pending||o.undelivered||o.has_result!=(o.edge==Edge::after))return false;
  return o.phase==Phase::postverify||o.verified_rows==0;
 }
 if(o.has_result||o.autocommit||o.txn_state||o.verified_rows||o.pending||o.undelivered)return false;
 if(o.has_win32_error!=(o.edge==Edge::after))return false;
 if(o.phase==Phase::recovery_copy)return o.io_kind==IoKind::read||o.io_kind==IoKind::write;
 // Native export IO is typed internally; its closed serialized detail keys
 // remain unchanged (only recovery_copy serializes the io_kind field).
 if(o.phase==Phase::export_write)return o.io_kind==IoKind::write;
 // This phase includes metadata-only target opening and bounded digest reads.
 if(o.phase==Phase::export_verify_target)return o.io_kind==IoKind::not_applicable||o.io_kind==IoKind::read;
 return o.io_kind==IoKind::not_applicable;
}
// Shared complete shape admission; the raw forensic record is kept even
// when one of these checks or its occurrence/ordinal history fails.
bool operation_shape_valid(const NativeObservation& o,std::span<const OperationSite> sites) noexcept {
 OperationSite site{o.kind,o.scope,o.phase,o.edge};
 return selector_valid(selector(o))&&site_valid(site)&&detail_valid(o)&&
  std::find(sites.begin(),sites.end(),site)!=sites.end();
}
bool allocation_shape_valid(const AllocationObservation& o) noexcept {
 return selector_valid(selector(o))&&static_cast<unsigned>(o.category)<=5&&o.requested<=33554432&&
  o.rounded<=33554432&&o.rounded%4096==0&&o.rounded>=o.requested&&o.reserved_pages<=8192&&o.live_pages<=8192;
}
#if defined(_WIN32)
struct Handle {
 HANDLE value{INVALID_HANDLE_VALUE};
 Handle()=default;explicit Handle(HANDLE v):value(v){}
 ~Handle(){if(value!=INVALID_HANDLE_VALUE&&value&&!CloseHandle(value))std::terminate();}
 Handle(const Handle&)=delete;Handle& operator=(const Handle&)=delete;
 explicit operator bool()const noexcept{return value&&value!=INVALID_HANDLE_VALUE;}
 void* release() noexcept {auto p=value;value=INVALID_HANDLE_VALUE;return p;}
};
struct Wide {
 std::array<wchar_t,4097> bytes{};int length{};
 bool set(std::string_view s) noexcept {
  if(!valid_local_absolute_path(s)||s.size()>4096||s.find('/')!=s.npos)return false;
  length=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s.data(),static_cast<int>(s.size()),bytes.data(),4096);
  if(length<3)return false;bytes[length]=0;return true;
 }
};
// Temporary filesystem syscall operand only. Wide::set has already admitted
// the bounded canonical absolute DOS path; identity/final-name comparisons
// continue to use that original path, without an extended prefix.
struct ExtendedFileOperand {
 std::array<wchar_t,4101> value{};
 explicit ExtendedFileOperand(const Wide& w) noexcept {
  value[0]=L'\\';value[1]=L'\\';value[2]=L'?';value[3]=L'\\';
  std::copy_n(w.bytes.data(),static_cast<std::size_t>(w.length)+1,value.data()+4);
 }
};
bool equal_path(std::string_view a,std::string_view b) noexcept {
 Wide x,y;return x.set(a)&&y.set(b)&&CompareStringOrdinal(x.bytes.data(),x.length,y.bytes.data(),y.length,TRUE)==CSTR_EQUAL;
}
bool within(std::string_view child,std::string_view parent) noexcept {
 if(child.size()<=parent.size()||child[parent.size()]!='\\')return false;
 return equal_path(child.substr(0,parent.size()),parent);
}
bool related(std::string_view a,std::string_view b) noexcept {return equal_path(a,b)||within(a,b)||within(b,a);}
bool identity(HANDLE h,FileIdentity& out,bool directory) noexcept {
 FILE_ID_INFO id{};FILE_STANDARD_INFO standard{};FILE_ATTRIBUTE_TAG_INFO attributes{};
 if(!GetFileInformationByHandleEx(h,FileIdInfo,&id,sizeof(id))||
    !GetFileInformationByHandleEx(h,FileStandardInfo,&standard,sizeof(standard))||
    !GetFileInformationByHandleEx(h,FileAttributeTagInfo,&attributes,sizeof(attributes))||
    bool(standard.Directory)!=directory||(attributes.FileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)||
    (!directory&&standard.NumberOfLinks!=1))return false;
 out={};out.volume_serial=id.VolumeSerialNumber;std::memcpy(out.file_id.data(),id.FileId.Identifier,16);
 out.links=standard.NumberOfLinks;out.valid=true;return true;
}
bool same(const FileIdentity& a,const FileIdentity& b) noexcept {return a.valid&&b.valid&&a==b;}
std::array<char,32> id_hex(const FileIdentity& id) noexcept {
 constexpr char digits[]="0123456789abcdef";std::array<char,32> out{};
 for(std::size_t i=0;i<16;++i){auto v=std::to_integer<unsigned>(id.file_id[i]);out[2*i]=digits[v>>4];out[2*i+1]=digits[v&15];}return out;
}
bool final_equal(HANDLE h,const Wide& expected) noexcept {
 wchar_t final[4097];auto n=GetFinalPathNameByHandleW(h,final,4097,FILE_NAME_NORMALIZED|VOLUME_NAME_DOS);
 return n>4&&n<4097&&std::wstring_view(final,4)==L"\\\\?\\"&&
  CompareStringOrdinal(final+4,static_cast<int>(n-4),expected.bytes.data(),expected.length,TRUE)==CSTR_EQUAL;
}
bool local_ntfs(const Wide& p) noexcept {
 wchar_t volume[4097],fs[64];return GetVolumePathNameW(p.bytes.data(),volume,4097)&&GetDriveTypeW(volume)==DRIVE_FIXED&&
  GetVolumeInformationW(volume,nullptr,0,nullptr,nullptr,nullptr,fs,64)&&CompareStringOrdinal(fs,-1,L"NTFS",-1,TRUE)==CSTR_EQUAL;
}
// Open every component without following reparses; verify opened final names,
// so a short-name/path alias cannot pass by a substring or casefold alone.
bool physical_directory(std::string_view path,FileIdentity& id,void*& retained) noexcept {
 retained=nullptr;Wide w;if(!w.set(path)||!local_ntfs(w))return false;
 for(int i=3;i<=w.length;++i){if(i<w.length&&w.bytes[i]!='\\')continue;
  const wchar_t saved=w.bytes[i];w.bytes[i]=0;
  Wide prefix=w;prefix.length=i;
  Handle h(CreateFileW(ExtendedFileOperand(prefix).value.data(),FILE_READ_ATTRIBUTES,FILE_SHARE_READ|FILE_SHARE_WRITE,nullptr,OPEN_EXISTING,
                      FILE_FLAG_BACKUP_SEMANTICS|FILE_FLAG_OPEN_REPARSE_POINT,nullptr));
  FileIdentity now;
  bool ok=h&&identity(h.value,now,true)&&final_equal(h.value,prefix);w.bytes[i]=saved;
  if(!ok)return false;if(i==w.length){id=now;retained=h.release();}
 }
 return retained!=nullptr;
}
bool ordinary_file(std::string_view path,Handle& result) noexcept {
 auto slash=path.find_last_of('\\');if(slash==path.npos||slash<3)return false;
 void* parent{};FileIdentity parent_id;if(!physical_directory(path.substr(0,slash),parent_id,parent))return false;
 Handle parent_guard(static_cast<HANDLE>(parent));Wide w;if(!w.set(path))return false;
 result.value=CreateFileW(ExtendedFileOperand(w).value.data(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
 FileIdentity id;return result&&identity(result.value,id,false)&&final_equal(result.value,w);
}
bool read_small(HANDLE h,std::span<char> out,std::size_t& used) noexcept {
 LARGE_INTEGER size{};if(!GetFileSizeEx(h,&size)||size.QuadPart<1||static_cast<std::uint64_t>(size.QuadPart)>out.size())return false;
 used=static_cast<std::size_t>(size.QuadPart);std::size_t done=0;
 while(done<used){DWORD n{};if(!ReadFile(h,out.data()+done,static_cast<DWORD>(used-done),&n,nullptr)||!n||n>used-done)return false;done+=n;}
 char extra{};DWORD n{};return ReadFile(h,&extra,1,&n,nullptr)&&n==0;
}
bool join_path(std::string_view a,std::string_view b,FixedText<4096>& out) noexcept {
 if(a.size()+1+b.size()>4096||!out.assign(a))return false;
 out.data[out.size++]='\\';for(char c:b)out.data[out.size++]=c;out.data[out.size]=0;return true;
}
bool recheck_directory(void* retained,std::string_view path,const FileIdentity& expected) noexcept {
 FileIdentity current;Wide w;return retained&&w.set(path)&&identity(static_cast<HANDLE>(retained),current,true)&&
  same(expected,current)&&final_equal(static_cast<HANDLE>(retained),w);
}
HANDLE actual_parent_process() noexcept {
 Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0));if(!snapshot)return nullptr;
 PROCESSENTRY32W row{};row.dwSize=sizeof(row);DWORD parent=0;const auto self=GetCurrentProcessId();
 if(Process32FirstW(snapshot.value,&row))do{if(row.th32ProcessID==self){parent=row.th32ParentProcessID;break;}}while(Process32NextW(snapshot.value,&row));
 if(!parent||parent==self)return nullptr;
 HANDLE h=OpenProcess(SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION,FALSE,parent);if(!h)return nullptr;
 // Reject recycled/older identity assumptions: the observed parent must still
 // be live and created before this actual child process.
 FILETIME pc,pe,pk,pu,cc,ce,ck,cu;
 if(WaitForSingleObject(h,0)!=WAIT_TIMEOUT||!GetProcessTimes(h,&pc,&pe,&pk,&pu)||
    !GetProcessTimes(GetCurrentProcess(),&cc,&ce,&ck,&cu)||CompareFileTime(&pc,&cc)>0){CloseHandle(h);return nullptr;}
 return h;
}
#endif
} // namespace

bool valid_plan(const FaultPlan& p) noexcept {
 if(p.count>max_actions||!p.maximum_actual_events||p.maximum_actual_events>max_events||p.sites.empty()||p.sites.size()>2700)return false;
 for(std::size_t i=0;i<p.sites.size();++i){const auto& s=p.sites[i];
  if(!site_valid(s))return false;
  for(std::size_t j=0;j<i;++j)if(s==p.sites[j])return false;
 }
 for(std::size_t i=0;i<p.count;++i){const auto& a=p.actions[i];
  if(!selector_valid(a.selector)||static_cast<unsigned>(a.action)>3)return false;
  if((a.action==ActionKind::fail_allocation)!=(a.selector.type==SelectorKind::allocation))return false;
  if(a.action==ActionKind::request_sqlite_interrupt&&!sql_interrupt_site(a.selector))return false;
  if(a.selector.type==SelectorKind::operation){OperationSite site{a.selector.kind,a.selector.scope,a.selector.phase,a.selector.edge};
   if(std::find(p.sites.begin(),p.sites.end(),site)==p.sites.end())return false;}
  for(std::size_t j=0;j<i;++j)if(a.selector==p.actions[j].selector)return false;
 }
 return true;
}
TrustedRoots::TrustedRoots(TrustedRoots&& x) noexcept { *this=std::move(x); }
TrustedRoots& TrustedRoots::operator=(TrustedRoots&& x) noexcept {
 if(this==&x)return *this;std::scoped_lock ledger_lock(mint_mutex_,x.mint_mutex_);
 bool source_closed=close_native_checked(source_handle_);
 bool parent_closed=close_native_checked(parent_handle_);
 if(!source_closed||!parent_closed)std::terminate(); // never overwrite a failed lease
 last_successful_mint_=std::max(last_successful_mint_,x.last_successful_mint_);
 error_=x.error_;source_=x.source_;parent_=x.parent_;product_=x.product_;source_id_=x.source_id_;parent_id_=x.parent_id_;
 source_handle_=std::exchange(x.source_handle_,nullptr);parent_handle_=std::exchange(x.parent_handle_,nullptr);
 x.error_=TestError::untrusted_prerequisite;return *this;
}
bool TrustedRoots::retire() noexcept {
 std::lock_guard ledger_lock(mint_mutex_);
 error_=TestError::untrusted_prerequisite; // before any close; no new mint
 bool source_closed=close_native_checked(source_handle_);
 bool parent_closed=close_native_checked(parent_handle_);
 return source_closed&&parent_closed; // high-water and failed handles retained
}
TrustedRoots::~TrustedRoots(){if(!retire())std::terminate();}
Capability::Capability(Capability&& x) noexcept {*this=std::move(x);}
Capability& Capability::operator=(Capability&& x) noexcept {
 if(this==&x)return *this;
 if(access_taken_&&!released_&&root_handle_)std::terminate();
 if(!access_taken_){if(!retire_unconsumed())std::terminate();}
 else {access_.reset();release_leases_after_join();}
 error_=x.error_;access_=std::move(x.access_);x.access_.reset();nonce_=x.nonce_;digest_=x.digest_;
 root_handle_=std::exchange(x.root_handle_,nullptr);parent_handle_=std::exchange(x.parent_handle_,nullptr);
 sentinel_handle_=std::exchange(x.sentinel_handle_,nullptr);
 access_taken_=x.access_taken_;released_=x.released_;x.access_taken_=false;x.released_=true;
 x.error_=TestError::invalid_descriptor;return *this;
}
Capability::~Capability(){
 // A forgotten live-token lease is a failed actor, never silent auto-retirement.
 if(access_taken_&&!released_&&root_handle_)std::terminate();
 if(!access_taken_){if(!retire_unconsumed())std::terminate();}
 else {access_.reset();release_leases_after_join();}
}
std::optional<StoreAccess> Capability::take_access() noexcept {
 if(!valid())return {};std::optional<StoreAccess> out(std::move(*access_));access_.reset();access_taken_=true;return out;
}
void Capability::release_leases_after_join() noexcept {
 close_native(sentinel_handle_);close_native(root_handle_);close_native(parent_handle_);released_=true;
}

bool Capability::retire_unconsumed() noexcept {
 if(access_taken_)return false; // cannot disguise a Service join
 error_=TestError::invalid_descriptor;
 access_.reset(); // minted platform has never acquired worker/store handles
 bool sentinel_closed=close_native_checked(sentinel_handle_);
 bool root_closed=close_native_checked(root_handle_);
 bool parent_closed=close_native_checked(parent_handle_);
 released_=sentinel_closed&&root_closed&&parent_closed;
 return released_;
}

TrustedRoots TestRootFactory::prepare_prerequisite(std::string_view source,std::string_view parent) noexcept {
 TrustedRoots out;
#if defined(_WIN32)
 out.error_=TestError::path;
 if(!out.source_.assign(source)||!out.parent_.assign(parent)||source.size()<=3||parent.size()<=3)return out;
 if(!physical_directory(source,out.source_id_,out.source_handle_)||!physical_directory(parent,out.parent_id_,out.parent_handle_))return out;
 // This resolver is intentionally separate, read-only and NEVER called by
 // admit_bytes/admit_file. No product directory is opened/created here.
 if(WindowsFileSystem::resolve_known_folder(out.product_)!=Error::none)return out;
 constexpr std::string_view suffix="\\FlightSimulator\\Players";
 auto product=out.product_.view();if(!product.ends_with(suffix))return out;
 FileIdentity local_id;void* local{};
 if(!physical_directory(product.substr(0,product.size()-suffix.size()),local_id,local))return out;
 if(!close_native_checked(local))std::terminate(); // no valid prerequisite after lost transient lease
 if(related(parent,product)||equal_path(source,parent)||within(source,parent))return out;
 if(within(parent,source)){
  auto relative=parent.substr(source.size()+1);
  if(relative!=".local"&&!relative.starts_with(".local\\"))return out;
 }
 out.error_=TestError::none;
#else
 (void)source;(void)parent;out.error_=TestError::unsupported;
#endif
 return out;
}
Capability TestRootFactory::admit_bytes(std::string_view raw,std::string_view expected,const TrustedRoots& trust,
                                      QualificationObserver* observer,std::uint64_t ordinal) noexcept {
 Capability out;std::lock_guard mint_lock(trust.mint_mutex_);
 if(!trust.valid()){out.error_=TestError::untrusted_prerequisite;return out;}
 if(raw.empty()||raw.size()>descriptor_cap){out.error_=TestError::invalid_descriptor;return out;}
 if(!eqhash(raw,expected)){out.error_=TestError::descriptor_hash;return out;}
 Descriptor d;if(!ordinal||ordinal>INT64_MAX||!parse_descriptor(raw,d)){out.error_=TestError::invalid_descriptor;return out;}
 // Only successful mint advances. Failure may retry the unminted ordinal;
 // disposing an already minted token never makes that identity reusable.
 if(ordinal<=trust.last_successful_mint_){out.error_=TestError::out_of_order;return out;}
#if defined(_WIN32)
 out.error_=TestError::path;
 if(!recheck_directory(trust.source_handle_,trust.source_.view(),trust.source_id_)||
    !recheck_directory(trust.parent_handle_,trust.parent_.view(),trust.parent_id_)||
    !equal_path(d.parent.view(),trust.parent_.view()))return out;
 FixedText<4096> leaf,path;leaf.assign("local-players-test-");for(char c:d.nonce.view())leaf.data[leaf.size++]=c;leaf.data[leaf.size]=0;
 auto basename=d.root.view().substr(d.root.view().find_last_of('\\')+1);
 if(!join_path(d.parent.view(),leaf.view(),path)||basename!=leaf.view()||!equal_path(d.root.view(),path.view())||
    related(d.root.view(),trust.product_.view())||equal_path(d.root.view(),trust.source_.view())||within(trust.source_.view(),d.root.view()))return out;
 FileIdentity root_id,parent_id;
 if(!physical_directory(d.parent.view(),parent_id,out.parent_handle_)||!physical_directory(d.root.view(),root_id,out.root_handle_))return out;
 out.error_=TestError::identity;
 auto rh=id_hex(root_id),ph=id_hex(parent_id);
 if(!same(parent_id,trust.parent_id_)||root_id==parent_id||root_id==trust.source_id_||root_id.volume_serial!=d.root_volume||
    parent_id.volume_serial!=d.parent_volume||std::string_view(rh.data(),32)!=d.root_id.view()||std::string_view(ph.data(),32)!=d.parent_id.view())return out;
 FixedText<4096> sentinel_path;Handle sentinel;
 out.error_=TestError::sentinel;
 if(!join_path(d.root.view(),".local-players-test-root.json",sentinel_path)||!ordinary_file(sentinel_path.view(),sentinel))return out;
 std::array<char,1024> content{};std::size_t length{};
 FileIdentity sentinel_id;
 if(!identity(sentinel.value,sentinel_id,false)||!read_small(sentinel.value,content,length))return out;
 std::array<char,128> wanted{};Writer writer(wanted);
 writer.raw("{\"schema\":\"LocalPlayersTestRootSentinel/v1\",\"nonce\":");writer.string(d.nonce.view());writer.raw("}\n");
 if(!writer.good()||std::string_view(content.data(),length)!=writer.bytes()||!eqhash(writer.bytes(),d.sentinel_hash.view()))return out;
 // Lease remains test-owned through actual service join. The v4 adapter
 // receives the actual sentinel identity/hash for its independent recheck.
 out.sentinel_handle_=sentinel.release();out.nonce_=d.nonce;std::copy(expected.begin(),expected.end(),out.digest_.begin());
 StoreAccess access;static_assert(sizeof(WindowsFileSystem)<=49152);
 auto* fs=new(access.platform_.data())WindowsFileSystem;
 fs->root_=d.root;fs->root_identity_=root_id;fs->parent_identity_=parent_id;
 fs->test_parent_=d.parent;fs->test_nonce_=d.nonce;fs->isolated_=true;
 fs->test_sentinel_identity_=sentinel_id;
 std::copy(d.sentinel_hash.view().begin(),d.sentinel_hash.view().end(),fs->test_sentinel_sha256_.begin());
 access.filesystem_=fs;access.observer_=observer;access.origin_=Origin::isolated_test;access.service_ordinal_=ordinal;
 out.access_.emplace(std::move(access));
 // Serialized with every other mint on this context; never a growing map.
 trust.last_successful_mint_=ordinal;out.error_=TestError::none;
#else
 (void)observer;out.error_=TestError::unsupported;
#endif
 return out;
}
Capability TestRootFactory::admit_file(std::string_view path,std::string_view expected,const TrustedRoots& trust,
                                     QualificationObserver* observer,std::uint64_t ordinal) noexcept {
 Capability failure;
 if(!trust.valid()){failure.error_=TestError::untrusted_prerequisite;return failure;}
#if defined(_WIN32)
 Handle file;std::array<char,descriptor_cap> raw{};std::size_t size{};Descriptor d;
 if(!ordinary_file(path,file)||!read_small(file.value,raw,size)){failure.error_=TestError::path;return failure;}
 std::string_view bytes(raw.data(),size);
 if(!eqhash(bytes,expected)){failure.error_=TestError::descriptor_hash;return failure;}
 if(!parse_descriptor(bytes,d)){failure.error_=TestError::invalid_descriptor;return failure;}
 if(equal_path(path,d.root.view())||within(path,d.root.view())){failure.error_=TestError::path;return failure;}
 return admit_bytes(bytes,expected,trust,observer,ordinal);
#else
 (void)path;(void)expected;(void)observer;(void)ordinal;failure.error_=TestError::unsupported;return failure;
#endif
}

TestController::TestController(std::string_view nonce,const FaultPlan& plan,std::span<ObservedEvent> events,
                               std::span<CounterState> counters) noexcept:plan_(plan),records_(events),counters_(counters) {
 if(!hex(nonce,32)||!nonce_.assign(nonce)||!valid_plan(plan)){error_=TestError::invalid_plan;return;}
 if(events.size()<plan.maximum_actual_events||events.size()>max_events||counters.size()<plan.maximum_actual_events||counters.size()>max_events){error_=TestError::capacity;return;}
 std::fill(counters.begin(),counters.end(),CounterState{});
#if defined(_WIN32)
 pid_=GetCurrentProcessId();bool need_parent=false;
 for(std::size_t i=0;i<plan.count;++i)need_parent|=plan.actions[i].action==ActionKind::await_parent_process_termination;
 if(need_parent){parent_process_=actual_parent_process();if(!parent_process_)error_=TestError::parent;}
#else
 error_=TestError::unsupported;
#endif
}
TestController::~TestController(){abort();close_native(parent_process_);}
void TestController::fail_locked(TestError e) noexcept {if(error_==TestError::none)error_=e;cv_.notify_all();}
bool TestController::append_locked(ObservedEvent& record) noexcept {
 if(used_>=plan_.maximum_actual_events||used_>=records_.size()||used_==UINT64_MAX){fail_locked(TestError::overflow);return false;}
 record.sequence=used_+1;record.pid=pid_;records_[used_++]=record;return true;
}
// Fixed caller-owned open-address table. No unbounded side map/event storage.
bool TestController::operation_counter_locked(const NativeObservation& o) noexcept {
 std::uint64_t key=o.service_ordinal*0x9e3779b97f4a7c15ULL+o.request_ordinal*131+
   static_cast<unsigned>(o.phase)*5+static_cast<unsigned>(o.scope);
 for(std::size_t probe=0;probe<counters_.size();++probe){auto& c=counters_[(key+probe)%counters_.size()];
  if(!c.occupied){c.occupied=true;c.service=o.service_ordinal;c.request=o.request_ordinal;c.kind=o.kind;c.phase=o.phase;c.scope=o.scope;}
  if(c.allocation||c.service!=o.service_ordinal||c.request!=o.request_ordinal||c.phase!=o.phase||c.scope!=o.scope)continue;
  if(c.kind!=o.kind||!o.occurrence)return false;
  if(o.phase==Phase::after_commit){if(o.edge!=Edge::after||c.occurrence==UINT64_MAX||o.occurrence!=c.occurrence+1)return false;c.occurrence=o.occurrence;return true;}
  if(o.edge==Edge::before){if(c.pending||c.occurrence==UINT64_MAX||o.occurrence!=c.occurrence+1)return false;c.occurrence=o.occurrence;c.pending=true;return true;}
  if(!c.pending||c.occurrence!=o.occurrence)return false;c.pending=false;return true;
 }
 return false;
}
bool TestController::allocation_counter_locked(const AllocationObservation& o) noexcept {
 std::uint64_t key=o.service_ordinal*0x9e3779b97f4a7c15ULL+static_cast<unsigned>(o.category);
 for(std::size_t probe=0;probe<counters_.size();++probe){auto& c=counters_[(key+probe)%counters_.size()];
  if(!c.occupied){c.occupied=true;c.allocation=true;c.service=o.service_ordinal;c.category=o.category;}
  if(!c.allocation||c.service!=o.service_ordinal||c.category!=o.category)continue;
  if(c.occurrence==UINT64_MAX||o.ordinal!=c.occurrence+1)return false;c.occurrence=o.ordinal;return true;
 }
 return false;
}
bool TestController::wait_parent_death(std::unique_lock<std::mutex>& lock) {
#if defined(_WIN32)
 auto handle=static_cast<HANDLE>(parent_process_);if(!handle){fail_locked(TestError::parent);return false;}
 lock.unlock();const auto result=WaitForSingleObject(handle,120000);lock.lock();
 // Real death is recorded as the action's outcome by the actor driver; it is
 // not labelled a graceful service join or fabricated operation failure.
 if(result!=WAIT_OBJECT_0){fail_locked(result==WAIT_TIMEOUT?TestError::timeout:TestError::parent);return false;}
 return true;
#else
 (void)lock;return false;
#endif
}
bool TestController::run_action(std::unique_lock<std::mutex>& lock,const Selector& selected) {
 std::size_t matched=plan_.count;
 for(std::size_t i=0;i<plan_.count;++i)if(plan_.actions[i].selector==selected){matched=i;break;}
 if(matched==plan_.count)return true;
 if(matched<next_action_){fail_locked(TestError::duplicate_action);return false;}
 if(matched!=next_action_){fail_locked(TestError::out_of_order);return false;}
 const auto action=plan_.actions[matched].action;++next_action_;
 if(action==ActionKind::fail_allocation)return false;
 if(action==ActionKind::request_sqlite_interrupt){if(interrupt_pending_){fail_locked(TestError::interrupt_unconsumed);return false;}
  interrupt_pending_=true;interrupt_thread_=std::this_thread::get_id();return true;}
 arrived_={true,pid_,static_cast<std::uint32_t>(matched+1),selected};released_=false;cv_.notify_all();
 if(action==ActionKind::await_parent_process_termination){bool ok=wait_parent_death(lock);arrived_={};return ok;}
 const bool woke=cv_.wait_for(lock,std::chrono::seconds(120),[&]{return released_||stopping_||error_!=TestError::none;});
 if(!woke)fail_locked(TestError::timeout);bool ok=woke&&released_&&!stopping_&&error_==TestError::none;arrived_={};released_=false;return ok;
}
void TestController::observe(const NativeObservation& o) {
 std::unique_lock lock(mutex_);
 ObservedEvent record;record.operation=o;if(!append_locked(record)||error_!=TestError::none)return;
 auto selected=selector(o);
 if(!operation_shape_valid(o,plan_.sites)||!operation_counter_locked(o)){
  fail_locked(TestError::invalid_observation);return;
 }
 records_[used_-1].admitted=true; // Complete shape and actual history passed.
 (void)run_action(lock,selected); // Cannot substitute or skip the real operation.
}
bool TestController::allow_allocation(const AllocationObservation& o) {
 std::unique_lock lock(mutex_);
 ObservedEvent record;record.allocation=true;record.charge=o;if(!append_locked(record)||error_!=TestError::none)return false;
 if(!allocation_shape_valid(o)||!allocation_counter_locked(o)){fail_locked(TestError::invalid_observation);return false;}
 records_[used_-1].admitted=true;
 return run_action(lock,selector(o));
}
bool TestController::take_sqlite_interrupt_request() noexcept {
 std::lock_guard lock(mutex_);if(error_!=TestError::none)return false;
 if(interrupt_pending_&&std::this_thread::get_id()!=interrupt_thread_){fail_locked(TestError::invalid_observation);return false;}
 const bool requested=interrupt_pending_;interrupt_pending_=false;return requested;
}
Arrival TestController::wait_arrived(std::uint32_t ordinal,std::uint32_t timeout_ms) {
 std::unique_lock lock(mutex_);
 if(!ordinal||ordinal>plan_.count||!timeout_ms||timeout_ms>45000){fail_locked(TestError::invalid_plan);return {};}
 if(!cv_.wait_for(lock,std::chrono::milliseconds(timeout_ms),[&]{return(arrived_.present&&arrived_.action_ordinal==ordinal)||error_!=TestError::none;}))fail_locked(TestError::timeout);
 return error_==TestError::none?arrived_:Arrival{};
}
bool TestController::release_bytes(std::string_view bytes) noexcept {
 std::array<JsonCell,8> cells{};std::array<std::byte,524288> duplicate{};
 auto parsed=parse_json(bytes,cells,duplicate,Limits{4096,8,2,128,128});
 if(!parsed){std::lock_guard lock(mutex_);fail_locked(TestError::release);return false;}
 auto d=parsed.value;auto n=d.root;FixedText<32> nonce;
 const auto* pid=d.at(d.member(n,"pid"));const auto* action=d.at(d.member(n,"action_ordinal"));
 bool shape=closed(d,n,{"type","nonce","pid","action_ordinal"})==Error::none&&d.string_is(d.member(n,"type"),"RELEASE")&&
  nonce.from(d,d.member(n,"nonce"))&&pid&&action&&pid->kind==ValueKind::integer&&action->kind==ValueKind::integer;
 std::lock_guard lock(mutex_);
 if(!shape||nonce.view()!=nonce_.view()||pid->scalar!=pid_||!arrived_.present||action->scalar!=arrived_.action_ordinal||released_||
    plan_.actions[arrived_.action_ordinal-1].action!=ActionKind::hold){fail_locked(TestError::release);return false;}
 released_=true;cv_.notify_all();return true;
}
void TestController::abort() noexcept {std::lock_guard lock(mutex_);stopping_=true;if(arrived_.present)fail_locked(TestError::release);cv_.notify_all();}
TestError TestController::error() const noexcept {std::lock_guard lock(mutex_);return error_;}
bool TestController::finish() noexcept {
 std::lock_guard lock(mutex_);
 if(!used_)fail_locked(TestError::invalid_observation);
 if(next_action_!=plan_.count)fail_locked(TestError::unmatched_action);
 if(interrupt_pending_)fail_locked(TestError::interrupt_unconsumed);
 for(const auto& c:counters_)if(c.occupied&&c.pending)fail_locked(TestError::invalid_observation);
 return error_==TestError::none&&!arrived_.present;
}
std::size_t TestController::event_count() const noexcept {std::lock_guard lock(mutex_);return used_;}
bool TestController::copy_event(std::size_t index,ObservedEvent& out) const noexcept {
 std::lock_guard lock(mutex_);if(index>=used_)return false;out=records_[index];return true;
}

namespace {
bool unsigned_string(Writer& w,std::uint64_t v) noexcept {
 char bytes[20];char* end=bytes+20;char* p=end;do{*--p=static_cast<char>('0'+v%10);v/=10;}while(v);return w.string({p,static_cast<std::size_t>(end-p)});
}
void nullable_int(Writer& w,bool present,std::int64_t value) noexcept {if(present)w.integer(value);else w.raw("null");}
}
bool TestController::write_event(std::size_t index,Writer& w) const noexcept {
 std::lock_guard lock(mutex_);if(index>=used_)return false;const auto& e=records_[index];
 // A rejected raw record remains copyable, never a valid closed event.
 // Recheck full pure shape/site admission before writing any byte; admitted
 // additionally binds successful actual counter/occurrence validation.
 if(!e.admitted||e.sequence!=index+1||!e.pid||e.pid!=pid_)return false;
 if(e.allocation){if(!allocation_shape_valid(e.charge))return false;}
 else if(!operation_shape_valid(e.operation,plan_.sites))return false;
 constexpr std::string_view phases[]={"before_open","before_begin","row_write","before_commit","after_commit","rollback","postverify","publish_ack","checkpoint","export_create","export_write","export_flush","export_move","export_verify_target","recovery_copy"};
 constexpr std::string_view scopes[]={"service","qualification_copy","original","export","recovery"};
 constexpr std::string_view categories[]={"control","request","terminal","delivery","workspace","export_spool"};
 constexpr std::string_view roles[]={"target","temp","main","wal","shm","journal"};
 w.raw("{\"run_nonce\":");w.string(nonce_.view());w.raw(",\"actor_pid\":");w.integer(e.pid);
 w.raw(",\"service_ordinal\":");w.integer(static_cast<std::int64_t>(e.allocation?e.charge.service_ordinal:e.operation.service_ordinal));
 w.raw(",\"request_ordinal\":");w.integer(static_cast<std::int64_t>(e.allocation?e.charge.request_ordinal:e.operation.request_ordinal));
 w.raw(",\"event_sequence\":");unsigned_string(w,e.sequence);
 if(e.allocation){const auto& a=e.charge;w.raw(",\"category\":");w.string(categories[static_cast<unsigned>(a.category)]);
  w.raw(",\"ordinal\":");w.integer(static_cast<std::int64_t>(a.ordinal));w.raw(",\"requested\":");w.integer(a.requested);
  w.raw(",\"rounded\":");w.integer(a.rounded);w.raw(",\"reserved_pages\":");w.integer(a.reserved_pages);w.raw(",\"live_pages\":");w.integer(a.live_pages);
 }else{const auto& o=e.operation;w.raw(",\"kind\":");w.string(o.request_ordinal?kind_name(o.kind):"lifecycle");
  w.raw(",\"scope\":");w.string(scopes[static_cast<unsigned>(o.scope)]);w.raw(",\"phase\":");w.string(phases[static_cast<unsigned>(o.phase)]);
  w.raw(",\"edge\":");w.string(o.edge==Edge::before?"before":"after");w.raw(",\"occurrence\":");w.integer(static_cast<std::int64_t>(o.occurrence));w.raw(",\"detail\":{");
  if(o.phase==Phase::publish_ack){w.raw("\"pending\":");w.integer(o.pending);w.raw(",\"undelivered\":");w.integer(o.undelivered);}
  else if(o.phase<=Phase::checkpoint){w.raw("\"sqlite_result\":");nullable_int(w,o.has_result,o.sqlite_result);
   if(o.phase!=Phase::before_open){w.raw(",\"autocommit\":");w.raw(o.autocommit?"true":"false");w.raw(",\"txn_state\":");w.integer(o.txn_state);
    if(o.phase==Phase::postverify){w.raw(",\"verified_rows\":");w.integer(o.verified_rows);}}
  }else{w.raw("\"win32_error\":");nullable_int(w,o.has_win32_error,o.win32_error);w.raw(",\"requested_bytes\":");nullable_int(w,o.has_requested,o.requested);
   w.raw(",\"completed_bytes\":");nullable_int(w,o.has_completed,o.completed);w.raw(",\"owned_handle\":");w.raw(o.owned_handle?"true":"false");
   w.raw(",\"installed\":");w.raw(o.installed<0?"null":o.installed?"true":"false");w.raw(",\"volume_serial\":");
   if(o.identity.valid)unsigned_string(w,o.identity.volume_serial);else w.raw("null");w.raw(",\"file_id\":");
   if(o.identity.valid){constexpr char digits[]="0123456789abcdef";char id[32];for(unsigned i=0;i<16;++i){auto b=std::to_integer<unsigned>(o.identity.file_id[i]);id[2*i]=digits[b>>4];id[2*i+1]=digits[b&15];}w.string({id,32});}else w.raw("null");
   w.raw(",\"chunk_index\":");w.integer(o.chunk_index);w.raw(",\"role\":");w.string(roles[static_cast<unsigned>(o.role)]);
   if(o.phase==Phase::recovery_copy){w.raw(",\"io_kind\":");w.string(o.io_kind==IoKind::read?"read":"write");}
  }
  w.character('}');
 }
 return w.character('}')&&w.good();
}
} // namespace flight::local_players::testing
