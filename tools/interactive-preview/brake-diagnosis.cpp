#include <flight/interactive/session.hpp>
#include <flight/fdm/protocol.hpp>
#include <algorithm>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <cmath>
namespace p=flight::interactive;namespace c=flight::contracts::v1;
double pitch(c::QuaternionBodyToNed q){return std::asin(std::clamp(2*(q.w*q.y-q.z*q.x),-1.,1.));}
double roll(c::QuaternionBodyToNed q){return std::atan2(2*(q.w*q.x+q.y*q.z),1-2*(q.x*q.x+q.y*q.y));}
double speed(const c::AircraftSnapshot& s){return c::magnitude(s.velocity_body_mps);}
bool all_wow(const c::AircraftSnapshot& s){return std::all_of(s.contacts.begin(),s.contacts.end(),[](const auto& g){return g.on_ground;});}
bool any_wow(const c::AircraftSnapshot& s){return std::any_of(s.contacts.begin(),s.contacts.end(),[](const auto& g){return g.on_ground;});}
c::PilotAxes hold_pitch(const p::Session& s,double desired,double throttle,double brakes=0){const auto a=s.latest();const double alpha=std::atan2(a.velocity_body_mps.z,a.velocity_body_mps.x);return {std::clamp(-2*roll(a.orientation_body_to_ned)-.3*a.angular_rate_body_radps.x,-.25,.25),std::clamp((alpha-.02)/.7+2*(desired-pitch(a.orientation_body_to_ned))-.5*a.angular_rate_body_radps.y,-.4,.4),0,throttle,1,brakes,brakes,0};}
struct Trial {
  p::SurfaceConfig cfg;std::shared_ptr<p::AnalyticSurface> world{std::make_shared<p::AnalyticSurface>(cfg,p::prepared_identity(cfg))};
  p::Config config;p::Session session;std::uint64_t sequence{1};std::ofstream raw,csv;
  Trial(const std::string& models,const std::string& prefix):config(make_config(models)),session(config),raw(prefix+".ndjson"),csv(prefix+".csv"){
    if(!session.register_host_source("scenario.proof",c::Authority::scenario)){throw std::runtime_error("Source registration failed");}
    csv<<"tick,speed_mps,north_m,east_m,pitch_rad,wow,total_normal_n,main_normal_n,contact_forward_n,left_brake,right_brake,throttle\n";
    emit();
  }
  p::Config make_config(const std::string& root){p::Config x;x.model_root=root;x.surface=world;return x;}
  double height(){const auto a=session.latest();const auto g=world->sample({a.header,a.position});return a.position.ellipsoid_height_m-std::get<c::ValidGround>(g.sample).surface_height_m;}
  void step(c::PilotAxes axes){const auto a=session.latest();c::ControlCommand command{{{a.header.tick.value+1},config.session_id},{sequence++},"scenario.proof",c::Authority::scenario,{"unassisted",{}},axes};
    if(session.submit(command)!=c::CommandRejection::none){throw std::runtime_error("Command rejected");}
    const auto result=session.step_fixed();if(result.status!=p::Status::completed||result.applied.size()!=1){throw std::runtime_error("Incomplete actual step: "+session.fault());}
  }
  void emit(){const auto a=session.latest();raw<<p::snapshot_json(a)<<'\n';const auto xy=world->coordinates(a.ecef_position_m);double normal=0,main=0,forward=0;unsigned wow=0;
    const auto fixed_up=p::Basis(cfg.anchor).ned_to_ecef({0,0,-1});
    for(const auto& g:a.contacts){if(g.on_ground){++wow;}const auto force=c::rotate_body_to_ned(a.orientation_body_to_ned,g.force_body_n);const auto ecef=p::Basis(a.position).ned_to_ecef({force.x,force.y,force.z});const double n=p::dot(ecef,fixed_up);normal+=n;if(g.id!="gear.nose"){main+=n;}forward+=g.force_body_n.x;}
    const auto axes=session.held();csv<<std::setprecision(17)<<a.header.tick.value<<','<<speed(a)<<','<<xy.x<<','<<xy.y<<','<<pitch(a.orientation_body_to_ned)<<','<<wow<<','<<normal<<','<<main<<','<<forward<<','<<axes.left_brake<<','<<axes.right_brake<<','<<axes.throttle<<'\n';
  }
};
void report(std::ofstream& out,Trial& trial,const std::string& id,double brake,double throttle,const c::AircraftSnapshot& begin,double path,bool stopped,unsigned lost){const auto end=trial.session.latest();const auto b=trial.world->coordinates(begin.ecef_position_m),e=trial.world->coordinates(end.ecef_position_m);
  out<<std::setprecision(17)<<"{\"trial\":\""<<id<<"\",\"brake\":"<<brake<<",\"throttle\":"<<throttle<<",\"start_tick\":"<<begin.header.tick.value<<",\"end_tick\":"<<end.header.tick.value<<",\"start_speed_mps\":"<<speed(begin)<<",\"end_speed_mps\":"<<speed(end)<<",\"duration_s\":"<<double(end.header.tick.value-begin.header.tick.value)/120<<",\"path_m\":"<<path<<",\"chord_m\":"<<std::hypot(e.x-b.x,e.y-b.y)<<",\"stopped_below_0_1_all_wow\":"<<(stopped?"true":"false")<<",\"non_all_wow_ticks\":"<<lost<<",\"live\":"<<(trial.session.live()?"true":"false")<<",\"source_fingerprint\":\""<<p::source_fingerprint()<<"\",\"world_sha256\":\""<<trial.world->identity().prepared_surface_sha256<<"\"}\n";
}
void ground(std::ofstream& out,const std::string& models,const std::string& folder,double target,double brake,double throttle){const auto id="ground_"+std::to_string(int(target))+"_b"+std::to_string(int(brake*100))+"_t"+std::to_string(int(throttle*100));Trial t(models,folder+"/"+id);
  for(unsigned i=0;i<600;++i){t.step({0,0,0,0,1,1,1,0});}t.emit();
  unsigned accelerated=0;while(speed(t.session.latest())<target&&accelerated++<120*60){t.step({0,0,0,1,1,0,0,0});}if(speed(t.session.latest())<target){throw std::runtime_error("Target speed not reached");}
  const auto begin=t.session.latest();t.emit();auto previous=t.world->coordinates(begin.ecef_position_m);double path=0;bool stopped=false;unsigned lost=0;
  for(unsigned i=0;i<120*60;++i){t.step({0,0,0,throttle,1,brake,brake,0});const auto a=t.session.latest();const auto xy=t.world->coordinates(a.ecef_position_m);path+=std::hypot(xy.x-previous.x,xy.y-previous.y);previous=xy;if(!all_wow(a)){++lost;}if(i%60==0){t.emit();}if(speed(a)<.1&&all_wow(a)){stopped=true;break;}}
  t.emit();report(out,t,id,brake,throttle,begin,path,stopped,lost);
}
void landing(std::ofstream& out,const std::string& models,const std::string& folder,double brake){const auto id="landing_b"+std::to_string(int(brake*100));Trial t(models,folder+"/"+id);int phase=0;unsigned phase_ticks=0;bool touched=false,stopped=false;double path=0;unsigned lost=0;c::AircraftSnapshot begin; auto previous=t.world->coordinates(t.session.latest().ecef_position_m);
  for(unsigned i=0;i<120*200;++i){const auto a=t.session.latest();const double h=t.height(),v=speed(a);const bool wow=any_wow(a);c::PilotAxes axes;
    if(phase==0){axes={0,0,0,0,1,1,1,0};if(i>=600){phase=1;phase_ticks=0;}}
    else if(phase==1){axes=hold_pitch(t.session,v>32?.12:0,1);if(!wow&&h>3){phase=2;phase_ticks=0;}}
    else if(phase==2){axes=hold_pitch(t.session,.08,.9);if(h>30){phase=3;phase_ticks=0;}}
    else if(phase==3){axes=hold_pitch(t.session,.03,.6);if(phase_ticks<60){axes.roll+=.02;}if(phase_ticks>360){phase=4;phase_ticks=0;}}
    else if(phase==4){const double alpha=std::atan2(a.velocity_body_mps.z,a.velocity_body_mps.x);axes=hold_pitch(t.session,alpha-(h>4?.045:.018),h>4?.3:0);if(wow){touched=true;begin=a;previous=t.world->coordinates(a.ecef_position_m);t.emit();phase=5;phase_ticks=0;}}
    else{axes=hold_pitch(t.session,0,0,brake);if(v<.1&&all_wow(a)){stopped=true;break;}if(phase_ticks>=120*120){break;}}
    t.step(axes);const auto observed=t.session.latest();if(touched){const auto xy=t.world->coordinates(observed.ecef_position_m);path+=std::hypot(xy.x-previous.x,xy.y-previous.y);previous=xy;if(!all_wow(observed)){++lost;}}if(i%60==0){t.emit();}++phase_ticks;
  }
  if(!touched){throw std::runtime_error("Script did not touch down");}t.emit();report(out,t,id,brake,0,begin,path,stopped,lost);
}
int main(int argc,char** argv){try{if(argc!=3){throw std::invalid_argument("models outputdir");}std::ofstream summary(std::string(argv[2])+"/summary.ndjson");for(const double target:{10.,20.,30.}){for(const double brake:{0.,.5,1.}){ground(summary,argv[1],argv[2],target,brake,0);}}ground(summary,argv[1],argv[2],20,1,1);for(const double brake:{0.,.5,1.}){landing(summary,argv[1],argv[2],brake);}std::cout<<"13 accepted-source brake trials complete\n";return 0;}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
