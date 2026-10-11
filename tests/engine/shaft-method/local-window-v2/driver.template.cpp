// Source-extraction consumer tests. No engine/session or replaceable DLL proof.
#include <algorithm>
#include <array>
#include <cfenv>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#include <xmmintrin.h>
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
static_assert(sizeof(void*)==8,"Reference qualification requires x64");
namespace immutable {
@@OWNED_TYPES@@
#include <immutable_helpers.inc>
}
namespace candidate {
@@OWNED_TYPES@@
#include <candidate_helpers.inc>
}
namespace j=candidate;
struct DyadicSpec {int sign,exponent;std::vector<std::uint32_t> limb;};
struct RatioSpec {DyadicSpec n,d;};
struct Cell {double lo,hi;DyadicSpec lower,upper;};
struct Certificate {bool certified;unsigned initial,used;std::vector<Cell> cells;};
struct Local {double half;Certificate certificate;bool has_time;RatioSpec time;int order;};
struct LawCase {
  const char* id;std::array<double,4> coefficients;double w,inertia,endpoint;
  bool source;RatioSpec remaining;std::vector<DyadicSpec> derivative;
  Certificate full;bool has_local;Local local;const char* outcome;
};
unsigned checks=0,cases=0,failures=0;
std::vector<std::string> failed,observations;
std::string bits(double x) {
  std::uint64_t u=0;std::memcpy(&u,&x,sizeof u);
  std::ostringstream s;s<<std::hex<<std::setw(16)<<std::setfill('0')<<u;return s.str();
}
double scalar(std::uint64_t u) {double x=0;std::memcpy(&x,&u,sizeof x);return x;}
void check(bool yes,const char* label) {++checks;if(!yes)throw std::runtime_error(label);}
template<class D>D exact(const DyadicSpec& s) {
  D value;check(s.limb.size()<=value.limb.size(),"reference_capacity");
  value.sign=s.sign;value.exponent=s.exponent;value.size=static_cast<unsigned>(s.limb.size());
  std::copy(s.limb.begin(),s.limb.end(),value.limb.begin());return value;
}
template<class D>bool matches(const D& value,const DyadicSpec& s) {
  return value.sign==s.sign&&value.exponent==s.exponent&&value.size==s.limb.size()&&
    std::equal(s.limb.begin(),s.limb.end(),value.limb.begin());
}
j::CoupledRatio ratio(const RatioSpec& s) {
  return {exact<j::CoupledDyadic>(s.n),exact<j::CoupledDyadic>(s.d)};
}
immutable::CoupledRatio old_ratio(const RatioSpec& s) {
  return {exact<immutable::CoupledDyadic>(s.n),exact<immutable::CoupledDyadic>(s.d)};
}
template<class A,class B>bool same_dyadic(const A& a,const B& b) {
  return a.sign==b.sign&&a.exponent==b.exponent&&a.size==b.size&&
    std::equal(a.limb.begin(),a.limb.begin()+a.size,b.limb.begin());
}
template<class A,class B>bool same_result(const A& a,const B& b) {
  return bits(a.w)==bits(b.w)&&a.source_event==b.source_event&&a.stop==b.stop&&a.hold==b.hold&&
    same_dyadic(a.remaining.n,b.remaining.n)&&same_dyadic(a.remaining.d,b.remaining.d);
}
template<class F>void rejection(F call,const std::string& reason) {
  bool rejected=false;
  try {call();}catch(const std::runtime_error& e) {
    rejected=true;check(e.what()==reason,"wrong_rejection_reason");
  }
  check(rejected,"required_rejection_missing");
}
template<class F>void run_case(const char* id,F call) {
  ++cases;const int rounding=std::fegetround();const unsigned csr=_mm_getcsr();
  try {
    call();check(std::fegetround()==rounding&&(_mm_getcsr()&0xe040u)==(csr&0xe040u),"fp_control_mutation");
  }catch(const std::exception& e) {
    ++failures;failed.push_back(std::string(id)+":"+e.what());
  }
}
j::CoupledPolynomial polynomial(const std::vector<DyadicSpec>& expected) {
  check(!expected.empty()&&expected.size()<=5,"reference_polynomial_size");
  j::CoupledPolynomial p;p.degree=static_cast<unsigned>(expected.size()-1);
  for(unsigned i=0;i<expected.size();++i) {p.c[i]=exact<j::CoupledDyadic>(expected[i]);}
  return p;
}
void certificate(const j::CoupledPolynomial& p,double w,double endpoint,
                 unsigned& splits,const Certificate& expected) {
  check(splits==expected.initial,"shared_split_input");
  const auto status=j::CCertifyDecayWindow(p,w,endpoint,splits);
  check((status==j::CoupledDecayCertificate::certified)==expected.certified,"certificate_admission");
  check(splits==expected.used&&splits<=8,"shared_split_output");
  // These are separately evaluated frozen reference cells, NOT instrumentation
  // or an assertion that the production loop visited this trace/evaluation count.
  for(const auto& cell:expected.cells) {
    const auto range=j::CIEval(p,cell.lo,cell.hi);
    check(matches(range.lo,cell.lower)&&matches(range.hi,cell.upper),"exact_reference_horner_cell");
  }
}
void law_case(const LawCase& c) {
  const auto& a=c.coefficients;
  const j::CoupledLaw p{a[0],a[1],a[2],a[3]};
  const immutable::CoupledLaw old{a[0],a[1],a[2],a[3]};
  const auto b=j::CTimeDerivative(p,c.w);
  check(b.degree+1==c.derivative.size(),"derivative_degree");
  for(unsigned i=0;i<c.derivative.size();++i)check(matches(b.c[i],c.derivative[i]),"exact_derivative_coefficient");
  unsigned splits=0;certificate(b,c.w,c.endpoint,splits,c.full);
  if(c.has_local) {
    const double half=j::CoupledRounded(c.endpoint+(c.w-c.endpoint)*0.5);
    check(bits(half)==bits(c.local.half)&&c.endpoint<half&&half<c.w,"exact_local_half");
    certificate(b,c.w,half,splits,c.local.certificate);
    if(c.local.has_time) {
      const auto time=j::CTime(p,c.inertia,c.w,half);
      check(j::CCompare(time,ratio(c.local.time))==0,"exact_half_time");
      check(j::CCompare(ratio(c.remaining),time)==c.local.order,"strict_remaining_time_order");
    }
  }
  const auto advance=[&](){return j::CAdvanceSegment(p,c.inertia,c.w,ratio(c.remaining),c.source,c.endpoint);};
  const auto old_advance=[&](){return immutable::CAdvanceSegment(old,c.inertia,c.w,old_ratio(c.remaining),c.source,c.endpoint);};
  const std::string outcome(c.outcome);
  if(outcome=="identical_original_full_path") {
    const auto was=old_advance();const auto now=advance();
    check(same_result(was,now),"immutable_full_path_bitwise_result");
    observations.push_back(std::string(c.id)+":w_bits="+bits(now.w));
  }else {
    rejection(old_advance,"coupled shaft: decay continuation uncertified");
    if(outcome=="ordinary_local_interior") {
      const auto now=advance();
      check(std::isfinite(now.w)&&now.w>c.local.half&&now.w<c.w,"local_connected_strict_interior");
      check(!now.source_event&&!now.stop&&!now.hold,"ordinary_segment_not_event_stop_hold");
      const auto requested=ratio(c.remaining);
      check(same_dyadic(now.remaining.n,requested.n)&&same_dyadic(now.remaining.d,requested.d),"no_event_time_subtraction");
      observations.push_back(std::string(c.id)+":w_bits="+bits(now.w));
    }else if(outcome=="reject_local_time") {
      rejection(advance,"coupled shaft: decay continuation uncertified");
    }else if(outcome=="reject_local_uncertified") {
      rejection(advance,"coupled shaft: decay continuation uncertified");
    }else throw std::runtime_error("unknown_frozen_outcome");
  }
}
void primitive(const std::vector<DyadicSpec>& coefficients,double lo,double hi,const Certificate& expected) {
  unsigned splits=expected.initial;certificate(polynomial(coefficients),hi,lo,splits,expected);
}
struct Controls {int rounding=std::fegetround();unsigned csr=_mm_getcsr();
  ~Controls(){std::fesetround(rounding);_mm_setcsr(csr);}};
