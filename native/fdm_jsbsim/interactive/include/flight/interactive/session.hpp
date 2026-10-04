#pragma once
#include <flight/interactive/surface.hpp>
#include <flight/fdm/session.hpp>
// ADR 006 bounded engineering prototype. Historical APIs/models stay unchanged.
namespace flight::interactive {
enum class Profile { legacy, piston };
enum class Start { ground, airborne, piston_cold_ground };
enum class Status { completed, paused, coverage_blocked, discarded };
struct Config {
  Profile profile{Profile::legacy};
  std::filesystem::path model_root;
  std::shared_ptr<const AnalyticSurface> surface;
  std::string session_id{"interactive-probe"};
  Start start{Start::ground};
  std::uint32_t hz{120}; // production120;60/240 research only
  c::ClockPurpose purpose{c::ClockPurpose::runtime};
  c::Seed seed{42};
  double requested_height_m{1.05},forward_mps{},down_mps{},pitch_rad{};
  bool trim{};
};
struct Step {Status status{};std::vector<c::ControlCommand> applied;};
// Native-only completed-stage engineering trace. No wire keys or mutation API.
struct PistonDiagnostics {
  c::SampleHeader header;
  double pre_prop_engine_rpm{},post_prop_rpm{},fuel_flow_lb_per_s{},fuel_used_lb{};
  double manifold_pressure_inhg{},engine_input_pressure_psf{},engine_input_density_slug_per_ft3{};
  double raw_engine_power_ftlb_per_s{},tank_contents_lb{},mass_slug{};
};
class Session final {
 public:
  // Every method and destruction belongs to the construction thread. Readbacks
  // are owned copies; bridge obtains them inside the synchronous worker call.
  explicit Session(Config);
  ~Session();
  Session(const Session&)=delete;Session& operator=(const Session&)=delete;
  bool register_host_source(std::string,c::Authority); // trusted native host only
  c::CommandRejection submit(c::ControlCommand);
  c::SessionControlRejection apply(const c::SessionControl&);
  Step step_fixed();
  c::AircraftSnapshot latest()const;
  c::AtmosphereSample atmosphere()const;
  c::PilotAxes held()const;
  Profile profile()const;
  PistonDiagnostics piston_diagnostics()const;
  std::string fault()const;
  bool paused()const;
  double time_scale()const;
  std::vector<c::OperationalEvent> events()const;
  bool live()const;
  void close();
 private:class Impl;std::unique_ptr<Impl> impl_;
};
std::string snapshot_json(const c::AircraftSnapshot&);
bool piston_system_id(std::string_view);
std::string command_json(const c::ControlCommand&,Profile=Profile::legacy);
std::string source_fingerprint();
}
