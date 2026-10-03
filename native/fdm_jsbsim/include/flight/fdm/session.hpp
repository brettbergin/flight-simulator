#pragma once
#include <flight/contracts/boundaries.hpp>
#include <chrono>
#include <filesystem>
#include <memory>

namespace flight::fdm {
namespace c = contracts::v1;
// All public structures own their data; no JSBSim/Godot objects cross this seam.
struct TrimOptions {
  bool longitudinal{true};
  int max_cycles{60}, max_cycles_per_axis{100};
  double acceleration_tolerance_mps2{0.0003048};
};
struct SessionConfig {
  std::filesystem::path model_root;
  std::string session_id{"synthetic-session"}, lifecycle_source{"session.owner"};
  c::ClockConfig clock;
  c::Seed seed;
  c::InitialConditions initial_conditions;
  TrimOptions trim;
  std::size_t command_capacity{4096};
  std::uint64_t future_horizon_ticks{72000};
  std::size_t history_capacity{65536}; // Finite P1 history; runtime streaming is a later recorder seam.
};
struct DiagnosticSample {
  c::SampleHeader header;
  double alpha_rad{}, beta_rad{}, dynamic_pressure_pa{}, airspeed_mps{};
  c::BodyRate air_relative_rate_radps;
  c::BodyForce aerodynamic_force_body_n;
  std::array<double, 3> aerodynamic_moment_cg_body_nm{};
  std::array<double, 3> drag_side_lift_n{};
  double fuel_kg{}, jsbsim_aileron{}, jsbsim_elevator{}, jsbsim_rudder{}, jsbsim_pitch_trim{}, throttle{};
};
struct Initialization {
  std::string loaded_library_path, library_version, compiler, source_fingerprint;
  c::InitialConditions requested, accepted;
  c::PilotAxes solved_controls;
  c::Seed requested_seed;
  std::uint32_t engine_seed{};
  TrimOptions trim;
  double initial_fuel_kg{};
  bool fuel_frozen_during_trim{true};
  double initialization_step_s{1.0 / 120};
};
struct SubmitReceipt {
  c::CommandRejection rejection{c::CommandRejection::none};
  bool queued{}; // Not an applied/accepted physics-log record.
};
struct AdmittedCommand { c::Tick received_after_tick; c::ControlCommand command; };
struct StepResult {
  bool stepped{};
  c::AircraftSnapshot aircraft;
  c::AtmosphereSample atmosphere;
  std::vector<c::ControlCommand> applied_commands;
};
struct AdvanceResult { std::uint32_t steps{}; bool overrun{}, paused{}; std::uint64_t owed_ticks{}; };
class Session final {
 public:
  explicit Session(SessionConfig config);
  ~Session();
  Session(const Session&) = delete;
  Session& operator=(const Session&) = delete;
  Session(Session&&) noexcept;
  Session& operator=(Session&&) noexcept;
  // Caller owns thread and lifetime. No background work survives close/destruction.
  [[nodiscard]] bool register_host_source(std::string id, c::Authority authority);
  [[nodiscard]] SubmitReceipt submit(c::ControlCommand command);
  [[nodiscard]] c::SessionControlRejection apply(const c::SessionControl& control);
  [[nodiscard]] StepResult step_fixed();
  // Integer rational budget; at most 32 steps per pump, never a larger solver dt.
  // Overrun pauses with debt retained. Resume, then pump zero wall time to drain debt.
  [[nodiscard]] AdvanceResult advance_wall_budget(std::chrono::nanoseconds elapsed);
  [[nodiscard]] c::AircraftSnapshot latest_snapshot() const;
  [[nodiscard]] c::AtmosphereSample latest_atmosphere() const;
  [[nodiscard]] DiagnosticSample diagnostics() const;
  [[nodiscard]] const Initialization& initialization() const;
  [[nodiscard]] std::vector<c::ControlCommand> applied_command_log() const;
  // Original successful submission order, including pending commands; distinct from execution order.
  [[nodiscard]] std::vector<AdmittedCommand> admitted_command_history() const;
  [[nodiscard]] std::vector<c::OperationalEvent> event_log() const;
  // Caller tracks delivered sequence; scheduler pumps never silently consume events.
  [[nodiscard]] std::vector<c::OperationalEvent> events_after(c::Sequence last_delivered, std::size_t max_count=128) const;
  [[nodiscard]] std::vector<c::SessionControl> accepted_session_controls() const;
  void close() noexcept;
 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};
// Pure frame/unit adapters, independently testable with nonzero asymmetric values.
[[nodiscard]] c::BodyPosition structural_cg_inches_to_body_datum_m(double x_aft, double y_right, double z_up) noexcept;
[[nodiscard]] c::BodyAcceleration earth_acceleration_body_mps2(c::BodyAcceleration component_derivative_mps2,
                                                              c::BodyRate earth_relative_rate_radps,
                                                              c::BodyVelocity earth_relative_velocity_mps) noexcept;
[[nodiscard]] c::QuaternionBodyToNed body_to_ned_from_matrix(const std::array<double, 9>& row_major);
} // namespace flight::fdm
