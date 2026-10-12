// Original MIT. Isolated test extension; never linked into the shipping DLL.
// Root owns the four user-argument bindings and immutable context/descriptor.
#include "local_players.hpp"
#include "test_capability.hpp"
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <optional>
#include <cwchar>
#include <exception>
#include <mutex>
#include <thread>
#include <windows.h>
#include <tlhelp32.h>

namespace flight::local_players::testing {
namespace {
using godot::Variant;
using godot::Dictionary;
using godot::String;
using bridge::LocalPlayersBoundary;
constexpr std::size_t input_cap=16384;
constexpr std::array<std::string_view,9> descriptor_keys={"schema","root","parent","nonce",
 "root_volume_serial","root_file_id","parent_volume_serial","parent_file_id","sentinel_sha256"};
constexpr std::array<std::string_view,9> context_keys={"schema","role","source_root","proof_parent",
 "parent_pid","parent_creation_100ns","godot_executable_sha256","test_bridge_sha256","descriptor_sha256"};
std::atomic<std::uint64_t> live_wrappers{};
int module_anchor;
struct Handle {
 HANDLE h{};
 ~Handle(){if(!close())std::terminate();}
 bool valid() const noexcept{return h&&h!=INVALID_HANDLE_VALUE;}
 bool close() noexcept {if(!valid()){h=nullptr;return true;}if(!CloseHandle(h))return false;h=nullptr;return true;}
};
struct Input {Handle handle;std::array<char,input_cap> bytes{};std::size_t size{};
 std::string_view view()const noexcept{return {bytes.data(),size};}};
struct Context {
 FixedText<4096> source,parent;FixedText<64> host_sha,dll_sha,descriptor_sha;
 DWORD parent_pid{};std::uint64_t parent_creation{};
};
// Fixed TEST-owned input/parser buffers, not Service-owned storage or caller
// Variants. No native service allocation is excused by this test workspace.
struct Inputs {
 std::thread::id owner{};bool loading{},loaded{},failed{};
 Input context,descriptor;Handle parent;
 std::array<JsonCell,64> cells{};std::array<std::byte,524288> duplicate{};
 std::array<FixedText<4096>,9> descriptor_fields{};
 Context parsed;std::optional<TrustedRoots> trusted;
 std::uint64_t next_ordinal{1};
};
Inputs inputs;
std::mutex inputs_mutex;
String gs(std::string_view s){return String::utf8(s.data(),static_cast<std::int64_t>(s.size()));}
template<std::size_t N> bool utf8(const String&s,FixedText<N>&out) noexcept {
 out.size=0;
 for(std::int64_t i=0;i<s.length();++i){auto cp=static_cast<std::uint32_t>(s.unicode_at(i));
  if(cp>0x10ffff||(cp>=0xd800&&cp<=0xdfff)||cp==0)return false;
  unsigned n=cp<0x80?1:cp<0x800?2:cp<0x10000?3:4;if(out.size+n>N)return false;
  if(n==1)out.data[out.size++]=static_cast<char>(cp);
  else {out.data[out.size++]=static_cast<char>((n==2?0xc0:n==3?0xe0:0xf0)|(cp>>(6*(n-1))));
   for(unsigned j=n-1;j>0;--j)out.data[out.size++]=static_cast<char>(0x80|((cp>>(6*(j-1)))&63));}
 }
 out.data[out.size]=0;return true;
}
bool wide(std::string_view s,std::array<wchar_t,4097>&out) noexcept {
 if(s.empty()||s.size()>4096)return false;
 const int n=MultiByteToWideChar(CP_UTF8,MB_ERR_INVALID_CHARS,s.data(),static_cast<int>(s.size()),out.data(),4096);
 if(n<=0)return false;out[static_cast<std::size_t>(n)]=0;
 for(int i=0;i<n;++i)if(out[static_cast<std::size_t>(i)]==L'/')out[static_cast<std::size_t>(i)]=L'\\';return true;
}
bool path_utf8(std::wstring_view s,FixedText<4096>&out) noexcept {
 if(s.empty()||s.size()>32767)return false;
 const int n=WideCharToMultiByte(CP_UTF8,WC_ERR_INVALID_CHARS,s.data(),static_cast<int>(s.size()),out.data.data(),4096,nullptr,nullptr);
 if(n<=0)return false;out.size=static_cast<std::uint32_t>(n);out.data[out.size]=0;return true;
}
// Every component must remain ordinary; the final retained handle denies write
// and delete sharing. No selected-root access occurs through these control reads.
bool ordinary_file(std::string_view path,Handle&out) noexcept {
 if(!valid_local_absolute_path(path))return false;std::array<wchar_t,4097>w{};if(!wide(path,w))return false;
 const auto length=wcslen(w.data());
 for(std::size_t i=3;i<=length;++i)if(i==length||w[i]==L'\\'){
  const auto saved=w[i];w[i]=0;const auto attributes=GetFileAttributesW(w.data());w[i]=saved;
  if(attributes==INVALID_FILE_ATTRIBUTES||(attributes&FILE_ATTRIBUTE_REPARSE_POINT)||
   (i!=length&&!(attributes&FILE_ATTRIBUTE_DIRECTORY))||(i==length&&(attributes&FILE_ATTRIBUTE_DIRECTORY)))return false;
 }
 out.h=CreateFileW(w.data(),GENERIC_READ,FILE_SHARE_READ,nullptr,OPEN_EXISTING,FILE_FLAG_OPEN_REPARSE_POINT,nullptr);
 if(!out.valid())return false;FILE_ATTRIBUTE_TAG_INFO tag{};BY_HANDLE_FILE_INFORMATION info{};
 return GetFileType(out.h)==FILE_TYPE_DISK&&GetFileInformationByHandleEx(out.h,FileAttributeTagInfo,&tag,sizeof tag)&&
  !(tag.FileAttributes&(FILE_ATTRIBUTE_REPARSE_POINT|FILE_ATTRIBUTE_DIRECTORY))&&GetFileInformationByHandle(out.h,&info)&&info.nNumberOfLinks==1;
}
bool digest_file(std::string_view path,std::string_view expected) noexcept {
 if(!lower_hex(expected,64))return false;Handle file;if(!ordinary_file(path,file))return false;
 LARGE_INTEGER length{};if(!GetFileSizeEx(file.h,&length)||length.QuadPart<=0||length.QuadPart>512LL*1024*1024)return false;
 Sha256 hash;std::array<std::byte,65536> chunk{};std::uint64_t total{};
 for(;;){DWORD n{};if(!ReadFile(file.h,chunk.data(),static_cast<DWORD>(chunk.size()),&n,nullptr))return false;
  if(!n)break;total+=n;if(total>static_cast<std::uint64_t>(length.QuadPart))return false;
  hash.update(std::span<const std::byte>(chunk).first(n));}
 auto raw=hash.finish();constexpr char digits[]="0123456789abcdef";std::array<char,64> hex{};
 for(std::size_t i=0;i<32;++i){auto b=std::to_integer<unsigned>(raw[i]);hex[2*i]=digits[b>>4];hex[2*i+1]=digits[b&15];}
 return file.close()&&total==static_cast<std::uint64_t>(length.QuadPart)&&std::string_view(hex.data(),hex.size())==expected;
}
bool load(std::string_view path,std::string_view expected,Input&out) noexcept {
 if(!lower_hex(expected,64)||!ordinary_file(path,out.handle))return false;
 LARGE_INTEGER length{};if(!GetFileSizeEx(out.handle.h,&length)||length.QuadPart<1||length.QuadPart>static_cast<LONGLONG>(input_cap))return false;
 out.size=static_cast<std::size_t>(length.QuadPart);std::size_t done{};
 while(done<out.size){DWORD n{};if(!ReadFile(out.handle.h,out.bytes.data()+done,static_cast<DWORD>(out.size-done),&n,nullptr)||!n||n>out.size-done)return false;done+=n;}
 char extra{};DWORD n{};if(!ReadFile(out.handle.h,&extra,1,&n,nullptr)||n)return false;
 auto hash=sha256_hex(out.view());return std::string_view(hash.data(),hash.size())==expected;
}
ParseResult parse(std::string_view bytes) noexcept {
 return parse_json(bytes,inputs.cells,inputs.duplicate,Limits{input_cap,64,2,4096,4096});
}
bool canonical_u64(DocumentView d,std::uint32_t n,std::uint64_t&v,bool positive=false) noexcept {
 FixedText<20>s;std::size_t count{};U64 u;
 if(!copy_string(d,n,s.data,count)||count>20)return false;s.size=static_cast<std::uint32_t>(count);
 if(!U64::parse(s.view(),u,positive))return false;v=0;for(char c:s.view())v=v*10+static_cast<unsigned>(c-'0');return true;
}
template<std::size_t N> bool field(DocumentView d,std::string_view key,FixedText<N>&out) noexcept {
 std::size_t n{};if(!copy_string(d,d.member(d.root,key),out.data,n)||n>N)return false;out.size=static_cast<std::uint32_t>(n);out.data[n]=0;return true;
}
template<std::size_t N> bool exact_keys(DocumentView d,const std::array<std::string_view,N>&keys) noexcept {
 if(!d.at(d.root)||d.at(d.root)->kind!=ValueKind::object||d.size(d.root)!=N)return false;
 for(auto key:keys)if(d.member(d.root,key)==no_cell)return false;return true;
}
bool context() noexcept {
 auto p=parse(inputs.context.view());if(!p||!exact_keys(p.value,context_keys))return false;auto d=p.value;auto&c=inputs.parsed;
 std::uint64_t pid{};
 if(!d.string_is(d.member(d.root,"schema"),"LocalPlayersGodotTestContext/v1")||!d.string_is(d.member(d.root,"role"),"bridge")||
  !field(d,"source_root",c.source)||!field(d,"proof_parent",c.parent)||!field(d,"godot_executable_sha256",c.host_sha)||
  !field(d,"test_bridge_sha256",c.dll_sha)||!field(d,"descriptor_sha256",c.descriptor_sha)||
  !canonical_u64(d,d.member(d.root,"parent_pid"),pid,true)||pid>MAXDWORD||
  !canonical_u64(d,d.member(d.root,"parent_creation_100ns"),c.parent_creation,true))return false;
 c.parent_pid=static_cast<DWORD>(pid);
 return valid_local_absolute_path(c.source.view())&&valid_local_absolute_path(c.parent.view())&&lower_hex(c.host_sha.view(),64)&&
  lower_hex(c.dll_sha.view(),64)&&lower_hex(c.descriptor_sha.view(),64);
}
bool descriptor() noexcept {
 auto p=parse(inputs.descriptor.view());if(!p||!exact_keys(p.value,descriptor_keys))return false;auto d=p.value;
 for(std::size_t i=0;i<descriptor_keys.size();++i)if(!field(d,descriptor_keys[i],inputs.descriptor_fields[i]))return false;
 const auto&v=inputs.descriptor_fields;U64 u;
 return v[0].view()=="LocalPlayersTestRootDescriptor/v1"&&valid_local_absolute_path(v[1].view())&&valid_local_absolute_path(v[2].view())&&
  lower_hex(v[3].view(),32)&&U64::parse(v[4].view(),u)&&lower_hex(v[5].view(),32)&&U64::parse(v[6].view(),u)&&lower_hex(v[7].view(),32)&&lower_hex(v[8].view(),64);
}
bool at_or_within(std::string_view path,std::string_view root) noexcept {
 std::array<wchar_t,4097>p{},r{};if(!wide(path,p)||!wide(root,r))return true;
 const auto pn=wcslen(p.data()),rn=wcslen(r.data());
 return pn>=rn&&CompareStringOrdinal(p.data(),static_cast<int>(rn),r.data(),static_cast<int>(rn),TRUE)==CSTR_EQUAL&&(pn==rn||p[rn]==L'\\');
}
bool parent_live() noexcept {return inputs.parent.valid()&&WaitForSingleObject(inputs.parent.h,0)==WAIT_TIMEOUT;}
bool bind_parent() noexcept {
 const auto&c=inputs.parsed;if(c.parent_pid==GetCurrentProcessId())return false;
 Handle snapshot;snapshot.h=CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS,0);if(!snapshot.valid())return false;
 PROCESSENTRY32W entry{};entry.dwSize=sizeof entry;bool found=false;
 if(Process32FirstW(snapshot.h,&entry))do{if(entry.th32ProcessID==GetCurrentProcessId()){found=entry.th32ParentProcessID==c.parent_pid;break;}}while(Process32NextW(snapshot.h,&entry));
 if(!snapshot.close()||!found)return false;
 inputs.parent.h=OpenProcess(SYNCHRONIZE|PROCESS_QUERY_LIMITED_INFORMATION,FALSE,c.parent_pid);if(!inputs.parent.valid())return false;
 FILETIME created{},exit{},kernel{},user{};if(!GetProcessTimes(inputs.parent.h,&created,&exit,&kernel,&user))return false;
 return ((std::uint64_t(created.dwHighDateTime)<<32)|created.dwLowDateTime)==c.parent_creation&&parent_live();
}
bool binaries() noexcept {
 std::array<wchar_t,32768>path{};FixedText<4096>utf;HMODULE module{};
 auto n=GetModuleFileNameW(nullptr,path.data(),static_cast<DWORD>(path.size()));
 if(!n||n>=path.size()||!path_utf8({path.data(),n},utf)||!digest_file(utf.view(),inputs.parsed.host_sha.view()))return false;
 if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(&module_anchor),&module))return false;
 n=GetModuleFileNameW(module,path.data(),static_cast<DWORD>(path.size()));
 return n&&n<path.size()&&path_utf8({path.data(),n},utf)&&digest_file(utf.view(),inputs.parsed.dll_sha.view());
}
bool load_inputs() noexcept {
 // Caller serializes this pure/native test setup; never called at registration.
 const auto args=godot::OS::get_singleton()->get_cmdline_user_args();
 constexpr std::array<std::string_view,4>names={"--local-players-test-context","--local-players-test-context-sha256","--local-players-test-descriptor","--local-players-test-descriptor-sha256"};
 std::array<FixedText<4096>,4>v;unsigned seen{};
 // Root invokes the dedicated script with exactly these four user pairs.
 if(args.size()!=8)return false;
 for(std::int64_t i=0;i<args.size();i+=2){FixedText<64>key;if(!utf8(args[i],key))return false;
  auto it=std::find(names.begin(),names.end(),key.view());if(it==names.end())return false;
  const auto j=static_cast<unsigned>(it-names.begin());if((seen&(1U<<j))||!utf8(args[i+1],v[j]))return false;seen|=1U<<j;}
 if(seen!=15||!load(v[0].view(),v[1].view(),inputs.context)||!context()||inputs.parsed.descriptor_sha.view()!=v[3].view()||
  !load(v[2].view(),v[3].view(),inputs.descriptor)||!descriptor())return false;
 const auto root=inputs.descriptor_fields[1].view();
 return !at_or_within(v[0].view(),root)&&!at_or_within(v[2].view(),root)&&bind_parent()&&binaries();
}
bool matches(const Variant&input) noexcept {
 if(input.get_type()!=Variant::DICTIONARY)return false;Dictionary d=input;if(d.size()!=9)return false;
 // get() with exact String keys alone would also find StringName aliases.
 bool valid{};Variant iterator;
 if(input.iter_init(iterator,valid)){do{if(!valid)return false;Variant key=input.iter_get(iterator,valid);if(!valid||key.get_type()!=Variant::STRING)return false;}while(input.iter_next(iterator,valid));}
 if(!valid&&d.size()!=0)return false;
 for(std::size_t i=0;i<descriptor_keys.size();++i){const auto key=gs(descriptor_keys[i]);if(!d.has(key))return false;Variant value=d[key];
  if(value.get_type()!=Variant::STRING)return false;FixedText<4096>text;
  if(!utf8(String(value),text)||text.view()!=inputs.descriptor_fields[i].view())return false;}
 return true;
}
// Check shape/types/caps without trusting any field before control-file IO.
bool pure_shape(const Variant&input) noexcept {
 if(input.get_type()!=Variant::DICTIONARY)return false;Dictionary d=input;if(d.size()!=9)return false;
 bool valid{};Variant iterator;
 if(!input.iter_init(iterator,valid)||!valid)return false;
 do{Variant key=input.iter_get(iterator,valid);if(!valid||key.get_type()!=Variant::STRING)return false;}while(input.iter_next(iterator,valid));
 for(auto name:descriptor_keys){auto key=gs(name);if(!d.has(key))return false;Variant value=d[key];if(value.get_type()!=Variant::STRING)return false;
  FixedText<4096>text;if(!utf8(String(value),text))return false;}
 return true;
}
} // namespace

