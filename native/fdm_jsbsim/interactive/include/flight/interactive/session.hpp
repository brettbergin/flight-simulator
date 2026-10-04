#pragma once
#include <flight/interactive/surface.hpp>
#include <flight/fdm/session.hpp>
// ADR 006 bounded engineering prototype. Historical APIs/models stay unchanged.
namespace flight::interactive {
enum class Start { ground, airborne };
enum class Status { completed, paused, coverage_blocked, discarded };
struct Config {
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
 private:class Impl;std::unique_ptr<Impl> impl_;
};
std::string snapshot_json(const c::AircraftSnapshot&);
std::string command_json(const c::ControlCommand&);
std::string source_fingerprint();
}
