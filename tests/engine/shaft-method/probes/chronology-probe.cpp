// Actual-DLL UNIT fixture with disclosed held inputs/RPM seeds. NEVER cold flight.
#include "loaded-library.hpp"
#include <FGFDMExec.h>
#include <models/FGPropulsion.h>
#include <models/propulsion/FGPiston.h>
#include <models/propulsion/FGPropeller.h>
#include <models/propulsion/FGTank.h>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#if !defined(FLIGHT_JSBSIM_COUPLED_MIDPOINT_SHAFT) || !FLIGHT_JSBSIM_COUPLED_MIDPOINT_SHAFT
#error Actual chronology probe requires reviewed schema3 source and DLL.
#endif
namespace j=JSBSim;
using Method=j::FGPropeller::AngularIntegrationMethod;
void demand(bool yes,const char* why){if(!yes)throw std::runtime_error(why);}
struct Fixture {
  std::unique_ptr<j::FGFDMExec> exec=std::make_unique<j::FGFDMExec>();
  j::FGPiston* engine=nullptr;j::FGPropeller* prop=nullptr;
  Fixture(const std::string& root,double rpm,bool prior,bool starter,double mixture,int magnetos,double h){
    exec->SetDebugLevel(0);exec->SetRootDir(SGPath::fromUtf8(root));exec->SetAircraftPath(SGPath("aircraft"));exec->SetEnginePath(SGPath("engine"));
    demand(exec->LoadModel("original-piston-prop"),"Chronology original model load failed");
    demand(exec->GetPropulsion()->GetNumEngines()==1&&exec->GetPropulsion()->GetNumTanks()==1,"Chronology original topology mismatch");
    engine=dynamic_cast<j::FGPiston*>(exec->GetPropulsion()->GetEngine(0).get());
    demand(engine,"Chronology actual piston missing");prop=dynamic_cast<j::FGPropeller*>(engine->GetThruster());
    demand(prop&&prop->SupportsCoupledShaftProfileV1()&&engine->SupportsCoupledShaftProfileV1(),"Chronology actual source profile mismatch");
    auto& in=engine->in;in={};
    in.Pressure=2116.22;in.PressureRatio=1.0;in.TotalPressure=in.Pressure;
    in.Temperature=518.67;in.Density=0.0023769;in.DensityRatio=1.0;
    in.Soundspeed=1116.45;in.TAT_c=15.0;in.TotalDeltaT=h;
    in.AeroUVW={0,0,0};in.AeroPQR={0,0,0};in.PQRi={0,0,0};
    in.ThrottleCmd={1.0};in.ThrottlePos={1.0};in.MixtureCmd={mixture};in.MixturePos={mixture};
    in.PropAdvance={0.0};in.PropFeather={false};
    // Explicit unit initialization, before any observed call. Reset sees valid
    // ambient inputs, hence starts its ordinary MAP/thermal state consistently.
    engine->ResetToIC();engine->SetRunning(prior);engine->SetStarved(false);
    engine->SetStarter(starter);engine->SetMagnetos(magnetos);prop->SetRPM(rpm);
    demand(prop->SetAngularIntegrationMethod(Method::event_aware_coupled_midpoint_v1)&&prop->GetAngularIntegrationMethod()==Method::event_aware_coupled_midpoint_v1,"Chronology actual method admission failed");
    exec->GetPropulsion()->SetFuelFreeze(false);
  }
  void observe(const char* id) {
    demand(prop->GetAngularIntegrationMethod()==Method::event_aware_coupled_midpoint_v1,"Chronology method changed");
    auto tank=exec->GetPropulsion()->GetTank(0);
    std::cout<<"{\"kind\":\"chronology\",\"id\":"<<piston_fixture::json_path(id)
      <<",\"unit_rpm_seed_only\":true,\"running\":"<<engine->GetRunning()<<",\"cranking\":"<<engine->GetCranking()<<",\"starved\":"<<engine->GetStarved()
      <<",\"pre_engine_rpm\":"<<engine->getRPM()<<",\"post_prop_rpm\":"<<prop->GetRPM()
      <<",\"fuel_lb_per_s\":"<<engine->GetFuelFlowRate()<<",\"fuel_pph\":"<<engine->getFuelFlow_pph()
      <<",\"power_ftlb_per_s\":"<<engine->GetPowerAvailable()<<",\"map_pa\":"<<exec->GetPropertyValue("propulsion/engine[0]/map-pa")
      <<",\"pressure_psf\":"<<engine->in.Pressure<<",\"h_s\":"<<engine->in.TotalDeltaT<<",\"reaction_torque_ftlb\":"<<prop->GetTorque()
      <<",\"fuel_used_lb\":"<<engine->GetFuelUsedLbs()<<",\"tank_lb\":"<<tank->GetContents()<<",\"tank_selected\":"<<tank->GetSelected()<<"}\n";
  }
};
int main(int argc,char** argv){try{
  demand(argc==2,"Usage chronology_probe corrected_model_root");
  const auto module=piston_fixture::loaded_library_path();
  std::cout<<std::setprecision(17)<<std::boolalpha;
  std::cout<<"{\"kind\":\"chronology-identity\",\"loaded_library_path\":"<<piston_fixture::json_path(module)<<",\"actual_model\":\"original-piston-prop\",\"scope\":\"fixed actual-DLL unit fixtures; not natural cold scenario\"}\n";
  for(int cut=0;cut<2;++cut){
    Fixture f(argv[1],1200.0,true,false,cut==0?0.0:1.0,cut==0?3:0,1.0/120.0);
    f.engine->Calculate();f.observe(cut==0?"M01-mixture-cutoff":"M01-spark-cutoff");
  }
  {
    Fixture f(argv[1],1200.0,true,false,1.0,3,1.0/120.0);
    f.exec->GetPropulsion()->GetTank(0)->SetSelected(false);
    demand(!f.engine->GetStarved(),"M02 previous fuel state fixture failed");
    demand(!f.exec->GetPropulsion()->Run(false),"M02 first actual propulsion Run skipped");f.observe("M02-feed-first");
    demand(!f.exec->GetPropulsion()->Run(false),"M02 second actual propulsion Run skipped");f.observe("M02-feed-second");
  }
  for(int prior=0;prior<2;++prior)for(int side=-1;side<=1;++side){
    const double rpm=480.0+side*std::ldexp(1.0,-12);
    Fixture f(argv[1],rpm,prior!=0,false,1.0,3,0.0);
    f.engine->Calculate();
    const std::string id="M03-rpm-"+std::to_string(prior)+"-"+std::to_string(side+1);f.observe(id.c_str());
  }
  {
    Fixture f(argv[1],480.0-std::ldexp(1.0,-12),false,true,1.0,3,1.0/120.0);
    f.engine->Calculate();f.observe("M04-crossing-first");
    f.engine->Calculate();f.observe("M04-crossing-next");
  }
  return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
