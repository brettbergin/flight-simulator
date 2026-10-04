#pragma once
#include <flight/interactive/surface.hpp>
#include <flight/fdm/session.hpp>
// ADR 006 bounded engineering prototype. Historical APIs/models stay unchanged.
namespace flight::interactive {
enum class Start { ground, airborne };
// ADR013 closed initialization-only choices; no numeric wind setter.
enum class SteadyWindProfile { calm, from_north, from_west, from_east };
enum class Status { completed, paused, coverage_blocked, discarded };
struct Config {
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
std::string command_json(const c::ControlCommand&);
std::string source_fingerprint();
}
