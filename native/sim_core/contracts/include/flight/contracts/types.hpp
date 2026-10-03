#pragma once

#include <array>
#include <charconv>
#include <cmath>
#include <compare>
#include <cstdint>
#include <limits>
#include <optional>
#include <stdexcept>
#include <string>
#include <string_view>
#include <vector>

namespace flight::contracts::v1 {
inline constexpr std::uint32_t schema_version = 1;
inline constexpr double pi = 3.141592653589793238462643383279502884;
inline constexpr double unit_tolerance = 1e-9;
struct Tick { std::uint64_t value{}; auto operator<=>(const Tick&) const = default; };
struct Sequence { std::uint64_t value{}; auto operator<=>(const Sequence&) const = default; };
struct Seed { std::uint64_t value{}; auto operator<=>(const Seed&) const = default; };
inline std::optional<std::uint64_t> parse_uint64(std::string_view text) noexcept {
  if (text.empty() || text.size() > 20 || (text.size() > 1 && text.front() == '0')) return std::nullopt;
  std::uint64_t value{};
  const auto [end, error] = std::from_chars(text.data(), text.data() + text.size(), value);
  if (error != std::errc{} || end != text.data() + text.size()) return std::nullopt;
  return value;
}
inline std::string wire_uint64(std::uint64_t value) { return std::to_string(value); }

struct Ecef {}; struct Ned {}; struct Body {}; struct Render {};
struct Meters {}; struct MetersPerSecond {}; struct RadiansPerSecond {}; struct MetersPerSecondSquared {}; struct Newtons {}; struct Dimensionless {};
template<class Frame, class Unit> struct Vector3 {
  double x{}, y{}, z{};
  auto operator<=>(const Vector3&) const = default;
};
template<class F, class U> inline bool finite(Vector3<F, U> v) noexcept { return std::isfinite(v.x) && std::isfinite(v.y) && std::isfinite(v.z); }
template<class F, class U> inline double magnitude(Vector3<F, U> v) noexcept { return std::hypot(v.x, v.y, v.z); }
using EcefPosition = Vector3<Ecef, Meters>;
using NedDisplacement = Vector3<Ned, Meters>;
using NedVelocity = Vector3<Ned, MetersPerSecond>;
using NedNormal = Vector3<Ned, Dimensionless>;
using BodyPosition = Vector3<Body, Meters>;
using BodyVelocity = Vector3<Body, MetersPerSecond>;
using BodyRate = Vector3<Body, RadiansPerSecond>;
using BodyAcceleration = Vector3<Body, MetersPerSecondSquared>;
using BodyForce = Vector3<Body, Newtons>;
using RenderPosition = Vector3<Render, Meters>;
struct GeodeticPosition { double latitude_rad{}, longitude_rad{}, ellipsoid_height_m{}; };
inline bool valid(GeodeticPosition p) noexcept {
  return std::isfinite(p.latitude_rad) && std::isfinite(p.longitude_rad) && std::isfinite(p.ellipsoid_height_m) &&
    std::abs(p.latitude_rad) <= pi / 2 && std::abs(p.longitude_rad) <= pi && p.ellipsoid_height_m >= -2000 && p.ellipsoid_height_m <= 10000000;
}
struct QuaternionBodyToNed { double w{1}, x{}, y{}, z{}; };
inline bool valid(QuaternionBodyToNed q) noexcept {
  return std::isfinite(q.w) && std::isfinite(q.x) && std::isfinite(q.y) && std::isfinite(q.z) &&
    std::abs(std::hypot(std::hypot(q.w, q.x), std::hypot(q.y, q.z)) - 1) <= unit_tolerance;
}
// Mathematical Hamilton active NED->body; JSBSim's raw tuple uses a passive matrix
// convention and must not be assigned this type based on its getter's label.
struct QuaternionNedToBody { double w{1}, x{}, y{}, z{}; };
inline QuaternionBodyToNed body_to_ned(QuaternionNedToBody q) noexcept { return {q.w, -q.x, -q.y, -q.z}; }
template<class Unit> inline Vector3<Ned, Unit> rotate_body_to_ned(QuaternionBodyToNed q, Vector3<Body, Unit> v) noexcept {
  // Caller validates quaternion; this transform never silently renormalizes corrupt input.
  const double tx = 2 * (q.y * v.z - q.z * v.y), ty = 2 * (q.z * v.x - q.x * v.z), tz = 2 * (q.x * v.y - q.y * v.x);
  return {v.x + q.w * tx + q.y * tz - q.z * ty, v.y + q.w * ty + q.z * tx - q.x * tz, v.z + q.w * tz + q.x * ty - q.y * tx};
}
template<class Unit> inline Vector3<Render, Unit> ned_to_render(Vector3<Ned, Unit> v) noexcept { return {v.y, -v.z, -v.x}; }

namespace units {
inline constexpr double feet_to_meters(double value) noexcept { return value * 0.3048; }
inline constexpr double meters_to_feet(double value) noexcept { return value / 0.3048; }
inline constexpr double knots_to_mps(double value) noexcept { return value * (1852.0 / 3600.0); }
inline constexpr double degrees_to_radians(double value) noexcept { return value * (pi / 180.0); }
inline constexpr double celsius_to_kelvin(double value) noexcept { return value + 273.15; }
inline constexpr double fahrenheit_to_kelvin(double value) noexcept { return (value - 32) * (5.0 / 9.0) + 273.15; }
inline constexpr double celsius_delta_to_kelvin_delta(double value) noexcept { return value; }
inline constexpr double pounds_mass_to_kg(double value) noexcept { return value * 0.45359237; }
inline constexpr double pounds_force_to_newtons(double value) noexcept { return value * 4.4482216152605; }
} // namespace units
struct ContentRef { std::string id, version, sha256; };
struct FileRef { std::string path, sha256; std::uint64_t bytes{}; std::string role; };
struct Assistance { std::string profile_id; std::vector<std::string> active; };
enum class EvidenceStatus { prototype, reference_reviewed, validated };
struct Evidence { EvidenceStatus status{EvidenceStatus::prototype}; std::vector<std::string> report_ids, source_ids; };
enum class Rights { redistributable, reference_only, pending };
struct Source {
  std::string id, revision, locator, sha256; Rights rights{Rights::pending}; std::string license, applicability;
  std::optional<std::string> effective_from, effective_until;
};
struct SampleHeader { Tick tick; std::string session_id; };
enum class ClockPurpose { runtime, convergence };
struct ClockConfig { std::uint32_t tick_rate_hz{120}; ClockPurpose purpose{ClockPurpose::runtime}; };
inline bool valid(ClockConfig config) noexcept {
  return config.purpose == ClockPurpose::runtime ? config.tick_rate_hz == 120 :
    config.purpose == ClockPurpose::convergence && (config.tick_rate_hz == 60 || config.tick_rate_hz == 120 || config.tick_rate_hz == 240);
}
inline std::optional<Tick> next_tick(Tick current) noexcept {
  return current.value == std::numeric_limits<std::uint64_t>::max() ? std::nullopt : std::optional{Tick{current.value + 1}};
}
class FixedClock {
 public:
  explicit FixedClock(ClockConfig config = {}) : config_(config) {
    if (!valid(config)) throw std::invalid_argument("Invalid fixed clock configuration");
  }
  [[nodiscard]] bool advance() noexcept {
    if (paused_ || !next_tick(completed_)) return false;
    ++completed_.value; return true;
  }
  void set_paused(bool paused) noexcept { paused_ = paused; }
  [[nodiscard]] bool paused() const noexcept { return paused_; }
  [[nodiscard]] Tick completed_tick() const noexcept { return completed_; }
  [[nodiscard]] double integration_step_s() const noexcept { return 1.0 / config_.tick_rate_hz; }
  [[nodiscard]] double elapsed_s() const noexcept { return static_cast<double>(completed_.value) / config_.tick_rate_hz; }
 private:
  ClockConfig config_; Tick completed_{}; bool paused_{};
};
} // namespace flight::contracts::v1
