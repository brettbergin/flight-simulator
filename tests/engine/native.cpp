#include "native-limits.hpp"
#include "loaded-library.hpp"
#include "selected-method.hpp"
#include <flight/fdm/protocol.hpp>
#include <fstream>
#include <iostream>
#include <iomanip>
#include <numbers>
#include <cfenv>
#include <xmmintrin.h>
namespace p=flight::interactive;namespace c=p::c;namespace fx=piston_fixture;
void require(bool value,const char* reason){if(!value){throw std::runtime_error(reason);}}
bool same(c::PilotAxes a,c::PilotAxes b){return std::tie(a.roll,a.pitch,a.yaw,a.throttle,a.mixture,a.left_brake,a.right_brake,a.trim)==std::tie(b.roll,b.pitch,b.yaw,b.throttle,b.mixture,b.left_brake,b.right_brake,b.trim);}
bool flag(const c::AircraftSnapshot& s,std::string_view id){for(const auto& x:s.systems){if(x.id==id){return std::get<bool>(x.value);}}throw std::runtime_error("Missing boolean native system");}
double reading(const c::AircraftSnapshot& s,std::string_view id){for(const auto& x:s.systems){if(x.id==id){return std::get<double>(x.value);}}throw std::runtime_error("Missing numeric native system");}
c::ControlCommand command(const p::Session& s,std::uint64_t seq,std::variant<c::PilotAxes,c::SystemControl> payload){return {{{s.latest().header.tick.value+1},s.latest().header.session_id},{seq},"pilot.controls",c::Authority::pilot,{"unassisted",{}},std::move(payload)};}
void record(std::ostream& out,const p::Session& s){require(s.angular_integration_method()==std::optional<std::string>{piston_test_selection::name},"Actual completed angular method mismatch");const auto d=s.piston_diagnostics();out<<std::setprecision(17)<<"{\"snapshot\":"<<p::snapshot_json(s.latest())<<",\"atmosphere\":"<<flight::fdm::transport::json(s.atmosphere())<<",\"stage\":{\"pre_prop_engine_rpm\":"<<d.pre_prop_engine_rpm<<",\"post_prop_rpm\":"<<d.post_prop_rpm<<",\"fuel_flow_lb_per_s\":"<<d.fuel_flow_lb_per_s<<",\"fuel_used_lb\":"<<d.fuel_used_lb<<",\"manifold_pressure_inhg\":"<<d.manifold_pressure_inhg<<",\"engine_input_pressure_psf\":"<<d.engine_input_pressure_psf<<",\"engine_input_density_slug_per_ft3\":"<<d.engine_input_density_slug_per_ft3<<",\"raw_engine_power_ftlb_per_s\":"<<d.raw_engine_power_ftlb_per_s<<",\"tank_contents_lb\":"<<d.tank_contents_lb<<",\"mass_slug\":"<<d.mass_slug<<"}}\n";}
unsigned admission(p::Session& s){unsigned checks=0;const auto reject=[&](c::ControlCommand x,c::CommandRejection want){require(s.submit(std::move(x))==want,"Wrong native admission rejection");++checks;};
 auto x=command(s,1,c::SystemControl{"engine.starter",1.});reject(x,c::CommandRejection::unsupported_control);
 x=command(s,1,c::SystemControl{"engine.unknown",true});reject(x,c::CommandRejection::unsupported_control);
 x=command(s,1,c::SystemControl{"engine.starter",true});x.header.tick.value+=1;reject(x,c::CommandRejection::late);
 x=command(s,1,c::SystemControl{"engine.starter",true});x.authority=c::Authority::scenario;reject(x,c::CommandRejection::unauthorized_source);
 x=command(s,1,c::SystemControl{"engine.starter",true});x.source_id="pilot.other";reject(x,c::CommandRejection::unauthorized_source);
 x=command(s,1,c::SystemControl{"engine.starter",true});x.header.session_id="wrong.session";reject(x,c::CommandRejection::wrong_session);
 x=command(s,1,c::SystemControl{"engine.starter",true});x.assistance.profile_id="assisted";reject(x,c::CommandRejection::invalid);
 x=command(s,1,c::SystemControl{"engine.ignition_left",true});reject(x,c::CommandRejection::none);reject(x,c::CommandRejection::duplicate);
 auto axes=s.held();axes.mixture=1;reject(command(s,2,axes),c::CommandRejection::none);
 reject(command(s,3,c::SystemControl{"engine.ignition_left",false}),c::CommandRejection::none);
 reject(command(s,4,c::SystemControl{"engine.ignition_right",true}),c::CommandRejection::none);
 reject(command(s,5,c::SystemControl{"engine.starter",true}),c::CommandRejection::none);
 reject(command(s,6,c::SystemControl{"fuel.feed",false}),c::CommandRejection::none);
 const auto step=s.step_fixed();require(step.status==p::Status::completed&&step.applied.size()==6,"Mixed boundary was not completed once");++checks;
 for(std::size_t i=0;i<step.applied.size();++i){require(step.applied[i].sequence.value==i+1,"Mixed ordering lost shared sequence");++checks;}
 const auto snapshot=s.latest();require(!flag(snapshot,"engine.ignition_left")&&flag(snapshot,"engine.ignition_right")&&flag(snapshot,"engine.starter")&&!flag(snapshot,"fuel.feed")&&reading(snapshot,"engine.mixture")==1,"Mixed final fold/readback mismatch");++checks;
 const auto before=p::snapshot_json(snapshot);const auto diagnostic=s.piston_diagnostics();
 require(s.apply({snapshot.header,{1},"session.owner",c::PauseControl{true}})==c::SessionControlRejection::none,"Native pause rejected");++checks;
 for(int i=0;i<16;++i){require(s.step_fixed().status==p::Status::paused&&p::snapshot_json(s.latest())==before&&s.piston_diagnostics().fuel_used_lb==diagnostic.fuel_used_lb&&flag(s.latest(),"engine.starter"),"Pause mutated engine truth");++checks;}
 reject(command(s,7,c::SystemControl{"engine.starter",false}),c::CommandRejection::none);
 require(s.apply({s.latest().header,{2},"session.owner",c::PauseControl{false}})==c::SessionControlRejection::none,"Native resume rejected");++checks;
 require(s.step_fixed().status==p::Status::completed&&!flag(s.latest(),"engine.starter"),"Recorded starter release did not precede resumed Run");++checks;
 const auto retained=p::snapshot_json(s.latest());s.close();require(!s.live()&&p::snapshot_json(s.latest())==retained&&s.step_fixed().status==p::Status::discarded,"Close lost retained state");++checks;return checks;}
