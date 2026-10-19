#include <flight/interactive/prepared_world.hpp>
#include "canonical_frame.hpp"
#include <bit>
#include <cfenv>
#include <iostream>
#include <limits>
#include <string>

namespace flight::interactive {
// Observation of private production predicates/parser only. No synthetic world
// binding, provider injection, writable pose or shipping factory is introduced.
struct PreparedWorldTestAccess {
  static auto rectangle(Vec center){return PreparedWorld::rectangle(center);}
  static bool distance(Vec a,Vec b,double limit){try{return PreparedWorld::distance_within(a,b,limit);}catch(...){return false;}}
  static bool support(Vec a,Vec d,double low,double high,const ground::grid::v1::Rectangle& rect){try{return PreparedWorld::support_within({a,d},low,high,rect);}catch(...){return false;}}
  static auto ray(c::GeodeticPosition anchor,c::GeodeticPosition query){const auto r=PreparedWorld::ray(anchor,query);return std::array<Vec,2>{r.a,r.d};}
  static bool json(std::string_view text,std::size_t depth=16,std::size_t values=20000){try{PreparedWorld::check_json(text,depth,values);return true;}catch(...){return false;}}
  static auto digest(std::span<const std::uint8_t> input){return PreparedWorld::digest(input);}
};
}
namespace i=flight::interactive;
namespace g=flight::ground::grid::v1;
namespace c=flight::contracts::v1;
namespace frame=flight::ground::grid::detail::canonical_frame;
using A=i::PreparedWorldTestAccess;
namespace {
int checks=0;
void check(bool result,const char* why){++checks;if(!result)throw std::runtime_error(why);}
std::uint64_t word(double value){return std::bit_cast<std::uint64_t>(value);}
void same(i::Vec actual,i::Vec expected,const char* why){for(std::size_t j=0;j<3;++j)check(word(actual[j])==word(expected[j]),why);}
bool rectangle_refused(i::Vec center){try{(void)A::rectangle(center);return false;}catch(...){return true;}}
std::shared_ptr<const g::PreparedGrid> flat(unsigned count,double origin,bool missing=false){
  g::Definition d;d.anchor={0,0,0};d.columns=count;d.rows=count;d.east_origin_m=origin;d.south_origin_m=origin;d.spacing=g::Spacing::metres_4;d.missing_vertices=g::MissingVertices::not_loaded;
  const auto vertices=static_cast<std::size_t>(count)*count;d.up_m.assign(vertices,0);d.valid_words.assign((vertices+63)/64,~0ULL);
  if(vertices%64){d.valid_words.back()=(1ULL<<(vertices%64))-1;}
  d.materials={{"original.fixture",.8,.6}};
  if(missing){const auto n=25*count+28;d.up_m[n]=std::bit_cast<float>(g::invalid_height_bits);d.valid_words[n/64]&=~(1ULL<<(n%64));}
  return g::PreparedGrid::prepare(std::move(d),{{"fixture.readiness","1.0.0",std::string(64,'a')},std::string(64,'b'),1});
}
void readiness(){
  // Hand references predate runtime output: readiness hand-oracles ece4c72a
  // and independent Fraction prediction852c2621. These A/D vectors are solely
  // represented-operand predicate tests, never claimed physical geodetic rays.
  const auto r=A::rectangle({0,0,0});check(r.east_min_m==-40&&r.east_max_m==40&&r.south_min_m==-40&&r.south_max_m==40,"80m exact rectangle");
  const auto plus=A::rectangle({0x1p-48,0,0}),minus=A::rectangle({-0x1p-48,0,0}),offset=A::rectangle({40+0x1p-47,0,0});
  check(word(plus.east_min_m)==word(-40.0)&&word(plus.east_max_m)==0x4044000000000001ULL,"least outward positive tie");
  check(word(minus.east_min_m)==0xc044000000000001ULL&&word(minus.east_max_m)==word(40.0),"least outward negative tie");
  check(offset.east_min_m==0x1p-47&&word(offset.east_max_m)==0x4054000000000001ULL,"separately exact cancellation");
  check(!rectangle_refused({0,8192,0})&&!rectangle_refused({0,-1024,0}),"inclusive altitude extrema");
  check(rectangle_refused({0,8192+0x1p-39,0})&&rectangle_refused({0,-1024-0x1p-42,0}),"altitude next representable refusals");
  check(rectangle_refused({std::numeric_limits<double>::infinity(),0,0}),"nonfinite rectangle refusal");
  check(A::distance({0,8192,0},{0,8196,0},4)&&A::distance({0,-1024,0},{0,-1028,0},4),"3D vertical closed boundary");
  check(!A::distance({0,0,0},{0,4,0x1p-30},4)&&!A::distance({0,0,0},{4+0x1p-50,0,0},4),"exact sphere rejects rounded/horizontal traps");
  const auto dx=g::max_ray_horizontal_component,dy=g::min_ray_up_component;
  check(A::support({0,8196,0},{dx,dy,dx},-1000,-1000,r),"high altitude full support");
  check(A::support({0,-1028,0},{dx,dy,-dx},4096,4096,r),"low altitude full support");
  check(A::support({0,-100,0},{dx,dy,0},4096,4096,r)&&!A::support({0,-100,0},{dx,dy,0},4096,4096,{-5,-5,5,5}),"span-only padding is insufficient");
  check(A::support({40,0,0},{0,1,0},0,0,r),"closed rational support equality");
  check(!A::support({40,0,0},{0x1p-60,1,0},0,0,r),"quotient rounding cannot hide exact outside");
  check(!A::support({0,0,0},{0,0,0},0,0,r),"zero direction refused");
  check(A::support({0,0,0},{dx,dy,-dx},0,0,r)&&!A::support({0,0,0},{dx+0x1p-61,dy,0},0,0,r)&&!A::support({0,0,0},{0,dy-0x1p-53,0},0,0,r),"exact cone operand boundaries");
  const auto grid=flat(51,-100);check(grid->coverage(r)==g::Coverage::ready,"441-cell runtime rectangle ready");
  check(grid->coverage(A::rectangle({60,0,0}))==g::Coverage::outside_coverage,"outer maximum half-open refusal");
  check(grid->coverage(A::rectangle({60-0x1p-47,0,0}))==g::Coverage::outside_coverage,"outward rounded maximum refused");
  check(grid->coverage(A::rectangle({60-0x1p-46,0,0}))==g::Coverage::ready,"representably inside outer maximum");
  check(flat(51,-100,true)->coverage(r)==g::Coverage::not_loaded,"missing cell beyond old small disk refused");
  const auto cap=flat(66,-128);check(cap->coverage({-128,-128,124,124})==g::Coverage::ready&&cap->coverage({-128,-128,128,128})==g::Coverage::invalid_data,"4096 coverage cap unchanged");
  const double sweep=2.5+(150+3*2.5)*(1.0/120)+.05,limit=sweep-2.5;
  check(word(sweep)==0x400ee66666666666ULL&&word(limit)==0x3ff5ccccccccccccULL,"motion limit retains existing arithmetic");
  check(A::distance({0,0,0},{limit,0,0},limit)&&!A::distance({0,0,0},{limit,0x1p-30,0},limit),"post-step exact 3D motion boundary");
}
void operands(){
  // Both actual core and runtime call this source-bound private constructor.
  // Compare every B64 operand, separately from mathematical interval fixtures.
  const std::array<c::GeodeticPosition,3> anchors{{{0,0,0},{.7,-2.1,12},{std::bit_cast<double>(0x3feae5e5c184fcfdULL),std::bit_cast<double>(0xc0010e7e83d3ed5eULL),0}}};
  for(const auto anchor:anchors){
    const auto canonical=frame::make(anchor);check(canonical.has_value(),"canonical frame present");
    for(const auto delta:std::array<i::Vec,4>{{{0,0,0},{0,0,8192},{0x1p-18,-0x1p-17,1000},{-0x1p-17,0x1p-18,-1000}}}){
      const c::GeodeticPosition query{anchor.latitude_rad+delta[0],anchor.longitude_rad+delta[1],delta[2]};const auto core=frame::query_ray(*canonical,query);check(core.has_value(),"core actual ray present");const auto runtime=A::ray(anchor,query);
      same(runtime[0],core->a,"actual core/runtime A bit parity");same(runtime[1],core->direction,"actual core/runtime D bit parity");
      if(delta[0]==0&&delta[1]==0){same(runtime[0],{0,-anchor.ellipsoid_height_m,0},"matching-angle algebraic A");same(runtime[1],{0,1,0},"matching-angle algebraic D");}
    }
  }
  const c::GeodeticPosition equator{0,0,0};const auto independent=A::ray(equator,{0,0,123});same(independent[0],{0,-0.0,0},"equator anchor A independent closed form");same(independent[1],{0,1,0},"equator anchor D independent closed form");
  // Existing frozen grid query/reference suites independently check the shared
  // helper's mathematics and samples. This parity check alone is not that oracle.
}
void parser(){
  check(A::json("{\"a\":[null,true,false,-1.25e+2],\"utf\":\"\\uD83C\\uDF32\"}"),"strict valid JSON");
  for(const auto input:{"{\"x\":1,\"x\":2}","{\"x\":1,\"\\u0078\":2}","[1,]","{\"x\":NaN}","1e9999","01","+1","1.","true false","\"\\uD800\"","\"\\uDC00\"","\"\\uD800x\"","{\"x\" 1}","["})check(!A::json(input),"malformed strict JSON refused");
  check(!A::json(std::string("\xef\xbb\xbf{}",5)),"BOM refused");check(!A::json(std::string("\"\xc0\xaf\"",4)),"overlong UTF-8 refused");check(!A::json(std::string("\"\xed\xa0\x80\"",5)),"UTF-8 surrogate refused");
  check(A::json("[[0]]",3,3)&&!A::json("[[0]]",2,3)&&!A::json("[[0]]",3,2),"depth/value budgets do not widen");
  const std::string empty,abc="abc",million(1000000,'a');
  const auto bytes=[](const std::string& s){return std::span<const std::uint8_t>(reinterpret_cast<const std::uint8_t*>(s.data()),s.size());};
  check(A::digest(bytes(empty))=="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","SHA empty standard KAT");
  check(A::digest(bytes(abc))=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","SHA abc standard KAT");
  check(A::digest(bytes(million))=="cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0","SHA million-a standard KAT");
}
void environment(){
  std::fenv_t saved{};check(std::fegetenv(&saved)==0,"capture caller environment");
  struct Restore{std::fenv_t* value;~Restore(){std::fesetenv(value);}} restore{&saved};
  check(std::fesetround(FE_DOWNWARD)==0,"set isolated unsupported rounding");
  check(!A::distance({0,0,0},{0,0,0},4)&&rectangle_refused({0,0,0}),"unsupported environment refuses certification");
  check(std::fegetround()==FE_DOWNWARD,"certification preserves caller environment");
}
}
int main(){try{readiness();operands();parser();environment();std::cout<<"KAWO native predicates/parser: "<<checks<<" checks passed; synthetic predicates and actual operand parity only\n";return 0;}catch(const std::exception& e){std::cerr<<"KAWO check "<<checks<<" refused: "<<e.what()<<'\n';return 1;}}
