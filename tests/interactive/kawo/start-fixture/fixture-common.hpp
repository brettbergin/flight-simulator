#pragma once
// Private, bounded offline physical-data probe. Not a runtime world admission API.
#include <flight/ground/grid_payload.hpp>
#include <flight/fdm/model.hpp>
#include "exact.hpp" // Accepted bounded grid-private dyadics, no public ABI addition.
#include <algorithm>
#include <array>
#include <bit>
#include <cfenv>
#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <locale>
#include <memory>
#include <span>
#include <sstream>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif
#ifndef START_METADATA_HEADER
#error Reviewed Root metadata header required
#endif
#include START_METADATA_HEADER

namespace start_fixture {
namespace c = flight::contracts::v1;
namespace g = flight::ground::v1;
namespace grid = flight::ground::grid::v1;
namespace codec = flight::ground::grid::payload::v1;
namespace m = kawo_start_metadata;
using Vec = std::array<double,3>;
using Mat = std::array<double,9>;
using Words = std::array<std::uint64_t,3>;
inline constexpr double feet = .3048;
inline constexpr double goal = .05;
inline constexpr double residual_limit = 0x1p-20;
// Independent toy geometry only, never the loaded-model physical start.
inline constexpr std::array<Vec,3> ideal_control_arms{{{2,0,1},{-1,-1.3,1},{-1,1.3,1}}};
inline void require(bool value,const char* why) { if(!value) throw std::runtime_error(why); }
inline double rnd(double x) { volatile double v=x; return v; }
inline double sum(double a,double b) { return rnd(a+b); }
inline double sub(double a,double b) { return rnd(a-b); }
inline double mul(double a,double b) { return rnd(a*b); }
inline double div(double a,double b) { return rnd(a/b); }
inline double dot(Vec a,Vec b) { return sum(sum(mul(a[0],b[0]),mul(a[1],b[1])),mul(a[2],b[2])); }
// Fixed original-model source transcript, not sampled/adjusted RunIC output.
// FGXMLElement.cpp66/72/75 and607..631: XML metres -> stored inches.
// FGLGear.cpp67 / FGLGear.h240: Ts2b*(inches-CG), with exact zero fixed CG.
// FGMatrix33.cpp487..497: each product then left-associated zero additions.
// RunIC's column(...,feet) finally promotes vendor body feet to metres.
inline const std::array<Vec,3>& model_arms() {
  require(std::fegetround()==FE_TONEAREST,"model arm derivation requires round-to-nearest");
  static const std::array<Vec,3> value=[] {
    const double metres_to_inches=mul(3.2808399,12.0);
    const double inches_to_feet=div(1.0,12.0);
    const std::array<Vec,3> structural_metres{{{-2,0,-1},{1,-1.3,-1},{1,1.3,-1}}};
    const std::array<Vec,3> rows{{{-inches_to_feet,0,0},{0,inches_to_feet,0},{0,0,-inches_to_feet}}};
    std::array<Vec,3> result{};
    for(std::size_t i=0;i<3;++i) {
      const Vec inches{mul(structural_metres[i][0],metres_to_inches),mul(structural_metres[i][1],metres_to_inches),mul(structural_metres[i][2],metres_to_inches)};
      const Vec delta{sub(inches[0],0.0),sub(inches[1],0.0),sub(inches[2],0.0)};
      for(std::size_t axis=0;axis<3;++axis)
        result[i][axis]=mul(dot(rows[axis],delta),feet);
    }
    return result;
  }();
  return value;
}
inline Vec plus(Vec a,Vec b) { return {sum(a[0],b[0]),sum(a[1],b[1]),sum(a[2],b[2])}; }
inline Vec minus(Vec a,Vec b) { return {sub(a[0],b[0]),sub(a[1],b[1]),sub(a[2],b[2])}; }
inline Vec scale(Vec a,double b) { return {mul(a[0],b),mul(a[1],b),mul(a[2],b)}; }
inline Vec vec(c::EcefPosition a) { return {a.x,a.y,a.z}; }
inline c::EcefPosition ecef(Vec a) { return {a[0],a[1],a[2]}; }
inline Vec geod_vec(c::GeodeticPosition a) { return {a.latitude_rad,a.longitude_rad,a.ellipsoid_height_m}; }
inline bool finite(Vec a) { return std::all_of(a.begin(),a.end(),[](double x){return std::isfinite(x);}); }
inline double maxabs(Vec a) { return std::max({std::abs(a[0]),std::abs(a[1]),std::abs(a[2])}); }
inline Vec decode(Words a) { return {std::bit_cast<double>(a[0]),std::bit_cast<double>(a[1]),std::bit_cast<double>(a[2])}; }
inline c::GeodeticPosition geod(Vec a) { return {a[0],a[1],a[2]}; }
inline c::GeodeticPosition inverse(Vec a) {
  const auto p=c::geodesy::from_ecef(ecef(a)); require(p.has_value(),"invalid ECEF inverse"); return *p;
}
inline Vec forward(c::GeodeticPosition p) {
  const auto v=c::geodesy::to_ecef(p); require(v.has_value(),"invalid geodetic forward"); return vec(*v);
}
inline std::string word(double v) {
  std::ostringstream out; out<<std::hex<<std::setfill('0')<<std::setw(16)<<std::bit_cast<std::uint64_t>(v); return out.str();
}
inline std::string quoted(std::string_view s) {
  std::ostringstream out; out<<'"';
  for(const unsigned char ch:s) {
    if(ch=='"'||ch=='\\') out<<'\\'<<static_cast<char>(ch);
    else if(ch<32) out<<"\\u00"<<std::hex<<std::setw(2)<<std::setfill('0')<<static_cast<unsigned>(ch)<<std::dec;
    else out<<static_cast<char>(ch);
  }
  out<<'"'; return out.str();
}
inline void emit_vec(std::ostream& o,Vec a) {
  require(finite(a),"nonfinite output vector");
  o<<"{\"values\":["<<a[0]<<','<<a[1]<<','<<a[2]<<"],\"words\":["<<quoted(word(a[0]))<<','<<quoted(word(a[1]))<<','<<quoted(word(a[2]))<<"]}";
}
inline void emit_mat(std::ostream& o,const Mat& a) {
  o<<"{\"values\":["; for(std::size_t i=0;i<a.size();++i){require(std::isfinite(a[i]),"nonfinite matrix"); if(i)o<<',';o<<a[i];}
  o<<"],\"words\":["; for(std::size_t i=0;i<a.size();++i){if(i)o<<',';o<<quoted(word(a[i]));}o<<"]}";
}
inline std::filesystem::path ordinary(const std::filesystem::path& p,bool directory) {
  require(p.is_absolute(),"absolute ordinary path required"); const auto clean=p.lexically_normal();
  require(clean==p,"noncanonical path spelling");
  std::filesystem::path walk;
  for(const auto& part:p) {
    walk/=part;if(!walk.has_root_directory())continue;const auto st=std::filesystem::symlink_status(walk);
    require(!std::filesystem::is_symlink(st),"symlink refused");
#ifdef _WIN32
    const auto attrs=GetFileAttributesW(walk.c_str());
    require(attrs!=INVALID_FILE_ATTRIBUTES && !(attrs&FILE_ATTRIBUTE_REPARSE_POINT),"reparse/unreadable path refused");
#endif
  }
  require(directory?std::filesystem::is_directory(p):std::filesystem::is_regular_file(p),"ordinary path kind mismatch");
  require(std::filesystem::canonical(p)==p,"path alias refused"); return p;
}
inline std::vector<std::uint8_t> read(const std::filesystem::path& path,std::uint64_t count) {
  ordinary(path,false); require(count<=codec::max_payload_bytes && std::filesystem::file_size(path)==count,"byte count mismatch");
  std::vector<std::uint8_t> data(static_cast<std::size_t>(count)); std::ifstream in(path,std::ios::binary);
  in.read(reinterpret_cast<char*>(data.data()),static_cast<std::streamsize>(data.size()));
  require(in.good() && in.peek()==std::char_traits<char>::eof(),"short/extra read"); return data;
}
inline void environment() {
  static_assert(sizeof(double)==8 && std::numeric_limits<double>::digits==53 && sizeof(float)==4);
  static_assert(std::endian::native==std::endian::little);
  std::cout.imbue(std::locale::classic()); std::cerr.imbue(std::locale::classic()); std::cout<<std::setprecision(17);
  require(std::fegetround()==FE_TONEAREST,"RNE environment required for private probe");
  volatile double tiny=std::numeric_limits<double>::denorm_min();
  require(std::bit_cast<std::uint64_t>(sum(tiny,tiny))==2,"FTZ/DAZ private probe environment refused");
  require(m::payload_bytes==25973686 && m::payload_sha256==std::string_view("b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb"),"wrong fixed candidate pin");
  require(m::receipt_bytes==22937 && m::receipt_sha256==std::string_view("cb1e0b28384aeb1c11173d991b5790a8a16e64953c2c479be6b07136c5f489f0"),"wrong fixed receipt pin");
}
struct Frame {
  c::GeodeticPosition anchor; Vec a,e,u,s;
  explicit Frame(c::GeodeticPosition p):anchor(p),a(forward(p)) {
    const double sp=std::sin(p.latitude_rad),cp=std::cos(p.latitude_rad),sl=std::sin(p.longitude_rad),cl=std::cos(p.longitude_rad);
    e={-sl,cl,0};u={mul(cp,cl),mul(cp,sl),sp};s={mul(sp,cl),mul(sp,sl),-cp};
  }
  Vec point(Vec eus) const {
    // Accepted compiler transcript: (((A+X*E)+Y*U)+Z*S), componentwise.
    Vec r{}; for(std::size_t i=0;i<3;++i) r[i]=sum(sum(sum(a[i],mul(eus[0],e[i])),mul(eus[1],u[i])),mul(eus[2],s[i])); return r;
  }
  Vec project(Vec p) const { const auto d=minus(p,a);return {dot(d,e),dot(d,u),dot(d,s)}; }
};
struct Local {
  Vec n,e,u;
  explicit Local(c::GeodeticPosition p) {
    const double sp=std::sin(p.latitude_rad),cp=std::cos(p.latitude_rad),sl=std::sin(p.longitude_rad),cl=std::cos(p.longitude_rad);
    n={-mul(sp,cl),-mul(sp,sl),cp};e={-sl,cl,0};u={mul(cp,cl),mul(cp,sl),sp};
  }
  Vec offset(Vec ned) const {return plus(plus(scale(n,ned[0]),scale(e,ned[1])),scale(u,-ned[2]));}
};
inline Mat rotation(double phi,double theta,double psi) {
  const double sr=std::sin(phi),cr=std::cos(phi),sp=std::sin(theta),cp=std::cos(theta),sy=std::sin(psi),cy=std::cos(psi);
  return {mul(cp,cy),sub(mul(mul(cy,sp),sr),mul(sy,cr)),sum(mul(mul(cy,sp),cr),mul(sy,sr)),
          mul(cp,sy),sum(mul(mul(sy,sp),sr),mul(cy,cr)),sub(mul(mul(sy,sp),cr),mul(cy,sr)),
          -sp,mul(cp,sr),mul(cp,cr)};
}
inline Vec rotate(const Mat& r,Vec p) {return {dot({r[0],r[1],r[2]},p),dot({r[3],r[4],r[5]},p),dot({r[6],r[7],r[8]},p)};}
inline bool in_polygon(double x,double z) {
  // Closed convex four-point footprint, checked against decoded payload below.
  using D=flight::ground::grid::detail::Dyadic;
  const auto px=D::binary64(x)*D::integer(1000),pz=D::binary64(z)*D::integer(1000);
  const auto integer=[](std::int32_t v){return D::binary64(static_cast<double>(v));};
  int sign=0;
  for(std::size_t i=0;i<4;++i) {
    const auto a=m::footprint_mm[i],b=m::footprint_mm[(i+1)%4];
    const auto cross=(integer(b[0])-integer(a[0]))*(pz-integer(a[1]))-(integer(b[1])-integer(a[1]))*(px-integer(a[0]));
    const int now=compare(cross,D::integer(0));if(now && sign && now!=sign)return false;if(now)sign=now;
  }
  return sign!=0;
}
struct Terrain {
  Frame frame; Vec p34,p16; double x{},z{};Vec direction;
  std::shared_ptr<const grid::PreparedGrid> provider;
  explicit Terrain(const std::filesystem::path& payload,const std::filesystem::path& receipt):
    frame(geod(decode(m::anchor_words))),p34(decode(m::end34_words)),p16(decode(m::end16_words)) {
    const auto receipt_data=read(receipt,m::receipt_bytes);
    require(flight::fdm::sha256(receipt_data)==m::receipt_sha256,"receipt raw digest changed");
    // Whole payload hash is checked by the mandatory external Root before/finally seal.
    const auto bytes=read(payload,m::payload_bytes); auto d=codec::decode(bytes);
    require(d.columns==3073 && d.rows==2049 && d.spacing==grid::Spacing::metres_4 && d.east_origin_m==-6144 && d.south_origin_m==-4096,"fixed grid mismatch");
    require(std::bit_cast<std::uint64_t>(d.anchor.latitude_rad)==m::anchor_words[0] && std::bit_cast<std::uint64_t>(d.anchor.longitude_rad)==m::anchor_words[1] && std::bit_cast<std::uint64_t>(d.anchor.ellipsoid_height_m)==m::anchor_words[2],"anchor words mismatch");
    require(d.polygons.size()==2 && d.polygons[1].id=="kawo.runway.16-34" && d.polygons[1].material_index==1 && d.polygons[1].priority==100 && d.polygons[1].vertices.size()==4,"runway polygon identity mismatch");
    for(std::size_t i=0;i<4;++i) require(d.polygons[1].vertices[i].east_mm==m::footprint_mm[i][0] && d.polygons[1].vertices[i].south_mm==m::footprint_mm[i][1],"receipt/payload footprint mismatch");
    const g::Identity id{{"qualification.kawo-start-fixture","1.0.0",std::string(m::receipt_sha256)},std::string(m::payload_sha256),1};
    provider=grid::PreparedGrid::prepare(std::move(d),id);
    require(finite(p34)&&finite(p16),"endpoint nonfinite");
    const double dx=sub(p16[0],p34[0]),dz=sub(p16[2],p34[2]);
    const double len=rnd(std::sqrt(sum(mul(dx,dx),mul(dz,dz))));require(std::isfinite(len)&&len>100,"bad centerline length");
    const double t=div(100,len);x=sum(p34[0],mul(t,dx));z=sum(p34[2],mul(t,dz));direction=plus(scale(frame.e,dx),scale(frame.s,dz));
    require(in_polygon(x,z),"chainage outside runway footprint");
    require(provider->coverage({sub(x,8),sub(z,8),sum(x,8),sum(z,8)})==grid::Coverage::ready,"fixture coverage rectangle missing");
  }
  c::ValidGround sample(g::Boundary& boundary,c::GeodeticPosition p) const {
    const auto a=boundary.sample(p);const auto* ground=std::get_if<c::ValidGround>(&a.sample);
    require(ground!=nullptr,"missing actual provider sample");return *ground;
  }
  double yaw(c::GeodeticPosition p) const {
    const Local local(p);const double n=dot(direction,local.n),e=dot(direction,local.e);
    require(std::isfinite(n)&&std::isfinite(e)&&(n!=0||e!=0),"degenerate heading");
    double v=rnd(std::atan2(e,n));if(v<0)v=sum(v,mul(2,c::pi));require(v>=0&&v<mul(2,c::pi),"heading normalization failed");return v;
  }
};
struct Evaluation {
  Vec unknown,cg_ecef,cg_eus,rpy,residual; c::GeodeticPosition cg; Mat matrix;
  c::ValidGround cg_ground;
  std::array<Vec,3> wheel_ecef;std::array<c::GeodeticPosition,3> wheel_geod;
  std::array<c::ValidGround,3> wheel_ground;
};
inline Evaluation evaluate(const Terrain& t,Vec unknown) {
  require(finite(unknown)&&unknown[0]>=-1000&&unknown[0]<=4096&&std::abs(unknown[1])<=.2&&std::abs(unknown[2])<=.2,"pose outside author domain");
  Evaluation r{};r.unknown=unknown;r.cg_eus={t.x,unknown[0],t.z};r.cg_ecef=t.frame.point(r.cg_eus);r.cg=inverse(r.cg_ecef);
  const auto roundtrip=t.frame.project(forward(r.cg));require(std::abs(roundtrip[0]-t.x)<=1e-5 && std::abs(roundtrip[2]-t.z)<=1e-5,"chainage inverse/forward mismatch");
  r.rpy={unknown[1],unknown[2],t.yaw(r.cg)};r.matrix=rotation(r.rpy[0],r.rpy[1],r.rpy[2]);
  g::Boundary boundary(t.provider,{{0},"qualification.kawo-start-author"},4);r.cg_ground=t.sample(boundary,r.cg);const Local local(r.cg);
  for(std::size_t i=0;i<3;++i) {
    r.wheel_ecef[i]=plus(r.cg_ecef,local.offset(rotate(r.matrix,model_arms()[i])));r.wheel_geod[i]=inverse(r.wheel_ecef[i]);
    r.wheel_ground[i]=t.sample(boundary,r.wheel_geod[i]);
    r.residual[i]=sub(sub(r.wheel_geod[i].ellipsoid_height_m,r.wheel_ground[i].surface_height_m),goal);
  }
  require(finite(r.residual)&&boundary.query_count()==4&&!boundary.failed(),"invalid residual evaluation");return r;
}
inline void clearances(const Terrain& t,const Evaluation& r) {
  require(r.cg.ellipsoid_height_m-r.cg_ground.surface_height_m>=1,"CG clearance below1m");
  require(maxabs(r.residual)<=residual_limit,"final gear residual exceeds fixed goal");
  for(std::size_t i=0;i<3;++i) {
    const double sep=r.wheel_geod[i].ellipsoid_height_m-r.wheel_ground[i].surface_height_m;
    const auto p=t.frame.project(r.wheel_ecef[i]);require(sep>=0&&sep<=.25&&in_polygon(p[0],p[2])&&r.wheel_ground[i].material_id=="original.asphalt","gear clearance/material/footprint mismatch");
  }
}
inline void emit_evaluation(std::ostream& out,const Evaluation& r) {
  out<<"{\"unknown\":";emit_vec(out,r.unknown);out<<",\"cg_ecef_m\":";emit_vec(out,r.cg_ecef);
  out<<",\"cg_geodetic\":";emit_vec(out,geod_vec(r.cg));out<<",\"cg_eus_m\":";emit_vec(out,r.cg_eus);
  out<<",\"rpy_rad\":";emit_vec(out,r.rpy);out<<",\"body_to_ned\":";emit_mat(out,r.matrix);
  out<<",\"residual_m\":";emit_vec(out,r.residual);out<<",\"cg_surface_height_word\":"<<quoted(word(r.cg_ground.surface_height_m))<<",\"wheels\":[";
  for(std::size_t i=0;i<3;++i){if(i)out<<',';out<<"{\"arm_body_m\":";emit_vec(out,model_arms()[i]);out<<",\"ecef_m\":";emit_vec(out,r.wheel_ecef[i]);out<<",\"geodetic\":";emit_vec(out,geod_vec(r.wheel_geod[i]));out<<",\"surface_height_word\":"<<quoted(word(r.wheel_ground[i].surface_height_m))<<",\"normal_ned\":";emit_vec(out,{r.wheel_ground[i].normal_ned.x,r.wheel_ground[i].normal_ned.y,r.wheel_ground[i].normal_ned.z});out<<",\"material\":"<<quoted(r.wheel_ground[i].material_id)<<'}';}
  out<<"]}";
}
inline void emit_inputs() {
  std::cout<<"{\"event\":\"inputs\",\"scope\":\"private-physical-data-only-not-runtime-pack\",\"payload_sha256\":"<<quoted(m::payload_sha256)<<",\"receipt_sha256\":"<<quoted(m::receipt_sha256)<<",\"payload_digest_authority\":\"mandatory-outer-Root-before-finally-seal\",\"frame_order\":\"(((A+XE)+YU)+ZS)\"}\n";
}
inline void verify_model(const std::filesystem::path& path) {
  ordinary(path,true);
  struct Pin{const char* path;std::uint64_t bytes;const char* sha;};
  constexpr std::array<Pin,4> pins{{
    {"inventory.json",1380,"98b30b5641ce86cc6f0af6298424606aa96a1e4a35ef3e9fcaf377bebb3f00cd"},
    {"aircraft/original-interactive/original-interactive.xml",6151,"0213ab8c1176e5d20b01f980da9cb94913f3e9ad8866838adc7e77bf3130722a"},
    {"engine/original-synthetic-thrust.xml",561,"547581e279e9b3f383422ddff7991b0ff1cef6f02054bf0a979cd6859d9ef073"},
    {"engine/original-synthetic-direct.xml",100,"30c8dbec55a756c71d639aef1cf720decff0ba6730af5ec2062608a08d24d00b"}}};
  for(const auto& pin:pins)require(flight::fdm::sha256(read(path/pin.path,pin.bytes))==pin.sha,"original model pin mismatch");
  std::size_t count=0;for(const auto& f:std::filesystem::recursive_directory_iterator(path)){
    ordinary(f.path(),f.is_directory());if(f.is_directory())continue;
    const auto relative=f.path().lexically_relative(path).generic_string();
    require(std::any_of(pins.begin(),pins.end(),[&](const Pin& pin){return relative==pin.path;}),"extra model file");++count;
  }
  require(count==4,"model roster mismatch");
}
} // namespace start_fixture
