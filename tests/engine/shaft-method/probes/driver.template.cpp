// Private source-extraction fixture. No actual engine/model is constructed.
// Scalars are supplied as exact binary64 bit strings, never decimal baselines.
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
@@PINNED_PI@@
static_assert(sizeof(void*)==8,"Only the actual x64 strict route is qualified");
static_assert(M_PI==3.14159265358979323846,"Pinned backend pi definition required");
namespace JSBSim {
@@OWNED_TYPES@@
@@EXACT_HELPERS@@
@@PISTON_CHECK@@
bool ExtractedModePolicy(bool Running,bool spark,bool fuel,double RPM,double IdleRPM,double prospectiveIndicated) {
@@EXACT_MODE_POLICY@@
  return Running;
}

// Held source fields. ME is the actual table RESULT, not an alternate table.
struct CoefficientInputs {
  bool Running,Cranking;
  double StarterTorque,StarterGain,StarterRPM,RPM,Cycles,displacement_SI;
  double StaticFriction_HP,PMEP,MAP,R_air,T_amb,volumetric_efficiency_reduced;
  double equivalence_ratio,ME,sparkFactor,ISFC,FMEPStatic,FMEPDynamic,Stroke,fttom;
};
CoupledShaftFrameV1 ExtractedCoefficients(const CoefficientInputs& q,double h) {
  ShaftEnvironment();
  const auto& [Running,Cranking,StarterTorque,StarterGain,StarterRPM,RPM,Cycles,displacement_SI,
    StaticFriction_HP,PMEP,MAP,R_air,T_amb,volumetric_efficiency_reduced,
    equivalence_ratio,ME,sparkFactor,ISFC,FMEPStatic,FMEPDynamic,Stroke,fttom]=q;
  @@EXACT_RATIO@@
  @@EXACT_SOURCE_FACTORS@@
  (void)omega;
  @@EXACT_COEFFICIENTS@@
  return {Running?ShaftOperatingModeV1::running:(Cranking?ShaftOperatingModeV1::cranking:ShaftOperatingModeV1::stopped),
    RPM,h,c0,c1,c2,starterTorque,starterLimit};
}

// Exact original encode statements and new angular wrapper branch are retained.
// This isolated class is a wrapper fixture, never an FGPropeller substitute.
struct ExtractedWrapper {
  double RPM,Ixx=2.0,Diameter=6.0;
  void apply(const CoupledShaftFrameV1* frame,double rho,double Vel) {
    double omega=0.0;
@@EXACT_ENCODE@@
@@EXACT_WRAPPER@@
  }
};
}
namespace j=JSBSim;
std::string bits(double x) {
  std::uint64_t u=0;std::memcpy(&u,&x,8);
  std::ostringstream s;s<<std::hex<<std::setw(16)<<std::setfill('0')<<u;return s.str();
}
double scalar(std::istringstream& in) {
  std::string s;if(!(in>>s)||s.size()!=16||s.find_first_not_of("0123456789abcdefABCDEF")!=s.npos)
    throw std::runtime_error("Expected exactly16 hexadecimal binary64 digits");
  const std::uint64_t u=std::stoull(s,nullptr,16);double d;std::memcpy(&d,&u,8);return d;
}
void end(std::istringstream& in) {std::string s;if(in>>s)throw std::runtime_error("Extra request field");}
void dyadic(const j::CoupledDyadic& a) {
  std::cout<<"{\"sign\":"<<a.sign<<",\"exponent\":"<<a.exponent<<",\"limbs_le\":[";
  for(unsigned i=0;i<a.size;++i){if(i)std::cout<<',';std::cout<<a.limb[i];}std::cout<<"]}";
}
void ratio(const j::CoupledRatio& r) {std::cout<<"{\"n\":";dyadic(r.n);std::cout<<",\"d\":";dyadic(r.d);std::cout<<'}';}
std::string quoted(const std::string& s) {
  std::ostringstream out;out<<'"';for(unsigned char c:s){
    if(c=='"'||c=='\\')out<<'\\'<<char(c);else if(c<32)out<<"\\u"<<std::hex<<std::setw(4)<<std::setfill('0')<<unsigned(c);else out<<char(c);
  }out<<'"';return out.str();
}
struct Controls {
  int rounding=std::fegetround();unsigned csr=_mm_getcsr();
  ~Controls(){std::fesetround(rounding);_mm_setcsr(csr);}
};
int main() {
  std::cout<<std::boolalpha;
  std::string line;
  while(std::getline(std::cin,line)) {
    const int incomingRounding=std::fegetround();const unsigned incomingCSR=_mm_getcsr();
    std::istringstream in(line);std::string id,kind;
    if(!(in>>id>>kind)||id.find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.")!=id.npos)
      {std::cerr<<"Malformed request id/kind\n";return 2;}
    try {
      if(kind=="K") {
        j::CoupledLaw p{scalar(in),scalar(in),scalar(in),scalar(in)};
        const double I=scalar(in),w=scalar(in),h=scalar(in);int has;
        if(!(in>>has)||(has!=0&&has!=1))throw std::runtime_error("Invalid endpoint flag");
        const double endpoint=scalar(in);end(in);
        const auto r=j::CAdvanceSegment(p,I,w,j::CoupledRatio(j::CoupledDyadic(h),j::CoupledDyadic(1.0)),has,endpoint);
        std::cout<<"{\"id\":"<<quoted(id)<<",\"kind\":\"K\",\"rejected\":false,\"w_bits\":\""<<bits(r.w)<<"\",\"hold\":"<<r.hold<<",\"stop\":"<<r.stop<<",\"source_event\":"<<r.source_event<<",\"remaining\":";ratio(r.remaining);std::cout<<"}\n";
      } else if(kind=="E"||kind=="W") {
        int mode;if(!(in>>mode))throw std::runtime_error("Missing mode");
        j::CoupledShaftFrameV1 f{static_cast<j::ShaftOperatingModeV1>(mode),scalar(in),scalar(in),scalar(in),scalar(in),scalar(in),scalar(in),scalar(in)};
        const double w=scalar(in),I=scalar(in),rho=scalar(in),D=scalar(in),V=scalar(in);end(in);
        if(kind=="E") {
          const auto r=j::CoupledMidpointStep(f,w,I,rho,D,V);
          std::cout<<"{\"id\":"<<quoted(id)<<",\"kind\":\"E\",\"rejected\":false,\"w_bits\":\""<<bits(r.final_w_radps)<<"\",\"hold\":"<<r.hold<<",\"stop\":"<<r.reached_stop<<",\"cp_crossings\":"<<r.cp_crossings<<",\"starter_crossings\":"<<r.starter_taper_crossings<<"}\n";
        } else {
          j::ExtractedWrapper fixture{f.pre_step_engine_rpm,I,D};fixture.apply(&f,rho,V);
          std::cout<<"{\"id\":"<<quoted(id)<<",\"kind\":\"W\",\"rejected\":false,\"rpm_bits\":\""<<bits(fixture.RPM)<<"\"}\n";
        }
      } else if(kind=="L") {
        int mode;if(!(in>>mode))throw std::runtime_error("Missing mode");
        j::CoupledShaftFrameV1 f{static_cast<j::ShaftOperatingModeV1>(mode),scalar(in),scalar(in),scalar(in),scalar(in),scalar(in),scalar(in),scalar(in)};
        const double w=scalar(in),knot=scalar(in),load=scalar(in),A=scalar(in);int direction;
        if(!(in>>direction)||(direction!=-1&&direction!=1))throw std::runtime_error("Invalid direction");end(in);
        const auto p=j::CBuildLaw(f,w,knot,load,A,direction);
        std::cout<<"{\"id\":"<<quoted(id)<<",\"kind\":\"L\",\"rejected\":false,\"c0_bits\":\""<<bits(p.c0)<<"\",\"c1_bits\":\""<<bits(p.c1)<<"\",\"c2_bits\":\""<<bits(p.c2)<<"\",\"c3_bits\":\""<<bits(p.c3)<<"\"}\n";
      } else if(kind=="P") {
        int prior,spark,fuel;if(!(in>>prior>>spark>>fuel)||(prior!=0&&prior!=1)||(spark!=0&&spark!=1)||(fuel!=0&&fuel!=1))throw std::runtime_error("Invalid policy boolean");
        const double rpm=scalar(in),idle=scalar(in),hp=scalar(in);end(in);
        std::cout<<"{\"id\":"<<quoted(id)<<",\"kind\":\"P\",\"rejected\":false,\"running\":"<<j::ExtractedModePolicy(prior!=0,spark!=0,fuel!=0,rpm,idle,hp)<<"}\n";
      } else if(kind=="C") {
        int running,cranking;if(!(in>>running>>cranking)||(running!=0&&running!=1)||(cranking!=0&&cranking!=1))throw std::runtime_error("Invalid coefficient mode");
        j::CoefficientInputs q{};q.Running=running!=0;q.Cranking=cranking!=0;
        double* fields[]={&q.StarterTorque,&q.StarterGain,&q.StarterRPM,&q.RPM,&q.Cycles,&q.displacement_SI,&q.StaticFriction_HP,&q.PMEP,&q.MAP,&q.R_air,&q.T_amb,&q.volumetric_efficiency_reduced,&q.equivalence_ratio,&q.ME,&q.sparkFactor,&q.ISFC,&q.FMEPStatic,&q.FMEPDynamic,&q.Stroke,&q.fttom};
        for(double* p:fields)*p=scalar(in);const double h=scalar(in);end(in);
        const auto f=j::ExtractedCoefficients(q,h);
        std::cout<<"{\"id\":"<<quoted(id)<<",\"kind\":\"C\",\"rejected\":false,\"c0_bits\":\""<<bits(f.engine_c0_ftlb_per_s)<<"\",\"c1_bits\":\""<<bits(f.engine_c1_ftlb)<<"\",\"c2_bits\":\""<<bits(f.engine_c2_ftlb_s)<<"\",\"t0_bits\":\""<<bits(f.starter_torque_ftlb)<<"\",\"ws_bits\":\""<<bits(f.starter_limit_w_radps)<<"\"}\n";
      } else if(kind=="G") {
        std::string guard;if(!(in>>guard))throw std::runtime_error("Missing guard name");
        if(guard=="operand"){const double x=scalar(in);end(in);j::ShaftEnvironment();j::CoupledOperand(x);}
        else {
          end(in);
          if(guard=="product"){j::CoupledRounded(std::ldexp(1.0,60)*2.0);}
          else if(guard=="bisect64") {
            j::CoupledPolynomial p;p.degree=1;p.c[0]=j::CoupledDyadic(-std::ldexp(1.0,-60));p.c[1]=j::CoupledDyadic(1.0);
            j::CIsolate(p,0.0,std::ldexp(1.0,60));
          } else if(guard=="split8") {j::CCertifyDecay(j::CoupledLaw{0.0,2.0,-1.0,0.0},2.0,1.0);}
          else if(guard=="capacity128") {j::CAdd(j::CScale(j::CoupledDyadic(1.0),4096),j::CoupledDyadic(1.0));}
          else if(guard=="ftz"||guard=="daz"||guard=="rounding") {
            Controls save;
            if(guard=="rounding")std::fesetround(FE_TOWARDZERO);
            else _mm_setcsr(save.csr|(guard=="ftz"?0x8000u:0x0040u));
            j::ShaftEnvironment();
          } else throw std::runtime_error("Unknown guard");
        }
        std::cout<<"{\"id\":"<<quoted(id)<<",\"kind\":\"G\",\"rejected\":false}\n";
      } else throw std::runtime_error("Unknown request kind");
    }catch(const std::exception& e){std::cout<<"{\"id\":"<<quoted(id)<<",\"kind\":"<<quoted(kind)<<",\"rejected\":true,\"reason\":"<<quoted(e.what())<<"}\n";}
    if(std::fegetround()!=incomingRounding||(_mm_getcsr()&0xe040u)!=(incomingCSR&0xe040u))
      {std::cerr<<"Fixture failed to retain FP control bits\n";return 3;}
  }
  return 0;
}
