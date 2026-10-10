// Isolated real-library unit fixture. Explicit held inputs/RPM; NEVER cold flight.
#include "loaded-library.hpp"
#include <FGFDMExec.h>
#include <models/FGPropulsion.h>
#include <models/propulsion/FGEngine.h>
#include <models/propulsion/FGPiston.h>
#include <models/propulsion/FGPropeller.h>
#include <math/FGTable.h>
#include <algorithm>
#include <cfenv>
#include <cmath>
#include <filesystem>
#include <iomanip>
#include <iostream>
#include <memory>
#include <limits>
#include <numbers>
#include <set>
#include <sstream>
#include <xmmintrin.h>
#if !defined(FLIGHT_JSBSIM_COUPLED_MIDPOINT_SHAFT) || !FLIGHT_JSBSIM_COUPLED_MIDPOINT_SHAFT
#error This fixture requires the reviewed matching patched backend and headers.
#endif
namespace j=JSBSim;
static_assert(sizeof(void*)==8&&sizeof(double)==8&&std::numeric_limits<double>::is_iec559&&std::numeric_limits<double>::digits==53,"Qualified fixture requires x64 binary64");
using Method=j::FGPropeller::AngularIntegrationMethod;
void demand(bool ok,const char* why){if(!ok)throw std::runtime_error(why);}
std::unique_ptr<j::FGFDMExec> load(const std::filesystem::path& root){
 auto exec=std::make_unique<j::FGFDMExec>();exec->SetDebugLevel(0);
 const auto utf8=root.u8string();exec->SetRootDir(SGPath::fromUtf8(std::string(utf8.begin(),utf8.end())));
 exec->SetAircraftPath(SGPath("aircraft"));exec->SetEnginePath(SGPath("engine"));
 demand(exec->LoadModel("original-piston-prop"),"Original corrected model load failed");return exec;
}
j::FGPropeller& prop(j::FGFDMExec& exec){
 demand(exec.GetPropulsion()->GetNumEngines()==1&&exec.GetPropulsion()->GetNumTanks()==1,"Original topology mismatch");
 auto* value=dynamic_cast<j::FGPropeller*>(exec.GetPropulsion()->GetEngine(0)->GetThruster());
 demand(value!=nullptr,"Actual propeller missing");
 demand(value->GetIxx()==2&&value->GetDiameter()==6&&value->GetGearRatio()==1&&!value->IsVPitch(),"Original prop identity mismatch");
 demand(value->GetCtFactor()==1&&value->GetCpFactor()==1&&value->GetCtMachTable()==nullptr&&value->GetCpMachTable()==nullptr,"Unexpected coefficient scaling");return *value;
}
int main(int argc,char** argv){
 try{
  demand(argc==2,"Usage prop_library_probe corrected_model_root < requests.txt");
  const int rounding=std::fegetround();const unsigned mxcsr=_mm_getcsr();
  demand(rounding==FE_TONEAREST&&(mxcsr&0xe040U)==0,"Unsupported FP environment; fixture does not repair it");
  const auto module=piston_fixture::loaded_library_path();const auto root=std::filesystem::canonical(argv[1]);
  {auto exec=load(root);auto& p=prop(*exec);
   demand(p.GetAngularIntegrationMethod()==Method::legacy_euler,"Fresh object is not legacy");
   demand(!p.SetAngularIntegrationMethod(static_cast<Method>(99))&&p.GetAngularIntegrationMethod()==Method::legacy_euler,"Unknown setter changed legacy");
   demand(p.SetAngularIntegrationMethod(Method::event_aware_constant_power_v1)&&p.GetAngularIntegrationMethod()==Method::event_aware_constant_power_v1,"Event selection failed");
   demand(!p.SetAngularIntegrationMethod(static_cast<Method>(99))&&p.GetAngularIntegrationMethod()==Method::event_aware_constant_power_v1,"Unknown setter changed event method");
   p.ResetToIC();demand(p.GetAngularIntegrationMethod()==Method::event_aware_constant_power_v1,"Reset lost event selection");
   demand(p.SetAngularIntegrationMethod(Method::legacy_euler)&&p.GetAngularIntegrationMethod()==Method::legacy_euler,"Legacy reselection failed");
   p.ResetToIC();demand(p.GetAngularIntegrationMethod()==Method::legacy_euler,"Reset lost legacy selection");
   auto* piston=dynamic_cast<j::FGPiston*>(exec->GetPropulsion()->GetEngine(0).get());
   demand(piston&&piston->SupportsCoupledShaftProfileV1()&&p.SupportsCoupledShaftProfileV1(),"Loaded pair does not admit source-law profile");
   demand(p.SetAngularIntegrationMethod(Method::event_aware_coupled_midpoint_v1)&&p.GetAngularIntegrationMethod()==Method::event_aware_coupled_midpoint_v1,"Coupled selection failed");
   demand(!p.SetAngularIntegrationMethod(static_cast<Method>(99))&&p.GetAngularIntegrationMethod()==Method::event_aware_coupled_midpoint_v1,"Unknown setter changed coupled method");
   p.ResetToIC();demand(p.GetAngularIntegrationMethod()==Method::event_aware_coupled_midpoint_v1,"Reset lost coupled selection");
   const double before=p.GetRPM();bool scalarRejected=false;
   try{p.Calculate(0.0);}catch(const std::runtime_error& e){scalarRejected=std::string(e.what())=="coupled shaft: scalar Calculate has no owned piston frame";}
   demand(scalarRejected&&p.GetRPM()==before&&p.GetAngularIntegrationMethod()==Method::event_aware_coupled_midpoint_v1,"Scalar Calculate was not rejected unchanged");
   // Existing public setters in a disclosed unit fixture, never production
   // content/properties or the cold scenario. Restore every value immediately.
   p.SetCpFactor(2.0);demand(!p.SupportsCoupledShaftProfileV1(),"Unsupported CP scale admitted");p.SetCpFactor(1.0);
   p.SetCtFactor(2.0);demand(!p.SupportsCoupledShaftProfileV1(),"Unsupported CT scale admitted");p.SetCtFactor(1.0);
   p.SetPitch(21.0);demand(!p.SupportsCoupledShaftProfileV1(),"Unsupported pitch admitted");p.SetPitch(20.0);
   p.SetConstantSpeed(1);demand(!p.SupportsCoupledShaftProfileV1(),"Unsupported pitch topology admitted");p.SetConstantSpeed(0);
   p.SetFeather(true);demand(!p.SupportsCoupledShaftProfileV1(),"Unsupported feather admitted");p.SetFeather(false);
   demand(p.SupportsCoupledShaftProfileV1(),"Unit topology fixture did not restore original profile");
   demand(p.SetAngularIntegrationMethod(Method::legacy_euler),"Legacy return from coupled failed");
  }
  // A separate fresh actual object runs every legacy case WITHOUT any setter.
  auto exec=load(root);auto& p=prop(*exec);demand(p.GetAngularIntegrationMethod()==Method::legacy_euler,"Second fresh object is not legacy");
  std::cout<<std::setprecision(17)<<std::boolalpha;
  std::cout<<"{\"kind\":\"guard\",\"passed\":true,\"fresh_legacy\":true,\"unknown_rejected_unchanged\":true,\"reset_retains_event\":true,\"legacy_return\":true,\"case_object_fresh_unset\":true,\"loaded_original_pair_supported\":true,\"reset_retains_coupled\":true,\"unknown_coupled_rejected_unchanged\":true,\"scalar_coupled_rejected_unchanged\":true,\"unsupported_public_prop_settings_rejected\":true,\"loaded_library_path\":"<<piston_fixture::json_path(module)<<",\"fp_rounding\":"<<rounding<<",\"fp_mxcsr\":"<<mxcsr<<"}\n";
  std::string line;std::set<std::string> ids;unsigned count=0;
  while(std::getline(std::cin,line)){
   std::istringstream input(line);std::string id,extra;double n,vel,power,rho,q,r;unsigned hz;
   demand(bool(input>>id>>n>>vel>>power>>rho>>hz>>q>>r)&&!(input>>extra),"Malformed case request");
   demand(ids.insert(id).second&&(hz==60||hz==120||hz==240)&&std::isfinite(n)&&n>=0&&std::isfinite(vel)&&std::isfinite(power)&&std::isfinite(rho)&&rho>0&&std::isfinite(q)&&std::isfinite(r),"Invalid case request");
   demand(p.GetAngularIntegrationMethod()==Method::legacy_euler,"Default method changed before case");
   p.in={};p.in.TotalDeltaT=1.0/hz;p.in.Density=rho;p.in.Soundspeed=1120;
   p.in.AeroUVW=j::FGColumnVector3(vel,0,0);p.in.AeroPQR=j::FGColumnVector3(0,0,0);p.in.PQRi=j::FGColumnVector3(0,q,r);
   p.SetRPM(n*60.0);const double pre_rps=p.GetRPM()/60.0,omega=pre_rps*2.0*std::numbers::pi;
   // Actual library Calculate sets J first, then calls GetPowerRequired, thrust,
   // torque/momentum and legacy RPM integration. Reading PowerRequired observes
   // that stored pre-stage load; calling GetPowerRequired now would use post-RPM.
   const double thrust=p.Calculate(power),post_rpm=p.GetRPM(),post=post_rpm/60.0*2.0*std::numbers::pi;
   const double advance=exec->GetPropertyValue("propulsion/engine[0]/advance-ratio");
   const double load_power=exec->GetPropertyValue("propulsion/engine[0]/propeller-power-ftlbps");
   const double ct=p.GetThrustCoefficient(),cp=p.GetCPowerTable()->GetValue(advance);
   p.GetBodyForces();const auto moments=p.GetMoments();
   const double excess=(power-load_power)/(omega>0.01?omega:1.0);
   const double unclamped=omega+excess/p.GetIxx()*p.in.TotalDeltaT;
   demand(p.GetAngularIntegrationMethod()==Method::legacy_euler,"Default method changed after case");
   // Arithmetic may set ordinary sticky exception flags; control bits must stay.
   demand(std::fegetround()==rounding&&(_mm_getcsr()&0xe040U)==(mxcsr&0xe040U),"Fixture changed FP controls");
   std::cout<<"{\"kind\":\"prop-discrete\",\"id\":"<<piston_fixture::json_path(id)<<",\"actual_default_legacy\":true,\"observations\":{";
   std::cout<<"\"advance_ratio\":"<<advance<<",\"ct\":"<<ct<<",\"cp\":"<<cp<<",\"thrust_lbf\":"<<thrust<<",\"thrust_n\":"<<thrust*4.4482216152605;
   std::cout<<",\"load_power_ftlbf_per_s\":"<<load_power<<",\"load_power_w\":"<<load_power*(0.3048*4.4482216152605)<<",\"pre_omega_radps\":"<<omega;
   std::cout<<",\"excess_torque_ftlbf\":"<<excess<<",\"post_omega_radps\":"<<post<<",\"post_rpm\":"<<post_rpm<<",\"body_torque_x_ftlbf\":"<<p.GetTorque();
   std::cout<<",\"gyro_moment_y_ftlbf\":"<<moments(2)<<",\"gyro_moment_z_ftlbf\":"<<moments(3);
   std::cout<<",\"unclamped_angular_impulse_residual\":"<<p.GetIxx()*(unclamped-omega)-excess*p.in.TotalDeltaT;
   std::cout<<",\"discrete_kinetic_energy_delta_ftlbf\":"<<p.GetIxx()*(post*post-omega*omega)/2.0<<",\"rpm_clamp_active\":"<<(unclamped<0)<<",\"near_zero_advance_branch\":"<<(pre_rps<=0.01)<<"}}\n";
   ++count;
  }
  demand(count==13,"Expected all 13 unchanged prop-discrete requests");return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
