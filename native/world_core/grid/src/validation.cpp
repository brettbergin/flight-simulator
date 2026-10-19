#include "validation.hpp"
#include <algorithm>
#include <bit>
#include <cfenv>
#include <climits>
#include <cmath>
#include <limits>
#include <stdexcept>
#if defined(_M_X64) || defined(_M_IX86) || defined(__SSE__)
#include <xmmintrin.h>
#endif

namespace flight::ground::grid::detail {
static_assert(CHAR_BIT == 8 && sizeof(float) == 4 && sizeof(double) == 8);
static_assert(std::numeric_limits<float>::is_iec559 && std::numeric_limits<double>::is_iec559);
[[noreturn]] void invalid() { throw std::invalid_argument("Invalid resident grid"); }
bool fp_environment() noexcept {
  if (std::fegetround() != FE_TONEAREST) return false;
#if defined(_M_X64) || defined(_M_IX86) || defined(__SSE__)
  if ((_mm_getcsr() & 0x8040U) != 0) return false; // No FTZ/DAZ, no caller-state mutation.
#endif
  return true;
}
double promoted_height(float value) noexcept {
  // Decode f32 bits without an arithmetic promotion that could honor DAZ.
  const auto bits = std::bit_cast<std::uint32_t>(value);
  const auto exponent = (bits >> 23) & 0xffU;
  const auto significand = exponent == 0 ? bits & 0x7fffffU : (bits & 0x7fffffU) | 0x800000U;
  const double magnitude = std::ldexp(static_cast<double>(significand), exponent == 0 ? -149 : static_cast<int>(exponent) - 150);
  return (bits >> 31) != 0 ? -magnitude : magnitude;
}
bool vertex_valid(const v::Definition& d, std::size_t n) noexcept { return ((d.valid_words[n / 64] >> (n % 64)) & 1U) != 0; }
bool cell_valid(const v::Definition& d, std::uint32_t column, std::uint32_t row) noexcept {
  const auto n = static_cast<std::size_t>(row) * d.columns + column;
  return vertex_valid(d, n) && vertex_valid(d, n + 1) && vertex_valid(d, n + d.columns) && vertex_valid(d, n + d.columns + 1);
}
double line(double origin, std::uint32_t index, v::Spacing spacing) noexcept {
  return origin + static_cast<double>(index) * static_cast<double>(spacing);
}
std::uint32_t cell_index(double coordinate, double origin, std::uint32_t vertices, v::Spacing spacing) noexcept {
  std::uint32_t lo = 0, hi = vertices - 1;
  while (lo + 1 < hi) {
    const auto mid = lo + (hi - lo) / 2;
    if (finite_compare(line(origin, mid, spacing), coordinate) <= 0) lo = mid; else hi = mid;
  }
  return lo;
}
std::int64_t orientation(v::PointMm a, v::PointMm b, v::PointMm p) noexcept {
  return (static_cast<std::int64_t>(b.east_mm) - a.east_mm) * (static_cast<std::int64_t>(p.south_mm) - a.south_mm) -
    (static_cast<std::int64_t>(b.south_mm) - a.south_mm) * (static_cast<std::int64_t>(p.east_mm) - a.east_mm);
}
bool on_segment(v::PointMm a, v::PointMm b, v::PointMm p) noexcept {
  return orientation(a, b, p) == 0 && p.east_mm >= std::min(a.east_mm, b.east_mm) && p.east_mm <= std::max(a.east_mm, b.east_mm) &&
    p.south_mm >= std::min(a.south_mm, b.south_mm) && p.south_mm <= std::max(a.south_mm, b.south_mm);
}
namespace {
// Finite numeric order including subnormals, independent of DAZ and rounding.
// Both signed zeros share the positive-zero key; all other raw bits are kept.
std::uint64_t numeric_key(double value) noexcept {
  auto bits = std::bit_cast<std::uint64_t>(value);
  if ((bits & 0x7fffffffffffffffULL) == 0) bits = 0;
  return (bits >> 63) != 0 ? ~bits : bits | 0x8000000000000000ULL;
}
bool same(v::PointMm a, v::PointMm b) noexcept { return a.east_mm == b.east_mm && a.south_mm == b.south_mm; }
bool crosses(v::PointMm a, v::PointMm b, v::PointMm c0, v::PointMm d) noexcept {
  const auto ab_c = orientation(a, b, c0), ab_d = orientation(a, b, d);
  const auto cd_a = orientation(c0, d, a), cd_b = orientation(c0, d, b);
  if ((ab_c == 0 && on_segment(a, b, c0)) || (ab_d == 0 && on_segment(a, b, d)) ||
      (cd_a == 0 && on_segment(c0, d, a)) || (cd_b == 0 && on_segment(c0, d, b))) return true;
  return ((ab_c < 0 && ab_d > 0) || (ab_c > 0 && ab_d < 0)) && ((cd_a < 0 && cd_b > 0) || (cd_a > 0 && cd_b < 0));
}
void add_bytes(std::uint64_t& bytes, std::size_t count, std::size_t unit) {
  if (unit == 0 || count > (v::max_definition_bytes - bytes) / unit) invalid();
  bytes += static_cast<std::uint64_t>(count) * unit;
}
void validate_ring(const v::MaterialPolygon& p) {
  const auto count = p.vertices.size();
  if (count < 3 || count > v::max_polygon_vertices) invalid();
  std::int64_t area = 0;
  for (std::size_t i = 0; i < count; ++i) {
    const auto a = p.vertices[i], b = p.vertices[(i + 1) % count];
    if (a.east_mm < -8192000 || a.east_mm > 8192000 || a.south_mm < -8192000 || a.south_mm > 8192000) invalid();
    for (std::size_t j = 0; j < i; ++j) if (same(a, p.vertices[j])) invalid();
    area += static_cast<std::int64_t>(a.east_mm) * b.south_mm - static_cast<std::int64_t>(a.south_mm) * b.east_mm;
  }
  if (area >= 0) invalid();
  for (std::size_t i = 0; i < count; ++i) {
    const auto a = p.vertices[i], b = p.vertices[(i + 1) % count];
    const auto next = p.vertices[(i + 2) % count];
    // Adjacent segments may be collinear in the forward direction but may not
    // reverse/overlap: no point beyond their shared vertex belongs to both.
    if (orientation(a, b, next) == 0 && (on_segment(a, b, next) || on_segment(b, next, a))) invalid();
    for (std::size_t j = i + 1; j < count; ++j) {
      if (j == i + 1 || (i == 0 && j + 1 == count)) continue;
      if (crosses(a, b, p.vertices[j], p.vertices[(j + 1) % count])) invalid();
    }
  }
}
Dyadic height(const v::Definition& d, std::size_t n) { return Dyadic::binary32_bits(std::bit_cast<std::uint32_t>(d.up_m[n])); }
void valid_gradient(const Dyadic& p, const Dyadic& q) {
  if (compare(p * p + q * q, Dyadic::integer(256)) > 0) invalid();
}
} // namespace
int finite_compare(double a, double b) noexcept {
  const auto ka = numeric_key(a), kb = numeric_key(b);
  return ka < kb ? -1 : (ka > kb ? 1 : 0);
}
bool polygon_contains(const v::MaterialPolygon& polygon, v::PointMm p) noexcept {
  int winding = 0;
  for (std::size_t i = 0; i < polygon.vertices.size(); ++i) {
    const auto a = polygon.vertices[i], b = polygon.vertices[(i + 1) % polygon.vertices.size()];
    if (on_segment(a, b, p)) return true;
    const auto o = orientation(a, b, p);
    if (a.south_mm <= p.south_mm && b.south_mm > p.south_mm && o > 0) ++winding;
    if (a.south_mm > p.south_mm && b.south_mm <= p.south_mm && o < 0) --winding;
  }
  return winding != 0;
}
Extrema validate(const v::Definition& d) {
  if ((d.spacing != v::Spacing::metres_2 && d.spacing != v::Spacing::metres_4) ||
      static_cast<unsigned>(d.missing_vertices) > 2 || d.columns < 2 || d.columns > v::max_axis_vertices ||
      d.rows < 2 || d.rows > v::max_axis_vertices) invalid();
  const auto n = static_cast<std::uint64_t>(d.columns) * d.rows;
  if (d.up_m.size() != n || d.valid_words.size() != (n + 63) / 64) invalid();
  if ((n % 64) != 0 && (d.valid_words.back() >> (n % 64)) != 0) invalid();
  if (!c::valid(d.anchor) || d.anchor.ellipsoid_height_m < -500 || d.anchor.ellipsoid_height_m > 10000) invalid();
  const auto axis = [&](double origin, std::uint32_t vertices) {
    const double endpoint = line(origin, vertices - 1, d.spacing);
    if (!std::isfinite(origin) || origin < -8192 || origin > 8192 || !std::isfinite(endpoint) || endpoint <= origin || endpoint > 8192 || endpoint < -8192) invalid();
    if (!Dyadic::binary64(origin).on_lattice(-32)) invalid();
  };
  axis(d.east_origin_m, d.columns); axis(d.south_origin_m, d.rows);
  if (d.materials.empty() || d.materials.size() > v::max_materials || d.default_material_index >= d.materials.size() || d.polygons.size() > v::max_polygons) invalid();
  std::uint64_t bytes = control_bytes;
  add_bytes(bytes, d.up_m.capacity(), sizeof(float)); add_bytes(bytes, d.valid_words.capacity(), sizeof(std::uint64_t));
  add_bytes(bytes, d.materials.capacity(), sizeof(v::Material)); add_bytes(bytes, d.polygons.capacity(), sizeof(v::MaterialPolygon));
  for (std::size_t i = 0; i < d.materials.size(); ++i) {
    const auto& m = d.materials[i];
    if (!c::stable_id(m.id) || !std::isfinite(m.static_friction) || !std::isfinite(m.dynamic_friction) ||
        numeric_key(m.dynamic_friction) < numeric_key(0) || numeric_key(m.dynamic_friction) > numeric_key(m.static_friction) ||
        numeric_key(m.static_friction) > numeric_key(5)) invalid();
    for (std::size_t j = 0; j < i; ++j) if (d.materials[j].id == m.id) invalid();
    add_bytes(bytes, m.id.capacity(), 1); add_bytes(bytes, 1, 1);
  }
  std::uint64_t polygon_vertices = 0;
  for (std::size_t i = 0; i < d.polygons.size(); ++i) {
    const auto& p = d.polygons[i];
    if (!c::stable_id(p.id) || p.material_index >= d.materials.size() || p.vertices.size() > v::max_polygon_vertices - polygon_vertices) invalid();
    polygon_vertices += p.vertices.size();
    for (std::size_t j = 0; j < i; ++j) if (d.polygons[j].id == p.id) invalid();
    add_bytes(bytes, p.id.capacity(), 1); add_bytes(bytes, 1, 1); add_bytes(bytes, p.vertices.capacity(), sizeof(v::PointMm));
    validate_ring(p);
  }
  Extrema extrema{std::numeric_limits<double>::infinity(), -std::numeric_limits<double>::infinity()};
  for (std::size_t i = 0; i < d.up_m.size(); ++i) {
    const auto bits = std::bit_cast<std::uint32_t>(d.up_m[i]);
    if (!vertex_valid(d, i)) { if (bits != v::invalid_height_bits) invalid(); continue; }
    if ((bits & 0x7f800000U) == 0x7f800000U) invalid();
    const double y = promoted_height(d.up_m[i]);
    if (y < -1000 || y > 4096) invalid();
    extrema.minimum = std::min(extrema.minimum, y); extrema.maximum = std::max(extrema.maximum, y);
  }
  if (!std::isfinite(extrema.minimum)) invalid();
  try {
    const auto span = Dyadic::binary64(extrema.maximum) - Dyadic::binary64(extrema.minimum) + Dyadic::binary64(0x1p-5);
    if (compare(span, Dyadic::integer(2048)) > 0) invalid();
    bool usable = false;
    const int divide_shift = d.spacing == v::Spacing::metres_2 ? -1 : -2;
    for (std::uint32_t row = 0; row + 1 < d.rows; ++row) {
      for (std::uint32_t col = 0; col + 1 < d.columns; ++col) {
        if (!cell_valid(d, col, row)) continue;
        usable = true;
        const auto i = static_cast<std::size_t>(row) * d.columns + col;
        const auto y00 = height(d, i), y10 = height(d, i + 1), y01 = height(d, i + d.columns), y11 = height(d, i + d.columns + 1);
        valid_gradient((y11 - y01).power2(divide_shift), (y01 - y00).power2(divide_shift));
        valid_gradient((y10 - y00).power2(divide_shift), (y11 - y10).power2(divide_shift));
      }
    }
    if (!usable) invalid();
  } catch (const ArithmeticFailure&) { invalid(); }
  return extrema;
}
} // namespace flight::ground::grid::detail
