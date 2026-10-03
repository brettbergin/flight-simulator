#include "executive.hpp"
#include <fstream>
#include <iomanip>
#include <iostream>
#include <algorithm>

namespace p=flight::ground::proof;
namespace g=flight::ground::v1;
namespace c=flight::contracts::v1;
int checks{},failures{};
void check(bool condition,const char* message) {
  ++checks;if(!condition){++failures;std::cerr<<"FAIL "<<message<<'\n';}
}
template<class F>void rejects(F action,const char* message){bool rejected=false;try{action();}catch(const std::exception&){rejected=true;}check(rejected,message);}
g::Identity identity(p::SurfaceConfig config={}) {return p::prepared_identity(config);}
double norm(c::BodyVelocity v){return std::hypot(v.x,v.y,v.z);}
double norm(c::BodyRate v){return std::hypot(v.x,v.y,v.z);}
double clearance(const p::AnalyticSurface& surface,const c::AircraftSnapshot& state) {
  const auto query=surface.sample({state.header,state.position});return state.position.ellipsoid_height_m-std::get<c::ValidGround>(query.sample).surface_height_m;
}
struct Trial {
  std::string name;std::uint32_t hz{};std::shared_ptr<const p::AnalyticSurface> surface;
  std::vector<c::AircraftSnapshot> samples;std::vector<p::ContactDiagnostics> diagnostics;
  double peak_compression{},max_height_step{},max_acceleration{},minimum_clearance{100};std::size_t queries{};
};
Trial run(const std::filesystem::path& root,std::uint32_t hz,bool slope,std::string_view operation,double friction=.8) {
  p::SurfaceConfig config;if(slope){config.slope_north=.03;config.slope_east=.02;}
  config.static_friction=friction;config.dynamic_friction=friction*.75;
  auto surface=std::make_shared<p::AnalyticSurface>(config,identity(config));
  p::GroundInitial initial;initial.align_to_slope=slope;
  if(operation!="stationary")initial.forward_mps=5;
  if(operation=="touchdown"){initial.clearance_m=2;initial.forward_mps=3;initial.down_mps=2;}
  p::GroundExecutive executive(root,surface,hz,initial);
  Trial result;result.name=std::string(slope?"slope.":"flat.")+std::string(operation);result.hz=hz;result.surface=surface;result.samples.push_back(executive.latest());result.diagnostics.push_back(executive.diagnostics());
  double previous=clearance(*surface,executive.latest());
  for(std::uint32_t tick=1;tick<=8*hz;++tick) {
    p::GroundControls controls;
    if(operation=="stationary"||((operation=="brake"||operation=="touchdown")&&tick>hz/2))controls.left_brake=controls.right_brake=1;
    if(operation=="steer"&&tick>hz/2)controls.steering=.25;
    const auto status=executive.step(controls);check(status==p::StepStatus::completed,"Supported contact tick completes");
    if(status!=p::StepStatus::completed)throw std::runtime_error(result.name+" discarded/blocked at "+std::to_string(tick));
    const auto& state=executive.latest();const auto& diagnostic=executive.diagnostics();
    check(state.header.tick.value==tick&&state.clock.tick_rate_hz==hz&&c::valid(state),"Finite owned publication and exact fixed tick");
    const double height=clearance(*surface,state);result.max_height_step=std::max(result.max_height_step,std::abs(height-previous));previous=height;
    result.minimum_clearance=std::min(result.minimum_clearance,height);result.queries+=diagnostic.queries;
    result.max_acceleration=std::max(result.max_acceleration,std::hypot(state.acceleration_body_mps2.x,state.acceleration_body_mps2.y,state.acceleration_body_mps2.z));
    for(std::size_t i=0;i<3;++i) {
      result.peak_compression=std::max(result.peak_compression,diagnostic.compression_m[i]);
      check(diagnostic.static_friction[i]==config.static_friction&&diagnostic.dynamic_friction[i]==config.dynamic_friction,"Per-wheel surface friction reaches actual backend properties");
    }
    if(tick%(hz/2)==0){result.samples.push_back(state);result.diagnostics.push_back(diagnostic);}
  }
  const auto& final=result.samples.back();
  check(result.peak_compression>0&&result.peak_compression<.25,"Contact penetration within authored 25cm research budget");
  check(result.minimum_clearance>.65,"CG remains above authored plane without tunneling");
  check(result.max_height_step<.1,"No per-tick 10cm datum snap");
  check(std::count_if(final.contacts.begin(),final.contacts.end(),[](const auto& contact){return contact.on_ground;})==3,"Three stable final contacts");
  if(operation=="stationary") {
    check(norm(final.velocity_body_mps)<.005&&norm(final.angular_rate_body_radps)<.005,"Stationary equilibrium speed and rate");
    check(std::abs(clearance(*surface,final)-.97602)<.004,"Independent spring equilibrium clearance with rotating-gravity allowance");
    if(!slope)for(const auto& contact:final.contacts)check(std::abs(-contact.force_body_n.z-3597)<110,"Independent flat equal support load with declared gravity allowance");
  }
  if(operation=="brake"||operation=="touchdown")check(norm(final.velocity_body_mps)<.02,"Full brakes settle to stationary contact");
  if(operation=="coast")check(norm(final.velocity_body_mps)<5.1,"Original rolling model coasts without artificial propulsion");
  if(operation=="steer")check(std::abs(final.orientation_body_to_ned.z)>.02,"Nose steering produces a measured turn");
  return result;
}
class FaultSurface final:public p::AnalyticSurface {
 public:
  enum class Mode{known_miss,callback_miss,callback_throw,callback_identity};
  FaultSurface(Mode mode,c::MissingGround missing=c::MissingGround::not_loaded):AnalyticSurface({},::identity()),mode_(mode),missing_(missing){}
  c::GroundSample sample(const g::Query& query)const override {
    if(query.header.tick.value>0) {
      ++calls_;
      if(mode_==Mode::known_miss||(mode_!=Mode::known_miss&&calls_>4)) {
        if(mode_==Mode::callback_throw)throw std::runtime_error("Injected unexpected query exception");
        if(mode_==Mode::callback_identity){auto value=AnalyticSurface::sample(query);std::get<c::ValidGround>(value.sample).world.sha256=std::string(64,'c');return value;}
        return {query.header,query.position,missing_};
      }
    }
    return AnalyticSurface::sample(query);
  }
 private:Mode mode_;c::MissingGround missing_;mutable std::size_t calls_{};
};
class IdentityFailureSurface final:public p::AnalyticSurface {
 public:
  IdentityFailureSurface():AnalyticSurface({},::identity()){}
  void inject_failure(){armed_=true;}
  g::Identity identity()const override {if(armed_){throw std::runtime_error("Injected malformed provider identity");}return AnalyticSurface::identity();}
 private:bool armed_{};
};
void failures_and_tiles(const std::filesystem::path& root) {
  auto identity_fault=std::make_shared<IdentityFailureSurface>();p::GroundExecutive malformed(root,identity_fault,120,{});
  const auto malformed_before=p::snapshot_json(malformed.latest());identity_fault->inject_failure();
  check(malformed.step({.5,1,1})==p::StepStatus::discarded&&!malformed.live()&&p::snapshot_json(malformed.latest())==malformed_before,"Boundary-construction identity exception discards before mutation/publication");
  for(auto missing:{c::MissingGround::outside_coverage,c::MissingGround::not_loaded,c::MissingGround::datum_unresolved,c::MissingGround::invalid_data}) {
    auto provider=std::make_shared<FaultSurface>(FaultSurface::Mode::known_miss,missing);p::GroundExecutive executive(root,provider,120,{});
    const auto before=p::snapshot_json(executive.latest());check(executive.step({.5,1,1})==p::StepStatus::coverage_blocked,"Explicit known miss blocks before mutation");
    check(executive.live()&&p::snapshot_json(executive.latest())==before&&executive.held().steering==0&&executive.held().left_brake==0,"Known miss retains state, tick and unapplied controls");
  }
  for(auto mode:{FaultSurface::Mode::callback_miss,FaultSurface::Mode::callback_throw,FaultSurface::Mode::callback_identity}) {
    auto provider=std::make_shared<FaultSurface>(mode);p::GroundExecutive executive(root,provider,120,{});const auto before=p::snapshot_json(executive.latest());
    check(executive.step({.5,1,1})==p::StepStatus::discarded,"Unexpected callback failure discards executive");
    check(!executive.live()&&p::snapshot_json(executive.latest())==before&&executive.held().steering==0,"Failed Run publishes no partial state");
    check(executive.step({})==p::StepStatus::discarded,"Discarded executive cannot retry or resume");
  }
  for(auto hz:{60U,120U,240U}) {
    p::SurfaceConfig unloaded;unloaded.second_tile_loaded=false;unloaded.seam_north=10;
    auto missing=std::make_shared<p::AnalyticSurface>(unloaded,identity(unloaded));p::GroundExecutive blocked(root,missing,hz,{1.05,5,0,false});
    p::StepStatus status=p::StepStatus::completed;unsigned tick=0;while(status==p::StepStatus::completed&&tick<5*hz){status=blocked.step({.2,0,0});++tick;}
    check(status==p::StepStatus::coverage_blocked&&blocked.live(),"Missing tile stops before swept footprint reaches seam");
    const auto before=p::snapshot_json(blocked.latest());const auto controls=blocked.held();
    check(blocked.step({-.5,1,1})==p::StepStatus::coverage_blocked&&p::snapshot_json(blocked.latest())==before&&blocked.held().steering==controls.steering,"Blocked tile repeats preserve completed publication and held inputs");
    check(missing->coordinates(blocked.latest().ecef_position_m).x<7.5,"Missing tile never reached by aircraft gear radius");
    unloaded.second_tile_loaded=true;auto loaded=std::make_shared<p::AnalyticSurface>(unloaded,identity(unloaded));p::GroundExecutive crossing(root,loaded,hz,{1.05,5,0,false});
    auto uniform_config=unloaded;uniform_config.seam_north=100;auto uniform=std::make_shared<p::AnalyticSurface>(uniform_config,identity(uniform_config));p::GroundExecutive control(root,uniform,hz,{1.05,5,0,false});
    double prior=clearance(*loaded,crossing.latest()),jump=0;
    for(unsigned i=0;i<5*hz;++i){check(crossing.step({})==p::StepStatus::completed&&control.step({})==p::StepStatus::completed,"Congruent loaded tiles continue");const double height=clearance(*loaded,crossing.latest());
      const double north=loaded->coordinates(crossing.latest().ecef_position_m).x;
      if(north>9&&north<11){jump=std::max(jump,std::abs(height-prior));}
      prior=height;check(p::snapshot_json(crossing.latest())==p::snapshot_json(control.latest()),"Congruent loaded seam is byte-identical to uniform geometry");}
    check(loaded->coordinates(crossing.latest().ecef_position_m).x>10&&jump<.02,"Loaded tile seam crossed without height correction or contact jump");
  }
}
void geometry() {
  for(const auto& anchor:std::array<c::GeodeticPosition,5>{{{0,0,1000},{0,c::pi/2,1000},{c::pi/2,0,1000},{-c::pi/2,0,1000},{.8,-2,1000}}}) {
    p::SurfaceConfig config;config.anchor=anchor;auto surface=p::AnalyticSurface(config,identity(config));
    const auto sample=std::get<c::ValidGround>(surface.sample({{{0},"ground-proof"},anchor}).sample);
    check(std::abs(sample.surface_height_m-1000)<1e-7,"Independent equator/pole/project anchor ellipsoid height");
    check(std::abs(sample.normal_ned.x)<1e-14&&std::abs(sample.normal_ned.y)<1e-14&&std::abs(sample.normal_ned.z+1)<1e-14,"Query-local NED upward normal");
  }
  p::SurfaceConfig config;config.slope_north=.03;config.slope_east=.02;auto surface=p::AnalyticSurface(config,identity(config));
  const std::array<c::GeodeticPosition,3> positions{{{.80001,-2,0},{.79999,-2,0},{.8,-1.99999,0}}};
  const std::array<double,3> heights{1001.9111147011582,998.0895235692766,1000.8905722984948};
  for(std::size_t i=0;i<positions.size();++i){const auto sample=std::get<c::ValidGround>(surface.sample({{{0},"ground-proof"},positions[i]}).sample);check(std::abs(sample.surface_height_m-heights[i])<1e-7,"Pre-observation independent slope height");}
}
double quaternion_distance(c::QuaternionBodyToNed a,c::QuaternionBodyToNed b){return 2*std::acos(std::clamp(std::abs(a.w*b.w+a.x*b.x+a.y*b.y+a.z*b.z),0.,1.));}
void convergence(const Trial& a,const Trial& b) {
  check(a.samples.size()==b.samples.size(),"Aligned 2Hz convergence sampling");
  double position{},velocity{},attitude{},rate{};
  for(std::size_t i=0;i<a.samples.size();++i){const auto& x=a.samples[i];const auto& y=b.samples[i];
    position=std::max(position,std::hypot(x.ecef_position_m.x-y.ecef_position_m.x,x.ecef_position_m.y-y.ecef_position_m.y,x.ecef_position_m.z-y.ecef_position_m.z));
    velocity=std::max(velocity,std::hypot(x.velocity_body_mps.x-y.velocity_body_mps.x,x.velocity_body_mps.y-y.velocity_body_mps.y,x.velocity_body_mps.z-y.velocity_body_mps.z));
    attitude=std::max(attitude,quaternion_distance(x.orientation_body_to_ned,y.orientation_body_to_ned));
    rate=std::max(rate,std::hypot(x.angular_rate_body_radps.x-y.angular_rate_body_radps.x,x.angular_rate_body_radps.y-y.angular_rate_body_radps.y,x.angular_rate_body_radps.z-y.angular_rate_body_radps.z));}
  std::cout<<a.name<<" "<<a.hz<<"vs"<<b.hz<<" maxima(m,m/s,rad,rad/s): "<<position<<","<<velocity<<","<<attitude<<","<<rate<<'\n';
  // Contact is nonsmooth. These are declared numerical research limits, not aircraft tolerances.
  check(position<.15&&velocity<.15&&attitude<.02&&rate<.05,"60/120 versus240Hz bounded sampled contact convergence");
}
int main(int argc,char** argv) {
 try {
  if(argc<2||argc>3)throw std::invalid_argument("Ground fixture root and optional output JSON required");
  const auto root=std::filesystem::path(argv[1]);geometry();failures_and_tiles(root);
  p::GroundExecutive controls(root,std::make_shared<p::AnalyticSurface>(p::SurfaceConfig{},identity()),120,{});
  const auto controls_before=p::snapshot_json(controls.latest());
  rejects([&]{(void)controls.step({2,0,0});},"Out-of-range steering rejected before mutation");
  rejects([&]{(void)controls.step({0,-1,0});},"Out-of-range brake rejected before mutation");
  check(controls.live()&&p::snapshot_json(controls.latest())==controls_before,"Invalid commands retain full completed publication");
  std::vector<Trial> trials;
  for(bool slope:{false,true})for(const auto* operation:{"stationary","coast","steer","brake","touchdown"}) {
    const auto offset=trials.size();for(auto hz:{60U,120U,240U})trials.push_back(run(root,hz,slope,operation));
    convergence(trials[offset],trials[offset+2]);convergence(trials[offset+1],trials[offset+2]);
  }
  auto low=run(root,120,false,"brake",.2);const auto& normal=trials[9+1];
  const double low_distance=low.surface->coordinates(low.samples.back().ecef_position_m).x;
  const double normal_distance=normal.surface->coordinates(normal.samples.back().ecef_position_m).x;
  check(low_distance>normal_distance+1,"Lower material friction lengthens measured braking distance");
  const auto repeated=run(root,120,false,"touchdown");const auto& original=trials[12+1];
  for(std::size_t i=0;i<original.samples.size();++i)check(p::snapshot_json(original.samples[i])==p::snapshot_json(repeated.samples[i]),"Same-build contact trace repeats byte for byte");
  if(argc==3) {
    const auto runtime=p::runtime_info();
    std::ofstream output(std::filesystem::path(argv[2]),std::ios::binary);output<<std::setprecision(17)<<"{\"type\":\"GroundProofReceipt\",\"version\":1,\"fixture_sha256\":\""<<p::fixture_sha256<<"\",\"loaded_library_path\":"<<std::quoted(runtime.loaded_library_path)<<",\"library_version\":"<<std::quoted(runtime.version)<<",\"compiler\":"<<std::quoted(runtime.compiler)<<",\"checks\":"<<checks<<",\"failures\":"<<failures<<",\"trials\":[";
    for(std::size_t n=0;n<trials.size();++n){if(n)output<<',';const auto& trial=trials[n];output<<"{\"name\":\""<<trial.name<<"\",\"hz\":"<<trial.hz<<",\"surface_identity_sha256\":\""<<trial.surface->identity().prepared_surface_sha256<<"\",\"peak_compression_m\":"<<trial.peak_compression<<",\"max_height_step_m\":"<<trial.max_height_step<<",\"max_acceleration_mps2\":"<<trial.max_acceleration<<",\"minimum_clearance_m\":"<<trial.minimum_clearance<<",\"queries\":"<<trial.queries<<",\"samples\":[";
      for(std::size_t i=0;i<trial.samples.size();++i){if(i)output<<',';output<<p::snapshot_json(trial.samples[i]);}output<<"],\"diagnostics\":[";
      for(std::size_t i=0;i<trial.diagnostics.size();++i){if(i)output<<',';const auto& diagnostic=trial.diagnostics[i];output<<"{\"compression_m\":[";
        for(std::size_t gear=0;gear<3;++gear){if(gear){output<<',';}output<<diagnostic.compression_m[gear];}output<<"],\"compression_rate_mps\":[";
        for(std::size_t gear=0;gear<3;++gear){if(gear){output<<',';}output<<diagnostic.compression_rate_mps[gear];}output<<"]}";}
      output<<"]}";}
    output<<"]}\n";if(!output)throw std::runtime_error("Ground proof output write failed");
  }
  std::cout<<checks<<" ground checks; "<<failures<<" failures\n";return failures?1:0;
 }catch(const std::exception& error){std::cerr<<"Ground proof error: "<<error.what()<<'\n';return 2;}
}
