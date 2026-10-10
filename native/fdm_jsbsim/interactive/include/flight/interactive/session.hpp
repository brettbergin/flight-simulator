#pragma once
#include <flight/interactive/surface.hpp>
#include <flight/fdm/session.hpp>
#include <optional>
#include <string>
// ADR 006 bounded engineering prototype. Historical APIs/models stay unchanged.
namespace flight::interactive {
enum class Profile { legacy, piston };
enum class Start { ground, airborne, piston_cold_ground };
// ADR013 closed initialization-only choices; no numeric wind setter.
enum class SteadyWindProfile { calm, from_north, from_west, from_east };
// First-party selector maps once to the checked vendor method before RunIC.
enum class AngularMethod { legacy_euler, event_aware_constant_power_v1, event_aware_coupled_midpoint_v1 };
enum class Status { completed, paused, coverage_blocked, discarded };
struct Config {
  Profile profile{Profile::legacy};
  // Absent selects the profile's defined default; explicit legacy is research.
  std::optional<AngularMethod> angular_method;
  std::filesystem::path model_root;
  std::shared_ptr<const AnalyticSurface> surface;
  std::string session_id{"interactive-probe"};
  Start start{Start::ground};
  SteadyWindProfile wind_profile{SteadyWindProfile::calm};
  std::uint32_t hz{120}; // production120;60/240 research only
  c::ClockPurpose purpose{c::ClockPurpose::runtime};
  c::Seed seed{42};
  double requested_height_m{1.05},forward_mps{},down_mps{},pitch_rad{};
  bool trim{};
};
struct Step {Status status{};std::vector<c::ControlCommand> applied;};
struct SessionTestAccess;
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
  std::optional<std::string> angular_integration_method()const;
  PistonDiagnostics piston_diagnostics()const;
  std::string fault()const;
  bool paused()const;
  double time_scale()const;
  std::vector<c::OperationalEvent> events()const;
  bool live()const;
  void close();
 private:friend struct SessionTestAccess;class Impl;std::unique_ptr<Impl> impl_;
};
// Observation-only friend seam for the source-bound native proof driver. It has
// no solver/property setters and is not a Godot/runtime wire interface.
struct SteadyWindObservation {
  std::string stage;
  c::BodyVelocity ground_body_mps,air_body_mps;
  c::BodyRate aero_rate_radps;
  c::NedVelocity base_wind_mps,total_wind_mps;
  c::QuaternionBodyToNed orientation;
  c::BodyForce aero_force_n;
  std::array<double,3> aero_moment_nm; // body FRD, N*m
  double alpha_rad{},beta_rad{},speed_mps{},qbar_pa{},density_kgpm3{};
  c::PilotAxes applied_controls;
};
struct SessionTestAccess {
  static std::array<SteadyWindObservation,2> initialization(const Session&);
  static SteadyWindObservation current(const Session&);
};
std::string snapshot_json(const c::AircraftSnapshot&);
bool piston_system_id(std::string_view);
std::string command_json(const c::ControlCommand&,Profile=Profile::legacy);
std::string source_fingerprint();
}
