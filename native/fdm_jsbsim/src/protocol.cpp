#include <flight/fdm/protocol.hpp>
#include <bit>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace flight::fdm::transport {
namespace {
class Reader {
 public:
  explicit Reader(std::span<const std::uint8_t> input) : bytes(input) { if (bytes.size() > 4*1024*1024) fail(); }
  [[noreturn]] static void fail() { throw std::invalid_argument("Malformed/unsupported private FDM transport"); }
  std::uint64_t integer(unsigned size) {
    if (size > bytes.size() - offset) fail();
    std::uint64_t value=0;
    for (unsigned i=0;i<size;++i) value |= static_cast<std::uint64_t>(bytes[offset++]) << (8*i);
    return value;
  }
  double real() {
    const double v=std::bit_cast<double>(integer(8));
    if (!std::isfinite(v)) fail();
    return v;
  }
  std::string id() {
    const auto size=integer(2); if (size>128 || size>bytes.size()-offset) fail();
    std::string value(reinterpret_cast<const char*>(bytes.data()+offset), static_cast<std::size_t>(size)); offset+=static_cast<std::size_t>(size);
    if (!c::stable_id(value)) fail();
    return value;
  }
  bool boolean() {
    const auto value=integer(1);
    if(value>1) fail();
    return value!=0;
  }
  void end() const { if (offset!=bytes.size()) fail(); }
 private: std::span<const std::uint8_t> bytes; std::size_t offset{};
};
std::string number(double value) {
  if (!std::isfinite(value)) throw std::invalid_argument("Nonfinite JSON output");
  std::ostringstream s; s.imbue(std::locale::classic()); s<<std::setprecision(std::numeric_limits<double>::max_digits10)<<value; return s.str();
}
std::string quote(std::string_view value) {
  if(!c::stable_id(value)) throw std::invalid_argument("Unexpected output identifier");
  return '"'+std::string(value)+'"';
}
std::string diagnostic_string(std::string_view value) {
  if(value.size()>32768) throw std::invalid_argument("Diagnostic string exceeds bound");
  std::string out="\"";
  for(unsigned char ch:value) {
    if(ch<32) throw std::invalid_argument("Control byte in diagnostic string");
    if(ch=='"'||ch=='\\') out+='\\';
    out+=static_cast<char>(ch);
  }
  return out+'"';
}
std::string header(std::string_view type, const c::SampleHeader& h) {
  return "{\"type\":\""+std::string(type)+"\",\"schema_version\":1,\"tick\":\""+c::wire_uint64(h.tick.value)+"\",\"session_id\":"+quote(h.session_id);
}
template<class F,class U> std::string vector(c::Vector3<F,U> v) { return "{\"x\":"+number(v.x)+",\"y\":"+number(v.y)+",\"z\":"+number(v.z)+"}"; }
std::string position(c::GeodeticPosition p) { return "{\"latitude_rad\":"+number(p.latitude_rad)+",\"longitude_rad\":"+number(p.longitude_rad)+",\"ellipsoid_height_m\":"+number(p.ellipsoid_height_m)+"}"; }
std::string clock(c::ClockConfig clock) { return "{\"tick_rate_hz\":"+std::to_string(clock.tick_rate_hz)+",\"purpose\":\""+(clock.purpose==c::ClockPurpose::runtime ? "runtime" : "convergence")+"\"}"; }
std::string axes(const c::PilotAxes& a) { return "{\"kind\":\"axes\",\"roll\":"+number(a.roll)+",\"pitch\":"+number(a.pitch)+",\"yaw\":"+number(a.yaw)+",\"throttle\":"+number(a.throttle)+",\"mixture\":"+number(a.mixture)+",\"left_brake\":"+number(a.left_brake)+",\"right_brake\":"+number(a.right_brake)+",\"trim\":"+number(a.trim)+"}"; }
} // namespace
Request decode(std::span<const std::uint8_t> bytes, std::filesystem::path model_root) {
  Reader r(bytes); for(char ch:std::string_view("FSFDM001")) if(r.integer(1)!=static_cast<unsigned char>(ch)) Reader::fail();
  if(r.integer(4)!=1) Reader::fail();
  Request result; auto& cfg=result.config; cfg.model_root=std::move(model_root);
  cfg.clock.tick_rate_hz=static_cast<std::uint32_t>(r.integer(4)); const auto purpose=r.integer(1); if(purpose>1) Reader::fail();
  cfg.clock.purpose=static_cast<c::ClockPurpose>(purpose); if(!c::valid(cfg.clock)) Reader::fail();
  cfg.trim.longitudinal=r.boolean(); result.duration_ticks=r.integer(8); result.sample_interval_ticks=static_cast<std::uint32_t>(r.integer(4));
  if(result.duration_ticks==0 || result.duration_ticks>static_cast<std::uint64_t>(cfg.clock.tick_rate_hz)*600 || result.sample_interval_ticks==0 || result.sample_interval_ticks>cfg.clock.tick_rate_hz) Reader::fail();
  cfg.future_horizon_ticks=result.duration_ticks;
  cfg.seed={r.integer(8)}; cfg.session_id=r.id(); auto& a=cfg.initial_conditions.aircraft; auto& w=cfg.initial_conditions.atmosphere;
  a.header={{0},cfg.session_id}; a.clock=cfg.clock; a.validity=c::Validity::initializing;
  a.position={r.real(),r.real(),r.real()}; a.ecef_position_m={r.real(),r.real(),r.real()}; a.orientation_body_to_ned={r.real(),r.real(),r.real(),r.real()};
  a.velocity_body_mps={r.real(),r.real(),r.real()}; a.angular_rate_body_radps={r.real(),r.real(),r.real()}; a.mass_kg=r.real(); a.center_of_gravity_body_m={r.real(),r.real(),r.real()};
  a.configuration={r.real(),r.real(),r.real()}; w.header=a.header; w.position=a.position; w.seed=cfg.seed;
  w.pressure_pa=r.real(); w.temperature_k=r.real(); w.density_kgpm3=r.real(); w.relative_humidity=r.real();
  w.wind_toward_ned_mps={r.real(),r.real(),r.real()}; w.turbulence_ned_mps={r.real(),r.real(),r.real()}; w.model_id=r.id();
  if(!c::valid(a)||!c::valid(w)||std::abs(a.mass_kg-1100)>.0001||c::magnitude(a.center_of_gravity_body_m)!=0||a.configuration.flap_fraction!=0||a.configuration.gear_fraction!=1||
     c::magnitude(a.velocity_body_mps)<20||c::magnitude(a.velocity_body_mps)>200||c::magnitude(a.angular_rate_body_radps)>2||a.position.ellipsoid_height_m<100||a.position.ellipsoid_height_m>10000||
     w.relative_humidity!=0||c::magnitude(w.turbulence_ned_mps)!=0||c::magnitude(w.wind_toward_ned_mps)>100||w.model_id!="jsbsim-dry-isa") Reader::fail();
  const auto count=r.integer(4); if(count>4096) Reader::fail();
  for(std::uint64_t i=0;i<count;++i) {
    c::ControlCommand cmd; cmd.header={{r.integer(8)},cfg.session_id}; cmd.sequence={r.integer(8)}; cmd.source_id=r.id();
    const auto authority=r.integer(1);
    if(authority!=0 || cmd.source_id!="pilot.controls") Reader::fail();
    cmd.authority=c::Authority::pilot;
    cmd.assistance={r.id(),{}}; c::PilotAxes values{r.real(),r.real(),r.real(),r.real(),r.real(),r.real(),r.real(),r.real()};
    if(!c::valid(values) || values.mixture!=1 || values.left_brake!=0 || values.right_brake!=0 || cmd.assistance.profile_id!="unassisted" ||
       cmd.header.tick.value==0 || cmd.header.tick.value>result.duration_ticks) Reader::fail();
    cmd.payload=values; result.commands.push_back(std::move(cmd));
  }
  r.end(); c::CommandGate gate(cfg.session_id); if(!gate.register_source("pilot.controls",c::Authority::pilot)) Reader::fail();
  for(const auto& cmd:result.commands) if(gate.accept(cmd,{1})!=c::CommandRejection::none) Reader::fail();
  return result;
}
std::string json(const c::AircraftSnapshot& s) {
  if(!c::valid(s)) throw std::invalid_argument("Invalid snapshot JSON");
  const auto q=s.orientation_body_to_ned;
  std::string out=header("AircraftSnapshot",s.header)+",\"clock\":"+clock(s.clock)+",\"elapsed_s\":"+number(s.elapsed_s)+",\"position\":"+position(s.position)+
    ",\"ecef_position_m\":"+vector(s.ecef_position_m)+",\"orientation_body_to_ned\":{\"w\":"+number(q.w)+",\"x\":"+number(q.x)+",\"y\":"+number(q.y)+",\"z\":"+number(q.z)+"}"+
    ",\"velocity_body_mps\":"+vector(s.velocity_body_mps)+",\"angular_rate_body_radps\":"+vector(s.angular_rate_body_radps)+",\"acceleration_body_mps2\":"+vector(s.acceleration_body_mps2)+
    ",\"mass_kg\":"+number(s.mass_kg)+",\"center_of_gravity_body_m\":"+vector(s.center_of_gravity_body_m)+",\"configuration\":{\"flap_fraction\":"+number(s.configuration.flap_fraction)+
    ",\"gear_fraction\":"+number(s.configuration.gear_fraction)+",\"trim_fraction\":"+number(s.configuration.trim_fraction)+"},\"systems\":[";
  for(std::size_t i=0;i<s.systems.size();++i) {
    const auto& sys=s.systems[i]; if(i) out+=',';
    if(sys.quantity!=c::Quantity::kilograms && sys.quantity!=c::Quantity::fraction) throw std::invalid_argument("Unsupported prototype channel serializer");
    out+="{\"id\":"+quote(sys.id)+",\"quantity\":\""+(sys.quantity==c::Quantity::kilograms?"kg":"fraction")+"\",\"value\":"+number(std::get<double>(sys.value))+",\"validity\":\"valid\"}";
  }
  if(!s.contacts.empty()) throw std::invalid_argument("Prototype has no contact serializer");
  return out+"],\"contacts\":[],\"validity\":\"valid\"}";
}
std::string json(const c::AtmosphereSample& w) {
  if(!c::valid(w)) throw std::invalid_argument("Invalid atmosphere JSON");
  return header("AtmosphereSample",w.header)+",\"position\":"+position(w.position)+",\"pressure_pa\":"+number(w.pressure_pa)+",\"temperature_k\":"+number(w.temperature_k)+
    ",\"density_kgpm3\":"+number(w.density_kgpm3)+",\"relative_humidity\":"+number(w.relative_humidity)+",\"wind_toward_ned_mps\":"+vector(w.wind_toward_ned_mps)+
    ",\"turbulence_ned_mps\":"+vector(w.turbulence_ned_mps)+",\"seed\":\""+c::wire_uint64(w.seed.value)+"\",\"model_id\":"+quote(w.model_id)+"}";
}
std::string json(const c::ControlCommand& cmd) {
  const char* auth=cmd.authority==c::Authority::pilot?"pilot":cmd.authority==c::Authority::avionics?"avionics":cmd.authority==c::Authority::scenario?"scenario":"instructor";
  return header("ControlCommand",cmd.header)+",\"sequence\":\""+c::wire_uint64(cmd.sequence.value)+"\",\"source_id\":"+quote(cmd.source_id)+",\"authority\":\""+auth+
    "\",\"assistance\":{\"profile_id\":"+quote(cmd.assistance.profile_id)+",\"active\":[]},\"payload\":"+axes(std::get<c::PilotAxes>(cmd.payload))+"}";
}
std::string json(const c::OperationalEvent& event) {
  std::string payload;
  if(const auto* p=std::get_if<c::PauseControl>(&event.payload)) payload=std::string("{\"kind\":\"pause\",\"paused\":")+(p->paused?"true":"false")+"}";
  else if(const auto* s=std::get_if<c::TimeScaleControl>(&event.payload)) payload="{\"kind\":\"time_scale\",\"scale\":"+number(s->scale)+"}";
  else throw std::invalid_argument("Unsupported prototype event serializer");
  return header("OperationalEvent",event.header)+",\"sequence\":\""+c::wire_uint64(event.sequence.value)+"\",\"source_id\":"+quote(event.source_id)+
    ",\"confidence\":\"observed\",\"content_version\":\"0.1.0-prototype\",\"payload\":"+payload+"}";
}
std::string json(const Initialization& i) {
  return "{\"kind\":\"fdm-initialization\",\"version\":1,\"loaded_library_path\":"+diagnostic_string(i.loaded_library_path)+",\"library_version\":"+diagnostic_string(i.library_version)+
    ",\"compiler\":"+diagnostic_string(i.compiler)+",\"source_fingerprint\":"+diagnostic_string(i.source_fingerprint)+",\"requested_seed\":\""+c::wire_uint64(i.requested_seed.value)+"\",\"engine_seed\":"+std::to_string(i.engine_seed)+
    ",\"trim\":{\"longitudinal\":"+(i.trim.longitudinal?std::string("true"):std::string("false"))+",\"gamma_fallback\":false,\"max_cycles\":"+std::to_string(i.trim.max_cycles)+
    ",\"max_cycles_per_axis\":"+std::to_string(i.trim.max_cycles_per_axis)+",\"acceleration_tolerance_mps2\":"+number(i.trim.acceleration_tolerance_mps2)+
    "},\"solved_controls\":"+axes(i.solved_controls)+",\"fuel_frozen_during_trim\":true,\"initial_fuel_kg\":"+number(i.initial_fuel_kg)+
    ",\"initialization_step_s\":"+number(i.initialization_step_s)+",\"accepted_aircraft\":"+json(i.accepted.aircraft)+",\"accepted_atmosphere\":"+json(i.accepted.atmosphere)+"}";
}
std::string json(const DiagnosticSample& d) {
  return "{\"kind\":\"fdm-diagnostics\",\"version\":1,\"tick\":\""+c::wire_uint64(d.header.tick.value)+"\",\"session_id\":"+quote(d.header.session_id)+
    ",\"alpha_rad\":"+number(d.alpha_rad)+",\"beta_rad\":"+number(d.beta_rad)+",\"dynamic_pressure_pa\":"+number(d.dynamic_pressure_pa)+",\"airspeed_mps\":"+number(d.airspeed_mps)+
    ",\"air_relative_rate_radps\":"+vector(d.air_relative_rate_radps)+",\"aerodynamic_force_body_n\":"+vector(d.aerodynamic_force_body_n)+
    ",\"aerodynamic_moment_cg_body_nm\":["+number(d.aerodynamic_moment_cg_body_nm[0])+","+number(d.aerodynamic_moment_cg_body_nm[1])+","+number(d.aerodynamic_moment_cg_body_nm[2])+
    "],\"drag_side_lift_n\":["+number(d.drag_side_lift_n[0])+","+number(d.drag_side_lift_n[1])+","+number(d.drag_side_lift_n[2])+"],\"fuel_kg\":"+number(d.fuel_kg)+
    ",\"jsbsim_controls\":{\"aileron\":"+number(d.jsbsim_aileron)+",\"elevator\":"+number(d.jsbsim_elevator)+",\"rudder\":"+number(d.jsbsim_rudder)+",\"pitch_trim\":"+number(d.jsbsim_pitch_trim)+",\"throttle\":"+number(d.throttle)+"}}";
}
} // namespace flight::fdm::transport
