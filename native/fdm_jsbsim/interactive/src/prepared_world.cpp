#include <flight/interactive/prepared_world.hpp>
#include <flight/ground/grid_payload.hpp>
#include "prepared_world_catalog.hpp"
#include "validation.hpp" // Accepted private dyadic/FENV kernel; no public API change.
#include "canonical_frame.hpp"
#include <algorithm>
#include <array>
#include <bit>
#include <charconv>
#include <fstream>
#include <iomanip>
#include <limits>
#include <map>
#include <set>
#include <sstream>
#include <string_view>
#include <utility>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

namespace flight::interactive {
namespace grid=flight::ground::grid::v1;
namespace exact=flight::ground::grid::detail;
namespace cat=generated_world;
namespace {
using Bytes=std::vector<std::uint8_t>;
[[noreturn]] void refuse(const char* why) {throw std::invalid_argument(why);}
void require(bool condition,const char* why) {if(!condition)refuse(why);}
double finite_word(std::uint64_t word) {const auto x=std::bit_cast<double>(word);require(std::isfinite(x),"Nonfinite catalog scalar");return x;}
c::GeodeticPosition position(const cat::GeoWords& p) {return {finite_word(p.latitude_rad),finite_word(p.longitude_rad),finite_word(p.ellipsoid_height_m)};}
double primitive(double value) {volatile double result=value;return result;}
double frame_dot(Vec a,Vec b) {
  const auto t0=primitive(a[0]*b[0]),t1=primitive(a[1]*b[1]);
  const auto s01=primitive(t0+t1),t2=primitive(a[2]*b[2]);return primitive(s01+t2);
}
using exact::canonical_frame::east_at;using exact::canonical_frame::up_at;using exact::canonical_frame::south_at;
bool finite(Vec p) {return std::all_of(p.begin(),p.end(),[](double x){return std::isfinite(x);});}
Vec projection(c::GeodeticPosition anchor,c::EcefPosition point) {
  require(exact::fp_environment()&&c::valid(anchor)&&c::finite(point),"Unsupported geographic projection/environment");
  const auto origin=c::geodesy::to_ecef(anchor);require(origin.has_value(),"Anchor conversion refused");
  const Vec delta{primitive(point.x-origin->x),primitive(point.y-origin->y),primitive(point.z-origin->z)};
  const Vec result{frame_dot(delta,east_at(anchor)),frame_dot(delta,up_at(anchor)),frame_dot(delta,south_at(anchor))};
  require(finite(result),"Nonfinite canonical projection");return result;
}

// Strict, bounded data parser. No extensions, BOM, duplicate decoded keys,
// invalid UTF-8/surrogates, nonfinite numeric conversion or partial success.
struct Json {
  enum class Kind {null_value,boolean,number,string,array,object};
  Kind kind{Kind::null_value};bool boolean{};double number{};std::string string;
  std::vector<Json> array;std::map<std::string,Json,std::less<>> object;
};
void utf8(std::string_view s) {
  require(!(s.size()>=3&&static_cast<unsigned char>(s[0])==0xef&&static_cast<unsigned char>(s[1])==0xbb&&static_cast<unsigned char>(s[2])==0xbf),"JSON/text BOM refused");
  for(std::size_t i=0;i<s.size();) {
    const auto a=static_cast<unsigned char>(s[i++]);if(a<0x80)continue;
    unsigned extra=0;std::uint32_t cp=0,minimum=0;
    if(a>=0xc2&&a<=0xdf){extra=1;cp=a&0x1fU;minimum=0x80;}
    else if(a>=0xe0&&a<=0xef){extra=2;cp=a&0x0fU;minimum=0x800;}
    else if(a>=0xf0&&a<=0xf4){extra=3;cp=a&7U;minimum=0x10000;}
    else refuse("Invalid UTF-8 lead byte");
    require(extra<=s.size()-i,"Truncated UTF-8");
    for(unsigned j=0;j<extra;++j){const auto b=static_cast<unsigned char>(s[i++]);require((b&0xc0U)==0x80U,"Invalid UTF-8 continuation");cp=(cp<<6)|(b&0x3fU);}
    require(cp>=minimum&&cp<=0x10ffff&&!(cp>=0xd800&&cp<=0xdfff),"Invalid UTF-8 code point");
  }
}
class Parser {
 public:
  Parser(std::string_view input,std::size_t depth,std::size_t values):input_(input),max_depth_(depth),max_values_(values) {utf8(input);}
  Json parse() {auto result=value(1);space();require(offset_==input_.size(),"Trailing JSON data");return result;}
 private:
  std::string_view input_;std::size_t offset_{},count_{},max_depth_,max_values_;
  void space(){while(offset_<input_.size()&&(input_[offset_]==' '||input_[offset_]=='\t'||input_[offset_]=='\r'||input_[offset_]=='\n'))++offset_;}
  char take(){require(offset_<input_.size(),"Truncated JSON");return input_[offset_++];}
  bool consume(char ch){space();if(offset_<input_.size()&&input_[offset_]==ch){++offset_;return true;}return false;}
  static unsigned nibble(char ch){if(ch>='0'&&ch<='9')return static_cast<unsigned>(ch-'0');if(ch>='a'&&ch<='f')return static_cast<unsigned>(ch-'a'+10);if(ch>='A'&&ch<='F')return static_cast<unsigned>(ch-'A'+10);refuse("Invalid JSON unicode escape");}
  std::uint32_t code(){std::uint32_t cp=0;for(unsigned i=0;i<4;++i)cp=(cp<<4)|nibble(take());return cp;}
  static void append(std::string& out,std::uint32_t cp) {
    if(cp<0x80)out.push_back(static_cast<char>(cp));
    else if(cp<0x800){out.push_back(static_cast<char>(0xc0U|(cp>>6)));out.push_back(static_cast<char>(0x80U|(cp&0x3fU)));}
    else if(cp<0x10000){out.push_back(static_cast<char>(0xe0U|(cp>>12)));out.push_back(static_cast<char>(0x80U|((cp>>6)&0x3fU)));out.push_back(static_cast<char>(0x80U|(cp&0x3fU)));}
    else {out.push_back(static_cast<char>(0xf0U|(cp>>18)));out.push_back(static_cast<char>(0x80U|((cp>>12)&0x3fU)));out.push_back(static_cast<char>(0x80U|((cp>>6)&0x3fU)));out.push_back(static_cast<char>(0x80U|(cp&0x3fU)));}
  }
  std::string string() {
    require(take()=='"',"Expected JSON string");std::string out;
    for(;;){const auto ch=take();if(ch=='"')return out;require(static_cast<unsigned char>(ch)>=0x20,"Unescaped JSON control");
      if(ch!='\\'){out.push_back(ch);continue;}
      switch(take()) {
        case '"':out.push_back('"');break;case '\\':out.push_back('\\');break;case '/':out.push_back('/');break;
        case 'b':out.push_back('\b');break;case 'f':out.push_back('\f');break;case 'n':out.push_back('\n');break;case 'r':out.push_back('\r');break;case 't':out.push_back('\t');break;
        case 'u':{auto cp=code();if(cp>=0xd800&&cp<=0xdbff){require(take()=='\\'&&take()=='u',"Missing low surrogate");const auto low=code();require(low>=0xdc00&&low<=0xdfff,"Invalid low surrogate");cp=0x10000+((cp-0xd800)<<10)+(low-0xdc00);}else require(!(cp>=0xdc00&&cp<=0xdfff),"Unpaired low surrogate");append(out,cp);break;}
        default:refuse("Invalid JSON escape");
      }
    }
  }
  Json value(std::size_t depth) {
    require(depth<=max_depth_&&++count_<=max_values_,"JSON depth/value budget");space();require(offset_<input_.size(),"Missing JSON value");Json out;
    const auto ch=input_[offset_];
    if(ch=='{'){++offset_;out.kind=Json::Kind::object;if(consume('}'))return out;for(;;){space();require(offset_<input_.size()&&input_[offset_]=='"',"Invalid JSON member");auto key=string();require(consume(':'),"Missing JSON colon");auto child=value(depth+1);require(out.object.emplace(std::move(key),std::move(child)).second,"Duplicate JSON member");if(consume('}'))return out;require(consume(','),"Missing JSON member separator");}}
    if(ch=='['){++offset_;out.kind=Json::Kind::array;if(consume(']'))return out;for(;;){out.array.push_back(value(depth+1));if(consume(']'))return out;require(consume(','),"Missing JSON array separator");}}
    if(ch=='"'){out.kind=Json::Kind::string;out.string=string();return out;}
    for(const auto literal:{std::string_view("null"),std::string_view("true"),std::string_view("false")})if(input_.substr(offset_,literal.size())==literal){offset_+=literal.size();if(literal!="null"){out.kind=Json::Kind::boolean;out.boolean=literal=="true";}return out;}
    const auto begin=offset_;if(ch=='-')++offset_;
    require(offset_<input_.size(),"Truncated JSON number");
    if(input_[offset_]=='0')++offset_;else{require(input_[offset_]>='1'&&input_[offset_]<='9',"Invalid JSON number");while(offset_<input_.size()&&input_[offset_]>='0'&&input_[offset_]<='9')++offset_;}
    if(offset_<input_.size()&&input_[offset_]=='.'){++offset_;const auto first=offset_;while(offset_<input_.size()&&input_[offset_]>='0'&&input_[offset_]<='9')++offset_;require(offset_>first,"Empty JSON fraction");}
    if(offset_<input_.size()&&(input_[offset_]=='e'||input_[offset_]=='E')){++offset_;if(offset_<input_.size()&&(input_[offset_]=='+'||input_[offset_]=='-'))++offset_;const auto first=offset_;while(offset_<input_.size()&&input_[offset_]>='0'&&input_[offset_]<='9')++offset_;require(offset_>first,"Empty JSON exponent");}
    const auto converted=std::from_chars(input_.data()+begin,input_.data()+offset_,out.number,std::chars_format::general);
    require(converted.ec==std::errc{}&&converted.ptr==input_.data()+offset_&&std::isfinite(out.number),"Nonfinite/unrepresentable JSON number");out.kind=Json::Kind::number;return out;
  }
};
const Json& field(const Json& value,std::string_view name) {require(value.kind==Json::Kind::object,"Expected JSON object");const auto it=value.object.find(name);require(it!=value.object.end(),"Missing closed JSON member");return it->second;}
void keys(const Json& value,std::initializer_list<std::string_view> names) {require(value.kind==Json::Kind::object&&value.object.size()==names.size(),"Unexpected closed JSON member");for(const auto name:names)(void)field(value,name);}
std::string_view text(const Json& value) {require(value.kind==Json::Kind::string,"Expected JSON String");return value.string;}
void equals(const Json& value,std::string_view expected) {require(text(value)==expected,"Pinned String mismatch");}
double number(const Json& value) {require(value.kind==Json::Kind::number,"Expected JSON number");return value.number;}
std::uint64_t integer(const Json& value,std::uint64_t maximum=2147483647) {const auto x=number(value);require(x>=0&&x<=static_cast<double>(maximum)&&std::floor(x)==x,"Expected bounded JSON integer");return static_cast<std::uint64_t>(x);}
const std::vector<Json>& array(const Json& value,std::size_t count) {require(value.kind==Json::Kind::array&&value.array.size()==count,"Pinned JSON array length");return value.array;}
std::uint64_t binary64(const Json& value) {
  keys(value,{"$binary64_le"});const auto encoded=text(field(value,"$binary64_le"));require(encoded.size()==16,"Invalid B64 tag size");std::uint64_t bits=0;
  for(unsigned i=0;i<8;++i){unsigned byte=0;for(unsigned j=0;j<2;++j){const auto ch=encoded[2*i+j];require((ch>='0'&&ch<='9')||(ch>='a'&&ch<='f'),"Noncanonical B64 tag");byte=(byte<<4)|static_cast<unsigned>(ch<='9'?ch-'0':ch-'a'+10);}bits|=static_cast<std::uint64_t>(byte)<<(8*i);}
  (void)finite_word(bits);return bits;
}
void geo(const Json& value,const cat::GeoWords& expected) {keys(value,{"latitude_rad","longitude_rad","ellipsoid_height_m"});require(binary64(field(value,"latitude_rad"))==expected.latitude_rad&&binary64(field(value,"longitude_rad"))==expected.longitude_rad&&binary64(field(value,"ellipsoid_height_m"))==expected.ellipsoid_height_m,"Pinned geodetic words differ");}
void model(const Json& value,const cat::Model& expected) {keys(value,{"id","version","backend_model"});equals(field(value,"id"),expected.id);equals(field(value,"version"),expected.version);equals(field(value,"backend_model"),expected.backend_model);}
void clock(const Json& value,const cat::Clock& expected) {keys(value,{"purpose","tick_rate_hz"});equals(field(value,"purpose"),expected.purpose);require(integer(field(value,"tick_rate_hz"))==expected.tick_rate_hz,"Pinned clock differs");}
std::string_view view(const Bytes& bytes) {return {reinterpret_cast<const char*>(bytes.data()),bytes.size()};}
} // namespace

class PreparedWorld::Impl {
 public:
  std::filesystem::path model_root;
  std::array<Bytes,7> bytes;
  // Windows read/no-delete handles bind the model files used by LoadModel and
  // their physical directory chain until the last session/worker reference.
  std::vector<std::shared_ptr<const void>> retained_handles;
  std::shared_ptr<const grid::PreparedGrid> provider;
  v1::Identity identity;
  double minimum{},maximum{};
};
PreparedWorld::PreparedWorld(std::unique_ptr<const Impl> state):impl_(std::move(state)) {}
PreparedWorld::~PreparedWorld()=default;
std::shared_ptr<const v1::SurfaceProvider> PreparedWorld::provider() const {return impl_->provider;}
v1::Identity PreparedWorld::identity() const {return impl_->identity;}
c::GeodeticPosition PreparedWorld::anchor() const {return position(cat::kawo_entry.world_anchor);}
c::GeodeticPosition PreparedWorld::start_position() const {return position(cat::kawo_start.position);}
Vec PreparedWorld::start_rpy() const {const auto& r=cat::kawo_start.orientation_rpy_ned_rad;return {finite_word(r.roll),finite_word(r.pitch),finite_word(r.yaw)};}
std::array<c::BodyPosition,3> PreparedWorld::nominal_arms() {
  // FGXMLElement M->FT 3.2808399, FT->IN12, triplet products; FGLGear
  // Ts2b signed1/12 and .3048m/ft. Independently predicted c414 references.
  return {{{finite_word(0x4000000000687420ULL),0,finite_word(0x3ff0000000687420ULL)},
           {finite_word(0xbff0000000687420ULL),finite_word(0xbff4cccccd5496f6ULL),finite_word(0x3ff0000000687420ULL)},
           {finite_word(0xbff0000000687420ULL),finite_word(0x3ff4cccccd5496f6ULL),finite_word(0x3ff0000000687420ULL)}}};
}
bool PreparedWorld::bound_to(const std::filesystem::path& root) const {
  return root.is_absolute()&&root.lexically_normal()==impl_->model_root&&impl_->provider&&v1::same(impl_->identity,impl_->provider->identity())&&
    impl_->identity.world.id==cat::kawo_entry.world.id&&impl_->identity.world.version==cat::kawo_entry.world.version&&impl_->identity.world.sha256==cat::kawo_entry.world.sha256&&
    impl_->identity.prepared_surface_sha256==cat::kawo_entry.files[0].sha256&&impl_->identity.generation==1;
}
Vec PreparedWorld::project(c::EcefPosition point) const {return projection(anchor(),point);}
PreparedWorld::Ray PreparedWorld::ray(c::GeodeticPosition anchor,c::GeodeticPosition query) {
  require(exact::fp_environment()&&c::valid(anchor)&&c::valid(query),"Invalid geographic ray/environment");
  const auto frame=exact::canonical_frame::make(anchor);require(frame.has_value(),"Geographic frame conversion failed");
  const auto operands=exact::canonical_frame::query_ray(*frame,query);require(operands.has_value(),"Geographic core ray conversion failed");
  return {operands->a,operands->direction};
}
grid::Rectangle PreparedWorld::rectangle(Vec center) {
  require(exact::fp_environment()&&finite(center)&&center[1]>=-1024&&center[1]<=8192,"Geographic CG altitude/environment domain");
  const auto outward=[](double value,bool upper){
    const auto mathematical=exact::Dyadic::binary64(value)+(upper?exact::Dyadic::integer(40):exact::Dyadic::integer(40).negated());
    double result=primitive(value+(upper?40.0:-40.0));require(std::isfinite(result),"Nonfinite readiness rectangle");
    const auto order=compare(exact::Dyadic::binary64(result),mathematical);
    if((upper&&order<0)||(!upper&&order>0))result=std::nextafter(result,upper?std::numeric_limits<double>::infinity():-std::numeric_limits<double>::infinity());
    require(std::isfinite(result),"Unbounded readiness rectangle");return result;
  };
  return {outward(center[0],false),outward(center[2],false),outward(center[0],true),outward(center[2],true)};
}
bool PreparedWorld::distance_within(Vec a,Vec b,double limit) {
  if(!exact::fp_environment()||!finite(a)||!finite(b)||!std::isfinite(limit)||limit<0)return false;
  auto sum=exact::Dyadic::integer(0);
  for(std::size_t i=0;i<3;++i){const auto delta=exact::Dyadic::binary64(a[i])-exact::Dyadic::binary64(b[i]);sum=sum+delta*delta;}
  const auto bound=exact::Dyadic::binary64(limit);return compare(sum,bound*bound)<=0;
}
bool PreparedWorld::support_within(const Ray& r,double minimum,double maximum,const grid::Rectangle& rect) {
  if(!exact::fp_environment()||!finite(r.a)||!finite(r.d)||!std::isfinite(minimum)||!std::isfinite(maximum)||minimum>maximum||minimum< -1000||maximum>4096||
    !std::isfinite(rect.east_min_m)||!std::isfinite(rect.east_max_m)||!std::isfinite(rect.south_min_m)||!std::isfinite(rect.south_max_m)||rect.east_min_m>rect.east_max_m||rect.south_min_m>rect.south_max_m||
    std::abs(r.d[0])>grid::max_ray_horizontal_component||std::abs(r.d[2])>grid::max_ray_horizontal_component||r.d[1]<grid::min_ray_up_component)return false;
  const auto dy=exact::Dyadic::binary64(r.d[1]),ay=exact::Dyadic::binary64(r.a[1]);
  const auto low=exact::Dyadic::binary64(minimum)-exact::Dyadic::binary64(0x1p-6),high=exact::Dyadic::binary64(maximum)+exact::Dyadic::binary64(0x1p-6);
  for(const auto axis:{0U,2U}){
    const auto a=exact::Dyadic::binary64(r.a[axis]),d=exact::Dyadic::binary64(r.d[axis]);
    auto lo=a*dy+d*(low-ay),hi=a*dy+d*(high-ay);if(compare(lo,hi)>0)std::swap(lo,hi);
    const auto lower=exact::Dyadic::binary64(axis==0?rect.east_min_m:rect.south_min_m)*dy,upper=exact::Dyadic::binary64(axis==0?rect.east_max_m:rect.south_max_m)*dy;
    if(compare(lo,lower)<0||compare(hi,upper)>0)return false;
  }
  return true;
}
std::optional<PreparedWorld::Readiness> PreparedWorld::certify(c::EcefPosition cg) const {
  try {
    if(!bound_to(impl_->model_root)){return std::nullopt;}
    Readiness result;result.owner_=this;result.center_=project(cg);result.rectangle_=rectangle(result.center_);
    if(impl_->provider->coverage(result.rectangle_)!=grid::Coverage::ready){return std::nullopt;}
    return result;
  }catch(...){return std::nullopt;}
}
bool PreparedWorld::allows(const Readiness& ready,c::GeodeticPosition query) const noexcept {
  try {
    if(ready.owner_!=this||!bound_to(impl_->model_root)||!c::valid(query))return false;
    const auto point=c::geodesy::to_ecef(query);if(!point||!distance_within(ready.center_,project(*point),4))return false;
    return support_within(ray(anchor(),query),impl_->minimum,impl_->maximum,ready.rectangle_);
  }catch(...){return false;}
}
bool PreparedWorld::motion_within(c::EcefPosition previous,c::EcefPosition next,double limit) const noexcept {
  try{return distance_within(project(previous),project(next),limit);}catch(...){return false;}
}
void PreparedWorld::check_json(std::string_view input,std::size_t depth,std::size_t values) {(void)Parser(input,depth,values).parse();}
// Same reviewed first-party SHA-256 algorithm as fdm/model.cpp. This private
// bounded-byte variant permits the separately bounded resident payload; the
// historical model hashing intake and its 4MiB limit are unchanged.
std::string PreparedWorld::digest(std::span<const std::uint8_t> bytes) {
  constexpr std::array<std::uint32_t, 64> k{0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,
    0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,
    0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
  std::array<std::uint32_t, 8> hash{0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
  if (bytes.size() > 288ULL * 1024 * 1024) throw std::invalid_argument("SHA input exceeds resident pack bound");
  std::vector<std::uint8_t> padded(bytes.begin(), bytes.end()); padded.push_back(0x80);
  while (padded.size() % 64 != 56) padded.push_back(0);
  const auto bits = static_cast<std::uint64_t>(bytes.size()) * 8;
  for (int i = 7; i >= 0; --i) padded.push_back(static_cast<std::uint8_t>(bits >> (i * 8)));
  for (std::size_t offset = 0; offset < padded.size(); offset += 64) {
    std::array<std::uint32_t, 64> w{};
    for (unsigned i = 0; i < 16; ++i) for (unsigned j = 0; j < 4; ++j) w[i] = (w[i] << 8) | padded[offset + 4 * i + j];
    for (unsigned i = 16; i < 64; ++i) {
      const auto s0 = std::rotr(w[i-15],7)^std::rotr(w[i-15],18)^(w[i-15]>>3);
      const auto s1 = std::rotr(w[i-2],17)^std::rotr(w[i-2],19)^(w[i-2]>>10); w[i]=w[i-16]+s0+w[i-7]+s1;
    }
    auto [a,b,c,d,e,f,g,h] = hash;
    for (unsigned i=0;i<64;++i) {
      const auto t1=h+(std::rotr(e,6)^std::rotr(e,11)^std::rotr(e,25))+((e&f)^(~e&g))+k[i]+w[i];
      const auto t2=(std::rotr(a,2)^std::rotr(a,13)^std::rotr(a,22))+((a&b)^(a&c)^(b&c));
      h=g;g=f;f=e;e=d+t1;d=c;c=b;b=a;a=t1+t2;
    }
    hash[0]+=a;hash[1]+=b;hash[2]+=c;hash[3]+=d;hash[4]+=e;hash[5]+=f;hash[6]+=g;hash[7]+=h;
  }
  std::ostringstream out; out << std::hex << std::setfill('0'); for (auto value : hash) out << std::setw(8) << value; return out.str();
}

namespace {
// Hold directory handles while enumerating/reading the fixed roster. On
// Windows deny deletion/rename and read each file once through a no-reparse,
// no-write-share handle. Hash exactly the owned bytes, never a second read.
class Handle {
 public:
#ifdef _WIN32
  HANDLE value{INVALID_HANDLE_VALUE};
  explicit Handle(HANDLE h):value(h){require(value!=INVALID_HANDLE_VALUE,"Resident ordinary path open failed");}
  ~Handle(){if(value!=INVALID_HANDLE_VALUE)CloseHandle(value);}
#else
  int value{-1};
  explicit Handle(int h):value(h){require(value>=0,"Resident ordinary path open failed");}
  ~Handle(){if(value>=0)::close(value);}
#endif
  Handle(const Handle&)=delete;Handle& operator=(const Handle&)=delete;
  Handle(Handle&& other)noexcept:value(other.value){
#ifdef _WIN32
    other.value=INVALID_HANDLE_VALUE;
#else
    other.value=-1;
#endif
  }
};
Handle ordinary(const std::filesystem::path& path,bool directory) {
#ifdef _WIN32
  const auto access=directory?(FILE_READ_ATTRIBUTES|FILE_LIST_DIRECTORY):(GENERIC_READ|FILE_READ_ATTRIBUTES);
  Handle handle(CreateFileW(path.c_str(),access,directory?(FILE_SHARE_READ|FILE_SHARE_WRITE):FILE_SHARE_READ,nullptr,OPEN_EXISTING,
    FILE_FLAG_OPEN_REPARSE_POINT|(directory?FILE_FLAG_BACKUP_SEMANTICS:FILE_FLAG_SEQUENTIAL_SCAN),nullptr));
  BY_HANDLE_FILE_INFORMATION info{};
  require(GetFileType(handle.value)==FILE_TYPE_DISK&&GetFileInformationByHandle(handle.value,&info)!=0,"Resident path is not an ordinary disk object");
  require((info.dwFileAttributes&FILE_ATTRIBUTE_REPARSE_POINT)==0&&((info.dwFileAttributes&FILE_ATTRIBUTE_DIRECTORY)!=0)==directory,"Resident reparse/special/type mismatch");
#else
  Handle handle(::open(path.c_str(),O_RDONLY|O_NOFOLLOW|(directory?O_DIRECTORY:0)));struct stat info{};
  require(::fstat(handle.value,&info)==0&&(directory?S_ISDIR(info.st_mode):S_ISREG(info.st_mode)),"Resident path is not ordinary");
#endif
  return handle;
}
std::filesystem::path absolute_ordinary_root(const std::filesystem::path& input,std::vector<Handle>& directories) {
  require(input.is_absolute(),"Resident model root must be absolute");
  for(const auto& part:input.relative_path())require(part!="."&&part!=".."&&!part.empty(),"Resident path traversal refused");
  const auto root=input.lexically_normal();auto current=root.root_path();directories.push_back(ordinary(current,true));
  for(const auto& part:root.relative_path()){current/=part;directories.push_back(ordinary(current,true));}
  require(std::filesystem::canonical(root)==root,"Resident model root alias refused");return root;
}
Bytes read_owned(const std::filesystem::path& path,std::uint64_t expected,std::uint64_t limit,std::vector<std::shared_ptr<const void>>* retain=nullptr) {
  require(expected>0&&expected<=limit&&limit<=288ULL*1024*1024,"Resident file byte bound");auto handle=ordinary(path,false);
#ifdef _WIN32
  LARGE_INTEGER size{};require(GetFileSizeEx(handle.value,&size)!=0&&size.QuadPart>=0&&static_cast<std::uint64_t>(size.QuadPart)==expected,"Resident file size mismatch");
#else
  struct stat size{};require(::fstat(handle.value,&size)==0&&size.st_size>=0&&static_cast<std::uint64_t>(size.st_size)==expected,"Resident file size mismatch");
#endif
  Bytes bytes(static_cast<std::size_t>(expected));std::size_t offset=0;
  while(offset<bytes.size()){
    const auto count=std::min<std::size_t>(bytes.size()-offset,1024*1024);
#ifdef _WIN32
    DWORD actual=0;require(ReadFile(handle.value,bytes.data()+offset,static_cast<DWORD>(count),&actual,nullptr)!=0&&actual>0&&actual<=count,"Resident byte read failed");offset+=actual;
#else
    const auto actual=::read(handle.value,bytes.data()+offset,count);require(actual>0&&static_cast<std::size_t>(actual)<=count,"Resident byte read failed");offset+=static_cast<std::size_t>(actual);
#endif
  }
  std::uint8_t tail{};
#ifdef _WIN32
  DWORD count=0;require(ReadFile(handle.value,&tail,1,&count,nullptr)!=0&&count==0,"Resident file changed size while reading");
#else
  require(::read(handle.value,&tail,1)==0,"Resident file changed size while reading");
#endif
  if(retain){retain->push_back(std::make_shared<Handle>(std::move(handle)));}
  return bytes;
}
void roster(const std::filesystem::path& root) {
  std::set<std::string> expected{"world.json","ground.fgrd","airport.json","dossier.json","compile-receipt.json","start-ready34.json","NOTICE.txt"};
  for(const auto& entry:std::filesystem::directory_iterator(root)){
    const auto status=entry.symlink_status();const auto name=entry.path().filename().generic_string();
    require(std::filesystem::is_regular_file(status)&&!std::filesystem::is_symlink(status)&&expected.erase(name)==1,"Extra/aliased resident pack object");
  }
  require(expected.empty(),"Incomplete resident pack");
}
void file_record(const Json& value,const cat::File& expected) {
  keys(value,{"path","sha256","bytes","role"});equals(field(value,"path"),expected.path);equals(field(value,"sha256"),expected.sha256);
  require(integer(field(value,"bytes"))==expected.bytes,"Resident manifest byte count differs");equals(field(value,"role"),expected.role);
}
void recipe(const Json& value) {
  const auto& expected=cat::kawo_start;
  keys(value,{"schema","id","selector","model_identity","named_start","wind_profile","seed","clock","position","orientation_rpy_ned_rad"});
  equals(field(value,"schema"),expected.schema);equals(field(value,"id"),expected.id);equals(field(value,"selector"),expected.selector);model(field(value,"model_identity"),expected.model_identity);
  equals(field(value,"named_start"),expected.named_start);equals(field(value,"wind_profile"),expected.wind_profile);equals(field(value,"seed"),expected.seed);clock(field(value,"clock"),expected.clock);geo(field(value,"position"),expected.position);
  const auto& rpy=field(value,"orientation_rpy_ned_rad");keys(rpy,{"roll","pitch","yaw"});
  require(binary64(field(rpy,"roll"))==expected.orientation_rpy_ned_rad.roll&&binary64(field(rpy,"pitch"))==expected.orientation_rpy_ned_rad.pitch&&binary64(field(rpy,"yaw"))==expected.orientation_rpy_ned_rad.yaw,"Resident recipe orientation differs");
  const auto p=position(expected.position);require(c::valid(p),"Invalid canonical recipe geodetic position");
  const auto roll=finite_word(expected.orientation_rpy_ned_rad.roll),pitch=finite_word(expected.orientation_rpy_ned_rad.pitch),yaw=finite_word(expected.orientation_rpy_ned_rad.yaw);
  require(std::abs(roll)<=.2&&std::abs(pitch)<=.2&&yaw>=0&&yaw<2*c::pi,"Resident recipe orientation domain");
}
void manifest(const Json& value) {
  const auto& entry=cat::kawo_entry;
  keys(value,{"type","schema_version","id","version","compatible_schema_version","evidence","sources","files","coverage","horizontal_datum","vertical_datum","geoid","magnetic_model","effective_from","effective_until","data_status","products","update_policy"});
  equals(field(value,"type"),"WorldPackage");require(integer(field(value,"schema_version"))==1&&integer(field(value,"compatible_schema_version"))==1,"Resident manifest schema mismatch");equals(field(value,"id"),entry.world.id);equals(field(value,"version"),entry.world.version);
  const auto& evidence=field(value,"evidence");keys(evidence,{"status","report_ids","source_ids"});equals(field(evidence,"status"),"prototype");
  const auto& sources=field(value,"sources");require(sources.kind==Json::Kind::array&&!sources.array.empty()&&sources.array.size()<=1024,"Resident manifest source count");
  for(const auto& source:sources.array){keys(source,{"id","revision","locator","sha256","rights","license","applicability","effective_from","effective_until"});require(v1::hash(text(field(source,"sha256"))),"Invalid resident source digest");}
  const auto& files=array(field(value,"files"),entry.files.size());for(std::size_t i=0;i<files.size();++i)file_record(files[i],entry.files[i]);
  const auto& coverage=field(value,"coverage");keys(coverage,{"south_rad","north_rad","west_rad","east_rad","crosses_antimeridian"});
  const auto south=number(field(coverage,"south_rad")),north=number(field(coverage,"north_rad")),west=number(field(coverage,"west_rad")),east=number(field(coverage,"east_rad"));
  require(south>=-c::pi/2&&north<=c::pi/2&&south<=north&&west>=-c::pi&&east<=c::pi&&west<=east,"Invalid resident geographic coverage");
  require(field(coverage,"crosses_antimeridian").kind==Json::Kind::boolean&&!field(coverage,"crosses_antimeridian").boolean,"Unexpected resident antimeridian");
  equals(field(value,"horizontal_datum"),"wgs84");equals(field(value,"vertical_datum"),"wgs84-ellipsoid");
  require(field(value,"geoid").kind==Json::Kind::null_value&&field(value,"magnetic_model").kind==Json::Kind::null_value,"Resident auxiliary model forbidden");
  const auto& products=array(field(value,"products"),2);equals(products[0],"terrain");equals(products[1],"airport");
}
void compiled_geometry(const Json& value,const grid::Definition& definition) {
  const auto& expected=cat::kawo_geometry;
  keys(value,{"schema","source_airport_sha256","ground_payload_sha256","world_anchor","position_frame","bearing_reference","runways"});
  equals(field(value,"schema"),expected.schema);equals(field(value,"source_airport_sha256"),expected.source_airport_sha256);equals(field(value,"ground_payload_sha256"),expected.ground_payload_sha256);geo(field(value,"world_anchor"),expected.world_anchor);equals(field(value,"position_frame"),expected.position_frame);equals(field(value,"bearing_reference"),expected.bearing_reference);
  const auto& runways=array(field(value,"runways"),2);require(definition.polygons.size()==2,"Resident runway polygon count differs");
  for(std::size_t i=0;i<2;++i){const auto& runway=runways[i];const auto& row=expected.runways[i];const auto& polygon=definition.polygons[i];
    keys(runway,{"id","material_polygon_id","published_length_m","width_m","footprint_mm","ends"});equals(field(runway,"id"),row.id);equals(field(runway,"material_polygon_id"),row.material_polygon_id);
    require(binary64(field(runway,"published_length_m"))==row.published_length_m&&binary64(field(runway,"width_m"))==row.width_m&&finite_word(row.published_length_m)>0&&finite_word(row.width_m)>0,"Resident runway dimensions differ");
    require(polygon.id==row.material_polygon_id&&polygon.material_index==1&&polygon.priority==100&&polygon.vertices.size()==4,"Resident runway material relation differs");
    const auto& ring=array(field(runway,"footprint_mm"),4);
    for(std::size_t j=0;j<4;++j){const auto& xy=array(ring[j],2);for(std::size_t axis=0;axis<2;++axis){const auto coordinate=number(xy[axis]);require(coordinate>=-8192000&&coordinate<=8192000&&std::floor(coordinate)==coordinate&&coordinate==row.footprint_mm[j][axis],"Resident runway ring differs");}require(polygon.vertices[j].east_mm==row.footprint_mm[j][0]&&polygon.vertices[j].south_mm==row.footprint_mm[j][1],"Resident payload footprint differs");}
    const auto& ends=array(field(runway,"ends"),2);for(std::size_t j=0;j<2;++j){keys(ends[j],{"designator","eus_m","published_true_bearing_deg"});equals(field(ends[j],"designator"),row.ends[j].designator);const auto& eus=array(field(ends[j],"eus_m"),3);for(std::size_t axis=0;axis<3;++axis)require(binary64(eus[axis])==row.ends[j].eus_m[axis],"Resident physical end differs");require(binary64(field(ends[j],"published_true_bearing_deg"))==row.ends[j].published_true_bearing_deg,"Resident source bearing differs");}
  }
}
void receipt(const Json& value,const grid::Definition& definition,double minimum,double maximum) {
  // The complete accepted receipt is itself an exact raw catalog pin. This
  // repeats strict bounded syntax, closed record keys and runtime cross-links;
  // it does not re-run the offline transform/source/rights qualification.
  keys(value,{"schema","contract_id","quality","inputs","tools","operations","frame","grid","mosaic","construction","validation","airport_geometry","outputs","limitations"});
  equals(field(value,"schema"),"KawoTerrainCompileReceipt/v1");equals(field(value,"contract_id"),"kawo-approx-terrain-v1");equals(field(value,"quality"),"approximate-unverified-frame-v1");
  const auto& inputs=array(field(value,"inputs"),7);for(const auto& input:inputs)keys(input,{"role","locator","sha256","bytes"});
  equals(field(inputs[0],"role"),"airport");equals(field(inputs[0],"sha256"),cat::kawo_entry.files[1].sha256);require(integer(field(inputs[0],"bytes"))==cat::kawo_entry.files[1].bytes,"Compiler airport byte relation");
  equals(field(inputs[1],"role"),"dossier");equals(field(inputs[1],"sha256"),cat::kawo_entry.files[2].sha256);require(integer(field(inputs[1],"bytes"))==cat::kawo_entry.files[2].bytes,"Compiler dossier byte relation");
  keys(field(value,"tools"),{"lock_sha256","qualification_sha256","python_executable_sha256","pyproj_wheel_sha256","pillow_wheel_sha256","certifi_wheel_sha256","proj_db_sha256","geoid_sha256"});
  const auto& operations=array(field(value,"operations"),4);for(const auto& operation:operations){keys(operation,{"id","direction","definition","projjson","axis_in","axis_out","units_in","units_out","grids","area_of_use","published_accuracy_m"});keys(field(operation,"area_of_use"),{"west_deg","south_deg","east_deg","north_deg"});const auto& grids=field(operation,"grids");require(grids.kind==Json::Kind::array&&grids.array.size()<=4,"Compiler operation grids");for(const auto& row:grids.array)keys(row,{"name","sha256"});}
  const auto& frame=field(value,"frame");keys(frame,{"world_anchor","horizontal_policy","vertical_policy","source_realization","source_epoch_year","total3d_accuracy"});geo(field(frame,"world_anchor"),cat::kawo_entry.world_anchor);equals(field(frame,"total3d_accuracy"),"unknown");
  const auto& grid_record=field(value,"grid");keys(grid_record,{"east_origin_m","south_origin_m","spacing_m","columns","rows","vertices","valid_words"});
  require(number(field(grid_record,"east_origin_m"))==definition.east_origin_m&&number(field(grid_record,"south_origin_m"))==definition.south_origin_m&&integer(field(grid_record,"spacing_m"))==4&&integer(field(grid_record,"columns"))==definition.columns&&integer(field(grid_record,"rows"))==definition.rows&&integer(field(grid_record,"vertices"))==definition.up_m.size()&&integer(field(grid_record,"valid_words"))==definition.valid_words.size(),"Compiler decoded grid relation");
  const auto& mosaic=field(value,"mosaic");keys(mosaic,{"policy","seam_easting_m","source_sample_offset_m","overlap_columns","overlap_word_mismatches","max_overlap_difference_m"});(void)binary64(field(mosaic,"source_sample_offset_m"));(void)binary64(field(mosaic,"max_overlap_difference_m"));
  const auto& construction=field(value,"construction");keys(construction,{"method","initial_y_m","updates","pre_round_residual_limit_m","last_delta_limit_m","post_round_residual_limit_m","rounding","reverse_horizontal","reverse_vertical"});
  for(const auto tag:{"initial_y_m","pre_round_residual_limit_m","last_delta_limit_m","post_round_residual_limit_m"})(void)binary64(field(construction,tag));
  const auto& validation=field(value,"validation");keys(validation,{"valid_vertices","missing_vertices","min_up_m","max_up_m","max_gradient_norm","bracket_span_m","max_pre_round_residual_m","max_last_delta_m","max_post_round_residual_m","core_definition_valid","decoded_source_sha256"});
  require(integer(field(validation,"valid_vertices"))==definition.up_m.size()&&integer(field(validation,"missing_vertices"))==0&&binary64(field(validation,"min_up_m"))==std::bit_cast<std::uint64_t>(minimum)&&binary64(field(validation,"max_up_m"))==std::bit_cast<std::uint64_t>(maximum),"Compiler extrema/count relation");
  for(const auto tag:{"max_gradient_norm","bracket_span_m","max_pre_round_residual_m","max_last_delta_m","max_post_round_residual_m"})(void)binary64(field(validation,tag));
  require(field(validation,"core_definition_valid").kind==Json::Kind::boolean&&field(validation,"core_definition_valid").boolean,"Compiler core validation absent");keys(field(validation,"decoded_source_sha256"),{"tile55","tile56"});
  compiled_geometry(field(value,"airport_geometry"),definition);
  const auto& outputs=array(field(value,"outputs"),1);keys(outputs[0],{"path","sha256","bytes"});equals(field(outputs[0],"path"),"ground.fgrd");equals(field(outputs[0],"sha256"),cat::kawo_entry.files[0].sha256);require(integer(field(outputs[0],"bytes"))==cat::kawo_entry.files[0].bytes,"Compiler output byte relation");
}
void catalog() {
  const auto& e=cat::kawo_entry;const auto& s=cat::kawo_start;const auto& g=cat::kawo_geometry;
  require(e.schema=="WorldRuntimeEntry/v1"&&e.selector=="kawo-prototype-v1"&&e.world.id=="kawo.prototype"&&e.world.version=="0.1.0-prototype"&&v1::hash(e.world.sha256)&&e.world.bytes>0&&e.world.bytes<=4*1024*1024,"Invalid fixed resident catalog world");
  require(e.model_identity.id=="original-interactive-prototype"&&e.model_identity.version=="0.1.0-prototype"&&e.model_identity.backend_model=="original-interactive"&&v1::hash(e.model_inventory_sha256)&&v1::hash(cat::catalog_source_sha256),"Invalid fixed resident catalog model/source");
  require(e.named_start=="ground-ready"&&e.wind_profile=="calm"&&e.seed=="42"&&e.clock.purpose=="runtime"&&e.clock.tick_rate_hz==120&&e.angular_integration_method==nullptr&&e.recording_version==3,"Invalid fixed resident catalog recipe");
  constexpr std::array<std::string_view,6> paths{"ground.fgrd","airport.json","dossier.json","compile-receipt.json","start-ready34.json","NOTICE.txt"};
  constexpr std::array<std::string_view,6> roles{"resident-ground-grid-v1","airport-source-record","airport-source-dossier","terrain-compile-receipt-v1","world-start-recipe-v1","source-notice"};
  constexpr std::array<std::uint64_t,6> limits{276946836,4194304,4194304,4194304,16384,65536};
  std::uint64_t total=e.world.bytes;
  for(std::size_t i=0;i<6;++i){const auto& f=e.files[i];require(f.path==paths[i]&&f.role==roles[i]&&v1::hash(f.sha256)&&f.bytes>0&&f.bytes<=limits[i],"Invalid fixed resident catalog file");total+=f.bytes;}
  require(total<=288ULL*1024*1024,"Resident aggregate byte bound");
  require(s.schema=="KawoStartRecipe/v1"&&s.id=="ready-runway34"&&s.selector==e.selector&&s.model_identity.id==e.model_identity.id&&s.model_identity.version==e.model_identity.version&&s.model_identity.backend_model==e.model_identity.backend_model&&s.named_start==e.named_start&&s.wind_profile==e.wind_profile&&s.seed==e.seed&&s.clock.purpose==e.clock.purpose&&s.clock.tick_rate_hz==e.clock.tick_rate_hz,"Catalog start tuple mismatch");
  require(g.schema=="CompiledAirportGeometry/v1"&&g.source_airport_sha256==e.files[1].sha256&&g.ground_payload_sha256==e.files[0].sha256&&g.position_frame=="anchor-eus-metres"&&g.bearing_reference=="published-geographic-true-degrees","Catalog compiled geometry relation");
  require(g.world_anchor.latitude_rad==e.world_anchor.latitude_rad&&g.world_anchor.longitude_rad==e.world_anchor.longitude_rad&&g.world_anchor.ellipsoid_height_m==e.world_anchor.ellipsoid_height_m,"Catalog geometry anchor relation");
  constexpr std::array<std::string_view,2> ids{"kawo.runway.11-29","kawo.runway.16-34"};constexpr std::array<std::string_view,4> ends{"11","29","16","34"};
  for(std::size_t i=0;i<2;++i)require(g.runways[i].id==ids[i]&&g.runways[i].material_polygon_id==ids[i]&&g.runways[i].ends[0].designator==ends[2*i]&&g.runways[i].ends[1].designator==ends[2*i+1],"Catalog closed runway roster");
}
} // namespace

std::shared_ptr<const PreparedWorld> load_kawo_world(const std::filesystem::path& admitted_model_root) {
  require(exact::fp_environment(),"Unsupported resident runtime floating environment");catalog();std::vector<Handle> directories;auto state=std::make_unique<PreparedWorld::Impl>();
  state->model_root=absolute_ordinary_root(admitted_model_root,directories);
  // Fixed sibling only. Parent traversal is not obtained from a catalog path.
  const auto payload=state->model_root.parent_path();const auto worlds=payload/"worlds",pack=worlds/"kawo-prototype-v1";
  directories.push_back(ordinary(worlds,true));directories.push_back(ordinary(pack,true));roster(pack);
  const auto& entry=cat::kawo_entry;
  state->bytes[0]=read_owned(pack/"world.json",entry.world.bytes,4194304);require(PreparedWorld::digest(state->bytes[0])==entry.world.sha256,"Resident manifest raw digest differs");
  constexpr std::array<std::uint64_t,6> limits{276946836,4194304,4194304,4194304,16384,65536};
  for(std::size_t i=0;i<6;++i){state->bytes[i+1]=read_owned(pack/std::filesystem::path(entry.files[i].path),entry.files[i].bytes,limits[i]);require(PreparedWorld::digest(state->bytes[i+1])==entry.files[i].sha256,"Resident file raw digest differs");}
  roster(pack);manifest(Parser(view(state->bytes[0]),16,20000).parse());recipe(Parser(view(state->bytes[5]),8,512).parse());utf8(view(state->bytes[6]));
  // Exact pinned source records have passed the complete offline schemas and
  // rights review. Runtime reads their data only, with strict syntax and links.
  const auto airport=Parser(view(state->bytes[2]),16,20000).parse(),dossier=Parser(view(state->bytes[3]),16,20000).parse();
  keys(airport,{"schema","airport_icao","purpose","dossier_sha256","review_state","name","reference_point","field_elevation","runways","notes"});equals(field(airport,"schema"),"NormalizedAirport/v1");equals(field(airport,"airport_icao"),"KAWO");equals(field(airport,"purpose"),"source-record");equals(field(airport,"dossier_sha256"),entry.files[2].sha256);
  keys(dossier,{"schema","airport_icao","purpose","as_of_utc","sources","conflicts","notes"});equals(field(dossier,"schema"),"AirportSourceDossier/v1");equals(field(dossier,"airport_icao"),"KAWO");equals(field(dossier,"purpose"),"source-record");
  const auto inventory_path=state->model_root/"inventory.json";const auto inventory_size=std::filesystem::file_size(inventory_path);
  const auto inventory=read_owned(inventory_path,inventory_size,4194304,&state->retained_handles);require(PreparedWorld::digest(inventory)==entry.model_inventory_sha256,"Resident model inventory differs");
  const auto model_data=Parser(view(inventory),8,2048).parse();equals(field(model_data,"id"),entry.model_identity.id);equals(field(model_data,"version"),entry.model_identity.version);
  const auto& model_files=array(field(model_data,"files"),3);
  constexpr std::array<std::string_view,3> model_paths{"aircraft/original-interactive/original-interactive.xml","engine/original-synthetic-thrust.xml","engine/original-synthetic-direct.xml"};
  directories.push_back(ordinary(state->model_root/"aircraft",true));directories.push_back(ordinary(state->model_root/"aircraft"/"original-interactive",true));directories.push_back(ordinary(state->model_root/"engine",true));
  for(std::size_t i=0;i<3;++i){keys(model_files[i],{"path","bytes","sha256"});equals(field(model_files[i],"path"),model_paths[i]);const auto bytes=read_owned(state->model_root/std::filesystem::path(model_paths[i]),integer(field(model_files[i],"bytes"),4194304),4194304,&state->retained_handles);require(PreparedWorld::digest(bytes)==text(field(model_files[i],"sha256")),"Resident model XML differs");}
  auto definition=ground::grid::payload::v1::decode(state->bytes[1]);
  const auto anchor=position(entry.world_anchor);
  require(std::bit_cast<std::uint64_t>(definition.anchor.latitude_rad)==entry.world_anchor.latitude_rad&&std::bit_cast<std::uint64_t>(definition.anchor.longitude_rad)==entry.world_anchor.longitude_rad&&std::bit_cast<std::uint64_t>(definition.anchor.ellipsoid_height_m)==entry.world_anchor.ellipsoid_height_m&&c::valid(anchor),"Resident payload anchor differs");
  require(definition.columns==3073&&definition.rows==2049&&definition.spacing==grid::Spacing::metres_4&&definition.east_origin_m==-6144&&definition.south_origin_m==-4096&&definition.default_material_index==0&&definition.materials.size()==2&&definition.missing_vertices==grid::MissingVertices::invalid_data,"Resident grid shape differs");
  require(definition.materials[0].id=="original.terrain-prototype"&&definition.materials[1].id=="original.asphalt","Resident material IDs differ");
  for(const auto& material:definition.materials)require(material.static_friction==.8&&material.dynamic_friction==.6,"Resident prototype material coefficients differ");
  state->minimum=std::numeric_limits<double>::infinity();state->maximum=-std::numeric_limits<double>::infinity();
  for(std::size_t i=0;i<definition.up_m.size();++i){require((definition.valid_words[i/64]&(1ULL<<(i%64)))!=0,"Resident pin unexpectedly has missing vertices");const auto y=static_cast<double>(definition.up_m[i]);require(std::isfinite(y),"Resident nonfinite valid height");state->minimum=std::min(state->minimum,y);state->maximum=std::max(state->maximum,y);}
  const auto compiled=Parser(view(state->bytes[4]),16,20000).parse();receipt(compiled,definition,state->minimum,state->maximum);
  state->identity={{std::string(entry.world.id),std::string(entry.world.version),std::string(entry.world.sha256)},std::string(entry.files[0].sha256),1};
  state->provider=grid::PreparedGrid::prepare(std::move(definition),state->identity);
  require(v1::same(state->provider->identity(),state->identity),"Prepared resident identity differs");
  for(auto& directory:directories){state->retained_handles.push_back(std::make_shared<Handle>(std::move(directory)));}
  return std::shared_ptr<const PreparedWorld>(new PreparedWorld(std::move(state)));
}
} // namespace flight::interactive
