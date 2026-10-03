#include <flight/fdm/session.hpp>
#include <flight/fdm/model.hpp>
#include <flight/fdm/protocol.hpp>
#include <iostream>
#include <stdexcept>
#include <fstream>
#include <FGFDMExec.h>
#include <initialization/FGInitialCondition.h>
#include <models/FGPropagate.h>
#include <models/FGMassBalance.h>
#include <models/FGPropulsion.h>
#include <models/propulsion/FGTank.h>
namespace f=flight::fdm; namespace c=flight::contracts::v1;
int failures=0,checks=0;
void check(bool condition,const char* description) { ++checks; if(!condition) { ++failures; std::cerr<<"FAIL: "<<description<<'\n'; } }
template<class F> void rejects(F action,const char* description) { bool rejected=false; try { action(); } catch(const std::exception&) { rejected=true; } check(rejected,description); }
f::SessionConfig config(const std::filesystem::path& root) {
  f::SessionConfig cfg; cfg.model_root=root; cfg.seed={9007199254740993ULL};
  auto& a=cfg.initial_conditions.aircraft; a.header={{0},cfg.session_id}; a.clock=cfg.clock;
  a.position={.8,-2,1000}; a.ecef_position_m=*c::geodesy::to_ecef(a.position); a.orientation_body_to_ned={std::cos(.01),0,std::sin(.01),0};
  a.velocity_body_mps={55*std::cos(.02),0,55*std::sin(.02)}; a.mass_kg=1100;
  // Independently authored US-standard lapse-layer calculation, conservative source-derived intake budget.
  const double geopotential=6356766.0*1000/(6356766.0+1000); const double t=288.15-.0065*geopotential;
  const double p=101325*std::pow(t/288.15,9.80665/(287.05287*.0065));
  cfg.initial_conditions.atmosphere={a.header,a.position,p,t,p/(287.05287*t),0,{},{},cfg.seed,"jsbsim-dry-isa"}; return cfg;
}
c::ControlCommand axes_command(const f::SessionConfig& cfg,const c::PilotAxes& axes,std::uint64_t tick=1,std::uint64_t sequence=1) {
  return {{{tick},cfg.session_id},{sequence},"pilot.controls",c::Authority::pilot,{"unassisted",{}},axes};
}
std::string stepped_trace(const f::SessionConfig& cfg,int cadence,double scale=1,bool with_pause=false) {
  f::Session instance(cfg); c::Sequence sequence{1};
  check(instance.apply({{{0},cfg.session_id},sequence,"session.owner",c::TimeScaleControl{scale}})==c::SessionControlRejection::none,"Time scale accepted");
  const std::uint64_t wall_duration_ns=static_cast<std::uint64_t>(10000000000.0/scale);
  const std::uint64_t frames=static_cast<std::uint64_t>(cadence)*wall_duration_ns/1000000000ULL;
  std::uint64_t previous=0;
  for(std::uint64_t frame=1;frame<=frames;++frame) {
    const auto now=frame*wall_duration_ns/frames;
    if(with_pause&&frame==frames/2) {
      const auto tick=instance.latest_snapshot().header.tick;
      check(instance.apply({{tick,cfg.session_id},{2},"session.owner",c::PauseControl{true}})==c::SessionControlRejection::none,"Mid-run pause");
      const auto state=f::transport::json(instance.latest_snapshot());
      for(int i=0;i<10;++i) { const auto paused=instance.advance_wall_budget(std::chrono::milliseconds(100));check(paused.steps==0,"Mid-run paused wall budget ignored"); }
      check(f::transport::json(instance.latest_snapshot())==state,"Mid-run pause preserves full aircraft state");
      check(instance.apply({{tick,cfg.session_id},{3},"session.owner",c::PauseControl{false}})==c::SessionControlRejection::none,"Mid-run resume");
    }
    const auto advanced=instance.advance_wall_budget(std::chrono::nanoseconds(now-previous));
    check(!advanced.overrun&&!advanced.paused,"Normal cadence has no overrun");previous=now;
  }
  check(instance.latest_snapshot().header.tick.value==1200,"Cadence and scale produce exactly10s/1200ticks");
  return f::transport::json(instance.latest_snapshot());
}
int main(int argc,char** argv) {
 try {
  if(argc!=4) throw std::runtime_error("Model root, transport and asymmetric reference fixture required");
  const std::vector<std::uint8_t> abc{'a','b','c'};
  check(f::sha256({})=="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855","SHA256 empty NIST vector");
  check(f::sha256(abc)=="ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad","SHA256 abc NIST vector");
  const std::vector<std::uint8_t> million_a(1000000,'a');
  check(f::sha256(million_a)=="cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0","SHA256 million-a multiblock NIST vector");
  auto cfg=config(argv[1]); f::Session session(cfg); const auto initial=session.latest_snapshot();
  check(c::valid(initial),"Actual engine initialized snapshot valid");
  check(std::abs(initial.position.ellipsoid_height_m-1000)<1e-5,"Actual immediate post-trim ellipsoid height");
  check(initial.mass_kg>1099.999 && initial.mass_kg<1100.001,"Actual pounds/slugs mass conversion");
  check(session.initialization().initial_fuel_kg>99.9999,"Fuel freeze applies through trim");
  auto controls=session.initialization().solved_controls;
  check(session.register_host_source("pilot.controls",c::Authority::pilot),"Host source registration");
  c::ControlCommand command{{{1},cfg.session_id},{1},"pilot.controls",c::Authority::pilot,{"unassisted",{}},controls};
  check(session.submit(command).queued,"Validated command queued");
  check(session.applied_command_log().empty(),"Queue does not publish applied physics log");
  check(session.submit(command).rejection==c::CommandRejection::duplicate,"Duplicate rejection");
  const auto step=session.step_fixed(); check(step.stepped&&step.aircraft.header.tick.value==1,"Actual fixed solver step");
  check(session.applied_command_log().size()==1,"Applied log only after successful step");
  const auto pause=c::SessionControl{{{1},cfg.session_id},{1},"session.owner",c::PauseControl{true}};
  check(session.apply(pause)==c::SessionControlRejection::none,"Pause lane");
  const auto paused= f::transport::json(session.latest_snapshot());
  for(int i=0;i<30;++i) { check(!session.step_fixed().stepped,"Paused solver does not run"); const auto advance=session.advance_wall_budget(std::chrono::seconds(1)); check(advance.paused&&advance.steps==0,"Paused scheduler ignores wall budget"); }
  check(paused==f::transport::json(session.latest_snapshot()),"Paused complete observable state exact");
  check(session.apply({{{1},cfg.session_id},{2},"session.owner",c::PauseControl{false}})==c::SessionControlRejection::none,"Resume while paused");
  session.close(); rejects([&]{(void)session.step_fixed();},"Close prevents stepping");
  const auto acceleration=f::earth_acceleration_body_mps2({4,5,6},{1,2,3},{7,11,13});
  check(acceleration.x==-3&&acceleration.y==13&&acceleration.z==3,"Rotating-frame SI derivative correction independently calculated");
  const auto cg=f::structural_cg_inches_to_body_datum_m(240.0/13,24.0/13,45.0/13);
  check(std::abs(cg.x+.4689230769230769)<1e-14&&std::abs(cg.y-.0468923076923077)<1e-14&&std::abs(cg.z+.0879230769230769)<1e-14,"Independent asymmetric CG fixed datum inches-to-FRD meters");
  const auto yaw=f::body_to_ned_from_matrix({0,-1,0,1,0,0,0,0,1}); const auto east=c::rotate_body_to_ned(yaw,c::BodyVelocity{1,0,0});
  check(std::abs(east.x)<1e-14&&std::abs(east.y-1)<1e-14,"Independent +90 yaw body forward to east");
  rejects([&]{(void)f::body_to_ned_from_matrix({1,0,0,0,1,0,0,0,-1});},"Reflection is not orientation");
  rejects([&]{(void)f::transport::decode({},argv[1]);},"Truncated private request rejected");
  const auto input_size=std::filesystem::file_size(argv[2]);std::vector<std::uint8_t> request_bytes(static_cast<std::size_t>(input_size));
  std::ifstream request_file(argv[2],std::ios::binary);request_file.read(reinterpret_cast<char*>(request_bytes.data()),static_cast<std::streamsize>(request_bytes.size()));
  check(static_cast<bool>(request_file),"Actual generated request fixture read");
  const auto decoded=f::transport::decode(request_bytes,argv[1]);
  check(decoded.config.seed.value==9007199254740993ULL&&decoded.commands.size()==1&&decoded.commands[0].sequence.value==9007199254740993ULL,"Full64-bit private transport integer preservation");
  for(std::size_t size=0;size<request_bytes.size();++size)rejects([&]{(void)f::transport::decode(std::span(request_bytes).first(size),argv[1]);},"Every truncated byte boundary rejected before solver");
  auto trailing=request_bytes;trailing.push_back(0);rejects([&]{(void)f::transport::decode(trailing,argv[1]);},"Trailing bytes rejected before solver");
  for(std::size_t index:{std::size_t{0},std::size_t{8},std::size_t{12},std::size_t{17}}) {
    auto malformed=request_bytes;malformed[index]=index==0?'X':2;
    rejects([&]{(void)f::transport::decode(malformed,argv[1]);},"Bad magic/version/rate/boolean rejected");
  }
  auto nonfinite=request_bytes;const std::size_t initial_offset=40+cfg.session_id.size();
  const std::uint64_t nan_bits=0x7ff8000000000000ULL;for(unsigned i=0;i<8;++i)nonfinite[initial_offset+i]=static_cast<std::uint8_t>(nan_bits>>(8*i));
  rejects([&]{(void)f::transport::decode(nonfinite,argv[1]);},"Native NaN intake rejected");
  auto excess=request_bytes;const std::size_t command_size=8+8+2+std::string("pilot.controls").size()+1+2+std::string("unassisted").size()+8*8;
  const std::size_t count_offset=request_bytes.size()-command_size-4;excess[count_offset]=1;excess[count_offset+1]=16;
  rejects([&]{(void)f::transport::decode(excess,argv[1]);},"Excess4097 command count rejected before allocation");
  auto invalid=cfg; invalid.initial_conditions.aircraft.mass_kg=1000; rejects([&]{f::Session bad(invalid);},"Incompatible mass request fails before engine");
  const auto cadence120=stepped_trace(cfg,120);
  check(stepped_trace(cfg,30)==cadence120,"30Hz virtualrender cadence produces exact same120Hz physics");
  check(stepped_trace(cfg,60)==cadence120,"60Hz virtualrender cadence produces exact same120Hz physics");
  for(double scale:{.25,.5,2.,4.})check(stepped_trace(cfg,60,scale)==cadence120,"Time scale leaves physics trajectory identical");
  check(stepped_trace(cfg,60,1,true)==cadence120,"Pause/resume leaves physics trajectory identical");
  f::Session overrun(cfg);const auto debt=overrun.advance_wall_budget(std::chrono::seconds(1));
  check(debt.overrun&&debt.paused&&debt.owed_ticks==120,"Overrun pauses with all120owedticks retained");
  check(overrun.latest_snapshot().header.tick.value==0,"Overrun never silently advances or enlarges dt");
  check(overrun.apply({{{0},cfg.session_id},{1},"session.owner",c::PauseControl{false}})==c::SessionControlRejection::none,"Explicit resume permits debt drain");
  rejects([&]{(void)overrun.advance_wall_budget(std::chrono::milliseconds(1));},"New wall budget rejected until debt drained");
  std::uint64_t owed=120;
  while(owed) {const auto pump=overrun.advance_wall_budget(std::chrono::nanoseconds(0));check(pump.steps<=32,"Debt pump remains bounded");owed=pump.owed_ticks;}
  check(overrun.latest_snapshot().header.tick.value==120,"Debt recovered without droppedticks");
  f::SessionConfig bounded_cfg=cfg;bounded_cfg.history_capacity=1;f::Session bounded(bounded_cfg);
  check(bounded.register_host_source("pilot.controls",c::Authority::pilot),"Bounded source registration");
  const auto bounded_axes=bounded.initialization().solved_controls;
  check(bounded.submit(axes_command(cfg,bounded_axes)).queued,"One history slot reserved for pendingcommand");
  check(bounded.submit(axes_command(cfg,bounded_axes,2,2)).rejection==c::CommandRejection::capacity,"Pending+applied total history bound");
  check(bounded.step_fixed().stepped,"Reserved command applies");
  check(bounded.submit(axes_command(cfg,bounded_axes,2,2)).rejection==c::CommandRejection::capacity,"Applied history never evicted silently");
  check(bounded.apply({{{1},cfg.session_id},{1},"session.owner",c::TimeScaleControl{1}})==c::SessionControlRejection::none,"One event slot");
  check(bounded.apply({{{1},cfg.session_id},{2},"session.owner",c::PauseControl{true}})==c::SessionControlRejection::invalid,"Lifecycle history full rejects before pausemutation");
  const auto unchanged=f::transport::json(bounded.latest_snapshot());
  rejects([&]{(void)bounded.advance_wall_budget(std::chrono::seconds(1));},"Automatic overrun event full rejects before budget/state mutation");
  check(f::transport::json(bounded.latest_snapshot())==unchanged&&bounded.step_fixed().stepped,"Event-cap rejection leaves clock unpaused");
  f::Session admission(cfg);check(admission.register_host_source("pilot.controls",c::Authority::pilot),"Arrival history source");
  check(admission.submit(axes_command(cfg,admission.initialization().solved_controls,5,1)).queued,"Future seq1 admitted first");
  check(admission.submit(axes_command(cfg,admission.initialization().solved_controls,1,2)).queued,"Earlier target seq2 admitted later");
  check(admission.admitted_command_history().size()==2&&admission.admitted_command_history()[0].command.sequence.value==1&&admission.admitted_command_history()[1].command.sequence.value==2,"Arrival order retained separately from target order");
  check(admission.step_fixed().applied_commands[0].sequence.value==2&&admission.applied_command_log()[0].sequence.value==2,"Execution may legitimately reverse admitted sequence order");
  check(admission.admitted_command_history()[0].received_after_tick.value==0,"Admitted history records actual receiving boundary including pendingcommand");
  check(admission.apply({{{1},cfg.session_id},{77},"session.owner",c::PauseControl{true}})==c::SessionControlRejection::none,"Original lifecycle sequence accepted");
  check(admission.accepted_session_controls()[0].sequence.value==77&&admission.event_log()[0].sequence.value==1,"Original lifecycle source sequence preserved independently of generated event sequence");
  check(admission.events_after({0},1).size()==1&&admission.events_after({1},1).empty(),"Caller-owned event cursor delivers immutable bounded batches without silent consumption");
  rejects([&]{(void)admission.events_after({2},1);},"Future event cursor rejected");
  rejects([&]{(void)admission.events_after({0},0);},"Zero event batch rejected");
  auto windy_cfg=cfg;windy_cfg.trim.longitudinal=false;windy_cfg.initial_conditions.atmosphere.wind_toward_ned_mps={4,-3,2};
  f::Session windy(windy_cfg);
  for(int i=0;i<2;++i) {
    const auto state=windy.latest_snapshot();const auto weather=windy.latest_atmosphere();const auto q=state.orientation_body_to_ned;
    // Inverse active rotation, calculated independently by matrix columns.
    const auto north=c::rotate_body_to_ned(q,c::BodyVelocity{1,0,0}),right=c::rotate_body_to_ned(q,c::BodyVelocity{0,1,0}),down=c::rotate_body_to_ned(q,c::BodyVelocity{0,0,1});
    const auto wind=weather.wind_toward_ned_mps;
    const c::BodyVelocity wind_body{north.x*wind.x+north.y*wind.y+north.z*wind.z,right.x*wind.x+right.y*wind.y+right.z*wind.z,down.x*wind.x+down.y*wind.y+down.z*wind.z};
    const double airspeed=std::hypot(state.velocity_body_mps.x-wind_body.x,state.velocity_body_mps.y-wind_body.y,state.velocity_body_mps.z-wind_body.z);
    check(std::hypot(wind.x-4,wind.y+3,wind.z-2)<1e-10,"Actual constant asymmetric wind-toward retained");
    check(std::abs(windy.diagnostics().airspeed_mps-airspeed)<1e-9,"Actual airspeed subtracts transformed wind from groundrelativeUVW");
    if(i==0)check(std::hypot(state.velocity_body_mps.x-cfg.initial_conditions.aircraft.velocity_body_mps.x,state.velocity_body_mps.y,state.velocity_body_mps.z-cfg.initial_conditions.aircraft.velocity_body_mps.z)<1e-9,"No-trim initialization preserves requested groundvelocity with wind");
    check(windy.step_fixed().stepped,"Wind step");
  }
  auto identity_cfg=windy_cfg;identity_cfg.initial_conditions.aircraft.orientation_body_to_ned={1,0,0,0};identity_cfg.initial_conditions.aircraft.velocity_body_mps={55,3,2};
  identity_cfg.initial_conditions.atmosphere.wind_toward_ned_mps={7,-4,1};f::Session identity(identity_cfg);
  for(int i=0;i<2;++i) {const auto q=identity.latest_snapshot().orientation_body_to_ned;check(std::abs(q.w)<=1&&std::abs(q.x)<=1&&std::abs(q.y)<=1&&std::abs(q.z)<=1&&c::valid(q),"Actual nearidentity wind/no-trim quaternion obeys strict wirecomponentbounds");check(identity.step_fixed().stepped,"Actual nearidentity solverstep");}
  JSBSim::FGFDMExec mass_reference;mass_reference.SetDebugLevel(0);mass_reference.SetRootDir(SGPath(argv[3]));mass_reference.SetAircraftPath(SGPath("aircraft"));
  check(mass_reference.LoadModel("asymmetric-cg"),"Actual independent asymmetric mass fixture load");
  mass_reference.GetIC()->SetAltitudeASLFtIC(1000/.3048);mass_reference.GetPropulsion()->SetFuelFreeze(true);check(mass_reference.RunIC(),"Actual asymmetric mass inventoryRunIC");
  for(double fuel:{100.,50.,0.}) {
    mass_reference.GetPropulsion()->GetTank(0)->SetContents(fuel/.45359237);check(mass_reference.Run(),"Actual asymmetric fuel change mass update");
    const auto mass=mass_reference.GetMassBalance();const auto structural=mass->GetXYZcg();const double total=1200+fuel;
    const std::array<double,3> expected{(21600+24*fuel)/total,(3600-12*fuel)/total,(4200+3*fuel)/total};
    check(std::abs(structural(1)-expected[0])<1e-10&&std::abs(structural(2)-expected[1])<1e-10&&std::abs(structural(3)-expected[2])<1e-10,"Backend GetXYZcg returns independent weighted asymmetric STRUCTURALinches");
    const auto datum=f::structural_cg_inches_to_body_datum_m(structural(1),structural(2),structural(3));
    check(std::abs(datum.x+expected[0]*.0254)<1e-12&&std::abs(datum.y-expected[1]*.0254)<1e-12&&std::abs(datum.z+expected[2]*.0254)<1e-12,"Actual asymmetric backend datumFRD SI mapping");
    check(mass->StructuralToBody(structural).Magnitude()<1e-12,"StructuralToBody(CG) is zero and cannot represent fixed-datumCG");
  }
  // Actual signed response, relative to a trimmed no-command baseline after0.2s.
  f::Session neutral(cfg);for(int i=0;i<24;++i)check(neutral.step_fixed().stepped,"Signed-response baseline step");
  const auto neutral_rate=neutral.latest_snapshot().angular_rate_body_radps;
  for(double sign:{-1.,1.}) {
    f::Session trim_response(cfg);auto pulse=trim_response.initialization().solved_controls;pulse.trim+=sign*.025;
    check(trim_response.register_host_source("pilot.controls",c::Authority::pilot),"Signed trim source");check(trim_response.submit(axes_command(cfg,pulse)).queued,"Signed trim request queued");
    for(int i=0;i<24;++i)check(trim_response.step_fixed().stepped,"Actual signed trim solverstep");
    check((trim_response.latest_snapshot().angular_rate_body_radps.y-neutral_rate.y)*sign>1e-4,"Positive/negative pilot trim produces corresponding nose-up/downbodyrate");
  }
  for(int axis=0;axis<3;++axis)for(double sign:{-1.,1.}) {
    f::Session response(cfg);auto pulse=response.initialization().solved_controls;
    if(axis==0)pulse.roll+=sign*.02;else if(axis==1)pulse.pitch+=sign*.025;else pulse.yaw+=sign*.04;
    check(response.register_host_source("pilot.controls",c::Authority::pilot),"Signed-response source");check(response.submit(axes_command(cfg,pulse)).queued,"Signed pulse queued");
    for(int i=0;i<24;++i)check(response.step_fixed().stepped,"Signed response actual solverstep");
    const auto rate=response.latest_snapshot().angular_rate_body_radps;
    const double delta=axis==0?rate.x-neutral_rate.x:axis==1?rate.y-neutral_rate.y:rate.z-neutral_rate.z;
    check(delta*sign>1e-4,"Positive/negative pilot axis produces corresponding signed bodyrate");
  }
  // Native library convention proof: raw components are checked against actualGetTb2l,
  // including independent Euler cases and mixed vectors rather than trusting labels.
  for(const auto& angles:std::array<std::array<double,3>,4>{{{0,0,c::pi/2},{c::pi/2,0,0},{0,c::pi/6,0},{.3,-.4,1.2}}}) {
    JSBSim::FGFDMExec executive;executive.SetDebugLevel(0);executive.SetRootDir(SGPath(argv[1]));executive.SetAircraftPath(SGPath("aircraft"));executive.SetEnginePath(SGPath("engine"));
    check(executive.LoadModel("original-synthetic"),"Actual quaternion fixture model load");auto ic=executive.GetIC();
    ic->SetGeodLatitudeRadIC(.8);ic->SetLongitudeRadIC(-2);ic->SetAltitudeASLFtIC(1000/.3048);ic->SetPhiRadIC(angles[0]);ic->SetThetaRadIC(angles[1]);ic->SetPsiRadIC(angles[2]);
    check(executive.RunIC(),"Actual quaternion fixtureRunIC");const auto p=executive.GetPropagate();const auto& m=p->GetTb2l();const auto& raw=p->GetQuaternion();
    std::array<double,9> values{};for(unsigned i=0;i<3;++i)for(unsigned j=0;j<3;++j)values[3*i+j]=m(i+1,j+1);
    const auto converted=f::body_to_ned_from_matrix(values);const c::QuaternionBodyToNed raw_active{raw(1),raw(2),raw(3),raw(4)};
    for(const auto& v:std::array<c::BodyVelocity,4>{{{1,0,0},{0,1,0},{0,0,1},{2,3,4}}}) {
      const auto public_vector=c::rotate_body_to_ned(converted,v);const auto raw_vector=c::rotate_body_to_ned(raw_active,v);
      check(std::hypot(public_vector.x-(m(1,1)*v.x+m(1,2)*v.y+m(1,3)*v.z),public_vector.y-(m(2,1)*v.x+m(2,2)*v.y+m(2,3)*v.z),public_vector.z-(m(3,1)*v.x+m(3,2)*v.y+m(3,3)*v.z))<1e-12,"Actual matrix mapsbodyvectors toNED");
      check(std::hypot(public_vector.x-raw_vector.x,public_vector.y-raw_vector.y,public_vector.z-raw_vector.z)<1e-12,"Actual rawtuple passiveGetT mapsactive body-to-NEDwithoutconjugation");
    }
  }
  std::cout<<"FDM "<<checks<<" checks, "<<failures<<" failures\n"; return failures?1:0;
 } catch(const std::exception& e) { std::cerr<<"FDM test exception: "<<e.what()<<'\n';return 1; }
}