int main(int argc,char** argv){
 std::string prefix=argc>2?argv[2]:"piston-native-failure";std::ofstream receipt(prefix+".json");std::string loaded_library;
 try{
  loaded_library=piston_fixture::loaded_library_path();
  if(argc<4){throw std::invalid_argument("Usage piston_native_tests model_root prefix case [hz]");}
  const std::string scenario=argv[3];const unsigned hz=argc>4?static_cast<unsigned>(std::stoul(argv[4])):120;
  require(hz==60||hz==120||hz==240,"Unsupported test clock");
  const bool negative=scenario=="no-spark"||scenario=="no-feed"||scenario=="mixture-zero";
  require(negative||scenario=="lifecycle"||scenario=="ignition-off"||scenario=="feed-off"||scenario=="admission"||scenario=="feed-recovery","Unknown frozen scenario");
  p::SurfaceConfig world_config;auto world=std::make_shared<const p::AnalyticSurface>(world_config,p::prepared_identity(world_config));
  p::Config config;config.profile=p::Profile::piston;config.angular_method=piston_test_selection::session;config.start=p::Start::piston_cold_ground;config.model_root=argv[1];config.surface=world;config.hz=hz;config.purpose=hz==120?c::ClockPurpose::runtime:c::ClockPurpose::convergence;config.session_id="piston-"+scenario+"-"+std::to_string(hz);
  p::Session s(config);const auto actual_method=s.angular_integration_method();require(actual_method&&*actual_method==piston_test_selection::name,"Actual initialized angular method mismatch");require(s.latest().header.tick.value==0&&s.latest().systems.size()==10&&std::abs(reading(s.latest(),"fuel.total")-100)<=1e-10&&reading(s.latest(),"propeller.angular_speed")==0&&!flag(s.latest(),"engine.running")&&!flag(s.latest(),"engine.starter")&&s.held().mixture==0,"Cold tick0 violated recipe");
  if(scenario=="admission"){const auto checks=admission(s);receipt<<"{\"passed\":true,\"scope\":\"native admission/pause/retained\",\"checks\":"<<checks<<",\"limits_sha256\":\""<<fx::limits_sha<<"\",\"loaded_library_path\":"<<fx::json_path(loaded_library)<<",\"angular_integration_method\":\""<<piston_test_selection::name<<"\",\"fp_rounding\":"<<std::fegetround()<<",\"fp_mxcsr\":"<<_mm_getcsr()<<",\"source_fingerprint\":\""<<p::source_fingerprint()<<"\"}\n";return 0;}
  std::ofstream trace(prefix+".ndjson"),commands(prefix+".commands.ndjson");record(trace,s);std::uint64_t sequence=1;auto held=fx::phases[0].axes;auto switches=fx::phases[0].switches;std::size_t phase=0;double previous_flow=0;
  const unsigned end=negative?13:scenario=="feed-recovery"?29:111;
  for(unsigned tick=0;tick<end*hz;++tick){
   while(phase+1<fx::phases.size()&&tick>=fx::phases[phase+1].second*hz){++phase;}
   auto next_axes=fx::phases[phase].axes;auto next_switches=fx::phases[phase].switches;
   if(tick>=hz&&negative){if(scenario=="no-spark"){next_switches[0]=next_switches[1]=false;}else if(scenario=="no-feed"){next_switches[3]=false;}else{next_axes.mixture=0;}}
   if(tick>=51*hz){if(scenario=="ignition-off"){next_axes.mixture=1;next_switches[0]=next_switches[1]=false;}else if(scenario=="feed-off"){next_axes.mixture=1;next_switches[3]=false;}}
   // Separate fixed recovery test: feed off t13..17, restored t17..29; no automatic starter.
   if(scenario=="feed-recovery"&&tick>=13*hz){next_switches[0]=next_switches[1]=true;next_switches[3]=tick>=17*hz;}
   if(tick==51*hz){const auto before=s.latest();require(flag(before,"engine.running")&&reading(before,"propeller.angular_speed")>0&&!flag(before,"engine.starter")&&flag(before,"fuel.feed")&&reading(before,"engine.mixture")==1&&previous_flow>0&&s.piston_diagnostics().fuel_flow_lb_per_s>0,"Shutdown causal precondition failed before command; early stall is not shutdown");}
   const auto before_flow=s.piston_diagnostics().fuel_flow_lb_per_s;
   std::vector<c::ControlCommand> admitted;
   if(!same(next_axes,held)){auto x=command(s,sequence++,next_axes);require(s.submit(x)==c::CommandRejection::none,"Axes schedule rejected");admitted.push_back(x);}
   for(std::size_t i=0;i<switches.size();++i){if(next_switches[i]!=switches[i]){auto x=command(s,sequence++,c::SystemControl{fx::switch_ids[i],next_switches[i]});require(s.submit(x)==c::CommandRejection::none,"System schedule rejected");admitted.push_back(x);}}
   const auto step=s.step_fixed();require(step.status==p::Status::completed,"Native lifecycle step failed");require(step.applied.size()==admitted.size(),"Applied count mismatch");
   for(std::size_t i=0;i<admitted.size();++i){require(p::command_json(step.applied[i],p::Profile::piston)==p::command_json(admitted[i],p::Profile::piston),"Applied intent changed");commands<<p::command_json(step.applied[i],p::Profile::piston)<<'\n';}
   held=next_axes;switches=next_switches;require(same(s.held(),held),"Native held axes mismatch");
   for(std::size_t i=0;i<switches.size();++i){require(flag(s.latest(),fx::switch_ids[i])==switches[i],"Native held system mismatch");}
   record(trace,s);previous_flow=before_flow;
  }
  receipt<<"{\"passed\":true,\"scope\":\"completed native trace; numerical oracle is separate\",\"case\":\""<<scenario<<"\",\"hz\":"<<hz<<",\"ticks\":"<<s.latest().header.tick.value<<",\"limits_sha256\":\""<<fx::limits_sha<<"\",\"loaded_library_path\":"<<fx::json_path(loaded_library)<<",\"angular_integration_method\":\""<<piston_test_selection::name<<"\",\"fp_rounding\":"<<std::fegetround()<<",\"fp_mxcsr\":"<<_mm_getcsr()<<",\"source_fingerprint\":\""<<p::source_fingerprint()<<"\",\"prepared_world_sha256\":\""<<world->identity().prepared_surface_sha256<<"\"}\n";return 0;
 }catch(const std::exception& error){std::cerr<<error.what()<<'\n';receipt<<"{\"passed\":false,\"scope\":\"native trace generation failed; preserve stderr\",\"limits_sha256\":\""<<fx::limits_sha<<"\",\"loaded_library_path\":"<<fx::json_path(loaded_library)<<"}\n";return 1;}
}
