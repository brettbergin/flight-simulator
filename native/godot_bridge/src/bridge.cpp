#include "codec.hpp"
#include "worker.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <memory>
#ifdef _WIN32
#include <windows.h>
#endif
namespace flight::bridge {
namespace {
godot::String string(const std::string& value) { return godot::String::utf8(value.c_str()); }
godot::Dictionary error(const std::exception& exception) {
  godot::Dictionary result; result["ok"]=false; result["error"]=string(exception.what()); return result;
}
godot::Dictionary runtime_modules(const std::filesystem::path& payload_root) {
  godot::Dictionary modules;
#ifdef _WIN32
  for(const auto* name:{L"MSVCP140.dll",L"MSVCP140_2.dll",L"MSVCP140_ATOMIC_WAIT.dll",L"VCRUNTIME140.dll",L"VCRUNTIME140_1.dll"}) {
    const auto module=GetModuleHandleW(name);
    if(!module) throw std::runtime_error("Required runtime module not loaded");
    std::wstring path(32768,L'\0');
    const auto length=GetModuleFileNameW(module,path.data(),static_cast<DWORD>(path.size()));
    if(length==0||length>=path.size()) throw std::runtime_error("Runtime module path unavailable");
    path.resize(length);
    const std::filesystem::path actual(path);
    const auto inside=[&](const std::filesystem::path& candidate) {
      return std::filesystem::exists(candidate)&&std::filesystem::equivalent(actual,candidate);
    };
    if(!inside(payload_root/name)&&!inside(payload_root/"bin"/name))
      throw std::runtime_error("Required release runtime loaded outside proof payload");
    const auto utf8=std::filesystem::path(path).u8string();
    modules[godot::String(name)]=string(std::string(utf8.begin(),utf8.end()));
  }
#else
  (void)payload_root;
#endif
  return modules;
}
godot::Dictionary encode(const Response& response,const std::filesystem::path& payload_root={}) {
  godot::Dictionary result; result["ok"]=true; result["schema_version"]=1;
  result["aircraft_json"]=string(response.aircraft); result["atmosphere_json"]=string(response.atmosphere);
  result["initialization_json"]=string(response.initialization);
  if(!response.initialization.empty()) result["runtime_modules"]=runtime_modules(payload_root);
  result["stepped"]=response.stepped; result["queued"]=response.queued; result["rejection"]=response.rejection;
  godot::Array commands,events;
  for(const auto& command:response.commands) commands.push_back(string(command));
  for(const auto& event:response.events) events.push_back(string(event));
  result["applied_commands_json"]=commands; result["events_json"]=events; return result;
}
}
class FlightProofSession final : public godot::RefCounted {
  GDCLASS(FlightProofSession,godot::RefCounted)
  std::unique_ptr<Worker> worker_;
  fdm::c::Sequence delivered_{};
 protected:
  static void _bind_methods() {
    godot::ClassDB::bind_method(godot::D_METHOD("open_session","model_root","initializer"),&FlightProofSession::open_session);
    godot::ClassDB::bind_method(godot::D_METHOD("submit","command"),&FlightProofSession::submit);
    godot::ClassDB::bind_method(godot::D_METHOD("session_control","control"),&FlightProofSession::session_control);
    godot::ClassDB::bind_method(godot::D_METHOD("step_fixed","count"),&FlightProofSession::step_fixed);
    godot::ClassDB::bind_method(godot::D_METHOD("close"),&FlightProofSession::close);
  }
 public:
  ~FlightProofSession() override { worker_.reset(); godot::UtilityFunctions::print("FLIGHT_BRIDGE_DESTRUCTOR_JOINED"); }
  godot::Dictionary open_session(godot::String model_root,godot::PackedByteArray initializer) {
    if(worker_) return error(std::invalid_argument("Session already initialized; close before reopening"));
    try {
      if(initializer.size()>4*1024*1024) throw std::invalid_argument("Initializer exceeds bound");
      const auto root_utf8=model_root.utf8();
      const auto root_path=std::filesystem::path(std::u8string(reinterpret_cast<const char8_t*>(root_utf8.get_data()),static_cast<std::size_t>(root_utf8.length())));
      auto request=fdm::transport::decode(std::span(initializer.ptr(),static_cast<std::size_t>(initializer.size())),
        root_path);
      if(!request.commands.empty()||request.config.clock.purpose!=fdm::c::ClockPurpose::runtime) throw std::invalid_argument("Proof initializer requires empty commands and runtime clock");
      worker_=std::make_unique<Worker>(std::move(request.config)); delivered_={};
      auto response=worker_->call([](fdm::Session& session) {
        auto out=sample(session); out.initialization=fdm::transport::json(session.initialization()); return out;
      });
      return encode(response,root_path.parent_path());
    } catch(const std::exception& exception) { worker_.reset(); return error(exception); }
  }
  godot::Dictionary submit(godot::Dictionary command) {
    try {
      if(!worker_) throw std::runtime_error("Session closed");
      auto decoded=decode_command(command);
      return encode(worker_->call([decoded=std::move(decoded)](fdm::Session& session) mutable {
        const auto receipt=session.submit(std::move(decoded)); auto out=sample(session);
        out.queued=receipt.queued; out.rejection=static_cast<int>(receipt.rejection); return out;
      }));
    } catch(const std::exception& exception) { return error(exception); }
  }
  godot::Dictionary session_control(godot::Dictionary control) {
    try {
      if(!worker_) throw std::runtime_error("Session closed");
      auto decoded=decode_session_control(control);
      return encode(worker_->call([decoded=std::move(decoded)](fdm::Session& session) {
        const auto rejection=session.apply(decoded); auto out=sample(session); out.rejection=static_cast<int>(rejection); return out;
      }));
    } catch(const std::exception& exception) { return error(exception); }
  }
  godot::Dictionary step_fixed(int64_t count) {
    try {
      if(!worker_) throw std::runtime_error("Session closed");
      if(count<1||count>32) throw std::invalid_argument("Fixed-step batch must be 1..32");
      const auto cursor=delivered_;
      auto out=worker_->call([count,cursor](fdm::Session& session) {
        Response response;
        for(int64_t i=0;i<count;++i) {
          auto step=session.step_fixed(); response.stepped=step.stepped;
          for(const auto& command:step.applied_commands) response.commands.push_back(fdm::transport::json(command));
          if(!step.stepped) break;
        }
        auto latest=sample(session); response.aircraft=std::move(latest.aircraft); response.atmosphere=std::move(latest.atmosphere);
        for(const auto& event:session.events_after(cursor,1024)) { response.events.push_back(fdm::transport::json(event)); response.delivered_sequence=event.sequence.value; }
        return response;
      });
      auto encoded=encode(out);
      if(out.delivered_sequence) delivered_={out.delivered_sequence};
      return encoded;
    } catch(const std::exception& exception) { return error(exception); }
  }
  godot::Dictionary close() {
    worker_.reset(); delivered_={};
    godot::Dictionary result; result["ok"]=true; result["joined"]=true;
    godot::UtilityFunctions::print("FLIGHT_BRIDGE_JOINED"); return result;
  }
};
void initialize(godot::ModuleInitializationLevel level) {
  if(level!=godot::MODULE_INITIALIZATION_LEVEL_SCENE) return;
  godot::ClassDB::register_class<FlightProofSession>();
  godot::UtilityFunctions::print("FLIGHT_BRIDGE_INITIALIZED");
}
void terminate(godot::ModuleInitializationLevel level) {
  if(level!=godot::MODULE_INITIALIZATION_LEVEL_SCENE) return;
  Worker::close_all();
  godot::UtilityFunctions::print("FLIGHT_BRIDGE_TERMINATED_JOINED");
}
}
extern "C" GDExtensionBool GDE_EXPORT flight_bridge_init(GDExtensionInterfaceGetProcAddress api,
  GDExtensionClassLibraryPtr library,GDExtensionInitialization* initialization) {
  godot::GDExtensionBinding::InitObject object(api,library,initialization);
  object.register_initializer(flight::bridge::initialize); object.register_terminator(flight::bridge::terminate);
  object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
  return object.init();
}