void supplements() {
  // Independent authored compatibility inputs, with old/new bitwise comparison;
  // these supplement the frozen17 and are not numerical angular-output goldens.
  for(const auto& c:std::array<std::array<double,4>,3>{{{{0,1,0,0}},{{0,0,0,0}},{{0,2,-1,0}}}}) {
    const j::CoupledLaw p{c[0],c[1],c[2],c[3]};
    const immutable::CoupledLaw old{c[0],c[1],c[2],c[3]};
    const j::CoupledRatio h(j::CoupledDyadic(0.125),j::CoupledDyadic(1));
    const immutable::CoupledRatio oh(immutable::CoupledDyadic(0.125),immutable::CoupledDyadic(1));
    check(same_result(j::CAdvanceSegment(p,1,2,h,false,0),immutable::CAdvanceSegment(old,1,2,oh,false,0)),"growth_hold_compatibility");
  }
  rejection([](){unsigned used=9;(void)j::CCertifyDecayWindow(polynomial({{-1,0,{1}}}),1,0,used);},"coupled shaft: invalid decay split state");
  rejection([](){j::CoupledPolynomial p;p.degree=1;p.c[0]=j::CScale(j::CoupledDyadic(1),4096);
    p.c[1]=j::CoupledDyadic(1);unsigned used=0;(void)j::CCertifyDecayWindow(p,2,1,used);},"coupled shaft: exact dyadic capacity");
  rejection([](){j::CoupledPolynomial p;unsigned used=0;
    (void)j::CCertifyDecayWindow(p,std::nextafter(1.0,2.0),1,used);},"coupled shaft: decay certificate stagnation");
  for(const unsigned mask:{0x8000u,0x0040u,0x2000u}) {
    Controls restore;_mm_setcsr(restore.csr|mask);const unsigned before=_mm_getcsr();
    const int rounding_before=std::fegetround();
    check((before&mask)==mask,"unsupported_sse_test_mask_installed");
    // The first fatal guard is fegetround, which can observe SSE rounding on
    // MSVC x64; use caller control state, never a returned candidate reason.
    const char* reason=rounding_before!=FE_TONEAREST
      ? "event-aware shaft: unsupported rounding mode"
      : "event-aware shaft: FTZ/DAZ or SSE rounding unsupported";
    rejection([](){(void)j::CAdvanceSegment({-1,0.5,-0.125,0},1,2,
      j::CoupledRatio(j::CoupledDyadic(0.125),j::CoupledDyadic(1)),false,0);},reason);
    check(std::fegetround()==rounding_before&&_mm_getcsr()==before,"unsupported_sse_control_not_repaired");
  }
  {Controls restore;check(std::fesetround(FE_TOWARDZERO)==0,"set_test_round_mode");
    rejection([](){(void)j::CAdvanceSegment({-1,0.5,-0.125,0},1,2,
      j::CoupledRatio(j::CoupledDyadic(0.125),j::CoupledDyadic(1)),false,0);},"event-aware shaft: unsupported rounding mode");
    check(std::fegetround()==FE_TOWARDZERO,"unsupported_rounding_not_repaired");}
}
int main() {
  try {immutable::ShaftEnvironment();j::ShaftEnvironment();}
  catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 2;}
@@REFERENCE_CASES@@
  run_case("supplemental_compatibility_fatal_fp",supplements);
  check(cases==18,"closed17_reference_roster_plus_one_supplement");
  std::cout<<"{\"schema\":\"PistonLocalWindowNativeReferenceReceipt/v1\",\"passed\":"<<(failures?"false":"true")
    <<",\"reference_cases\":17,\"supplement_cases\":1,\"checks\":"<<checks<<",\"failures\":[";
  for(unsigned i=0;i<failed.size();++i){if(i)std::cout<<',';std::cout<<std::quoted(failed[i]);}
  std::cout<<"],\"observations\":[";
  for(unsigned i=0;i<observations.size();++i){if(i)std::cout<<',';std::cout<<std::quoted(observations[i]);}
  std::cout<<"]}\n";return failures?1:0;
}
