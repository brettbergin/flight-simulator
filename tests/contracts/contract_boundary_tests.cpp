#include <flight/contracts/boundaries.hpp>
#include <iostream>
#include <type_traits>

namespace c = flight::contracts::v1;
namespace g = c::geodesy;
namespace {
int checks = 0, failures = 0;
void check(bool condition, const char* label) {
  ++checks; if (!condition) { ++failures; std::cerr << "FAIL: " << label << '\n'; }
}
bool near(double actual, double expected, double tolerance = 1e-10) { return std::abs(actual - expected) <= tolerance; }
void types_and_units() {
  static_assert(!std::is_convertible_v<c::BodyVelocity, c::NedVelocity>);
  static_assert(!std::is_convertible_v<c::EcefPosition, c::RenderPosition>);
  static_assert(!std::is_convertible_v<c::BodyVelocity, c::BodyPosition>);
  static_assert(!std::is_convertible_v<c::Tick, c::Sequence>);
  static_assert(!std::is_convertible_v<c::QuaternionNedToBody, c::QuaternionBodyToNed>);
  check(near(c::units::feet_to_meters(1), 0.3048), "exact international foot");
  check(near(c::units::knots_to_mps(1), 0.5144444444444444), "knot is nautical mile/hour");
  check(near(c::units::celsius_to_kelvin(0), 273.15), "absolute Celsius offset");
  check(near(c::units::fahrenheit_to_kelvin(32), 273.15), "absolute Fahrenheit conversion");
  check(near(c::units::celsius_delta_to_kelvin_delta(1), 1), "temperature difference has no offset");
  check(near(c::units::pounds_mass_to_kg(1), 0.45359237), "pound mass differs from pound force");
  check(near(c::units::pounds_force_to_newtons(1), 4.4482216152605), "pound force conversion");
  for (const auto value : {0ULL, 9007199254740993ULL, 18446744073709551615ULL}) check(c::parse_uint64(c::wire_uint64(value)) == value, "uint64 decimal roundtrip");
  for (const auto text : {"", "01", "+1", "-1", "1.0", "1e3", "18446744073709551616", " 1"}) check(!c::parse_uint64(text), "reject invalid uint64");
  check(!c::next_tick({18446744073709551615ULL}), "tick overflow rejected");
}
void frames_and_geodesy() {
  struct Case { c::GeodeticPosition position; c::EcefPosition expected; };
  // Independently specified analytical fixture values, also in fixtures/geodesy.json.
  const Case cases[] = {{{0, 0, 0}, {6378137, 0, 0}}, {{0, c::pi / 2, 0}, {0, 6378137, 0}},
    {{c::pi / 2, 0, 0}, {0, 0, 6356752.314245179}}, {{-c::pi / 2, 0, 0}, {0, 0, -6356752.314245179}},
    {{0, c::pi, 1000}, {-6379137, 0, 0}}, {{c::pi / 4, c::pi / 4, 0}, {3194419.1450605746, 3194419.1450605746, 4487348.408865919}}};
  for (const auto& entry : cases) {
    const auto ecef = g::to_ecef(entry.position); check(ecef.has_value(), "geodetic accepted"); if (!ecef) continue;
    check(near(ecef->x, entry.expected.x, 1e-5) && near(ecef->y, entry.expected.y, 1e-5) && near(ecef->z, entry.expected.z, 1e-5), "independent ECEF coordinates");
    const auto inverse = g::from_ecef(entry.expected); check(inverse.has_value(), "ECEF inverse accepted"); if (!inverse) continue;
    check(near(inverse->latitude_rad, entry.position.latitude_rad, 1e-11) && near(inverse->ellipsoid_height_m, entry.position.ellipsoid_height_m, 1e-5), "inverse latitude/height");
    if (std::abs(entry.position.latitude_rad) < c::pi / 2) check(near(inverse->longitude_rad, entry.position.longitude_rad, 1e-11), "inverse longitude");
  }
  check(!g::to_ecef({45, 0, 0}), "degrees cannot enter radian latitude");
  check(!g::from_ecef({0, 0, 0}), "earth center is not a geodetic position");
  check(!g::from_ecef({std::numeric_limits<double>::infinity(), 0, 0}), "nonfinite ECEF rejected");
  const c::GeodeticPosition origin{0, 0, 0}; const c::EcefPosition anchor{6378137, 0, 0};
  const auto north = g::ecef_delta_to_ned({6378137, 0, 1}, anchor, origin);
  const auto east = g::ecef_delta_to_ned({6378137, 1, 0}, anchor, origin);
  const auto up = g::ecef_delta_to_ned({6378138, 0, 0}, anchor, origin);
  check(north && *north == c::NedDisplacement{1, 0, 0}, "ECEF Z is local north at equator");
  check(east && *east == c::NedDisplacement{0, 1, 0}, "ECEF Y is local east at equator");
  check(up && *up == c::NedDisplacement{0, 0, -1}, "ECEF outward is negative down");
  check(c::ned_to_render(c::NedDisplacement{1, 2, 3}) == c::RenderPosition{2, -3, -1}, "render east/up/south basis");
  const double half = std::sqrt(0.5);
  const auto yaw = c::body_to_ned(c::QuaternionNedToBody{half, 0, 0, -half});
  const auto forward = c::rotate_body_to_ned(yaw, c::BodyVelocity{1, 0, 0});
  check(near(forward.x, 0) && near(forward.y, 1) && near(forward.z, 0), "+90 true yaw sends forward east after conjugation");
  const auto render = c::ned_to_render(forward);
  check(near(render.x, 1) && near(render.y, 0) && near(render.z, 0), "east-facing forward renders +X");
  const auto pitch = c::rotate_body_to_ned(c::QuaternionBodyToNed{half, 0, half, 0}, c::BodyVelocity{1, 0, 0});
  check(near(pitch.z, -1), "positive pitch raises nose in NED");
  const auto roll = c::rotate_body_to_ned(c::QuaternionBodyToNed{half, half, 0, 0}, c::BodyVelocity{0, 1, 0});
  check(near(roll.z, 1), "positive roll lowers right wing");
  check(c::valid(yaw) && !c::valid(c::QuaternionBodyToNed{2, 0, 0, 0}), "unit quaternion enforced");
  const auto rotated = c::rotate_body_to_ned(yaw, c::BodyVelocity{2, 3, 4});
  check(near(c::magnitude(rotated), std::sqrt(29.0)), "rotation preserves velocity magnitude");
  const c::EcefPosition shifted{6378137, 1000, 0};
  const auto original_local = g::ecef_delta_to_ned({6378137, 1010, 0}, anchor, origin);
  const auto rebased_local = g::ecef_delta_to_ned({6378137, 1010, 0}, shifted, origin);
  check(original_local && rebased_local && near(original_local->y - rebased_local->y, 1000), "render anchor changes local translation only");
}
void clock_and_commands() {
  c::FixedClock clock; check(clock.integration_step_s() == 1.0 / 120, "fixed integration dt");
  for (int i = 0; i < 120; ++i) check(clock.advance(), "clock advances fixed tick");
  check(clock.completed_tick().value == 120 && near(clock.elapsed_s(), 1), "120 ticks is one second");
  clock.set_paused(true); check(!clock.advance() && clock.completed_tick().value == 120, "pause stops physics time");
  clock.set_paused(false); check(clock.advance() && clock.completed_tick().value == 121, "resume uses same dt");
  c::SessionControlGate lifecycle("session", "session.owner", clock);
  c::SessionControl pause{{clock.completed_tick(), "session"}, {1}, "session.owner", c::PauseControl{true}};
  check(lifecycle.apply(pause) == c::SessionControlRejection::none && !clock.advance(), "pause applied on lifecycle lane");
  pause.sequence = {2}; pause.payload = c::PauseControl{false};
  check(lifecycle.apply(pause) == c::SessionControlRejection::none && clock.advance(), "paused lifecycle lane can resume");
  pause.sequence = {3}; pause.header.tick = clock.completed_tick(); pause.payload = c::TimeScaleControl{4};
  check(lifecycle.apply(pause) == c::SessionControlRejection::none && lifecycle.time_scale() == 4 && clock.integration_step_s() == 1.0 / 120, "time scale never changes integration dt");
  check(lifecycle.apply(pause) == c::SessionControlRejection::duplicate, "lifecycle rejects duplicate sequence");
  pause.sequence = {4}; pause.payload = c::TimeScaleControl{std::numeric_limits<double>::quiet_NaN()};
  check(lifecycle.apply(pause) == c::SessionControlRejection::invalid, "lifecycle rejects nonfinite time scale");
  pause.payload = c::PauseControl{false}; pause.header.tick = {0};
  check(lifecycle.apply(pause) == c::SessionControlRejection::wrong_boundary, "lifecycle boundary explicit while paused");
  for (const std::uint32_t hz : {60U, 120U, 240U}) { c::FixedClock convergence({hz, c::ClockPurpose::convergence}); check(convergence.advance() && near(convergence.elapsed_s(), 1.0 / hz), "explicit convergence rates"); }
  bool threw = false; try { c::FixedClock invalid({60, c::ClockPurpose::runtime}); } catch (const std::invalid_argument&) { threw = true; }
  check(threw, "runtime rejects convergence-only rate");
  check(near(c::pitch_to_elevator_trailing_edge_down(0.5), -0.5), "nose-up request maps to elevator trailing-edge up");
  c::CommandGate gate("session"); check(gate.register_source("pilot.a", c::Authority::pilot), "register trusted input source");
  check(!gate.register_source("pilot.a", c::Authority::instructor), "source authority cannot be overwritten");
  check(gate.register_control({"electrical.master", c::ControlCapability::ValueType::boolean, 0, 1}), "declare aircraft capability");
  c::ControlCommand command{{{2}, "session"}, {1}, "pilot.a", c::Authority::pilot, {"unassisted", {}}, c::PilotAxes{0, 0.5, 0, 0, 1, 0, 0, 0}};
  check(gate.accept(command, {2}) == c::CommandRejection::none, "valid command accepted");
  check(gate.accept(command, {2}) == c::CommandRejection::duplicate, "duplicate sequence rejected");
  command.sequence = {2}; std::get<c::PilotAxes>(command.payload).pitch = 2;
  check(gate.accept(command, {2}) == c::CommandRejection::invalid, "out of range axes rejected");
  std::get<c::PilotAxes>(command.payload).pitch = 0.5;
  check(gate.accept(command, {2}) == c::CommandRejection::none, "rejected command does not consume sequence");
  command.sequence = {3}; check(gate.accept(command, {3}) == c::CommandRejection::late, "late command never shifted silently");
  command.authority = c::Authority::instructor; check(gate.accept(command, {2}) == c::CommandRejection::unauthorized_source, "source cannot self-elevate authority");
  command.authority = c::Authority::pilot; command.payload = c::SystemControl{"unknown.control", true};
  check(gate.accept(command, {2}) == c::CommandRejection::unsupported_control, "unknown property write rejected");
  command.payload = c::SystemControl{"electrical.master", 1.0}; check(gate.accept(command, {2}) == c::CommandRejection::invalid, "boolean capability rejects scalar");
  command.payload = c::SystemControl{"electrical.master", true}; check(gate.accept(command, {2}) == c::CommandRejection::none, "typed capability accepted");
  auto other = command; other.header.session_id = "other"; check(gate.accept(other, {2}) == c::CommandRejection::wrong_session, "cross-session input rejected");
  other = command; other.authority = c::Authority::instructor; check(c::command_before(command, other), "higher authority applied last within tick");
  other = command; other.source_id = "pilot.b"; other.sequence = {0}; check(c::command_before(command, other), "stable source ID resolves equal-priority ties");
}
void state_boundaries() {
  c::AircraftSnapshot state; state.header.session_id = "session"; state.position = {0, 0, 0}; state.ecef_position_m = {6378137, 0, 0}; state.mass_kg = 1000;
  check(c::valid(state), "valid SI initial aircraft snapshot");
  state.ecef_position_m.x /= 0.3048; check(!c::valid(state), "ECEF feet mistaken for meters rejected"); state.ecef_position_m.x = 6378137;
  state.velocity_body_mps.x = std::numeric_limits<double>::quiet_NaN(); check(!c::valid(state), "NaN cannot escape snapshot boundary"); state.velocity_body_mps.x = 0;
  state.header.tick = {120}; check(!c::valid(state), "elapsed time cannot drift from tick"); state.elapsed_s = 1; check(c::valid(state), "tick derived elapsed time");
  c::GroundSample ground{{{0}, "session"}, {0, 0, 0}, c::ValidGround{0, {0, 0, -1}, 0.8, 0.6, "asphalt", {"world", "0.1.0", "hash"}}};
  check(c::valid(ground), "valid upward contact normal"); std::get<c::ValidGround>(ground.sample).normal_ned = {0, 0, 0}; check(!c::valid(ground), "zero contact normal rejected");
  ground.sample = c::MissingGround::not_loaded; check(c::valid(ground) && !std::holds_alternative<c::ValidGround>(ground.sample), "missing terrain never fabricates surface");
  c::InstrumentSnapshot instruments{{{10}, "session"}, {{"airspeed", {9}, c::Quantity::meters_per_second, c::SystemValue{10.0}, 0.1, "none", c::InstrumentStatus::normal}}};
  check(c::valid(instruments), "instrument carries lagged sensed value");
  instruments.channels[0].sensor_tick = {11}; check(!c::valid(instruments), "instrument rejects future sample"); instruments.channels[0].sensor_tick = {9};
  instruments.channels[0].status = c::InstrumentStatus::off; check(!c::valid(instruments), "powered-off instrument cannot expose truth"); instruments.channels[0].value.reset();
  check(c::valid(instruments), "powered-off channel has no value");
  auto second_channel = instruments.channels[0]; second_channel.status = c::InstrumentStatus::normal; second_channel.value = 20.0;
  instruments.channels.push_back(second_channel); check(!c::valid(instruments), "conflicting duplicate instrument ID rejected");
  instruments.channels.back().id = "altimeter"; check(c::valid(instruments), "distinct instrument IDs accepted");
  state.systems = {{"engine.rotation", c::Quantity::radians_per_second, 0.0, c::Validity::valid}, {"engine.rotation", c::Quantity::radians_per_second, 20.0, c::Validity::valid}};
  check(!c::valid(state), "conflicting duplicate system ID rejected"); state.systems.back().id = "propeller.rotation";
  check(c::valid(state), "distinct system IDs accepted");
  state.contacts = {{"left-main", {0, 0, 0}, {0, 0, 0}, true}, {"left-main", {0, 0, 0}, {0, 0, 0}, false}};
  check(!c::valid(state), "conflicting duplicate contact ID rejected"); state.contacts.back().id = "right-main";
  check(c::valid(state), "distinct contact IDs accepted");
  c::AtmosphereSample air{{{0}, "session"}, {0, 0, 0}, 101325, 288.15, 1.225, 0, {0, 0, 0}, {0, 0, 0}, {0}, "still-air"};
  check(c::valid(air), "SI atmosphere sample"); air.temperature_k = 0; check(!c::valid(air), "atmosphere rejects zero kelvin");
  c::TrainingResult result; result.session_id = "session";
  check(c::valid(result), "empty incomplete training result allowed"); result.status = c::TrainingResult::Status::complete;
  check(!c::valid(result), "complete result needs objective evidence");
  result.observations = {{"objective", c::Observation::Result::met, {1}, {2}, {{1}}, "observed"}};
  check(c::valid(result), "complete result with observed objective accepted");
  result.observations.push_back(result.observations.front()); result.observations.back().result = c::Observation::Result::not_met;
  check(!c::valid(result), "conflicting duplicate objective ID rejected"); result.observations.back().objective_id = "second-objective";
  check(c::valid(result), "unique observed objective IDs accepted");
  c::WorldPackage world; c::Source source; source.id = "original-fixture"; world.pack.sources.push_back(source);
  check(c::source_references_resolved(world), "world without magnetic model resolves sources");
  world.magnetic_model = c::MagneticModel{"synthetic-magnetic", 2025, "missing-source"};
  check(!c::source_references_resolved(world), "magnetic model cannot cite unknown source");
  world.magnetic_model->source_id = "original-fixture";
  check(c::source_references_resolved(world), "magnetic model source resolves declared provenance");
}
}
int main() {
  types_and_units(); frames_and_geodesy(); clock_and_commands(); state_boundaries();
  std::cout << checks << " contract checks, " << failures << " failures\n";
  return failures == 0 ? 0 : 1;
}
