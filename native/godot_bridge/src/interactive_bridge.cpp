#include "interactive_worker.hpp"
#include "codec.hpp"
#include <flight/fdm/protocol.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <chrono>
#include <atomic>
#include <cmath>
#include <thread>
#ifdef _WIN32
#include <windows.h>
#endif
namespace flight::bridge {
namespace {
godot::String gs(const std::string& x){return godot::String::utf8(x.c_str());}
godot::Dictionary failure(const std::exception& x){godot::Dictionary d;d["ok"]=false;d["error"]=gs(x.what());return d;}
godot::Dictionary axes(interactive::c::PilotAxes a){godot::Dictionary d;d["kind"]="axes";d["roll"]=a.roll;d["pitch"]=a.pitch;d["yaw"]=a.yaw;d["throttle"]=a.throttle;d["mixture"]=a.mixture;d["left_brake"]=a.left_brake;d["right_brake"]=a.right_brake;d["trim"]=a.trim;return d;}
const char* outcome(interactive::Status status){switch(status){case interactive::Status::completed:return "completed";case interactive::Status::paused:return "paused";case interactive::Status::coverage_blocked:return "coverage_blocked";case interactive::Status::discarded:return "discarded";}throw std::runtime_error("Unknown interactive outcome");}
godot::Dictionary encode(const InteractiveReply& x){
  godot::Dictionary d;d["ok"]=true;d["schema_version"]=1;d["aircraft_json"]=gs(x.aircraft);d["atmosphere_json"]=gs(x.atmosphere);d["held_axes"]=axes(x.held);
  d["outcome"]=outcome(x.status);d["completed"]=x.completed;d["live"]=x.live;d["historical"]=!x.live;d["paused"]=x.paused;d["time_scale"]=x.time_scale;d["fault"]=gs(x.fault);d["queued"]=x.queued;d["rejection"]=x.rejection;
  d["ground_query_valid"]=x.ground_valid;d["surface_height_m"]=x.surface_height_m;d["plane_clearance_m"]=x.clearance_m;
  godot::Array commands,events;for(const auto& value:x.commands)commands.push_back(gs(value));for(const auto& value:x.events)events.push_back(gs(value));d["applied_commands_json"]=commands;d["events_json"]=events;return d;
}
godot::Dictionary modules(const std::filesystem::path& payload){
 godot::Dictionary d;
#ifdef _WIN32
 for(const auto* name:{L"flight_godot_bridge.dll",L"JSBSim.dll",L"MSVCP140.dll",L"MSVCP140_2.dll",L"MSVCP140_ATOMIC_WAIT.dll",L"VCRUNTIME140.dll",L"VCRUNTIME140_1.dll"}){
  const auto module=GetModuleHandleW(name);if(!module)throw std::runtime_error("Required interactive module not loaded");
  std::wstring path(32768,L'\0');const auto size=GetModuleFileNameW(module,path.data(),static_cast<DWORD>(path.size()));if(size==0||size>=path.size())throw std::runtime_error("Interactive module path unavailable");path.resize(size);
  const std::filesystem::path actual(path);const auto inside=[&](const auto& candidate){return std::filesystem::exists(candidate)&&std::filesystem::equivalent(actual,candidate);};
  if(!inside(payload/name)&&!inside(payload/"bin"/name))throw std::runtime_error("Interactive runtime loaded outside payload");
  const auto utf8=actual.u8string();d[godot::String(name)]=gs(std::string(utf8.begin(),utf8.end()));
 }
#else
 (void)payload;
#endif
 return d;
}
}
class FlightInteractiveSession final:public godot::RefCounted {
 GDCLASS(FlightInteractiveSession,godot::RefCounted)
 std::unique_ptr<InteractiveWorker> worker_;
 std::shared_ptr<const interactive::AnalyticSurface> surface_;
 std::uint64_t delivered_{};
 const std::thread::id owner_{std::this_thread::get_id()};
 void check_thread()const{if(owner_!=std::this_thread::get_id())throw std::logic_error("Interactive bridge requires its construction thread");}
 protected:
 static void _bind_methods(){
  godot::ClassDB::bind_method(godot::D_METHOD("open_session","model_root","named_start","wind_profile"),&FlightInteractiveSession::open_session,DEFVAL(godot::String("calm")));
  godot::ClassDB::bind_method(godot::D_METHOD("submit","command"),&FlightInteractiveSession::submit);
  godot::ClassDB::bind_method(godot::D_METHOD("session_control","control"),&FlightInteractiveSession::session_control);
  godot::ClassDB::bind_method(godot::D_METHOD("step_fixed","count"),&FlightInteractiveSession::step_fixed);
  godot::ClassDB::bind_method(godot::D_METHOD("read_state"),&FlightInteractiveSession::read_state);
  godot::ClassDB::bind_method(godot::D_METHOD("close"),&FlightInteractiveSession::close);
 }
 public:
 ~FlightInteractiveSession() override {worker_.reset();godot::UtilityFunctions::print("INTERACTIVE_DESTRUCTOR_JOINED");}
 godot::Dictionary open_session(godot::String root,godot::String start,godot::Variant profile){
  if(owner_!=std::this_thread::get_id())return failure(std::logic_error("Interactive open requires its construction thread"));
  if(profile.get_type()!=godot::Variant::STRING)return failure(std::invalid_argument("Wind profile requires an exact String"));
  const godot::String wind=profile;
  interactive::SteadyWindProfile selected;
  if(wind=="calm")selected=interactive::SteadyWindProfile::calm;
  else if(wind=="from-north")selected=interactive::SteadyWindProfile::from_north;
  else if(wind=="from-west")selected=interactive::SteadyWindProfile::from_west;
  else if(wind=="from-east")selected=interactive::SteadyWindProfile::from_east;
  else return failure(std::invalid_argument("Unknown steady-wind profile"));
  if(worker_)return failure(std::invalid_argument("Close before a fresh interactive attempt"));
  try {
   interactive::Config config;config.wind_profile=selected;const auto utf8=root.utf8();config.model_root=std::filesystem::path(std::u8string(reinterpret_cast<const char8_t*>(utf8.get_data()),static_cast<std::size_t>(utf8.length())));
   if(start=="ground-ready")config.start=interactive::Start::ground;
   else if(start=="airborne-prepared"){config.start=interactive::Start::airborne;config.requested_height_m=1000;config.forward_mps=55*std::cos(.02);config.down_mps=55*std::sin(.02);config.pitch_rad=.02;config.trim=true;}
   else throw std::invalid_argument("Only ground-ready and airborne-prepared starts are supported");
   static std::atomic<std::uint64_t> epoch{0};const auto sequence=++epoch;if(sequence==0)throw std::overflow_error("Interactive epoch exhausted");
   const auto stamp=std::chrono::steady_clock::now().time_since_epoch().count();
   config.session_id="interactive-"+std::to_string(godot::OS::get_singleton()->get_process_id())+"-"+std::to_string(stamp)+"-"+std::to_string(sequence);
   interactive::SurfaceConfig plane;surface_=std::make_shared<const interactive::AnalyticSurface>(plane,interactive::prepared_identity(plane));config.surface=surface_;config.hz=120;config.seed={42};
   const auto model_root=config.model_root;worker_=std::make_unique<InteractiveWorker>(std::move(config));delivered_=0;
   auto d=encode(worker_->call([surface=surface_](auto& session){return interactive_sample(session,*surface);}));
   d["runtime_modules"]=modules(model_root.parent_path());d["named_start"]=start;d["wind_profile"]=wind;d["native_source_fingerprint"]=gs(interactive::source_fingerprint());
   godot::Dictionary anchor;anchor["latitude_rad"]=plane.anchor.latitude_rad;anchor["longitude_rad"]=plane.anchor.longitude_rad;anchor["ellipsoid_height_m"]=plane.anchor.ellipsoid_height_m;d["world_anchor"]=anchor;d["prepared_world_sha256"]=gs(surface_->identity().prepared_surface_sha256);return d;
  }catch(const std::exception& error){worker_.reset();surface_.reset();return failure(error);}
 }
 godot::Dictionary read_state(){try{check_thread();if(!worker_)throw std::runtime_error("Interactive session closed");return encode(worker_->call([surface=surface_](auto& s){return interactive_sample(s,*surface);}));}catch(const std::exception& error){return failure(error);}}
 godot::Dictionary submit(godot::Dictionary value){try{
  check_thread();
  if(!worker_) {throw std::runtime_error("Interactive session closed");}
  auto command=decode_command(value);
  return encode(worker_->call([command=std::move(command),surface=surface_](auto& s)mutable{const auto reject=s.submit(std::move(command));auto r=interactive_sample(s,*surface);r.rejection=static_cast<int>(reject);r.queued=reject==interactive::c::CommandRejection::none;return r;}));
 }catch(const std::exception& error){return failure(error);}}
 godot::Dictionary session_control(godot::Dictionary value){try{
  check_thread();
  if(!worker_) {throw std::runtime_error("Interactive session closed");}
  const auto control=decode_session_control(value);
  return encode(worker_->call([control,surface=surface_](auto& s){const auto reject=s.apply(control);auto r=interactive_sample(s,*surface);r.rejection=static_cast<int>(reject);return r;}));
 }catch(const std::exception& error){return failure(error);}}
 godot::Dictionary step_fixed(int64_t count){try{
  check_thread();
  if(!worker_) {throw std::runtime_error("Interactive session closed");}
  if(count<1||count>32) {throw std::invalid_argument("Interactive batch must be1..32");}
  const auto cursor=delivered_;
  auto r=worker_->call([count,cursor,surface=surface_](auto& s){InteractiveReply out;interactive::Status status=interactive::Status::completed;int completed=0;
   for(int64_t i=0;i<count;++i){auto step=s.step_fixed();status=step.status;if(status!=interactive::Status::completed)break;++completed;for(const auto& cmd:step.applied)out.commands.push_back(interactive::command_json(cmd));}
   auto current=interactive_sample(s,*surface);current.completed=completed;current.status=status;current.commands=std::move(out.commands);
   for(const auto& event:s.events())if(event.sequence.value>cursor){current.events.push_back(fdm::transport::json(event));current.event_sequence=event.sequence.value;}
   return current;});
  auto d=encode(r);if(r.event_sequence)delivered_=r.event_sequence;return d;
 }catch(const std::exception& error){return failure(error);}}
 godot::Dictionary close(){if(owner_!=std::this_thread::get_id())return failure(std::logic_error("Interactive close requires its construction thread"));worker_.reset();surface_.reset();delivered_=0;godot::Dictionary d;d["ok"]=true;d["joined"]=true;godot::UtilityFunctions::print("INTERACTIVE_WORKER_JOINED");return d;}
};
void register_interactive_bridge(){godot::ClassDB::register_class<FlightInteractiveSession>();godot::UtilityFunctions::print("INTERACTIVE_BRIDGE_INITIALIZED");}
void close_interactive_bridges() noexcept {InteractiveWorker::close_all();}
}
