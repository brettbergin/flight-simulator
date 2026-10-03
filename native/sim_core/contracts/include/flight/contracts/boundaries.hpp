#pragma once
#include "geodesy.hpp"
#include <algorithm>
#include <tuple>
#include <variant>

namespace flight::contracts::v1 {
enum class Authority : std::uint8_t { pilot = 0, avionics = 1, scenario = 2, instructor = 3 };
struct PilotAxes {
  // Positive requests: right bank, nose up, nose right. Sample-and-hold until replaced.
  double roll{}, pitch{}, yaw{}, throttle{}, mixture{}, left_brake{}, right_brake{}, trim{};
};
inline bool valid(PilotAxes a) noexcept {
  const auto bipolar = [](double v) { return std::isfinite(v) && v >= -1 && v <= 1; };
  const auto unipolar = [](double v) { return std::isfinite(v) && v >= 0 && v <= 1; };
  return bipolar(a.roll) && bipolar(a.pitch) && bipolar(a.yaw) && bipolar(a.trim) &&
    unipolar(a.throttle) && unipolar(a.mixture) && unipolar(a.left_brake) && unipolar(a.right_brake);
}
// Adapter seam, not an aircraft response model. Applies only to a mapping whose
// positive elevator command is trailing-edge down; other mappings must be explicit.
inline constexpr double pitch_to_elevator_trailing_edge_down(double pilot_pitch) noexcept { return -pilot_pitch; }
using SystemValue = std::variant<bool, double>;
struct SystemControl { std::string control_id; SystemValue value; };
struct ControlCommand {
  SampleHeader header; Sequence sequence; std::string source_id; Authority authority{Authority::pilot};
  Assistance assistance; std::variant<PilotAxes, SystemControl> payload;
};
inline bool command_before(const ControlCommand& a, const ControlCommand& b) noexcept {
  return std::tie(a.header.tick, a.authority, a.source_id, a.sequence) < std::tie(b.header.tick, b.authority, b.source_id, b.sequence);
}
enum class CommandRejection { none, wrong_session, late, duplicate, invalid, unauthorized_source, unsupported_control, capacity };
inline bool stable_id(std::string_view id) noexcept {
  if (id.empty() || id.size() > 128 || id.front() < 'a' || id.front() > 'z') return false;
  bool separator = false;
  for (const char c : id) {
    const bool alnum = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9');
    if (!alnum && c != '.' && c != '_' && c != '-') return false;
    if (!alnum && separator) return false;
    separator = !alnum;
  }
  return !separator;
}
struct ControlCapability { std::string id; enum class ValueType { boolean, normalized } value_type{}; double minimum{}, maximum{}; };
class CommandGate {
 public:
  explicit CommandGate(std::string session) : session_(std::move(session)) {}
  [[nodiscard]] bool register_source(std::string id, Authority authority) {
    if (!stable_id(id) || sources_.size() >= 256 || std::any_of(sources_.begin(), sources_.end(), [&](const auto& s) { return s.id == id; })) return false;
    sources_.push_back({std::move(id), authority, std::nullopt}); return true;
  }
  [[nodiscard]] bool register_control(ControlCapability control) {
    if (!stable_id(control.id) || controls_.size() >= 256 || !std::isfinite(control.minimum) || !std::isfinite(control.maximum) ||
        control.minimum < -1 || control.maximum > 1 || control.minimum > control.maximum ||
        std::any_of(controls_.begin(), controls_.end(), [&](const auto& c) { return c.id == control.id; })) return false;
    controls_.push_back(std::move(control)); return true;
  }
  [[nodiscard]] CommandRejection accept(const ControlCommand& command, Tick next_unexecuted) {
    if (command.header.session_id != session_) return CommandRejection::wrong_session;
    if (command.header.tick < next_unexecuted) return CommandRejection::late;
    const auto source = std::find_if(sources_.begin(), sources_.end(), [&](const auto& s) { return s.id == command.source_id; });
    if (source == sources_.end() || source->authority != command.authority) return CommandRejection::unauthorized_source;
    if (source->last && command.sequence <= *source->last) return CommandRejection::duplicate;
    if (const auto* axes = std::get_if<PilotAxes>(&command.payload)) {
      if (!valid(*axes)) return CommandRejection::invalid;
    } else {
      const auto& control = std::get<SystemControl>(command.payload);
      const auto capability = std::find_if(controls_.begin(), controls_.end(), [&](const auto& c) { return c.id == control.control_id; });
      if (capability == controls_.end()) return CommandRejection::unsupported_control;
      if (capability->value_type == ControlCapability::ValueType::boolean) {
        if (!std::holds_alternative<bool>(control.value)) return CommandRejection::invalid;
      } else {
        const auto* value = std::get_if<double>(&control.value);
        if (!value || !std::isfinite(*value) || *value < capability->minimum || *value > capability->maximum) return CommandRejection::invalid;
      }
    }
    source->last = command.sequence; return CommandRejection::none;
  }
 private:
  struct SourceState { std::string id; Authority authority; std::optional<Sequence> last; };
  std::string session_; std::vector<SourceState> sources_; std::vector<ControlCapability> controls_;
};
struct PauseControl { bool paused{}; };
struct TimeScaleControl { double scale{1}; };
struct SessionControl { SampleHeader header; Sequence sequence; std::string source_id; std::variant<PauseControl, TimeScaleControl> payload; };
enum class SessionControlRejection { none, wrong_session, wrong_boundary, unauthorized_source, duplicate, invalid };
class SessionControlGate {
 public:
  SessionControlGate(std::string session, std::string owner_source, FixedClock& clock)
      : session_(std::move(session)), owner_source_(std::move(owner_source)), clock_(clock) {}
  // This lane is pumped at the completed boundary even while simulation is paused.
  [[nodiscard]] SessionControlRejection apply(const SessionControl& control) noexcept {
    if (control.header.session_id != session_) return SessionControlRejection::wrong_session;
    if (control.header.tick != clock_.completed_tick()) return SessionControlRejection::wrong_boundary;
    if (control.source_id != owner_source_) return SessionControlRejection::unauthorized_source;
    if (last_ && control.sequence <= *last_) return SessionControlRejection::duplicate;
    if (const auto* pause = std::get_if<PauseControl>(&control.payload)) clock_.set_paused(pause->paused);
    else {
      const double scale = std::get<TimeScaleControl>(control.payload).scale;
      if (scale != 0.25 && scale != 0.5 && scale != 1 && scale != 2 && scale != 4) return SessionControlRejection::invalid;
      time_scale_ = scale; // Scheduler scales wall-time budget; FixedClock's dt is immutable.
    }
    last_ = control.sequence; return SessionControlRejection::none;
  }
  [[nodiscard]] double time_scale() const noexcept { return time_scale_; }
 private:
  std::string session_, owner_source_; FixedClock& clock_; std::optional<Sequence> last_; double time_scale_{1};
};
enum class Validity { valid, invalid, initializing, unavailable };
enum class Quantity { meters, meters_per_second, radians, radians_per_second, kelvin, pascals, kilograms, amperes, volts, fraction, boolean };
struct SystemState { std::string id; Quantity quantity{}; SystemValue value; Validity validity{Validity::valid}; };
struct Contact { std::string id; BodyPosition point_body_m; BodyForce force_body_n; bool on_ground{}; };
struct Configuration { double flap_fraction{}, gear_fraction{1}, trim_fraction{}; };
struct AircraftSnapshot {
  SampleHeader header; ClockConfig clock; double elapsed_s{}; GeodeticPosition position; EcefPosition ecef_position_m;
  QuaternionBodyToNed orientation_body_to_ned; BodyVelocity velocity_body_mps; BodyRate angular_rate_body_radps;
  BodyAcceleration acceleration_body_mps2; double mass_kg{}; BodyPosition center_of_gravity_body_m;
  Configuration configuration; std::vector<SystemState> systems; std::vector<Contact> contacts; Validity validity{Validity::initializing};
};
inline bool valid(const AircraftSnapshot& s) noexcept {
  const auto fraction = [](double v) { return std::isfinite(v) && v >= 0 && v <= 1; };
  if (!stable_id(s.header.session_id) || !valid(s.clock) || !valid(s.position) || !finite(s.ecef_position_m) || !valid(s.orientation_body_to_ned) ||
      !finite(s.velocity_body_mps) || !finite(s.angular_rate_body_radps) || !finite(s.acceleration_body_mps2) || !finite(s.center_of_gravity_body_m) ||
      !std::isfinite(s.mass_kg) || s.mass_kg < 0.001 || s.mass_kg > 1000000 || !std::isfinite(s.elapsed_s) ||
      !fraction(s.configuration.flap_fraction) || !fraction(s.configuration.gear_fraction) || !std::isfinite(s.configuration.trim_fraction) ||
      std::abs(s.configuration.trim_fraction) > 1 || s.systems.size() > 256 || s.contacts.size() > 32) return false;
  const auto time = static_cast<double>(s.header.tick.value) / s.clock.tick_rate_hz;
  if (std::abs(time - s.elapsed_s) > std::max(1e-9, time * std::numeric_limits<double>::epsilon() * 4)) return false;
  const auto expected_ecef = geodesy::to_ecef(s.position);
  if (!expected_ecef || std::hypot(s.ecef_position_m.x - expected_ecef->x, s.ecef_position_m.y - expected_ecef->y,
      s.ecef_position_m.z - expected_ecef->z) > 0.0001) return false;
  for (const auto& contact : s.contacts) if (!stable_id(contact.id) || !finite(contact.point_body_m) || !finite(contact.force_body_n)) return false;
  for (const auto& system : s.systems) {
    if (!stable_id(system.id) || (system.quantity == Quantity::boolean) != std::holds_alternative<bool>(system.value)) return false;
    if (const auto* value = std::get_if<double>(&system.value)) {
      if (!std::isfinite(*value) || (system.quantity == Quantity::kelvin && *value <= 0) ||
          (system.quantity == Quantity::fraction && (*value < 0 || *value > 1))) return false;
    }
  }
  return true;
}
enum class InstrumentStatus { normal, failed, unreliable, off, unavailable };
struct InstrumentChannel {
  std::string id; Tick sensor_tick; Quantity quantity{}; std::optional<SystemValue> value;
  double latency_s{}; std::string filter_id; InstrumentStatus status{InstrumentStatus::unavailable};
};
struct InstrumentSnapshot { SampleHeader header; std::vector<InstrumentChannel> channels; };
inline bool valid(const InstrumentSnapshot& s) noexcept {
  if (!stable_id(s.header.session_id) || s.channels.size() > 256) return false;
  for (const auto& channel : s.channels) {
    if (!stable_id(channel.id) || !stable_id(channel.filter_id) || channel.sensor_tick > s.header.tick ||
        !std::isfinite(channel.latency_s) || channel.latency_s < 0 || channel.latency_s > 60) return false;
    if (channel.status == InstrumentStatus::normal && !channel.value) return false;
    if ((channel.status == InstrumentStatus::off || channel.status == InstrumentStatus::unavailable) && channel.value) return false;
    if (channel.value) {
      if ((channel.quantity == Quantity::boolean) != std::holds_alternative<bool>(*channel.value)) return false;
      if (const auto* value = std::get_if<double>(&*channel.value)) {
        if (!std::isfinite(*value) || (channel.quantity == Quantity::kelvin && *value <= 0) ||
            (channel.quantity == Quantity::fraction && (*value < 0 || *value > 1))) return false;
      }
    }
  }
  return true;
}
struct AtmosphereSample {
  SampleHeader header; GeodeticPosition position; double pressure_pa{}, temperature_k{}, density_kgpm3{}, relative_humidity{};
  NedVelocity wind_toward_ned_mps, turbulence_ned_mps; Seed seed; std::string model_id;
};
inline bool valid(const AtmosphereSample& s) noexcept {
  return stable_id(s.header.session_id) && valid(s.position) && stable_id(s.model_id) && finite(s.wind_toward_ned_mps) && finite(s.turbulence_ned_mps) &&
    std::isfinite(s.pressure_pa) && s.pressure_pa >= 1 && s.pressure_pa <= 200000 &&
    std::isfinite(s.temperature_k) && s.temperature_k >= 1 && s.temperature_k <= 400 &&
    std::isfinite(s.density_kgpm3) && s.density_kgpm3 >= 0.000001 && s.density_kgpm3 <= 10 &&
    std::isfinite(s.relative_humidity) && s.relative_humidity >= 0 && s.relative_humidity <= 1;
}
struct ValidGround {
  double surface_height_m{}; NedNormal normal_ned; double static_friction{}, dynamic_friction{};
  std::string material_id; ContentRef world;
};
enum class MissingGround { outside_coverage, not_loaded, datum_unresolved, invalid_data };
struct GroundSample { SampleHeader header; GeodeticPosition position; std::variant<ValidGround, MissingGround> sample; };
inline bool valid(const GroundSample& s) noexcept {
  if (!valid(s.position) || !stable_id(s.header.session_id)) return false;
  const auto* ground = std::get_if<ValidGround>(&s.sample);
  return !ground || (std::isfinite(ground->surface_height_m) && ground->surface_height_m >= -2000 && ground->surface_height_m <= 100000 &&
    finite(ground->normal_ned) && std::abs(magnitude(ground->normal_ned) - 1) <= unit_tolerance &&
    std::isfinite(ground->static_friction) && std::isfinite(ground->dynamic_friction) && ground->static_friction >= 0 && ground->static_friction <= 5 &&
    ground->dynamic_friction >= 0 && ground->dynamic_friction <= ground->static_friction && stable_id(ground->material_id));
}
struct RejectedCommandEvent { Sequence command_sequence; CommandRejection reason{}; };
struct SystemStateEvent { std::string system_id, state; };
struct FailureEvent { std::string failure_id; bool active{}; };
struct ProcedureEvent { std::string procedure_id, step_id; enum class Result { observed, omitted, incorrect } result{}; };
struct ClearanceEvent { std::string clearance_id, aircraft_id; bool acknowledged{}; };
struct AssistanceEvent { std::string assistance_id; bool active{}; };
struct SessionBranchEvent { std::string parent_session_id; Tick parent_tick; };
struct SaveEvent { std::string checkpoint_id; bool saved{}; };
struct OperationalEvent {
  SampleHeader header; Sequence sequence; std::string source_id;
  enum class Confidence { observed, derived, unknown } confidence{Confidence::unknown}; std::string content_version;
  std::variant<RejectedCommandEvent, SystemStateEvent, FailureEvent, ProcedureEvent, ClearanceEvent, AssistanceEvent, PauseControl, TimeScaleControl, SessionBranchEvent, SaveEvent> payload;
};
enum class RestoreCapability { unsupported, replay_from_start, safe_restart, complete_checkpoint };
struct InitialConditions { AircraftSnapshot aircraft; AtmosphereSample atmosphere; };
struct BuildRef { std::string id, git_commit, fingerprint; };
struct SessionManifest {
  std::string session_id; BuildRef build; std::string contract_set_sha256; ContentRef aircraft, world, scenario;
  Seed seed; ClockConfig clock; ContentRef calibration; Assistance assistance; InitialConditions initial_conditions;
  FileRef command_log, event_log; RestoreCapability restore_capability{RestoreCapability::unsupported};
  std::optional<std::string> restore_evidence_id; std::string created_utc;
};
struct ReplayHeader {
  ContentRef session; std::string build_fingerprint, contract_set_sha256; ClockConfig clock; Seed seed;
  std::uint64_t record_count{}; std::string command_log_sha256; enum class Determinism { same_build_tolerances, unproven } determinism{Determinism::unproven};
};
struct Checkpoint {
  SampleHeader header; std::string id, session_manifest_sha256, build_fingerprint; RestoreCapability restore_capability{RestoreCapability::replay_from_start};
  std::string restore_evidence_id; std::vector<FileRef> blobs; std::optional<Tick> replay_until_tick;
};
struct Observation {
  std::string objective_id; enum class Result { met, not_met, not_observed } result{Result::not_observed};
  Tick start_tick, end_tick; std::vector<Sequence> evidence_event_sequences; std::string explanation_id;
};
struct TrainingResult {
  std::string session_id; ContentRef lesson, rubric; enum class Status { complete, incomplete, invalid } status{Status::incomplete};
  enum class Repeatability { same_build, unverified } repeatability{Repeatability::unverified};
  Assistance assistance; std::vector<Observation> observations; std::vector<std::string> invalid_reasons;
};
struct PackManifest { std::string id, version; Evidence evidence; std::vector<Source> sources; std::vector<FileRef> files; };
struct AircraftIdentity { std::string manufacturer, family, variant, configuration_id, serial_applicability, engine, propeller, panel; std::optional<std::string> poh_source_id; };
struct DynamicsDefinition {
  enum class Backend { jsbsim, fixture } backend{Backend::fixture}; std::string model_path;
  enum class Provenance { original_synthetic, licensed_source } provenance{Provenance::original_synthetic}; std::vector<std::string> parameter_source_ids;
};
struct AircraftManifest {
  PackManifest pack; AircraftIdentity identity; DynamicsDefinition dynamics; std::vector<std::string> capabilities; std::vector<ControlCapability> controls;
  struct MassEnvelope { double minimum{}, maximum{}; } mass_envelope_kg;
  struct CgEnvelope { BodyPosition minimum, maximum; } cg_envelope_body_m;
  struct Geometry { double wingspan_m{}, length_m{}, height_m{}; } geometry;
  std::vector<std::string> checklist_ids, limit_source_ids; std::string mapping_path;
};
struct MagneticModel { std::string id; double epoch_year{}; std::string source_id; };
struct WorldPackage {
  PackManifest pack; struct Coverage { double south_rad{}, north_rad{}, west_rad{}, east_rad{}; bool crosses_antimeridian{}; } coverage;
  enum class VerticalDatum { wgs84_ellipsoid, egm96, egm2008, navd88 } vertical_datum{VerticalDatum::wgs84_ellipsoid};
  std::optional<ContentRef> geoid; std::optional<MagneticModel> magnetic_model; std::string effective_from, effective_until;
  enum class DataStatus { synthetic, historical, current_source } data_status{DataStatus::synthetic};
  enum class Product { terrain, airport, navaid, vector, imagery }; std::vector<Product> products;
  enum class UpdatePolicy { fixed_scenario, explicit_owner_update } update_policy{UpdatePolicy::fixed_scenario};
};
struct ScheduledAction { Tick tick; std::string action_id, target_id; };
struct ScenarioManifest {
  PackManifest pack; std::string jurisdiction; std::vector<std::string> prerequisites; ContentRef required_aircraft, required_world;
  Seed seed; ClockConfig clock; InitialConditions initial_conditions; std::vector<std::string> objectives; ContentRef rubric;
  std::vector<std::string> allowed_assists; std::vector<ScheduledAction> scheduled_actions; std::vector<Tick> safe_restart_ticks;
  std::vector<std::string> evidence_event_kinds, source_edition_ids;
};
} // namespace flight::contracts::v1
