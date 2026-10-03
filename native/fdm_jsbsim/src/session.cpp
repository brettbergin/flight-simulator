#include <flight/fdm/session.hpp>
#include <flight/fdm/model.hpp>
#include <FGFDMExec.h>
#include <initialization/FGInitialCondition.h>
#include <initialization/FGTrim.h>
#include <models/FGAccelerations.h>
#include <models/FGAtmosphere.h>
#include <models/FGAerodynamics.h>
#include <models/FGAuxiliary.h>
#include <models/FGMassBalance.h>
#include <models/FGPropagate.h>
#include <models/FGPropulsion.h>
#include <models/atmosphere/FGWinds.h>
#include <models/propulsion/FGTank.h>
#include <algorithm>
#include <stdexcept>
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>
#else
#include <dlfcn.h>
#endif

namespace flight::fdm {
namespace {
constexpr double slug_to_kg = 4.4482216152605 / 0.3048;
constexpr double psf_to_pa = 4.4482216152605 / (0.3048 * 0.3048);
constexpr std::uint64_t units_per_tick = 4000000000ULL;
struct LibrarySymbol : JSBSim::FGJSBBase { using FGJSBBase::CreateIndexedPropertyName; };
std::string loaded_library_path() {
  // Resolve exported code, not inline GetVersion static data (ELF copy relocation risk).
  const void* address=reinterpret_cast<const void*>(&LibrarySymbol::CreateIndexedPropertyName);
#ifdef _WIN32
  HMODULE module=nullptr;
  if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,reinterpret_cast<LPCWSTR>(address),&module))
    throw std::runtime_error("Cannot identify loaded JSBSim DLL");
  std::vector<wchar_t> path(32768); const auto size=GetModuleFileNameW(module,path.data(),static_cast<DWORD>(path.size()));
  if(size==0||size>=path.size()) throw std::runtime_error("Cannot resolve loaded JSBSim DLL path");
  const auto utf8=std::filesystem::path(std::wstring(path.data(),size)).u8string(); return std::string(utf8.begin(),utf8.end());
#else
  Dl_info info{};
  if(!dladdr(address,&info)||!info.dli_fname) throw std::runtime_error("Cannot identify loaded JSBSim shared object");
  return std::filesystem::canonical(info.dli_fname).string();
#endif
}
bool supported_axes(const c::PilotAxes& a) {
  return c::valid(a) && a.mixture == 1 && a.left_brake == 0 && a.right_brake == 0;
}
std::array<double, 3> euler(c::QuaternionBodyToNed q) {
  return {std::atan2(2 * (q.w * q.x + q.y * q.z), 1 - 2 * (q.x * q.x + q.y * q.y)),
          std::asin(std::clamp(2 * (q.w * q.y - q.z * q.x), -1.0, 1.0)),
          std::atan2(2 * (q.w * q.z + q.x * q.y), 1 - 2 * (q.y * q.y + q.z * q.z))};
}
} // namespace
c::BodyPosition structural_cg_inches_to_body_datum_m(double x, double y, double z) noexcept {
  return {-x * .0254, y * .0254, -z * .0254};
}
c::BodyAcceleration earth_acceleration_body_mps2(c::BodyAcceleration d, c::BodyRate r, c::BodyVelocity v) noexcept {
  return {d.x + r.y * v.z - r.z * v.y, d.y + r.z * v.x - r.x * v.z, d.z + r.x * v.y - r.y * v.x};
}
c::QuaternionBodyToNed body_to_ned_from_matrix(const std::array<double, 9>& m) {
  for (double value : m) if (!std::isfinite(value)) throw std::invalid_argument("Nonfinite orientation matrix");
  for (std::size_t i = 0; i < 3; ++i) for (std::size_t j = 0; j < 3; ++j) {
    double dot = 0; for (std::size_t k = 0; k < 3; ++k) dot += m[3 * k + i] * m[3 * k + j];
    if (std::abs(dot - (i == j ? 1 : 0)) > 1e-9) throw std::invalid_argument("Nonorthogonal orientation matrix");
  }
  const double determinant = m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6]);
  if (std::abs(determinant - 1) > 1e-9) throw std::invalid_argument("Improper orientation matrix");
  c::QuaternionBodyToNed q; const double trace = m[0] + m[4] + m[8];
  if (trace > 0) {
    const double s = 2 * std::sqrt(trace + 1); q = {s / 4, (m[7] - m[5]) / s, (m[2] - m[6]) / s, (m[3] - m[1]) / s};
  } else if (m[0] > m[4] && m[0] > m[8]) {
    const double s = 2 * std::sqrt(1 + m[0] - m[4] - m[8]); q = {(m[7] - m[5]) / s, s / 4, (m[1] + m[3]) / s, (m[2] + m[6]) / s};
  } else if (m[4] > m[8]) {
    const double s = 2 * std::sqrt(1 + m[4] - m[0] - m[8]); q = {(m[2] - m[6]) / s, (m[1] + m[3]) / s, s / 4, (m[5] + m[7]) / s};
  } else {
    const double s = 2 * std::sqrt(1 + m[8] - m[0] - m[4]); q = {(m[3] - m[1]) / s, (m[2] + m[6]) / s, (m[5] + m[7]) / s, s / 4};
  }
  const double norm=std::hypot(std::hypot(q.w,q.x),std::hypot(q.y,q.z));
  if(!std::isfinite(norm)||std::abs(norm-1)>1e-9) throw std::invalid_argument("Invalid orientation quaternion");
  // The checked proper matrix may accumulate roundoff. Normalize its derived rotation
  // so each component obeys the strict wire[-1,1] bounds even near identity.
  q={q.w/norm,q.x/norm,q.y/norm,q.z/norm};
  if (!c::valid(q)) throw std::invalid_argument("Invalid normalized orientation quaternion");
  if (q.w < 0) q = {-q.w, -q.x, -q.y, -q.z};
  return q;
}
class Session::Impl {
 public:
  explicit Impl(SessionConfig configuration)
      : config(std::move(configuration)), clock(config.clock), commands(config.session_id), lifecycle(config.session_id, config.lifecycle_source, clock) {
    const auto& a = config.initial_conditions.aircraft; const auto& w = config.initial_conditions.atmosphere;
    if (!c::stable_id(config.session_id) || !c::stable_id(config.lifecycle_source) || !c::valid(a) || !c::valid(w) ||
        a.header.session_id != config.session_id || w.header.session_id != config.session_id || a.header.tick.value || w.header.tick.value ||
        a.clock.tick_rate_hz != config.clock.tick_rate_hz || a.clock.purpose != config.clock.purpose ||
        a.validity != c::Validity::initializing || !a.systems.empty() || !a.contacts.empty() || c::magnitude(a.acceleration_body_mps2) != 0 ||
        std::abs(a.mass_kg - 1100) > .0001 || c::magnitude(a.center_of_gravity_body_m) != 0 ||
        c::magnitude(a.velocity_body_mps) < 20 || c::magnitude(a.velocity_body_mps) > 200 || c::magnitude(a.angular_rate_body_radps) > 2 ||
        a.position.ellipsoid_height_m < 100 || a.position.ellipsoid_height_m > 10000 || c::magnitude(w.wind_toward_ned_mps) > 100 ||
        a.configuration.flap_fraction != 0 || a.configuration.gear_fraction != 1 ||
        w.seed != config.seed || w.model_id != "jsbsim-dry-isa" || w.relative_humidity != 0 || c::magnitude(w.turbulence_ned_mps) != 0 ||
        std::abs(w.position.latitude_rad - a.position.latitude_rad) > 1e-9 || std::abs(w.position.longitude_rad - a.position.longitude_rad) > 1e-9 ||
        std::abs(w.position.ellipsoid_height_m - a.position.ellipsoid_height_m) > 1e-9 ||
        config.command_capacity == 0 || config.command_capacity > 4096 || config.future_horizon_ticks == 0 || config.future_horizon_ticks > 144000 ||
        config.history_capacity == 0 || config.history_capacity > 65536 ||
        config.trim.max_cycles < 1 || config.trim.max_cycles > 1000 || config.trim.max_cycles_per_axis < 1 || config.trim.max_cycles_per_axis > 1000 ||
        !std::isfinite(config.trim.acceleration_tolerance_mps2) || config.trim.acceleration_tolerance_mps2 < 0.0000003048 || config.trim.acceleration_tolerance_mps2 > .003048)
      throw std::invalid_argument("Unsupported or invalid synthetic initial conditions/configuration");
    verify_original_model(config.model_root);
    fdm = std::make_unique<JSBSim::FGFDMExec>(); fdm->SetDebugLevel(0);
    initialization.loaded_library_path=loaded_library_path(); initialization.library_version=JSBSim::FGJSBBase::GetVersion();
    initialization.compiler=FLIGHT_FDM_COMPILER; initialization.source_fingerprint=FLIGHT_FDM_SOURCE_FINGERPRINT;
    initialization.requested = config.initial_conditions; initialization.requested_seed = config.seed;
    initialization.engine_seed = static_cast<std::uint32_t>((config.seed.value ^ (config.seed.value >> 31) ^ (config.seed.value >> 62)) & 0x7fffffffULL);
    // SRand is private in pinned 1.3.1; its documented tied property is the public seam.
    fdm->SetPropertyValue("simulation/randomseed", static_cast<double>(initialization.engine_seed));
    if(fdm->GetPropertyValue("simulation/randomseed") != static_cast<double>(initialization.engine_seed)) throw std::runtime_error("Seed application failed");
    const auto root_utf8=config.model_root.u8string();
    fdm->SetRootDir(SGPath::fromUtf8(std::string(root_utf8.begin(),root_utf8.end()))); fdm->SetAircraftPath(SGPath("aircraft")); fdm->SetEnginePath(SGPath("engine"));
    fdm->Setdt(1.0 / 120);
    if (!fdm->LoadModel("original-synthetic")) throw std::runtime_error("Original synthetic model load failed");
    fdm->GetWinds()->SetTurbType(JSBSim::FGWinds::ttNone);
    auto ic = fdm->GetIC(); ic->SetGeodLatitudeRadIC(a.position.latitude_rad); ic->SetLongitudeRadIC(a.position.longitude_rad);
    double radial_asl_ft = c::units::meters_to_feet(a.position.ellipsoid_height_m);
    for (int i = 0; i < 12; ++i) {
      ic->SetAltitudeASLFtIC(radial_asl_ft);
      const double error = c::units::meters_to_feet(a.position.ellipsoid_height_m) - ic->GetPosition().GetGeodAltitude();
      if (std::abs(error * .3048) < 1e-7) break;
      radial_asl_ft += error;
    }
    if (std::abs(ic->GetPosition().GetGeodAltitude() * .3048 - a.position.ellipsoid_height_m) > 1e-6) throw std::runtime_error("Ellipsoid-height initialization failed");
    const auto angles = euler(a.orientation_body_to_ned);
    ic->SetPhiRadIC(angles[0]); ic->SetThetaRadIC(angles[1]); ic->SetPsiRadIC(angles[2]);
    ic->SetWindNEDFpsIC(w.wind_toward_ned_mps.x / .3048, w.wind_toward_ned_mps.y / .3048, w.wind_toward_ned_mps.z / .3048);
    ic->SetUBodyFpsIC(a.velocity_body_mps.x / .3048); ic->SetVBodyFpsIC(a.velocity_body_mps.y / .3048); ic->SetWBodyFpsIC(a.velocity_body_mps.z / .3048);
    ic->SetPRadpsIC(a.angular_rate_body_radps.x); ic->SetQRadpsIC(a.angular_rate_body_radps.y); ic->SetRRadpsIC(a.angular_rate_body_radps.z);
    fdm->GetPropulsion()->SetFuelFreeze(true);
    if (!fdm->RunIC()) throw std::runtime_error("Initial-condition application failed");
    const auto initialized_weather = atmosphere();
    if (std::abs(initialized_weather.pressure_pa - w.pressure_pa) > 1 || std::abs(initialized_weather.temperature_k - w.temperature_k) > .02 ||
        std::abs(initialized_weather.density_kgpm3 - w.density_kgpm3) > .0001) throw std::invalid_argument("Atmosphere request differs from supported dry ISA");
    fdm->GetPropulsion()->InitRunning(-1);
    held = {0, 0, 0, .65, 1, 0, 0, a.configuration.trim_fraction}; set_axes(held);
    if (config.trim.longitudinal) {
      JSBSim::FGTrim trim(fdm.get(), JSBSim::tLongitudinal);
      trim.SetGammaFallback(false); trim.SetMaxCycles(config.trim.max_cycles); trim.SetMaxCyclesPerAxis(config.trim.max_cycles_per_axis);
      trim.SetTolerance(config.trim.acceleration_tolerance_mps2 / .3048); trim.ClearDebug();
      if (!trim.DoTrim()) throw std::runtime_error("Longitudinal trim did not converge");
      held.roll = fdm->GetPropertyValue("fcs/aileron-cmd-norm"); held.pitch = -fdm->GetPropertyValue("fcs/elevator-cmd-norm");
      held.yaw = -fdm->GetPropertyValue("fcs/rudder-cmd-norm"); held.throttle = fdm->GetPropertyValue("fcs/throttle-cmd-norm");
      held.trim = -fdm->GetPropertyValue("fcs/pitch-trim-cmd-norm");
      if (!supported_axes(held)) throw std::runtime_error("Trim produced unsupported controls");
    }
    fdm->Setdt(clock.integration_step_s()); fdm->GetPropagate()->InitializeDerivatives(); fdm->GetPropulsion()->SetFuelFreeze(false);
    initialization.trim = config.trim; initialization.solved_controls = held; initialization.initial_fuel_kg = fuel_kg();
    latest = snapshot(); weather = atmosphere(); initialization.accepted = {latest, weather};
  }
  void require_open() const { if (!fdm || failed) throw std::logic_error("Session closed/failed; reset requires a fresh executive"); }
  void set_axes(const c::PilotAxes& a) {
    fdm->SetPropertyValue("fcs/aileron-cmd-norm", a.roll); fdm->SetPropertyValue("fcs/elevator-cmd-norm", -a.pitch);
    fdm->SetPropertyValue("fcs/rudder-cmd-norm", -a.yaw); fdm->SetPropertyValue("fcs/pitch-trim-cmd-norm", -a.trim);
    fdm->SetPropertyValue("fcs/throttle-cmd-norm", a.throttle); fdm->SetPropertyValue("fcs/mixture-cmd-norm", 1);
  }
  double fuel_kg() const { return c::units::pounds_mass_to_kg(fdm->GetPropulsion()->GetTank(0)->GetContents()); }
  c::AircraftSnapshot snapshot() const {
    const auto p = fdm->GetPropagate(); const auto m = fdm->GetMassBalance(); const auto& transform = p->GetTb2l(); std::array<double, 9> matrix{};
    for (unsigned i = 0; i < 3; ++i) for (unsigned j = 0; j < 3; ++j) matrix[3 * i + j] = transform(i + 1, j + 1);
    const auto& uvw = p->GetUVW(); const auto& pqr = p->GetPQR(); const auto& derivative = fdm->GetAccelerations()->GetUVWdot();
    const auto& position = p->GetLocation(); const auto& cg = m->GetXYZcg(); c::AircraftSnapshot s;
    s.header = {clock.completed_tick(), config.session_id}; s.clock = config.clock; s.elapsed_s = clock.elapsed_s();
    s.position = {p->GetGeodLatitudeRad(), p->GetLongitude(), p->GetGeodeticAltitude() * .3048};
    s.ecef_position_m = {position(1) * .3048, position(2) * .3048, position(3) * .3048}; s.orientation_body_to_ned = body_to_ned_from_matrix(matrix);
    s.velocity_body_mps = {uvw(1) * .3048, uvw(2) * .3048, uvw(3) * .3048}; s.angular_rate_body_radps = {pqr(1), pqr(2), pqr(3)};
    s.acceleration_body_mps2 = earth_acceleration_body_mps2({derivative(1) * .3048, derivative(2) * .3048, derivative(3) * .3048}, {pqr(1), pqr(2), pqr(3)}, s.velocity_body_mps);
    s.mass_kg = m->GetMass() * slug_to_kg; s.center_of_gravity_body_m = structural_cg_inches_to_body_datum_m(cg(1), cg(2), cg(3));
    s.configuration = {0, 1, held.trim}; s.systems = {{"fuel.total", c::Quantity::kilograms, fuel_kg(), c::Validity::valid},
      {"engine.throttle", c::Quantity::fraction, held.throttle, c::Validity::valid}}; s.validity = c::Validity::valid;
    if (!c::valid(s)) throw std::runtime_error("Invalid authoritative aircraft state");
    return s;
  }
  c::AtmosphereSample atmosphere() const {
    const auto a = fdm->GetAtmosphere(); const auto p = fdm->GetPropagate(); const auto& wind = fdm->GetWinds()->GetWindNED();
    c::AtmosphereSample w{{clock.completed_tick(), config.session_id}, {p->GetGeodLatitudeRad(), p->GetLongitude(), p->GetGeodeticAltitude() * .3048},
      a->GetPressure() * psf_to_pa, a->GetTemperature() * 5 / 9, a->GetDensity() * slug_to_kg / std::pow(.3048, 3),
      0, {wind(1) * .3048, wind(2) * .3048, wind(3) * .3048}, {}, config.seed, "jsbsim-dry-isa"};
    if (!c::valid(w)) throw std::runtime_error("Invalid authoritative atmosphere state");
    return w;
  }
  void record(std::variant<c::PauseControl, c::TimeScaleControl> action, std::string source) {
    c::OperationalEvent event; event.header = {clock.completed_tick(), config.session_id}; event.sequence = {++event_sequence}; event.source_id = std::move(source);
    event.confidence = c::OperationalEvent::Confidence::observed; event.content_version = "0.1.0-prototype";
    std::visit([&](auto value) { event.payload = value; }, action); events.push_back(std::move(event));
  }
  SessionConfig config; c::FixedClock clock; c::CommandGate commands; c::SessionControlGate lifecycle; std::unique_ptr<JSBSim::FGFDMExec> fdm;
  Initialization initialization; c::PilotAxes held; std::vector<c::ControlCommand> pending, applied; std::vector<AdmittedCommand> admitted;
  std::vector<c::OperationalEvent> events; std::vector<c::SessionControl> accepted_lifecycle;
  c::AircraftSnapshot latest; c::AtmosphereSample weather; std::uint64_t budget_units{}, event_sequence{}; bool failed{}, debt_drain{};
};
Session::Session(SessionConfig config) : impl_(std::make_unique<Impl>(std::move(config))) {}
Session::~Session() = default;
Session::Session(Session&&) noexcept = default;
Session& Session::operator=(Session&&) noexcept = default;
bool Session::register_host_source(std::string id, c::Authority authority) {
  impl_->require_open();
  if(static_cast<unsigned>(authority)>static_cast<unsigned>(c::Authority::instructor)) return false;
  return impl_->commands.register_source(std::move(id), authority);
}
SubmitReceipt Session::submit(c::ControlCommand command) {
  impl_->require_open(); const auto next = c::next_tick(impl_->clock.completed_tick()); if (!next) return {c::CommandRejection::late, false};
  if (impl_->pending.size() >= impl_->config.command_capacity || impl_->pending.size()+impl_->applied.size() >= impl_->config.history_capacity ||
      (command.header.tick >= *next && command.header.tick.value - next->value > impl_->config.future_horizon_ticks)) return {c::CommandRejection::capacity, false};
  const auto* axes = std::get_if<c::PilotAxes>(&command.payload);
  if(!axes) return {c::CommandRejection::unsupported_control, false};
  if(!c::valid(*axes)) return {c::CommandRejection::invalid, false};
  if(!supported_axes(*axes)) return {c::CommandRejection::unsupported_control, false};
  if (command.assistance.profile_id != "unassisted" || !command.assistance.active.empty()) return {c::CommandRejection::invalid, false};
  const auto rejection = impl_->commands.accept(command, *next); if (rejection != c::CommandRejection::none) return {rejection, false};
  impl_->admitted.push_back({impl_->clock.completed_tick(),command});
  impl_->pending.push_back(std::move(command)); std::sort(impl_->pending.begin(), impl_->pending.end(), c::command_before); return {c::CommandRejection::none, true};
}
c::SessionControlRejection Session::apply(const c::SessionControl& control) {
  impl_->require_open();
  if(impl_->events.size() >= impl_->config.history_capacity) return c::SessionControlRejection::invalid;
  const auto rejection = impl_->lifecycle.apply(control);
  if (rejection == c::SessionControlRejection::none) {
    impl_->accepted_lifecycle.push_back(control);
    if (const auto* p = std::get_if<c::PauseControl>(&control.payload)) impl_->record(*p, control.source_id);
    else impl_->record(std::get<c::TimeScaleControl>(control.payload), control.source_id);
  }
  return rejection;
}
StepResult Session::step_fixed() {
  impl_->require_open(); StepResult result;
  if (impl_->clock.paused()) { result.aircraft = impl_->latest; result.atmosphere = impl_->weather; return result; }
  const auto next = c::next_tick(impl_->clock.completed_tick()); if (!next) throw std::overflow_error("Simulation tick exhausted");
  const auto end = std::find_if(impl_->pending.begin(), impl_->pending.end(), [&](const auto& cmd) { return cmd.header.tick > *next; });
  std::vector<c::ControlCommand> applied(impl_->pending.begin(), end); for (const auto& command : applied) impl_->held = std::get<c::PilotAxes>(command.payload);
  impl_->set_axes(impl_->held);
  try {
    if (!impl_->fdm->Run() || !impl_->clock.advance()) throw std::runtime_error("Solver step failed");
    impl_->latest = impl_->snapshot(); impl_->weather = impl_->atmosphere();
    if (std::abs(impl_->fdm->GetSimTime() - impl_->clock.elapsed_s()) > 1e-7 + impl_->clock.elapsed_s() * 1e-10) throw std::runtime_error("Solver clock diverged");
  } catch (...) { impl_->failed = true; impl_->clock.set_paused(true); throw; }
  impl_->pending.erase(impl_->pending.begin(), end); impl_->applied.insert(impl_->applied.end(), applied.begin(), applied.end());
  result.stepped = true; result.aircraft = impl_->latest; result.atmosphere = impl_->weather; result.applied_commands = std::move(applied); return result;
}
AdvanceResult Session::advance_wall_budget(std::chrono::nanoseconds elapsed) {
  impl_->require_open(); if (elapsed.count() < 0 || elapsed.count() > 10000000000LL) throw std::invalid_argument("Wall delta outside [0,10s]");
  if (impl_->clock.paused()) return {0, false, true, impl_->budget_units / units_per_tick};
  if (impl_->debt_drain && elapsed.count() != 0) throw std::invalid_argument("Drain overrun debt with zero wall time first");
  const auto scale_quarters = static_cast<std::uint64_t>(impl_->lifecycle.time_scale() * 4);
  const auto added = static_cast<std::uint64_t>(elapsed.count()) * scale_quarters * impl_->config.clock.tick_rate_hz;
  if (impl_->budget_units > std::numeric_limits<std::uint64_t>::max() - added) throw std::overflow_error("Scheduler budget overflow");
  const auto new_budget=impl_->budget_units+added;
  if(!impl_->debt_drain && new_budget>static_cast<std::uint64_t>(impl_->config.clock.tick_rate_hz)*1000000000ULL && impl_->events.size()>=impl_->config.history_capacity)
    throw std::overflow_error("No event capacity for scheduler overrun; budget/state unchanged");
  impl_->budget_units=new_budget;
  if (!impl_->debt_drain && impl_->budget_units > static_cast<std::uint64_t>(impl_->config.clock.tick_rate_hz) * 1000000000ULL) {
    impl_->clock.set_paused(true); impl_->debt_drain = true; impl_->record(c::PauseControl{true}, "scheduler.overrun");
    return {0, true, true, impl_->budget_units / units_per_tick};
  }
  std::uint32_t steps = 0;
  while (impl_->budget_units >= units_per_tick && steps < 32) {
    const auto result = step_fixed();
    if (!result.stepped) break;
    impl_->budget_units -= units_per_tick; ++steps;
  }
  if (impl_->budget_units < units_per_tick) impl_->debt_drain = false;
  return {steps, false, impl_->clock.paused(), impl_->budget_units / units_per_tick};
}
c::AircraftSnapshot Session::latest_snapshot() const { impl_->require_open(); return impl_->latest; }
c::AtmosphereSample Session::latest_atmosphere() const { impl_->require_open(); return impl_->weather; }
DiagnosticSample Session::diagnostics() const {
  impl_->require_open(); const auto auxiliary=impl_->fdm->GetAuxiliary(); const auto aero=impl_->fdm->GetAerodynamics();
  const auto& force=aero->GetForces(); const auto& moment=aero->GetMoments(); const auto& wind_force=aero->GetvFw(); const auto& rate=auxiliary->GetAeroPQR();
  constexpr double lbf=4.4482216152605;
  return {{impl_->clock.completed_tick(),impl_->config.session_id},auxiliary->Getalpha(),auxiliary->Getbeta(),auxiliary->Getqbar()*psf_to_pa,auxiliary->GetVt()*.3048,
    {rate(1),rate(2),rate(3)},{force(1)*lbf,force(2)*lbf,force(3)*lbf},{moment(1)*lbf*.3048,moment(2)*lbf*.3048,moment(3)*lbf*.3048},
    {wind_force(1)*lbf,wind_force(2)*lbf,wind_force(3)*lbf},impl_->fuel_kg(),impl_->held.roll,-impl_->held.pitch,-impl_->held.yaw,-impl_->held.trim,impl_->held.throttle};
}
const Initialization& Session::initialization() const { impl_->require_open(); return impl_->initialization; }
std::vector<c::ControlCommand> Session::applied_command_log() const { impl_->require_open(); return impl_->applied; }
std::vector<AdmittedCommand> Session::admitted_command_history() const { impl_->require_open(); return impl_->admitted; }
std::vector<c::OperationalEvent> Session::event_log() const { impl_->require_open(); return impl_->events; }
std::vector<c::OperationalEvent> Session::events_after(c::Sequence last,std::size_t max_count) const {
  impl_->require_open();
  if(max_count==0||max_count>1024||last.value>impl_->event_sequence) throw std::invalid_argument("Invalid event delivery cursor/batch bound");
  std::vector<c::OperationalEvent> result;
  for(const auto& event:impl_->events) if(event.sequence>last) {
    result.push_back(event);
    if(result.size()==max_count) break;
  }
  return result;
}
std::vector<c::SessionControl> Session::accepted_session_controls() const { impl_->require_open(); return impl_->accepted_lifecycle; }
void Session::close() noexcept { if (impl_) { impl_->pending.clear(); impl_->fdm.reset(); } }
} // namespace flight::fdm