class LocalPlayersTest final:public godot::RefCounted {
 GDCLASS(LocalPlayersTest,godot::RefCounted)
 public:
 LocalPlayersTest():owner_(std::this_thread::get_id()),boundary_(std::in_place,LocalPlayersBoundary::Origin::isolated_test){++live_wrappers;}
 ~LocalPlayersTest() override {
  if(std::this_thread::get_id()!=owner_)std::terminate();
  if(configured_&&!joined_){if(!boundary_->begin_shutdown())std::terminate();while(!try_join())std::this_thread::sleep_for(std::chrono::milliseconds(1));}
  --live_wrappers;
 }
 bool configure_test_root(const Variant&descriptor_input) {
  if(std::this_thread::get_id()!=owner_||configured_||closed_||!pure_shape(descriptor_input))return false;
  // Only test controls are serialized here. No Service/registry/queue lock is
  // held through this separate prerequisite/factory; observer is always null.
  std::lock_guard lock(inputs_mutex);
  if(inputs.owner!=std::thread::id{}&&inputs.owner!=owner_)return false;
  if(inputs.failed||inputs.loading)return false;
  if(!inputs.loaded){inputs.owner=owner_;inputs.loading=true;
   const bool loaded=load_inputs();inputs.loading=false;if(!loaded){inputs.failed=true;return false;}inputs.loaded=true;}
  if(!matches(descriptor_input)||!parent_live())return false;
  // Root's actual descriptor hash/equality is established BEFORE this one
  // explicit read-only source/proof-parent/KnownFolder prerequisite.
  if(!inputs.trusted){inputs.trusted.emplace(TestRootFactory::prepare_prerequisite(inputs.parsed.source.view(),inputs.parsed.parent.view()));
   if(!inputs.trusted->valid()){inputs.failed=true;return false;}}
  if(inputs.next_ordinal>INT64_MAX)return false;
  const auto ordinal=inputs.next_ordinal++;
  auto cap=TestRootFactory::admit_bytes(inputs.descriptor.view(),inputs.parsed.descriptor_sha.view(),*inputs.trusted,nullptr,ordinal);
  if(!cap.valid())return false;
  auto access=cap.take_access();if(!access)return false;
  if(!boundary_->configure_test_access(std::move(*access))){
   // create(null) preserves this exact unconsumed token. This wrapper discards
   // it, never retries that minted service ID; no worker/root was created.
   if(!access->isolated_test())std::terminate();
   // SAME Boundary must establish never-created quiescence before these
   // consumed capability leases retire. Void release is NOT a join witness.
   if(!boundary_->begin_shutdown()||!boundary_->try_join()){
    capability_.emplace(std::move(cap));configured_=true;closed_=true;return false;
   }
   access.reset();cap.release_leases_after_join();boundary_.reset();
   boundary_.emplace(LocalPlayersBoundary::Origin::isolated_test);return false;
  }
  access.reset();capability_.emplace(std::move(cap));configured_=true;return true;
 }
 Dictionary start(){return boundary_->start();}
 Dictionary start_management(){return boundary_->start(true);}
 Dictionary submit(const Variant&v){return boundary_->submit(v);}
 Variant poll(const Variant&v=Variant(std::int64_t{8})){return boundary_->poll(v);}
 Variant status()const{return boundary_->status();}
 bool begin_shutdown(){if(std::this_thread::get_id()!=owner_)return false;const bool ok=boundary_->begin_shutdown();if(ok)closed_=true;return ok;}
 bool try_join(){if(std::this_thread::get_id()!=owner_)return false;const bool ok=boundary_->try_join();
  if(ok&&!joined_){if(capability_)capability_->release_leases_after_join();joined_=true;closed_=true;}return ok;}
 protected:
 static void _bind_methods(){using namespace godot;
  ClassDB::bind_method(D_METHOD("configure_test_root","descriptor"),&LocalPlayersTest::configure_test_root);
  ClassDB::bind_method(D_METHOD("start"),&LocalPlayersTest::start);
  ClassDB::bind_method(D_METHOD("start_management"),&LocalPlayersTest::start_management);
  ClassDB::bind_method(D_METHOD("submit","request"),&LocalPlayersTest::submit);
  ClassDB::bind_method(D_METHOD("poll","max_results"),&LocalPlayersTest::poll,DEFVAL(std::int64_t{8}));
  ClassDB::bind_method(D_METHOD("status"),&LocalPlayersTest::status);
  ClassDB::bind_method(D_METHOD("begin_shutdown"),&LocalPlayersTest::begin_shutdown);
  ClassDB::bind_method(D_METHOD("try_join"),&LocalPlayersTest::try_join);
 }
 private:
 const std::thread::id owner_;std::optional<LocalPlayersBoundary> boundary_;
 std::optional<Capability> capability_;bool configured_{},closed_{},joined_{};
};
namespace {
void initialize(godot::ModuleInitializationLevel level){if(level==godot::MODULE_INITIALIZATION_LEVEL_SCENE)godot::ClassDB::register_class<LocalPlayersTest>();}
void terminate(godot::ModuleInitializationLevel level){
 if(level!=godot::MODULE_INITIALIZATION_LEVEL_SCENE)return;
 // A void terminator cannot authorize unload with live owner objects/workers.
 // The focused script explicitly releases its objects after real joined close.
 while(!bridge::LocalPlayers::close_all()||live_wrappers.load()!=0)std::this_thread::sleep_for(std::chrono::milliseconds(1));
 if(inputs.trusted&&!inputs.trusted->retire())std::terminate();
 if(!inputs.context.handle.close()||!inputs.descriptor.handle.close()||!inputs.parent.close())std::terminate();
}
}
} // namespace flight::local_players::testing
extern "C" GDExtensionBool GDE_EXPORT flight_local_players_test_init(
 GDExtensionInterfaceGetProcAddress api,GDExtensionClassLibraryPtr library,GDExtensionInitialization*initialization){
 godot::GDExtensionBinding::InitObject object(api,library,initialization);
 object.register_initializer(flight::local_players::testing::initialize);
 object.register_terminator(flight::local_players::testing::terminate);
 object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);return object.init();
}
