#pragma once
#include <flight/interactive/session.hpp>
#include <iostream>
#include <thread>
namespace interactive_checks {
namespace p=flight::interactive;namespace c=flight::contracts::v1;
inline void require(bool value,const char* message){if(!value){throw std::runtime_error(message);}}
class FaultSurface final:public p::AnalyticSurface {
 public:
  explicit FaultSurface(p::SurfaceConfig cfg):AnalyticSurface(cfg,p::prepared_identity(cfg)){}
  enum class Mode{none,known,callback_missing,callback_throw,wrong_world,identity_throw,unknown_throw,identity_changed,coherent_identity_drift};
  mutable unsigned queries{};Mode mode{};c::MissingGround reason{c::MissingGround::not_loaded};
  flight::ground::v1::Identity identity()const override{if(mode==Mode::identity_throw){throw std::runtime_error("Injected identity fault");}auto out=AnalyticSurface::identity();if(mode==Mode::identity_changed||mode==Mode::coherent_identity_drift){out.world.id="alternate.world";}if(mode==Mode::coherent_identity_drift){++out.generation;out.world.sha256=std::string(64,'a');out.prepared_surface_sha256=out.world.sha256;}return out;}
  c::GroundSample sample(const flight::ground::v1::Query& query)const override {
    ++queries;if((mode==Mode::known&&queries==1)||(mode==Mode::callback_missing&&queries==5)){return {query.header,query.position,reason};}
    if(mode==Mode::callback_throw&&queries==5){throw std::runtime_error("Injected callback fault");}
    if(mode==Mode::unknown_throw&&queries==5){throw 7;}
    auto out=AnalyticSurface::sample(query);if(mode==Mode::wrong_world&&queries==5){std::get<c::ValidGround>(out.sample).world.id="wrong.world";}if(mode==Mode::coherent_identity_drift){std::get<c::ValidGround>(out.sample).world=identity().world;}return out;
  }
  void arm(Mode next){mode=next;queries=0;}
};
inline c::ControlCommand command(const p::Session& s,std::uint64_t seq,c::PilotAxes axes){return {{c::Tick{s.latest().header.tick.value+1},s.latest().header.session_id},{seq},"pilot.controls",c::Authority::pilot,{"unassisted",{}},axes};}
inline unsigned run(const std::filesystem::path& model,const std::filesystem::path& output_prefix){unsigned checks=0;const auto check=[&](bool x,const char* message){require(x,message);++checks;};
  for(const auto reason:{c::MissingGround::outside_coverage,c::MissingGround::not_loaded,c::MissingGround::datum_unresolved,c::MissingGround::invalid_data}){
    auto world=std::make_shared<FaultSurface>(p::SurfaceConfig{});p::Config cfg;cfg.model_root=model;cfg.surface=world;p::Session s(cfg);const auto before=p::snapshot_json(s.latest());const auto held=s.held();auto axes=held;axes.throttle=1;
    check(s.submit(command(s,1,axes))==c::CommandRejection::none,"Known-miss command admission failed");world->reason=reason;world->arm(FaultSurface::Mode::known);
    check(s.step_fixed().status==p::Status::coverage_blocked,"Known miss did not block");check(s.live()&&p::snapshot_json(s.latest())==before,"Known miss changed published state/solver lifetime");check(s.held().throttle==held.throttle,"Known miss changed held controls");
    world->arm(FaultSurface::Mode::none);const auto resumed=s.step_fixed();check(resumed.status==p::Status::completed&&resumed.applied.size()==1&&s.held().throttle==1,"Pure known miss lost pending command");
  }
  for(const auto mode:{FaultSurface::Mode::callback_missing,FaultSurface::Mode::callback_throw,FaultSurface::Mode::wrong_world,FaultSurface::Mode::identity_throw,FaultSurface::Mode::unknown_throw,FaultSurface::Mode::identity_changed,FaultSurface::Mode::coherent_identity_drift}){
    auto world=std::make_shared<FaultSurface>(p::SurfaceConfig{});p::Config cfg;cfg.model_root=model;cfg.surface=world;p::Session s(cfg);const auto before=p::snapshot_json(s.latest());auto axes=s.held();axes.throttle=1;check(s.submit(command(s,1,axes))==c::CommandRejection::none,"Fault command admission failed");world->arm(mode);
    check(s.step_fixed().status==p::Status::discarded,"Unexpected fault did not discard");check(!s.live()&&p::snapshot_json(s.latest())==before,"Terminal fault lost previous publication");check(s.held().throttle==0,"Terminal fault committed candidate controls");check(s.step_fixed().status==p::Status::discarded,"Terminal executive resumed");s.close();check(p::snapshot_json(s.latest())==before,"Terminal close changed immutable publication");
    if(mode==FaultSurface::Mode::coherent_identity_drift){check(world->queries==0,"Coherent identity drift reached provider sampling/mutation");}
  }
  auto world=std::make_shared<FaultSurface>(p::SurfaceConfig{});p::Config cfg;cfg.model_root=model;cfg.surface=world;p::Session s(cfg);auto axes=s.held();axes.roll=2;
  check(s.submit(command(s,1,axes))==c::CommandRejection::invalid,"Invalid axes accepted");axes=s.held();check(s.submit(command(s,1,axes))==c::CommandRejection::none,"Rejected input consumed sequence");check(s.submit(command(s,1,axes))==c::CommandRejection::duplicate,"Duplicate source sequence accepted");
  const auto before=p::snapshot_json(s.latest());c::SessionControl pause{{s.latest().header.tick,cfg.session_id},{1},"session.owner",c::PauseControl{true}};check(s.apply(pause)==c::SessionControlRejection::none,"Pause rejected");check(s.step_fixed().status==p::Status::paused&&p::snapshot_json(s.latest())==before,"Pause mutated state");
  c::SessionControl scale{{s.latest().header.tick,cfg.session_id},{2},"session.owner",c::TimeScaleControl{.5}};check(s.apply(scale)==c::SessionControlRejection::none&&s.time_scale()==.5,"Time scale rejected");pause.sequence={3};pause.payload=c::PauseControl{false};check(s.apply(pause)==c::SessionControlRejection::none,"Resume rejected");check(s.step_fixed().applied.size()==1,"Paused pending command did not apply once");
  check(s.events().size()==3&&s.events()[0].sequence.value==1&&s.events()[2].sequence.value==3,"Lifecycle events not ordered");
  std::ofstream lifecycle_records(output_prefix.string()+".events.ndjson");
  for(const auto& event:s.events()){lifecycle_records<<flight::fdm::transport::json(event)<<'\n';}
  check(std::abs(s.latest().elapsed_s-1./120)<1e-12,"Time scale changed integration dt");
  auto forbidden=command(s,2,s.held());forbidden.authority=c::Authority::instructor;
  check(s.submit(forbidden)==c::CommandRejection::unauthorized_source,"Pilot self-elevated authority");
  forbidden=command(s,2,s.held());forbidden.source_id="unknown.source";
  check(s.submit(forbidden)==c::CommandRejection::unauthorized_source,"Unregistered source accepted");
  forbidden=command(s,2,s.held());forbidden.header.session_id="wrong.session";
  check(s.submit(forbidden)==c::CommandRejection::wrong_session,"Wrong session accepted");
  forbidden=command(s,2,s.held());forbidden.header.tick=s.latest().header.tick;
  check(s.submit(forbidden)==c::CommandRejection::late,"Completed tick accepted");
  forbidden=command(s,2,s.held());forbidden.assistance.active={"hidden.assist"};
  check(s.submit(forbidden)==c::CommandRejection::invalid,"Undeclared assistance accepted");
  forbidden=command(s,2,s.held());std::get<c::PilotAxes>(forbidden.payload).mixture=.5;
  check(s.submit(forbidden)==c::CommandRejection::unsupported_control,"Variable mixture accepted");
  forbidden=command(s,2,s.held());forbidden.payload=c::SystemControl{"arbitrary.property",1.};
  check(s.submit(forbidden)==c::CommandRejection::unsupported_control,"Arbitrary backend property accepted");
  check(s.register_host_source("scenario.test",c::Authority::scenario),"Native scenario registration failed");
  auto high=command(s,1,s.held());high.source_id="scenario.test";high.authority=c::Authority::scenario;std::get<c::PilotAxes>(high.payload).throttle=.2;
  auto low=command(s,2,s.held());std::get<c::PilotAxes>(low.payload).throttle=.1;
  check(s.submit(high)==c::CommandRejection::none&&s.submit(low)==c::CommandRejection::none,"Rejected commands consumed sequence");
  const auto ordered=s.step_fixed();check(ordered.applied.size()==2&&ordered.applied[0].authority==c::Authority::pilot&&ordered.applied[1].authority==c::Authority::scenario&&s.held().throttle==.2,"Arrival order displaced canonical command authority");
  bool wrong_read_rejected=false,wrong_close_rejected=false;std::thread other([&]{try{(void)s.latest();}catch(const std::logic_error&){wrong_read_rejected=true;}try{s.close();}catch(const std::logic_error&){wrong_close_rejected=true;}});other.join();
  check(wrong_read_rejected,"Off-owner readback allowed");check(wrong_close_rejected&&s.live(),"Off-owner close allowed");
  for(unsigned malformed=0;malformed<3;++malformed){auto invalid=s.latest();if(malformed==0){invalid.contacts[0].force_body_n.x=std::numeric_limits<double>::quiet_NaN();}else if(malformed==1){invalid.contacts[0].id="invalid\"contact";}else{invalid.contacts[1].id=invalid.contacts[0].id;}bool rejected=false;try{(void)p::snapshot_json(invalid);}catch(const std::invalid_argument&){rejected=true;}check(rejected,"Malformed complete contact snapshot serialized");}
  for(unsigned malformed=0;malformed<6;++malformed){auto invalid=command(s,3,s.held());auto& brake_axes=std::get<c::PilotAxes>(invalid.payload);
    if(malformed==0){brake_axes.left_brake=std::numeric_limits<double>::quiet_NaN();}else if(malformed==1){brake_axes.right_brake=std::numeric_limits<double>::quiet_NaN();}
    else if(malformed==2){brake_axes.left_brake=-.01;}else if(malformed==3){brake_axes.right_brake=1.01;}
    else if(malformed==4){invalid.source_id="bad\"source";}else{invalid.header.session_id="bad\"session";}
    bool rejected=false;try{(void)p::command_json(invalid);}catch(const std::invalid_argument&){rejected=true;}check(rejected,"Malformed original brake command serialized");
  }
  auto differential=command(s,3,s.held());auto& differential_axes=std::get<c::PilotAxes>(differential.payload);differential_axes.left_brake=.2;differential_axes.right_brake=.8;
  std::ofstream brake_record(output_prefix.string()+".brakes.ndjson");brake_record<<p::command_json(differential)<<'\n';
  p::Config air;air.model_root=model;air.surface=world;air.start=p::Start::airborne;air.requested_height_m=1000;air.forward_mps=55*std::cos(.02);air.down_mps=55*std::sin(.02);air.pitch_rad=.02;air.trim=true;p::Session airborne(air);
  const auto observed_airborne=airborne.latest();check(observed_airborne.contacts.size()==3&&std::none_of(observed_airborne.contacts.begin(),observed_airborne.contacts.end(),[](const auto& x){return x.on_ground;}),"Airborne gear state invalid");check(observed_airborne.position.ellipsoid_height_m>999,"Airborne actual clearance not positive");
  for(unsigned i=0;i<1200;++i){check(airborne.step_fixed().status==p::Status::completed,"Trimmed airborne finite run failed");}
  check(c::valid(airborne.latest())&&c::valid(airborne.atmosphere()),"Invalid airborne v1 publication");
  for(unsigned bad=0;bad<3;++bad){auto invalid=cfg;if(bad==0){invalid.start=static_cast<p::Start>(9);}else if(bad==1){invalid.trim=true;}else invalid.forward_mps=1;bool rejected=false;try{p::Session unsupported(invalid);}catch(const std::invalid_argument&){rejected=true;}check(rejected,"Unsupported named startup accepted");}
  for(unsigned alternate=0;alternate<6;++alternate){
    p::SurfaceConfig shape;
    if(alternate==0){shape.anchor.latitude_rad+=.01;}
    else if(alternate==1){shape.anchor.ellipsoid_height_m=1000;}
    else if(alternate==2){shape.slope_north=.03;}
    else if(alternate==3){shape.static_friction=.9;}
    else if(alternate==4){shape.north_max=21000;}
    else shape.second_tile_loaded=false;
    auto unsupported_world=std::make_shared<FaultSurface>(shape);
    auto invalid=cfg;invalid.surface=unsupported_world;bool rejected=false;
    try{p::Session unsupported(invalid);}catch(const std::invalid_argument&){rejected=true;}
    check(rejected&&unsupported_world->queries==0,"Alternate prepared world reached allocation/sampling");
  }
  auto incompatible_identity=std::make_shared<FaultSurface>(p::SurfaceConfig{});
  incompatible_identity->mode=FaultSurface::Mode::identity_changed;auto invalid_world=cfg;invalid_world.surface=incompatible_identity;bool identity_rejected=false;
  try{p::Session unsupported(invalid_world);}catch(const std::invalid_argument&){identity_rejected=true;}
  check(identity_rejected&&incompatible_identity->queries==0,"Alternate source identity accepted");
  auto invalid_clock=cfg;invalid_clock.hz=60;bool clock_rejected=false;
  try{p::Session unsupported(invalid_clock);}catch(const std::invalid_argument&){clock_rejected=true;}
  check(clock_rejected,"Runtime60Hz was inferred as research purpose");
  for(const unsigned hz:{60U,240U}){auto research=cfg;research.hz=hz;research.purpose=c::ClockPurpose::convergence;p::Session explicit_research(research);
    check(explicit_research.latest().clock.purpose==c::ClockPurpose::convergence,"Research purpose missing");
    for(unsigned tick=0;tick<hz;++tick){check(explicit_research.step_fixed().status==p::Status::completed,"Explicit research fixed step failed");}
  }
  p::Session bounded(cfg);auto queued_axes=bounded.held();
  for(std::uint64_t seq=1;seq<=4096;++seq){auto queued=command(bounded,seq,queued_axes);queued.header.tick={2};check(bounded.submit(queued)==c::CommandRejection::none,"Bounded control admission failed");}
  auto full=command(bounded,4097,queued_axes);full.header.tick={2};
  check(bounded.submit(full)==c::CommandRejection::capacity,"Control capacity silently exceeded");
  check(bounded.step_fixed().applied.empty(),"Future control applied early");
  check(bounded.step_fixed().applied.size()==4096,"Queued full samples did not apply exactly once");
  full.header.tick={3};check(bounded.submit(full)==c::CommandRejection::none,"Capacity rejection consumed source sequence");
  p::Session event_bounded(cfg);
  for(std::uint64_t seq=1;seq<=4096;++seq){c::SessionControl operation{{{0},cfg.session_id},{seq},"session.owner",c::PauseControl{true}};check(event_bounded.apply(operation)==c::SessionControlRejection::none,"Lifecycle capacity admission failed");}
  c::SessionControl full_event{{{0},cfg.session_id},{4097},"session.owner",c::PauseControl{false}};
  check(event_bounded.apply(full_event)==c::SessionControlRejection::invalid&&event_bounded.paused()&&event_bounded.events().size()==4096,"Lifecycle capacity changed clock/events");
  std::cout<<"interactive negative/readback checks "<<checks<<" PASS\n";
  return checks;
}
}
