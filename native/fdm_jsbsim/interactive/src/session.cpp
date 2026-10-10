#include <flight/interactive/session.hpp>
#include "piston-model-pins.hpp"
#include <flight/fdm/protocol.hpp>
#include <FGFDMExec.h>
#include <initialization/FGInitialCondition.h>
#include <initialization/FGTrim.h>
#include <input_output/FGGroundCallback.h>
#include <models/FGAccelerations.h>
#include <models/FGFCS.h>
#include <models/FGGroundReactions.h>
#include <models/FGInertial.h>
#include <models/FGMassBalance.h>
#include <models/FGPropagate.h>
#include <models/FGPropulsion.h>
#include <models/propulsion/FGTank.h>
#include <models/propulsion/FGPiston.h>
#include <models/propulsion/FGPropeller.h>
#include <set>
#include <numbers>
#include <models/atmosphere/FGWinds.h>
#include <models/FGAtmosphere.h>
#include <models/FGAuxiliary.h>
#include <models/FGAerodynamics.h>
#include <fstream>
#include <sstream>
#include <iomanip>
#include <thread>

namespace flight::interactive {
namespace j=JSBSim;namespace f=flight::fdm;
namespace {
#if defined(FLIGHT_JSBSIM_EVENT_AWARE_SHAFT) && FLIGHT_JSBSIM_EVENT_AWARE_SHAFT
j::FGPropeller::AngularIntegrationMethod vendor_angular_method(AngularMethod method) {
  switch(method) {
    case AngularMethod::legacy_euler:return j::FGPropeller::AngularIntegrationMethod::legacy_euler;
    case AngularMethod::event_aware_constant_power_v1:return j::FGPropeller::AngularIntegrationMethod::event_aware_constant_power_v1;
#if defined(FLIGHT_JSBSIM_COUPLED_MIDPOINT_SHAFT) && FLIGHT_JSBSIM_COUPLED_MIDPOINT_SHAFT
    case AngularMethod::event_aware_coupled_midpoint_v1:return j::FGPropeller::AngularIntegrationMethod::event_aware_coupled_midpoint_v1;
#else
    case AngularMethod::event_aware_coupled_midpoint_v1:break;
#endif
  }
  throw std::invalid_argument("Selected backend lacks the requested angular method");
}
#endif
constexpr double slug_to_kg=14.5939029372064, speed_limit=150, rate_limit=3, gear_radius=2.5;
c::NedVelocity steady_wind(SteadyWindProfile profile) {
  switch(profile) {
    case SteadyWindProfile::calm:return {0,0,0};
    case SteadyWindProfile::from_north:return {-5,0,0};
    case SteadyWindProfile::from_west:return {0,5,0};
    case SteadyWindProfile::from_east:return {0,-5,0};
  }
  throw std::invalid_argument("Unknown steady-wind profile");
}
c::GeodeticPosition geodetic(const j::FGLocation& input) {
  auto p=input;p.SetEllipse(c::geodesy::semi_major_m/.3048,c::geodesy::semi_minor_m/.3048);
  return {p.GetGeodLatitudeRad(),p.GetLongitude(),p.GetGeodAltitude()*.3048};
}
c::EcefPosition ecef(const j::FGLocation& p){return {p(1)*.3048,p(2)*.3048,p(3)*.3048};}
void verify_model(const std::filesystem::path& root) {
  const auto base=std::filesystem::canonical(root);
  for(const auto& pin:file_pins) {
    const auto path=std::filesystem::canonical(base/std::filesystem::path(pin.path));const auto relative=path.lexically_relative(base);
    if(relative.empty()||*relative.begin()==".."||!std::filesystem::is_regular_file(path)||std::filesystem::file_size(path)!=pin.bytes){throw std::invalid_argument("New original model pin/path mismatch");}
    std::ifstream input(path,std::ios::binary);std::vector<std::uint8_t> bytes(pin.bytes);input.read(reinterpret_cast<char*>(bytes.data()),static_cast<std::streamsize>(bytes.size()));
    if(!input||f::sha256(bytes)!=pin.sha){throw std::invalid_argument("New original model byte hash mismatch");}
  }

}
void verify_piston_model(const std::filesystem::path& root) {
  if(std::filesystem::is_symlink(std::filesystem::symlink_status(root))){throw std::invalid_argument("Piston model root alias rejected");}
  const auto base=std::filesystem::canonical(root);std::set<std::filesystem::path> expected;
  for(const auto& pin:piston_file_pins) {
    const std::filesystem::path relative(pin.path);const auto path=base/relative;expected.insert(relative);
    if(std::filesystem::is_symlink(std::filesystem::symlink_status(path))||!std::filesystem::is_regular_file(path)||std::filesystem::file_size(path)!=pin.bytes||std::filesystem::canonical(path)!=path){throw std::invalid_argument("Piston model pin/path mismatch");}
    std::ifstream input(path,std::ios::binary);std::vector<std::uint8_t> bytes(pin.bytes);input.read(reinterpret_cast<char*>(bytes.data()),static_cast<std::streamsize>(bytes.size()));
    if(!input||f::sha256(bytes)!=pin.sha){throw std::invalid_argument("Piston model byte hash mismatch");}
  }
  for(const auto& entry:std::filesystem::recursive_directory_iterator(base)) {
    const auto status=entry.symlink_status();if(std::filesystem::is_symlink(status)){throw std::invalid_argument("Piston model alias rejected");}
    if(std::filesystem::is_directory(status)){continue;}
    if(!std::filesystem::is_regular_file(status)||!expected.erase(entry.path().lexically_relative(base))){throw std::invalid_argument("Unexpected piston model file");}
  }
  if(!expected.empty()){throw std::invalid_argument("Missing piston model file");}
}
struct PistonSwitches {bool left{},right{},starter{},feed{true};};
void fold_system(PistonSwitches& state,const c::SystemControl& system) {
  const bool value=std::get<bool>(system.value);
  if(system.control_id=="engine.ignition_left"){state.left=value;}
  else if(system.control_id=="engine.ignition_right"){state.right=value;}
  else if(system.control_id=="engine.starter"){state.starter=value;}
  else if(system.control_id=="fuel.feed"){state.feed=value;}
  else {throw std::logic_error("Unadmitted piston system");}
}
}
class Session::Impl {
 public:
  class Callback final:public j::FGGroundCallback {
   public:
    explicit Callback(Impl& owner):owner_(owner){}
    double GetAGLevel(double,const j::FGLocation& query,j::FGLocation& contact,j::FGColumnVector3& normal,j::FGColumnVector3& velocity,j::FGColumnVector3& angular)const override {
      // Terminal JSBSim Unbind getter edge only; never Run/publish/provider here.
      if(owner_.disposing){contact=query;normal={0,0,0};velocity={0,0,0};angular={0,0,0};return 0;}
      if(!owner_.boundary){throw std::runtime_error("No prepared boundary");}
      const auto pos=geodetic(query);
      if(owner_.checking_sweep) {
        const auto local=owner_.settings.surface->coordinates(*c::geodesy::to_ecef(pos));const auto center=owner_.settings.surface->coordinates(owner_.publication.ecef_position_m);
        if(std::hypot(local.x-center.x,local.y-center.y)>owner_.sweep_radius){throw std::runtime_error("Actual callback outside prepared footprint");}
      }
      const auto sample=owner_.boundary->sample(pos);const auto* ground=std::get_if<c::ValidGround>(&sample.sample);
      if(!ground){throw std::runtime_error("Unexpected missing ground during mutation");}
      contact=query;contact.SetEllipse(c::geodesy::semi_major_m/.3048,c::geodesy::semi_minor_m/.3048);contact.SetPositionGeodetic(pos.longitude_rad,pos.latitude_rad,ground->surface_height_m/.3048);
      const auto n=Basis(pos).ned_to_ecef(ground->normal_ned);normal={n[0],n[1],n[2]};velocity={0,0,0};angular={0,0,0};
      return (pos.ellipsoid_height_m-ground->surface_height_m)/.3048;
    }
   private:Impl& owner_;
  };
  bool disposing{};
  std::array<SteadyWindObservation,2> initialization_observations;
  struct Deleter{bool* disposing;void operator()(j::FGFDMExec* p)const noexcept{if(p){*disposing=true;delete p;}}};
  Config settings;c::FixedClock clock;c::CommandGate gate;c::SessionControlGate lifecycle;
  std::unique_ptr<v1::Boundary> boundary;
  std::unique_ptr<j::FGFDMExec,Deleter> exec{nullptr,Deleter{&disposing}};
  c::AircraftSnapshot publication;c::AtmosphereSample weather;c::PilotAxes controls;PistonSwitches switches;PistonDiagnostics completed_piston;
  std::vector<c::ControlCommand> pending;
  std::vector<c::OperationalEvent> event_history;std::uint64_t event_sequence{};
  std::thread::id owner{std::this_thread::get_id()};std::string failure;
  bool checking_sweep{};double sweep_radius{};
  void check_thread()const{if(owner!=std::this_thread::get_id()){throw std::logic_error("Caller-owned session used on another thread");}}
  explicit Impl(Config cfg):settings(std::move(cfg)),clock({settings.hz,settings.purpose}),gate(settings.session_id),lifecycle(settings.session_id,"session.owner",clock) {
    (void)steady_wind(settings.wind_profile); // Reject before solver/provider allocation.
    if(!(settings.profile==Profile::legacy||settings.profile==Profile::piston)){throw std::invalid_argument("Unknown interactive profile");}
    const bool cold=settings.profile==Profile::piston;
    if(!settings.angular_method){settings.angular_method=cold?AngularMethod::event_aware_constant_power_v1:AngularMethod::legacy_euler;}
    if(!(settings.angular_method==AngularMethod::legacy_euler||settings.angular_method==AngularMethod::event_aware_constant_power_v1||settings.angular_method==AngularMethod::event_aware_coupled_midpoint_v1)||(!cold&&settings.angular_method!=AngularMethod::legacy_euler)){throw std::invalid_argument("Unsupported angular method/profile pair");}
#if !defined(FLIGHT_JSBSIM_EVENT_AWARE_SHAFT) || !FLIGHT_JSBSIM_EVENT_AWARE_SHAFT
    // The pristine route remains available for the accepted direct-thrust
    // profile. Piston publication requires the reviewed actual vendor getter.
    if(cold||settings.angular_method==AngularMethod::event_aware_constant_power_v1){throw std::invalid_argument("Selected backend lacks reviewed piston/angular method API");}
#endif
#if !defined(FLIGHT_JSBSIM_COUPLED_MIDPOINT_SHAFT) || !FLIGHT_JSBSIM_COUPLED_MIDPOINT_SHAFT
    if(settings.angular_method==AngularMethod::event_aware_coupled_midpoint_v1){throw std::invalid_argument("Selected backend lacks reviewed coupled-midpoint API");}
#endif
    if(cold&&settings.wind_profile!=SteadyWindProfile::calm){throw std::invalid_argument("Piston profile requires calm wind");}
    if(cold&&settings.seed.value!=42){throw std::invalid_argument("Piston cold recipe requires seed42");}
    if((cold&&(settings.start!=Start::piston_cold_ground||settings.trim))||(!cold&&settings.start==Start::piston_cold_ground)){throw std::invalid_argument("Unsupported profile/start pair");}
    if(!(settings.start==Start::ground||settings.start==Start::airborne||settings.start==Start::piston_cold_ground)||(settings.start==Start::ground&&settings.trim)){throw std::invalid_argument("Unknown start or ground trim unsupported");}
    // First human prototype exposes only these two explicit named recipes.
    const auto near=[](double a,double b){return std::isfinite(a)&&std::abs(a-b)<=1e-12;};
    if((settings.start==Start::ground||cold)&&(!near(settings.requested_height_m,1.05)||!near(settings.forward_mps,0)||!near(settings.down_mps,0)||!near(settings.pitch_rad,0))){throw std::invalid_argument("Unsupported ground named recipe");}
    if(settings.start==Start::airborne&&(!settings.trim||!near(settings.requested_height_m,1000)||!near(settings.forward_mps,55*std::cos(.02))||!near(settings.down_mps,55*std::sin(.02))||!near(settings.pitch_rad,.02))){throw std::invalid_argument("Unsupported airborne named recipe");}
    if(!settings.surface||!c::stable_id(settings.session_id)||!(settings.hz==60||settings.hz==120||settings.hz==240)||!std::isfinite(settings.requested_height_m)||
       !std::isfinite(settings.forward_mps)||settings.forward_mps<0||settings.forward_mps>100||!std::isfinite(settings.down_mps)||std::abs(settings.down_mps)>3||
       !std::isfinite(settings.pitch_rad)||std::abs(settings.pitch_rad)>.2){throw std::invalid_argument("Unsupported interactive intake");}
    const auto expected_world=prepared_identity(SurfaceConfig{});
    if(!v1::same(prepared_identity(settings.surface->config()),expected_world)||
       !v1::same(settings.surface->identity(),expected_world)) {
      throw std::invalid_argument("ADR 006 requires the exact prepared default world");
    }
    if(cold){verify_piston_model(settings.model_root);}else{verify_model(settings.model_root);}pending.reserve(4096);event_history.reserve(4096);failure.reserve(256);
    if(!gate.register_source("pilot.controls",c::Authority::pilot)){throw std::runtime_error("Pilot registration failed");}
    if(cold){for(const auto* id:{"engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"}){if(!gate.register_control({id,c::ControlCapability::ValueType::boolean,0,1})){throw std::runtime_error("Piston control capability registration failed");}}}
    const auto anchor=settings.surface->config().anchor;auto cg=anchor;cg.ellipsoid_height_m=settings.requested_height_m;
    const auto point=c::geodesy::to_ecef(cg);if(!point||!settings.surface->covers(*point,gear_radius+.05)){throw std::invalid_argument("Initial coverage missing before allocation");}
    boundary=std::make_unique<v1::Boundary>(settings.surface,c::SampleHeader{{0},settings.session_id},4096);
    const auto initial_ground=boundary->sample(cg);const auto* floor=std::get_if<c::ValidGround>(&initial_ground.sample);
    if(!floor||cg.ellipsoid_height_m-floor->surface_height_m<1){throw std::invalid_argument("Explicit requested CG lacks required clearance");}
    const c::QuaternionBodyToNed q{std::cos(settings.pitch_rad/2),0,std::sin(settings.pitch_rad/2),0};
    for(const auto arm:std::array<c::BodyPosition,3>{{{2,0,1},{-1,-1.3,1},{-1,1.3,1}}}) {
      const auto ned=c::rotate_body_to_ned(q,arm);const auto b=Basis(cg);const auto pos=add(vector(*point),b.ned_to_ecef({ned.x,ned.y,ned.z}));
      const auto geod=c::geodesy::from_ecef({pos[0],pos[1],pos[2]});if(!geod||!std::holds_alternative<c::ValidGround>(boundary->sample(*geod).sample)){throw std::invalid_argument("Initial gear query missing");}
    }
    exec.reset(new j::FGFDMExec());exec->SetDebugLevel(0);
    const auto root=settings.model_root.u8string();exec->SetRootDir(SGPath::fromUtf8(std::string(root.begin(),root.end())));exec->SetAircraftPath(SGPath("aircraft"));exec->SetEnginePath(SGPath("engine"));
    if(!exec->LoadModel(cold?"original-piston-prop":"original-interactive")){throw std::runtime_error("New original model load failed");}
    if(exec->GetGroundReactions()->GetNumGearUnits()!=3){throw std::runtime_error("Gear inventory mismatch");}
    exec->Setdt(1./120);exec->GetInertial()->SetGroundCallback(new Callback(*this));exec->GetWinds()->SetTurbType(j::FGWinds::ttNone);
    const auto seed=static_cast<std::uint32_t>((settings.seed.value^(settings.seed.value>>31)^(settings.seed.value>>62))&0x7fffffffULL);exec->SetPropertyValue("simulation/randomseed",seed);
    const auto ic=exec->GetIC();ic->SetGeodLatitudeRadIC(anchor.latitude_rad);ic->SetLongitudeRadIC(anchor.longitude_rad);ic->SetThetaRadIC(settings.pitch_rad);
    // Solve the caller's explicit ellipsoid CG height in IC only. The vendor's
    // radial-ASL/AGL setter differs by micrometers from ellipsoid height; this
    // does not ground-snap or modify a completed state.
    double radial_asl_ft=cg.ellipsoid_height_m/.3048;
    for(int iteration=0;iteration<12;++iteration){ic->SetAltitudeASLFtIC(radial_asl_ft);const double error=cg.ellipsoid_height_m-geodetic(ic->GetPosition()).ellipsoid_height_m;if(std::abs(error)<1e-8){break;}radial_asl_ft+=error/.3048;}
    const auto requested_wind=steady_wind(settings.wind_profile);
    ic->SetWindNEDFpsIC(requested_wind.x/.3048,requested_wind.y/.3048,requested_wind.z/.3048);
    ic->SetUBodyFpsIC(settings.forward_mps/.3048);ic->SetWBodyFpsIC(settings.down_mps/.3048);
    if(cold) {
      const auto propulsion=exec->GetPropulsion();
      if(propulsion->GetNumEngines()!=1||propulsion->GetNumTanks()!=1){throw std::runtime_error("Piston topology mismatch");}
      const auto engine=propulsion->GetEngine(0);const auto piston=dynamic_cast<j::FGPiston*>(engine.get());
      const auto prop=dynamic_cast<j::FGPropeller*>(engine->GetThruster());
      // Feed index0 is bound by exact authored aircraft XML; pinned DLL does not export GetSourceTank.
      if(!piston||!prop||engine->GetNumSourceTanks()!=1||prop->GetGearRatio()!=1||prop->GetConstantSpeed()!=0||prop->GetPitch()!=20){throw std::runtime_error("Piston/fixed-prop topology mismatch");}
#if defined(FLIGHT_JSBSIM_COUPLED_MIDPOINT_SHAFT) && FLIGHT_JSBSIM_COUPLED_MIDPOINT_SHAFT
      if(settings.angular_method==AngularMethod::event_aware_coupled_midpoint_v1&&
         (!piston->SupportsCoupledShaftProfileV1()||!prop->SupportsCoupledShaftProfileV1())){throw std::runtime_error("Loaded piston/propeller parameters do not support the closed coupled-shaft profile");}
#endif
#if defined(FLIGHT_JSBSIM_EVENT_AWARE_SHAFT) && FLIGHT_JSBSIM_EVENT_AWARE_SHAFT
      const auto selected=vendor_angular_method(*settings.angular_method);
      if(!prop->SetAngularIntegrationMethod(selected)||prop->GetAngularIntegrationMethod()!=selected){throw std::runtime_error("Piston angular method selection/readback mismatch");}
#else
      throw std::logic_error("Piston backend method API unavailable");
#endif
      // Fresh IC mask starts zero. <running>0 would START engine0; no setter or IC XML.
      if(ic->IsEngineRunning(0)){throw std::runtime_error("Cold IC requested an engine start");}
      controls={0,0,0,0,0,1,1,0};engine->SetRunning(false);set_controls(controls);set_switches(switches);
    }
    exec->GetPropulsion()->SetFuelFreeze(true);if(!exec->RunIC()||boundary->failed()){throw std::runtime_error("Initial RunIC failed");}
    verify_wind("RunIC");
    initialization_observations[0]=observe("RunIC");
    const auto& initial_uvw=exec->GetPropagate()->GetUVW();
    if(std::abs(initial_uvw(1)*.3048-settings.forward_mps)>1e-6||std::abs(initial_uvw(2)*.3048)>1e-6||std::abs(initial_uvw(3)*.3048-settings.down_mps)>1e-6){throw std::runtime_error("RunIC changed requested ground-body velocity");}
    if(!cold){exec->GetPropulsion()->InitRunning(-1);}
    if(!cold){controls={0,0,0,settings.start==Start::ground?0:.65,1,settings.start==Start::ground?1.:0,settings.start==Start::ground?1.:0,0};}
    set_controls(controls);
    if(settings.trim) {
      j::FGTrim trim(exec.get(),j::tLongitudinal);trim.SetGammaFallback(false);trim.SetMaxCycles(60);trim.SetMaxCyclesPerAxis(100);trim.SetTolerance(.001);trim.ClearDebug();
      if(!trim.DoTrim()){throw std::runtime_error("Combined airborne trim failed");}
      controls.roll=exec->GetPropertyValue("fcs/aileron-cmd-norm");controls.pitch=-exec->GetPropertyValue("fcs/elevator-cmd-norm");controls.yaw=-exec->GetPropertyValue("fcs/rudder-cmd-norm");
      controls.trim=-exec->GetPropertyValue("fcs/pitch-trim-cmd-norm");controls.throttle=exec->GetPropertyValue("fcs/throttle-cmd-norm");
      verify_wind("post-trim");
    }
    exec->Setdt(clock.integration_step_s());exec->GetPropagate()->InitializeDerivatives();exec->GetPropulsion()->SetFuelFreeze(false);
    if(cold){verify_switches(controls,switches);}
    publication=snapshot({0});weather=atmosphere({0});if(cold){completed_piston=piston_diagnostics({0});}
    if(cold&&(exec->GetPropulsion()->GetEngine(0)->GetRunning()||exec->GetPropulsion()->GetEngine(0)->GetThruster()->GetRPM()!=0||std::abs(exec->GetPropulsion()->GetTank(0)->GetContents()*.45359237-100)>1e-10||exec->GetSimTime()!=0)){throw std::runtime_error("Cold tick0 state mismatch");}
    initialization_observations[1]=observe(settings.trim?"post-trim":"prepared");
    if(!settings.trim&&std::abs(publication.position.ellipsoid_height_m-settings.requested_height_m)>1e-5){throw std::runtime_error("Requested CG height changed during initialization: requested="+std::to_string(settings.requested_height_m)+" observed="+std::to_string(publication.position.ellipsoid_height_m));}
  }
  void verify_angular_method()const {
    if(settings.profile!=Profile::piston){return;}
    const auto prop=dynamic_cast<j::FGPropeller*>(exec->GetPropulsion()->GetEngine(0)->GetThruster());
#if defined(FLIGHT_JSBSIM_EVENT_AWARE_SHAFT) && FLIGHT_JSBSIM_EVENT_AWARE_SHAFT
    const auto selected=vendor_angular_method(*settings.angular_method);
    if(!prop||prop->GetAngularIntegrationMethod()!=selected){throw std::runtime_error("Piston angular method changed before publication");}
#else
    (void)prop;
    throw std::logic_error("Piston backend method getter unavailable");
#endif
  }
  void set_controls(c::PilotAxes a) {
    exec->SetPropertyValue("fcs/aileron-cmd-norm",a.roll);exec->SetPropertyValue("fcs/elevator-cmd-norm",-a.pitch);exec->SetPropertyValue("fcs/rudder-cmd-norm",-a.yaw);exec->SetPropertyValue("fcs/pitch-trim-cmd-norm",-a.trim);exec->SetPropertyValue("fcs/throttle-cmd-norm",a.throttle);
    if(settings.profile==Profile::piston){const auto fcs=exec->GetFCS();fcs->SetThrottleCmd(0,a.throttle);fcs->SetThrottlePos(0,a.throttle);fcs->SetMixtureCmd(0,a.mixture);fcs->SetMixturePos(0,a.mixture);}
    exec->GetFCS()->SetLBrake(a.left_brake);exec->GetFCS()->SetRBrake(a.right_brake);exec->GetFCS()->SetDsCmd(a.yaw);
  }
  void set_switches(PistonSwitches value) {
    const auto engine=exec->GetPropulsion()->GetEngine(0);const auto piston=dynamic_cast<j::FGPiston*>(engine.get());
    if(!piston){throw std::runtime_error("Piston type changed");}
    piston->SetMagnetos((value.left?1:0)|(value.right?2:0));piston->SetStarter(value.starter);exec->GetPropulsion()->GetTank(0)->SetSelected(value.feed);
  }
  PistonDiagnostics piston_diagnostics(c::Tick tick)const {
    const auto engine=exec->GetPropulsion()->GetEngine(0);const auto piston=dynamic_cast<j::FGPiston*>(engine.get());
    if(!piston){throw std::runtime_error("Piston diagnostic type mismatch");}
    PistonDiagnostics result{{tick,settings.session_id},piston->getRPM(),engine->GetThruster()->GetRPM(),engine->GetFuelFlowRate(),engine->GetFuelUsedLbs(),piston->getManifoldPressure_inHg(),engine->in.Pressure,engine->in.Density,piston->GetPowerAvailable(),exec->GetPropulsion()->GetTank(0)->GetContents(),exec->GetMassBalance()->GetMass()};
    for(const double value:{result.pre_prop_engine_rpm,result.post_prop_rpm,result.fuel_flow_lb_per_s,result.fuel_used_lb,result.manifold_pressure_inhg,result.engine_input_pressure_psf,result.engine_input_density_slug_per_ft3,result.raw_engine_power_ftlb_per_s,result.tank_contents_lb,result.mass_slug}){if(!std::isfinite(value)){throw std::runtime_error("Nonfinite piston stage diagnostic");}}
    return result;
  }
  void verify_switches(c::PilotAxes axes,PistonSwitches value)const {
    const auto engine=exec->GetPropulsion()->GetEngine(0);const auto piston=dynamic_cast<j::FGPiston*>(engine.get());const auto fcs=exec->GetFCS();
    if(!piston||piston->GetMagnetos()!=((value.left?1:0)|(value.right?2:0))||engine->GetStarter()!=value.starter||exec->GetPropulsion()->GetTank(0)->GetSelected()!=value.feed||fcs->GetThrottlePos(0)!=axes.throttle||fcs->GetMixturePos(0)!=axes.mixture){throw std::runtime_error("Applied piston controls/readback disagree");}
  }
  c::AircraftSnapshot snapshot(c::Tick tick,c::AircraftSnapshot s={})const {
    verify_angular_method();
    const auto p=exec->GetPropagate();const auto m=exec->GetMassBalance();const auto& uvw=p->GetUVW();const auto& rate=p->GetPQR();const auto& derivative=exec->GetAccelerations()->GetUVWdot();const auto& cg=m->GetXYZcg();
    std::array<double,9> matrix{};const auto& transform=p->GetTb2l();for(unsigned i=0;i<3;++i){for(unsigned k=0;k<3;++k){matrix[3*i+k]=transform(i+1,k+1);}}
    s.header={tick,settings.session_id};s.clock={settings.hz,settings.purpose};s.elapsed_s=static_cast<double>(tick.value)/settings.hz;
    s.position=geodetic(p->GetLocation());s.ecef_position_m=ecef(p->GetLocation());s.orientation_body_to_ned=f::body_to_ned_from_matrix(matrix);
    s.velocity_body_mps={uvw(1)*.3048,uvw(2)*.3048,uvw(3)*.3048};s.angular_rate_body_radps={rate(1),rate(2),rate(3)};s.acceleration_body_mps2=f::earth_acceleration_body_mps2({derivative(1)*.3048,derivative(2)*.3048,derivative(3)*.3048},s.angular_rate_body_radps,s.velocity_body_mps);
    s.mass_kg=m->GetMass()*slug_to_kg;s.center_of_gravity_body_m=f::structural_cg_inches_to_body_datum_m(cg(1),cg(2),cg(3));s.validity=c::Validity::valid;s.configuration={0,1,controls.trim};
    s.systems={{"fuel.total",c::Quantity::kilograms,exec->GetPropulsion()->GetTank(0)->GetContents()*.45359237,c::Validity::valid},{"engine.throttle",c::Quantity::fraction,controls.throttle,c::Validity::valid}};
    if(settings.profile==Profile::piston) {
      const auto engine=exec->GetPropulsion()->GetEngine(0);const auto piston=dynamic_cast<j::FGPiston*>(engine.get());const auto prop=dynamic_cast<j::FGPropeller*>(engine->GetThruster());
      if(!piston||!prop){throw std::runtime_error("Piston snapshot type mismatch");}
      const double shaft=prop->GetRPM()*2*std::numbers::pi/60;
      if(!std::isfinite(shaft)||shaft<0||shaft>120*std::numbers::pi){throw std::runtime_error("Piston shaft outside pretrial engineering domain");}
      s.systems.push_back({"engine.mixture",c::Quantity::fraction,exec->GetFCS()->GetMixturePos(0),c::Validity::valid});
      s.systems.push_back({"propeller.angular_speed",c::Quantity::radians_per_second,shaft,c::Validity::valid});
      s.systems.push_back({"engine.running",c::Quantity::boolean,engine->GetRunning(),c::Validity::valid});
      s.systems.push_back({"engine.ignition_left",c::Quantity::boolean,bool(piston->GetMagnetos()&1),c::Validity::valid});
      s.systems.push_back({"engine.ignition_right",c::Quantity::boolean,bool(piston->GetMagnetos()&2),c::Validity::valid});
      s.systems.push_back({"engine.starter",c::Quantity::boolean,engine->GetStarter(),c::Validity::valid});
      s.systems.push_back({"fuel.feed",c::Quantity::boolean,exec->GetPropulsion()->GetTank(0)->GetSelected(),c::Validity::valid});
      s.systems.push_back({"engine.starved",c::Quantity::boolean,engine->GetStarved(),c::Validity::valid});
    }
    s.contacts.clear();s.contacts.reserve(3);
    for(int i=0;i<3;++i){const auto gear=exec->GetGroundReactions()->GetGearUnit(i);const bool wow=gear->GetWOW();const auto arm=wow?m->StructuralToBody(gear->GetActingLocation()):gear->GetBodyLocation();
      s.contacts.push_back({i==0?"gear.nose":i==1?"gear.left":"gear.right",{arm(1)*.3048,arm(2)*.3048,arm(3)*.3048},{c::units::pounds_force_to_newtons(gear->GetBodyXForce()),c::units::pounds_force_to_newtons(gear->GetBodyYForce()),c::units::pounds_force_to_newtons(gear->GetBodyZForce())},wow});}
    if(!c::valid(s)||c::magnitude(s.velocity_body_mps)>speed_limit||c::magnitude(s.angular_rate_body_radps)>rate_limit){throw std::runtime_error("Nonfinite/out-of-domain prototype publication");}return s;
  }
  SteadyWindObservation observe(const char* stage)const {
    const auto p=exec->GetPropagate();const auto auxiliary=exec->GetAuxiliary();const auto aero=exec->GetAerodynamics();const auto winds=exec->GetWinds();
    const auto& ground=p->GetUVW();const auto& air=auxiliary->GetAeroUVW();const auto& rate=auxiliary->GetAeroPQR();const auto& base=winds->GetWindNED();const auto& total=winds->GetTotalWindNED();
    const auto& force=aero->GetForces();const auto& moment=aero->GetMoments();
    std::array<double,9> matrix{};for(unsigned i=0;i<3;++i){for(unsigned k=0;k<3;++k){matrix[3*i+k]=p->GetTb2l()(i+1,k+1);}}
    SteadyWindObservation out;out.stage=stage;out.ground_body_mps={ground(1)*.3048,ground(2)*.3048,ground(3)*.3048};out.air_body_mps={air(1)*.3048,air(2)*.3048,air(3)*.3048};
    out.aero_rate_radps={rate(1),rate(2),rate(3)};out.base_wind_mps={base(1)*.3048,base(2)*.3048,base(3)*.3048};out.total_wind_mps={total(1)*.3048,total(2)*.3048,total(3)*.3048};out.orientation=f::body_to_ned_from_matrix(matrix);
    out.aero_force_n={c::units::pounds_force_to_newtons(force(1)),c::units::pounds_force_to_newtons(force(2)),c::units::pounds_force_to_newtons(force(3))};
    out.aero_moment_nm={moment(1)*1.3558179483314004,moment(2)*1.3558179483314004,moment(3)*1.3558179483314004};
    out.alpha_rad=auxiliary->Getalpha();out.beta_rad=auxiliary->Getbeta();out.speed_mps=auxiliary->GetVt()*.3048;out.qbar_pa=auxiliary->Getqbar()*47.8802589803358;out.density_kgpm3=exec->GetAtmosphere()->GetDensity()*slug_to_kg/std::pow(.3048,3);
    out.applied_controls={exec->GetPropertyValue("fcs/aileron-cmd-norm"),-exec->GetPropertyValue("fcs/elevator-cmd-norm"),-exec->GetPropertyValue("fcs/rudder-cmd-norm"),exec->GetPropertyValue("fcs/throttle-cmd-norm"),settings.profile==Profile::piston?exec->GetFCS()->GetMixturePos(0):1,exec->GetFCS()->GetLBrake(),exec->GetFCS()->GetRBrake(),-exec->GetPropertyValue("fcs/pitch-trim-cmd-norm")};
    return out;
  }
  void verify_wind(const char* stage)const {
    // No-gust/ttNone closure is checked against the actual aerodynamic input,
    // not inferred from a preset echo or a vendor direction getter.
    const auto winds=exec->GetWinds();const auto& base=winds->GetWindNED();const auto& total=winds->GetTotalWindNED();
    const auto requested=steady_wind(settings.wind_profile);
    const std::array<double,3> nominal{requested.x,requested.y,requested.z};
    const auto& ground=exec->GetPropagate()->GetUVW();
    const auto expected_air=ground-exec->GetPropagate()->GetTl2b()*total;
    const auto& actual_air=exec->GetAuxiliary()->GetAeroUVW();
    for(int i=1;i<=3;++i) {
      const auto value=base(i)*.3048;
      if(!std::isfinite(value)||std::abs(value-nominal[i-1])>1e-6||!std::isfinite(total(i))||total(i)!=base(i)||winds->GetGustNED(i)!=0||winds->GetTurbNED(i)!=0||winds->GetTurbPQR(i)!=0||winds->GetTurbType()!=j::FGWinds::ttNone) {
        std::ostringstream detail;detail<<std::setprecision(17)<<stage<<" steady-wind admission failed axis="<<i<<" requested_mps="<<nominal[i-1]<<" actual_mps="<<value<<" total_mps="<<total(i)*.3048;
        throw std::runtime_error(detail.str());
      }
      if(!std::isfinite(actual_air(i))||std::abs((actual_air(i)-expected_air(i))*.3048)>1e-6){throw std::runtime_error(std::string(stage)+" ground-minus-toward-wind airflow mismatch");}
    }
  }
  c::AtmosphereSample atmosphere(c::Tick tick)const {
    verify_wind("publication");
    const auto a=exec->GetAtmosphere();const auto& w=exec->GetWinds()->GetWindNED();c::AtmosphereSample out{{tick,settings.session_id},geodetic(exec->GetPropagate()->GetLocation()),a->GetPressure()*47.8802589803358,a->GetTemperature()*5/9,a->GetDensity()*slug_to_kg/std::pow(.3048,3),0,{w(1)*.3048,w(2)*.3048,w(3)*.3048},{},settings.seed,"jsbsim-dry-isa"};
    if(!c::valid(out)){throw std::runtime_error("Invalid actual atmosphere");}return out;
  }
  Step step() {
    check_thread();if(!exec){return {Status::discarded,{}};}if(clock.paused()){return {Status::paused,{}};}
    const auto next=c::next_tick(clock.completed_tick());if(!next){throw std::overflow_error("Tick exhausted");}
    const double dt=clock.integration_step_s();
    // Policy uses supported150m/s/3rad/s +5cm. No400m/s2 acceleration assumption.
    // It is an actual-query/post-step tested footprint, NOT a continuous bound.
    sweep_radius=gear_radius+(speed_limit+rate_limit*gear_radius)*dt+.05;
    try {
      const auto expected_world=prepared_identity(SurfaceConfig{});
      if(!v1::same(prepared_identity(settings.surface->config()),expected_world)||
         !v1::same(settings.surface->identity(),expected_world)) {
        throw std::runtime_error("Prepared session world changed");
      }
      if(!settings.surface->covers(publication.ecef_position_m,sweep_radius)){return {Status::coverage_blocked,{}};}
      boundary=std::make_unique<v1::Boundary>(settings.surface,c::SampleHeader{*next,settings.session_id},256);
      if(!std::holds_alternative<c::ValidGround>(boundary->sample(publication.position).sample)){return {Status::coverage_blocked,{}};}
      const auto p=exec->GetPropagate();std::array<c::ValidGround,3> material;
      for(int i=0;i<3;++i){const auto gear=exec->GetGroundReactions()->GetGearUnit(i);const auto wheel=p->GetLocation().LocalToLocation(p->GetTb2l()*gear->GetBodyLocation());const auto sample=boundary->sample(geodetic(wheel));if(!std::holds_alternative<c::ValidGround>(sample.sample)){return {Status::coverage_blocked,{}};}material[i]=std::get<c::ValidGround>(sample.sample);}
      const auto end=std::find_if(pending.begin(),pending.end(),[&](const auto& x){return x.header.tick>*next;});std::vector<c::ControlCommand> applied(pending.begin(),end);auto candidate_controls=controls;auto candidate_switches=switches;for(const auto& item:applied){if(const auto* axes=std::get_if<c::PilotAxes>(&item.payload)){candidate_controls=*axes;}else{fold_system(candidate_switches,std::get<c::SystemControl>(item.payload));}}
      auto candidate=publication;checking_sweep=true;
      for(int i=0;i<3;++i){const auto prefix="gear/unit["+std::to_string(i)+"]/";exec->SetPropertyValue(prefix+"static_friction_coeff",material[i].static_friction);exec->SetPropertyValue(prefix+"dynamic_friction_coeff",material[i].dynamic_friction);}
      set_controls(candidate_controls);if(settings.profile==Profile::piston){set_switches(candidate_switches);}
      if(!exec->Run()||boundary->failed()){throw std::runtime_error("Combined Run/callback failed");}
      // Candidate controls are used for observed configuration/system readback,
      // but only committed if every readback/guard/clock test succeeds.
      if(settings.profile==Profile::piston){verify_switches(candidate_controls,candidate_switches);}
      const auto candidate_piston=settings.profile==Profile::piston?piston_diagnostics(*next):PistonDiagnostics{};
      const auto previous_controls=controls;controls=candidate_controls;
      try {candidate=snapshot(*next,std::move(candidate));}catch(...){controls=previous_controls;throw;}controls=previous_controls;
      auto next_weather=atmosphere(*next);const auto a=settings.surface->coordinates(publication.ecef_position_m),b=settings.surface->coordinates(candidate.ecef_position_m);
      if(std::hypot(b.x-a.x,b.y-a.y)>sweep_radius-gear_radius||!settings.surface->covers(candidate.ecef_position_m,gear_radius)){throw std::runtime_error("Actual movement outside prepared footprint");}
      if(std::abs(exec->GetSimTime()-static_cast<double>(next->value)/settings.hz)>1e-7+next->value/settings.hz*1e-10){throw std::runtime_error("Solver tick time mismatch");}
      if(!clock.advance()){throw std::runtime_error("Clock commit failed");}
      publication=std::move(candidate);weather=std::move(next_weather);controls=candidate_controls;switches=candidate_switches;completed_piston=candidate_piston;pending.erase(pending.begin(),end);checking_sweep=false;return {Status::completed,std::move(applied)};
    }catch(const std::exception& e){exec.reset();checking_sweep=false;failure=std::string(e.what()).substr(0,255);return {Status::discarded,{}};}
    catch(...){exec.reset();checking_sweep=false;failure="Unknown provider/solver fault";return {Status::discarded,{}};}
  }
};
std::array<SteadyWindObservation,2> SessionTestAccess::initialization(const Session& session){session.impl_->check_thread();return session.impl_->initialization_observations;}
SteadyWindObservation SessionTestAccess::current(const Session& session){session.impl_->check_thread();if(!session.impl_->exec){throw std::logic_error("No live solver diagnostic");}return session.impl_->observe("completed");}
Session::Session(Config cfg):impl_(std::make_unique<Impl>(std::move(cfg))){}
Session::~Session(){if(impl_&&impl_->owner!=std::this_thread::get_id()){std::terminate();}}
bool Session::register_host_source(std::string id,c::Authority authority){impl_->check_thread();if(!impl_->exec||static_cast<unsigned>(authority)>static_cast<unsigned>(c::Authority::instructor)){return false;}return impl_->gate.register_source(std::move(id),authority);}
c::CommandRejection Session::submit(c::ControlCommand cmd){auto& s=*impl_;s.check_thread();if(!s.exec){return c::CommandRejection::invalid;}if(s.pending.size()==4096){return c::CommandRejection::capacity;}const auto next=c::next_tick(s.clock.completed_tick());if(!next){return c::CommandRejection::late;}
  const auto* axes=std::get_if<c::PilotAxes>(&cmd.payload);const auto* system=std::get_if<c::SystemControl>(&cmd.payload);
  if(s.settings.profile==Profile::legacy){if(!axes||axes->mixture!=1){return c::CommandRejection::unsupported_control;}}
  else if(system){
    if(!piston_system_id(system->control_id)||!std::holds_alternative<bool>(system->value)){return c::CommandRejection::unsupported_control;}
    if(cmd.source_id!="pilot.controls"||cmd.authority!=c::Authority::pilot){return c::CommandRejection::unauthorized_source;}
    if(cmd.header.tick!=*next){return c::CommandRejection::late;}
  } else if(!axes){return c::CommandRejection::unsupported_control;}
  if((axes&&!c::valid(*axes))||cmd.assistance.profile_id!="unassisted"||!cmd.assistance.active.empty()){return c::CommandRejection::invalid;}
  // vector storage reserved before gate consumes the sequence; all command-owned
  // strings are prepared by caller and moved only after acceptance.
  const auto rejection=s.gate.accept(cmd,*next);if(rejection!=c::CommandRejection::none){return rejection;}s.pending.push_back(std::move(cmd));std::sort(s.pending.begin(),s.pending.end(),c::command_before);return c::CommandRejection::none;}
c::SessionControlRejection Session::apply(const c::SessionControl& x){auto& s=*impl_;s.check_thread();if(!s.exec||s.event_history.size()==4096){return c::SessionControlRejection::invalid;}
  c::OperationalEvent event;event.header={s.clock.completed_tick(),s.settings.session_id};event.sequence={s.event_sequence+1};event.source_id=x.source_id;event.confidence=c::OperationalEvent::Confidence::observed;event.content_version="0.1.0-prototype";
  std::visit([&](auto payload){event.payload=payload;},x.payload);const auto rejection=s.lifecycle.apply(x);if(rejection==c::SessionControlRejection::none){s.event_history.push_back(std::move(event));++s.event_sequence;}return rejection;}
Step Session::step_fixed(){return impl_->step();}
c::AircraftSnapshot Session::latest()const{impl_->check_thread();return impl_->publication;}
c::AtmosphereSample Session::atmosphere()const{impl_->check_thread();return impl_->weather;}
c::PilotAxes Session::held()const{impl_->check_thread();return impl_->controls;}
Profile Session::profile()const{impl_->check_thread();return impl_->settings.profile;}
std::optional<std::string> Session::angular_integration_method()const{impl_->check_thread();if(impl_->settings.profile==Profile::legacy){return std::nullopt;}if(!impl_->exec){throw std::logic_error("No live piston angular-method getter");}impl_->verify_angular_method();switch(*impl_->settings.angular_method){case AngularMethod::legacy_euler:return "legacy_euler";case AngularMethod::event_aware_constant_power_v1:return "event_aware_constant_power_v1";case AngularMethod::event_aware_coupled_midpoint_v1:return "event_aware_coupled_midpoint_v1";}throw std::logic_error("Unknown angular method after verification");}
PistonDiagnostics Session::piston_diagnostics()const{impl_->check_thread();if(impl_->settings.profile!=Profile::piston){throw std::logic_error("Legacy profile has no piston diagnostic");}return impl_->completed_piston;}
std::string Session::fault()const{impl_->check_thread();return impl_->failure;}
bool Session::paused()const{impl_->check_thread();return impl_->clock.paused();}
double Session::time_scale()const{impl_->check_thread();return impl_->lifecycle.time_scale();}
std::vector<c::OperationalEvent> Session::events()const{impl_->check_thread();return impl_->event_history;}
bool Session::live()const{impl_->check_thread();return bool(impl_->exec);}
void Session::close(){impl_->check_thread();impl_->exec.reset();}
std::string source_fingerprint(){return FLIGHT_INTERACTIVE_SOURCE_SHA256;}
bool piston_system_id(std::string_view id){return id=="engine.ignition_left"||id=="engine.ignition_right"||id=="engine.starter"||id=="fuel.feed";}
std::string command_json(const c::ControlCommand& x,Profile profile){
  const auto* a=std::get_if<c::PilotAxes>(&x.payload);const auto* system=std::get_if<c::SystemControl>(&x.payload);
  if(!(profile==Profile::legacy||profile==Profile::piston)||(!a&&!system)||(a&&(!c::valid(*a)||(profile==Profile::legacy&&a->mixture!=1)))||
    (system&&(profile!=Profile::piston||!piston_system_id(system->control_id)||!std::holds_alternative<bool>(system->value)||x.authority!=c::Authority::pilot||x.source_id!="pilot.controls"))||
    !c::stable_id(x.header.session_id)||!c::stable_id(x.source_id)||x.assistance.profile_id!="unassisted"||!x.assistance.active.empty()||static_cast<unsigned>(x.authority)>3){throw std::invalid_argument("Invalid combined command JSON");}
  constexpr std::array<const char*,4> authority{"pilot","avionics","scenario","instructor"};std::ostringstream out;out<<std::setprecision(17)<<"{\"type\":\"ControlCommand\",\"schema_version\":1,\"tick\":\""<<c::wire_uint64(x.header.tick.value)<<"\",\"session_id\":\""<<x.header.session_id<<"\",\"sequence\":\""<<c::wire_uint64(x.sequence.value)<<"\",\"source_id\":\""<<x.source_id<<"\",\"authority\":\""<<authority[static_cast<unsigned>(x.authority)]<<"\",\"assistance\":{\"profile_id\":\"unassisted\",\"active\":[]},\"payload\":{";
  if(a){out<<"\"kind\":\"axes\",\"roll\":"<<a->roll<<",\"pitch\":"<<a->pitch<<",\"yaw\":"<<a->yaw<<",\"throttle\":"<<a->throttle<<",\"mixture\":"<<a->mixture<<",\"left_brake\":"<<a->left_brake<<",\"right_brake\":"<<a->right_brake<<",\"trim\":"<<a->trim;}
  else {out<<"\"kind\":\"system\",\"control_id\":\""<<system->control_id<<"\",\"value\":"<<(std::get<bool>(system->value)?"true":"false");}
  out<<"}}";return out.str();}

std::string snapshot_json(const c::AircraftSnapshot& snapshot){if(!c::valid(snapshot)){throw std::invalid_argument("Invalid combined snapshot JSON");}auto base=snapshot;base.contacts.clear();
  const bool extended=std::any_of(base.systems.begin(),base.systems.end(),[](const auto& x){return x.quantity==c::Quantity::boolean||x.quantity==c::Quantity::radians_per_second;});
  if(extended){base.systems.clear();}
  auto text=f::transport::json(base);
  if(extended){std::ostringstream channels;channels<<std::setprecision(17)<<"\"systems\":[";for(std::size_t i=0;i<snapshot.systems.size();++i){const auto& x=snapshot.systems[i];if(i){channels<<',';}const char* unit=x.quantity==c::Quantity::kilograms?"kg":x.quantity==c::Quantity::fraction?"fraction":x.quantity==c::Quantity::radians_per_second?"radps":x.quantity==c::Quantity::boolean?"bool":nullptr;if(!unit||x.validity!=c::Validity::valid){throw std::invalid_argument("Unsupported interactive system serializer");}channels<<"{\"id\":\""<<x.id<<"\",\"quantity\":\""<<unit<<"\",\"value\":";if(x.quantity==c::Quantity::boolean){channels<<(std::get<bool>(x.value)?"true":"false");}else{channels<<std::get<double>(x.value);}channels<<",\"validity\":\"valid\"}";}channels<<']';const auto offset=text.find("\"systems\":[]");if(offset==std::string::npos){throw std::runtime_error("System serializer drift");}text.replace(offset,12,channels.str());}
std::ostringstream out;out<<std::setprecision(17)<<"\"contacts\":[";for(std::size_t i=0;i<snapshot.contacts.size();++i){const auto& x=snapshot.contacts[i];if(i){out<<',';}out<<"{\"id\":\""<<x.id<<"\",\"point_body_m\":{\"x\":"<<x.point_body_m.x<<",\"y\":"<<x.point_body_m.y<<",\"z\":"<<x.point_body_m.z<<"},\"force_body_n\":{\"x\":"<<x.force_body_n.x<<",\"y\":"<<x.force_body_n.y<<",\"z\":"<<x.force_body_n.z<<"},\"on_ground\":"<<(x.on_ground?"true":"false")<<'}';}out<<']';const auto offset=text.find("\"contacts\":[]");if(offset==std::string::npos){throw std::runtime_error("Contact serializer drift");}text.replace(offset,13,out.str());return text;}
}
