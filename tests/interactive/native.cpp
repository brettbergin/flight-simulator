#include <flight/interactive/session.hpp>
#include <flight/fdm/protocol.hpp>
#include <iostream>
#include <fstream>
#include <iomanip>
#include <algorithm>
#include "negatives.hpp"
namespace p=flight::interactive;namespace c=flight::contracts::v1;
double pitch(c::QuaternionBodyToNed q){return std::asin(std::clamp(2*(q.w*q.y-q.z*q.x),-1.,1.));}
double roll(c::QuaternionBodyToNed q){return std::atan2(2*(q.w*q.x+q.y*q.z),1-2*(q.x*q.x+q.y*q.y));}
double height(const p::Session& s,const p::AnalyticSurface& world){const auto sample=world.sample({s.latest().header,s.latest().position});return s.latest().position.ellipsoid_height_m-std::get<c::ValidGround>(sample.sample).surface_height_m;}
c::PilotAxes hold_pitch(const p::Session& session,double desired,double throttle,bool brakes=false){const auto& a=session.latest();const double alpha=std::atan2(a.velocity_body_mps.z,a.velocity_body_mps.x);return {std::clamp(-2*roll(a.orientation_body_to_ned)-.3*a.angular_rate_body_radps.x,-.25,.25),std::clamp((alpha-.02)/.7+2*(desired-pitch(a.orientation_body_to_ned))-.5*a.angular_rate_body_radps.y,-.4,.4),0,throttle,1,brakes?1.:0,brakes?1.:0,0};}
int main(int argc,char** argv){
  try{
    if(argc<3){throw std::invalid_argument("Usage interactive_tests model_root output_prefix [airborne|negatives]");}
    if(argc>3&&std::string(argv[3])=="negatives"){const auto checks=interactive_checks::run(argv[1],argv[2]);std::ofstream out(std::string(argv[2])+".json");out<<"{\"engineering_prototype\":true,\"passed\":true,\"checks\":"<<checks<<",\"compiled_source_fingerprint\":\""<<p::source_fingerprint()<<"\"}\n";return 0;}
    p::SurfaceConfig cfg;auto world=std::make_shared<p::AnalyticSurface>(cfg,p::prepared_identity(cfg));p::Config start;start.model_root=argv[1];start.surface=world;
    if(argc>3){start.start=p::Start::airborne;start.requested_height_m=1000;start.forward_mps=55*std::cos(.02);start.down_mps=55*std::sin(.02);start.pitch_rad=.02;start.trim=true;}
    p::Session session(start);if(!session.register_host_source("scenario.proof",c::Authority::scenario)){throw std::runtime_error("Trusted proof source registration failed");}
    std::ofstream trace(std::string(argv[2])+".ndjson"),weather(std::string(argv[2])+".atmosphere.ndjson"),commands(std::string(argv[2])+".commands.ndjson"),metrics(std::string(argv[2])+".csv");trace<<p::snapshot_json(session.latest())<<'\n';weather<<flight::fdm::transport::json(session.atmosphere())<<'\n';metrics<<"tick,time_s,height_m,speed_mps,pitch,roll,wow,pilot_pitch,throttle\n";
    bool stationary=false,takeoff=false,air_control=false,touchdown=false;double maximum_height=0;std::uint64_t seq=1,last_recorded_tick=0,takeoff_tick=0,touchdown_tick=0;int phase=start.start==p::Start::airborne?4:0;unsigned phase_ticks=0;
    for(unsigned i=0;i<120*180;++i){const auto& a=session.latest();const double h=height(session,*world),speed=c::magnitude(a.velocity_body_mps);const bool wow=std::any_of(a.contacts.begin(),a.contacts.end(),[](const auto& x){return x.on_ground;});maximum_height=std::max(maximum_height,h);
      c::PilotAxes axes;
      if(phase==0){axes={0,0,0,0,1,1,1,0};if(i>=600){stationary=wow&&speed<.05;phase=1;phase_ticks=0;std::cerr<<"settled "<<stationary<<" h="<<h<<" speed="<<speed<<'\n';}}
      else if(phase==1){axes=hold_pitch(session,speed>32?.12:0,1);if(!wow&&h>3){takeoff=true;takeoff_tick=a.header.tick.value;phase=2;phase_ticks=0;std::cerr<<"takeoff t="<<a.elapsed_s<<" h="<<h<<" speed="<<speed<<'\n';}}
      else if(phase==2){axes=hold_pitch(session,.08,.9);if(h>30){phase=3;phase_ticks=0;}}
      else if(phase==3){axes=hold_pitch(session,.03,.6);if(phase_ticks<60){axes.roll+=.02;}air_control=air_control||std::abs(roll(a.orientation_body_to_ned))>.001;if(phase_ticks>360){phase=4;phase_ticks=0;}}
      else if(phase==4){const double alpha=std::atan2(a.velocity_body_mps.z,a.velocity_body_mps.x);axes=hold_pitch(session,alpha-(h>4?.045:.018),h>4?.3:0);if(wow){touchdown=true;touchdown_tick=a.header.tick.value;phase=5;phase_ticks=0;std::cerr<<"touchdown t="<<a.elapsed_s<<" h="<<h<<" speed="<<speed<<'\n';}}
      else {axes=hold_pitch(session,0,0,true);if(phase_ticks>600&&speed<.1){break;}}
      c::ControlCommand cmd{{c::Tick{a.header.tick.value+1},start.session_id},{seq++},"scenario.proof",c::Authority::scenario,{"unassisted",{}},axes};
      const auto reject=session.submit(cmd);if(reject!=c::CommandRejection::none){throw std::runtime_error("Controller command rejected");}
      const auto step=session.step_fixed();if(step.status!=p::Status::completed){std::cerr<<"stopped status="<<static_cast<int>(step.status)<<" tick="<<a.header.tick.value<<" reason="<<session.fault()<<'\n';break;}
      if(step.applied.size()!=1||step.applied[0].sequence!=cmd.sequence){throw std::runtime_error("Proof command did not apply exactly once");}commands<<p::command_json(step.applied[0])<<'\n';
      if(i%12==0){const auto observed=session.latest();trace<<p::snapshot_json(observed)<<'\n';weather<<flight::fdm::transport::json(session.atmosphere())<<'\n';last_recorded_tick=observed.header.tick.value;const bool observed_wow=std::any_of(observed.contacts.begin(),observed.contacts.end(),[](const auto& x){return x.on_ground;});metrics<<std::setprecision(12)<<observed.header.tick.value<<','<<observed.elapsed_s<<','<<height(session,*world)<<','<<c::magnitude(observed.velocity_body_mps)<<','<<pitch(observed.orientation_body_to_ned)<<','<<roll(observed.orientation_body_to_ned)<<','<<observed_wow<<','<<axes.pitch<<','<<axes.throttle<<'\n';}
      ++phase_ticks;
    }
    if(session.latest().header.tick.value!=last_recorded_tick){trace<<p::snapshot_json(session.latest())<<'\n';weather<<flight::fdm::transport::json(session.atmosphere())<<'\n';}
    const auto final=session.latest();const double final_speed=c::magnitude(final.velocity_body_mps);const bool stopped=final_speed<.1&&std::all_of(final.contacts.begin(),final.contacts.end(),[](const auto& x){return x.on_ground;});
    const bool passed=stationary&&takeoff&&air_control&&touchdown&&stopped&&session.live();std::ofstream receipt(std::string(argv[2])+".json");receipt<<std::boolalpha<<std::setprecision(17)<<"{\"engineering_prototype\":true,\"passed\":"<<passed<<",\"stationary\":"<<stationary<<",\"takeoff\":"<<takeoff<<",\"air_control\":"<<air_control<<",\"touchdown\":"<<touchdown<<",\"stopped_all_wow\":"<<stopped<<",\"live\":"<<session.live()<<",\"final_tick\":"<<session.latest().header.tick.value<<",\"final_speed_mps\":"<<final_speed<<",\"final_clearance_m\":"<<height(session,*world)<<",\"takeoff_tick\":"<<takeoff_tick<<",\"touchdown_tick\":"<<touchdown_tick<<",\"max_clearance_m\":"<<maximum_height<<",\"fault\":\""<<session.fault()<<"\",\"prepared_surface_sha256\":\""<<world->identity().prepared_surface_sha256<<"\",\"compiled_source_fingerprint\":\""<<p::source_fingerprint()<<"\"}\n";
    std::cout<<"scripted combined trial "<<(passed?"PASS":"INCOMPLETE")<<" finaltick="<<session.latest().header.tick.value<<" maxheight="<<maximum_height<<'\n';return passed?0:2;
  }catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}
}
