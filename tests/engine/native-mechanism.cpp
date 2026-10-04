// Separate backend mechanism fixture. NEVER linked as a production Session setter.
#include "native-limits.hpp"
#include "../../native/fdm_jsbsim/interactive/src/piston-model-pins.hpp"
#include <FGFDMExec.h>
#include <initialization/FGInitialCondition.h>
#include <input_output/FGGroundCallback.h>
#include <models/FGFCS.h>
#include <models/FGInertial.h>
#include <models/FGMassBalance.h>
#include <models/FGPropulsion.h>
#include <models/FGPropagate.h>
#include <models/propulsion/FGPiston.h>
#include <models/propulsion/FGThruster.h>
#include <models/propulsion/FGTank.h>
#include <models/atmosphere/FGWinds.h>
#include <fstream>
#include <iostream>
#include <iomanip>
namespace p=flight::interactive;namespace j=JSBSim;namespace c=p::c;
void demand(bool yes,const char* reason){if(!yes){throw std::runtime_error(reason);}}
c::GeodeticPosition geod(const j::FGLocation& input){auto q=input;q.SetEllipse(c::geodesy::semi_major_m/.3048,c::geodesy::semi_minor_m/.3048);return {q.GetGeodLatitudeRad(),q.GetLongitude(),q.GetGeodAltitude()*.3048};}
class Floor final:public j::FGGroundCallback {
 const p::AnalyticSurface& world_;const bool& disposing_;const std::uint64_t& tick_;
 public:Floor(const p::AnalyticSurface& world,const bool& disposing,const std::uint64_t& tick):world_(world),disposing_(disposing),tick_(tick){}
 double GetAGLevel(double,const j::FGLocation& q,j::FGLocation& contact,j::FGColumnVector3& normal,j::FGColumnVector3& velocity,j::FGColumnVector3& angular)const override{
  if(disposing_){contact=q;normal={0,0,0};velocity={0,0,0};angular={0,0,0};return 0;}
  const auto position=geod(q);const auto sample=world_.sample({{{tick_},"fuel-mechanism"},position});const auto* floor=std::get_if<c::ValidGround>(&sample.sample);demand(floor,"Mechanism world coverage missing");
  contact=q;contact.SetEllipse(c::geodesy::semi_major_m/.3048,c::geodesy::semi_minor_m/.3048);contact.SetPositionGeodetic(position.longitude_rad,position.latitude_rad,floor->surface_height_m/.3048);const auto n=p::Basis(position).ned_to_ecef(floor->normal_ned);normal={n[0],n[1],n[2]};velocity={0,0,0};angular={0,0,0};return (position.ellipsoid_height_m-floor->surface_height_m)/.3048;
 }
};
struct Dispose {bool* disposing;void operator()(j::FGFDMExec* x)const noexcept{if(x){*disposing=true;delete x;}}};
int main(int argc,char** argv){const std::string prefix=argc>2?argv[2]:"fuel-mechanism-failure";std::ofstream receipt(prefix+".json");
 try{
  if(argc<3){throw std::invalid_argument("Usage piston_fuel_mechanism model_root prefix");}
  const auto root=std::filesystem::canonical(argv[1]);for(const auto& pin:piston_file_pins){const auto path=root/std::filesystem::path(pin.path);demand(std::filesystem::is_regular_file(path)&&std::filesystem::file_size(path)==pin.bytes,"Mechanism model pin mismatch");std::ifstream in(path,std::ios::binary);std::vector<std::uint8_t> bytes(pin.bytes);in.read(reinterpret_cast<char*>(bytes.data()),static_cast<std::streamsize>(bytes.size()));demand(bool(in)&&flight::fdm::sha256(bytes)==pin.sha,"Mechanism model hash mismatch");}
  p::SurfaceConfig cfg;p::AnalyticSurface world(cfg,p::prepared_identity(cfg));std::uint64_t tick=0;bool disposing=false;std::unique_ptr<j::FGFDMExec,Dispose> exec(new j::FGFDMExec(),Dispose{&disposing});exec->SetDebugLevel(0);
  const auto utf8=root.u8string();exec->SetRootDir(SGPath::fromUtf8(std::string(utf8.begin(),utf8.end())));exec->SetAircraftPath(SGPath("aircraft"));exec->SetEnginePath(SGPath("engine"));demand(exec->LoadModel("original-piston-prop"),"Mechanism model load failed");exec->Setdt(1./120);exec->GetInertial()->SetGroundCallback(new Floor(world,disposing,tick));exec->GetWinds()->SetTurbType(j::FGWinds::ttNone);exec->SetPropertyValue("simulation/randomseed",42);
  const auto ic=exec->GetIC();demand(!ic->IsEngineRunning(0),"Mechanism IC requests running engine");ic->SetGeodLatitudeRadIC(cfg.anchor.latitude_rad);ic->SetLongitudeRadIC(cfg.anchor.longitude_rad);ic->SetThetaRadIC(0);ic->SetUBodyFpsIC(0);ic->SetWBodyFpsIC(0);ic->SetWindNEDFpsIC(0,0,0);
  double altitude=1.05/.3048;for(int i=0;i<12;++i){ic->SetAltitudeASLFtIC(altitude);const double error=1.05-geod(ic->GetPosition()).ellipsoid_height_m;if(std::abs(error)<1e-8){break;}altitude+=error/.3048;}
  const auto engine=exec->GetPropulsion()->GetEngine(0);const auto piston=dynamic_cast<j::FGPiston*>(engine.get());demand(piston,"Mechanism engine is not piston");const auto tank=exec->GetPropulsion()->GetTank(0);const auto fcs=exec->GetFCS();
  const auto controls=[&](c::PilotAxes a,std::array<bool,4> systems){fcs->SetThrottleCmd(0,a.throttle);fcs->SetThrottlePos(0,a.throttle);fcs->SetMixtureCmd(0,a.mixture);fcs->SetMixturePos(0,a.mixture);fcs->SetLBrake(a.left_brake);fcs->SetRBrake(a.right_brake);piston->SetMagnetos((systems[0]?1:0)|(systems[1]?2:0));engine->SetStarter(systems[2]);tank->SetSelected(systems[3]);};
  engine->SetRunning(false);controls(piston_fixture::phases[0].axes,piston_fixture::phases[0].switches);exec->GetPropulsion()->SetFuelFreeze(true);demand(exec->RunIC(),"Mechanism RunIC failed");controls(piston_fixture::phases[0].axes,piston_fixture::phases[0].switches);exec->GetPropulsion()->SetFuelFreeze(false);exec->GetPropagate()->InitializeDerivatives();demand(!engine->GetRunning()&&engine->GetThruster()->GetRPM()==0,"Mechanism shaft not naturally cold");
  for(int i=0;i<3;++i){const auto prefix_="gear/unit["+std::to_string(i)+"]/";exec->SetPropertyValue(prefix_+"static_friction_coeff",cfg.static_friction);exec->SetPropertyValue(prefix_+"dynamic_friction_coeff",cfg.dynamic_friction);}
  std::ofstream trace(prefix+".ndjson");const auto record=[&](const char* phase,double before,double requested){trace<<std::setprecision(17)<<"{\"fixture\":\"backend-mechanism-piston-partial-draw-v1\",\"phase\":\""<<phase<<"\",\"tick\":"<<tick<<",\"tank_before_lb\":"<<before<<",\"tank_after_lb\":"<<tank->GetContents()<<",\"requested_lb\":"<<requested<<",\"actual_lb\":"<<before-tank->GetContents()<<",\"potential_flow_lb_per_s\":"<<engine->GetFuelFlowRate()<<",\"fuel_used_lb\":"<<engine->GetFuelUsedLbs()<<",\"mass_pre_drain_slug\":"<<exec->GetMassBalance()->GetMass()<<",\"pre_prop_engine_rpm\":"<<piston->getRPM()<<",\"post_prop_rpm\":"<<engine->GetThruster()->GetRPM()<<",\"running\":"<<(engine->GetRunning()?"true":"false")<<",\"starved\":"<<(engine->GetStarved()?"true":"false")<<",\"starter\":"<<(engine->GetStarter()?"true":"false")<<"}\n";};
  record("natural-cold",tank->GetContents(),0);
  for(unsigned i=0;i<8*120;++i){const auto& phase=piston_fixture::phases[i>=120?1:0];controls(phase.axes,phase.switches);const double before=tank->GetContents(),used=engine->GetFuelUsedLbs();++tick;demand(exec->Run(),"Mechanism natural startup Run failed");record("natural-setup",before,engine->GetFuelUsedLbs()-used);}
  demand(engine->GetRunning()&&engine->GetThruster()->GetRPM()>=480&&engine->GetFuelFlowRate()*.45359237>=1e-4,"Mechanism fixed t8 natural setup precondition failed");
  // SINGLE disclosed test-only fuel seed, not a production Session capability.
  engine->SetStarter(false);const double previous_mass=exec->GetMassBalance()->GetMass();tank->SetContents(1e-7/.45359237);
  trace<<std::setprecision(17)<<"{\"fixture\":\"backend-mechanism-piston-partial-draw-v1\",\"phase\":\"seeded-boundary-not-completed\",\"tick\":"<<tick<<",\"seed_count\":1,\"initial_observed_contents_kg\":1e-7,\"previous_completed_mass_slug\":"<<previous_mass<<",\"starter\":false}\n";
  for(unsigned i=0;i<8;++i){const double before=tank->GetContents(),used=engine->GetFuelUsedLbs();++tick;demand(exec->Run(),"Mechanism observed Run failed");record("observed-drain",before,engine->GetFuelUsedLbs()-used);}
  receipt<<"{\"passed\":true,\"scope\":\"backend mechanism trace only; separate numerical oracle\",\"fixture\":\"backend-mechanism-piston-partial-draw-v1\",\"model_inventory_sha256\":\"f8ef5011243ef8cf16e13924a5cdc902c2055ba4789a4bfd0cba209533594b7a\",\"initial_observed_contents_kg\":1e-7,\"hz\":120,\"seed\":42,\"seed_count\":1,\"production_session_mutation_api\":false,\"limits_sha256\":\""<<piston_fixture::limits_sha<<"\",\"source_fingerprint\":\""<<p::source_fingerprint()<<"\",\"prepared_world_sha256\":\""<<world.identity().prepared_surface_sha256<<"\"}\n";return 0;
 }catch(const std::exception& e){std::cerr<<e.what()<<'\n';receipt<<"{\"passed\":false,\"scope\":\"backend mechanism trace failed; preserve stderr\"}\n";return 1;}
}
