#include "validation.hpp"
#include "canonical_frame.hpp"
#include <algorithm>
#include <array>
#include <bit>
#include <cmath>
#include <memory>
#include <utility>

namespace flight::ground::grid::v1 {
namespace d = flight::ground::grid::detail;
namespace {
using Vector = std::array<double, 3>;
using ExactVector = std::array<d::Dyadic, 3>;
namespace frame=d::canonical_frame;
using frame::dot;using frame::east_at;using frame::up_at;using frame::south_at;
ExactVector exact(const Vector& a) { return {d::Dyadic::binary64(a[0]), d::Dyadic::binary64(a[1]), d::Dyadic::binary64(a[2])}; }
c::MissingGround missing(MissingVertices reason) noexcept {
  return static_cast<c::MissingGround>(static_cast<unsigned>(reason) + 1U);
}
Coverage missing_coverage(MissingVertices reason) noexcept { return static_cast<Coverage>(static_cast<unsigned>(reason) + 2U); }
struct AxisSupport { std::uint32_t first{}, last{}; };
bool rational_axis(const d::Dyadic& low, const d::Dyadic& high, const d::Dyadic& denominator,
                   double origin, std::uint32_t vertices, Spacing spacing, AxisSupport& support) {
  const auto grid = [&](std::uint32_t i) { return d::Dyadic::binary64(d::line(origin, i, spacing)) * denominator; };
  if (compare(low, grid(0)) < 0 || compare(high, grid(vertices - 1)) >= 0) return false;
  const auto floor_index = [&](const d::Dyadic& numerator) {
    std::uint32_t lo = 0, hi = vertices - 1;
    while (lo + 1 < hi) {
      const auto mid = lo + (hi - lo) / 2;
      if (compare(numerator, grid(mid)) >= 0) lo = mid; else hi = mid;
    }
    return lo;
  };
  support = {floor_index(low), floor_index(high)};
  return true;
}
struct Root {
  d::Dyadic numerator, denominator, x_numerator, z_numerator, p, q;
};
} // namespace

class PreparedGrid::Impl {
 public:
  d::Storage state;
  Impl(Definition definition, g::Identity identity) {
    static_assert(sizeof(Impl) == sizeof(d::Storage));
    state.definition = std::move(definition);
    state.identity = std::move(identity);
    if (!g::valid(state.identity)) d::invalid();
    const auto extrema = d::validate(state.definition);
    try {
      state.low = d::Dyadic::binary64(extrema.minimum) - d::Dyadic::binary64(0x1p-6);
      state.high = d::Dyadic::binary64(extrema.maximum) + d::Dyadic::binary64(0x1p-6);
    } catch (const d::ArithmeticFailure&) { d::invalid(); }
  }
};
PreparedGrid::PreparedGrid(Definition definition, g::Identity identity)
  : impl_(std::make_unique<Impl>(std::move(definition), std::move(identity))) {}
PreparedGrid::~PreparedGrid() = default;
std::shared_ptr<const PreparedGrid> PreparedGrid::prepare(Definition definition, g::Identity identity) {
  return std::shared_ptr<const PreparedGrid>(new PreparedGrid(std::move(definition), std::move(identity)));
}
g::Identity PreparedGrid::identity() const { return impl_->state.identity; }

Coverage PreparedGrid::coverage(const Rectangle& r) const noexcept {
  const auto& def = impl_->state.definition;
  if (!std::isfinite(r.east_min_m) || !std::isfinite(r.east_max_m) || !std::isfinite(r.south_min_m) || !std::isfinite(r.south_max_m) ||
      d::finite_compare(r.east_min_m, r.east_max_m) > 0 || d::finite_compare(r.south_min_m, r.south_max_m) > 0) return Coverage::invalid_data;
  if (d::finite_compare(r.east_min_m, def.east_origin_m) < 0 || d::finite_compare(r.south_min_m, def.south_origin_m) < 0 ||
      d::finite_compare(r.east_max_m, d::line(def.east_origin_m, def.columns - 1, def.spacing)) >= 0 ||
      d::finite_compare(r.south_max_m, d::line(def.south_origin_m, def.rows - 1, def.spacing)) >= 0) return Coverage::outside_coverage;
  const auto x0 = d::cell_index(r.east_min_m, def.east_origin_m, def.columns, def.spacing);
  const auto x1 = d::cell_index(r.east_max_m, def.east_origin_m, def.columns, def.spacing);
  const auto z0 = d::cell_index(r.south_min_m, def.south_origin_m, def.rows, def.spacing);
  const auto z1 = d::cell_index(r.south_max_m, def.south_origin_m, def.rows, def.spacing);
  const auto count = static_cast<std::uint64_t>(x1 - x0 + 1) * (z1 - z0 + 1);
  if (count > max_coverage_cells) return Coverage::invalid_data;
  for (auto z = z0; z <= z1; ++z)
    for (auto x = x0; x <= x1; ++x)
      if (!d::cell_valid(def, x, z)) return missing_coverage(def.missing_vertices);
  return Coverage::ready;
}

c::GroundSample PreparedGrid::sample(const g::Query& query) const {
  if (!c::stable_id(query.header.session_id) || !c::valid(query.position)) d::invalid();
  const auto failed = [&](c::MissingGround reason) { return c::GroundSample{query.header, query.position, reason}; };
  if (!d::fp_environment()) return failed(c::MissingGround::invalid_data);
  const auto& storage = impl_->state;
  const auto& def = storage.definition;
  // Preparation has no caller-FENV precondition. Build numerical frame operands
  // only here, after the query's certification check, never cache operands that
  // might have been prepared with another rounding/FTZ/DAZ configuration.
  const auto canonical=frame::make(def.anchor);
  if(!canonical)return failed(c::MissingGround::invalid_data);
  const auto anchor_east=canonical->east,anchor_up=canonical->up,anchor_south=canonical->south;
  const auto ray=frame::query_ray(*canonical,query.position);
  if(!ray)return failed(c::MissingGround::invalid_data);
  const auto a=ray->a,direction=ray->direction;
  if (std::abs(direction[0]) > max_ray_horizontal_component || std::abs(direction[2]) > max_ray_horizontal_component ||
      direction[1] < min_ray_up_component) return failed(c::MissingGround::outside_coverage);
  try {
    const auto aa = exact(a), dd = exact(direction);
    const auto low_delta = storage.low - aa[1], high_delta = storage.high - aa[1];
    const auto support_numerators = [&](std::size_t axis) {
      auto lo = aa[axis] * dd[1] + dd[axis] * low_delta;
      auto hi = aa[axis] * dd[1] + dd[axis] * high_delta;
      if (compare(lo, hi) > 0) std::swap(lo, hi);
      return std::array<d::Dyadic, 2>{lo, hi};
    };
    const auto xs = support_numerators(0), zs = support_numerators(2);
    AxisSupport x_support, z_support;
    if (!rational_axis(xs[0], xs[1], dd[1], def.east_origin_m, def.columns, def.spacing, x_support) ||
        !rational_axis(zs[0], zs[1], dd[1], def.south_origin_m, def.rows, def.spacing, z_support)) return failed(c::MissingGround::outside_coverage);
    const auto first_x = x_support.first > 0 ? x_support.first - 1 : 0;
    const auto first_z = z_support.first > 0 ? z_support.first - 1 : 0;
    const auto last_x = std::min(x_support.last + 1, def.columns - 2);
    const auto last_z = std::min(z_support.last + 1, def.rows - 2);
    const auto candidate_count = static_cast<std::uint64_t>(last_x - first_x + 1) * (last_z - first_z + 1);
    if (candidate_count > max_query_cells) return failed(c::MissingGround::invalid_data);
    for (auto row = z_support.first; row <= z_support.last; ++row)
      for (auto col = x_support.first; col <= x_support.last; ++col)
        if (!d::cell_valid(def, col, row)) return failed(missing(def.missing_vertices));
    Root accepted;
    bool found = false;
    const auto shift = def.spacing == Spacing::metres_2 ? -1 : -2;
    for (auto row = first_z; row <= last_z; ++row) {
      for (auto col = first_x; col <= last_x; ++col) {
        if (!d::cell_valid(def, col, row)) continue;
        const auto n = static_cast<std::size_t>(row) * def.columns + col;
        const auto y00 = d::Dyadic::binary32_bits(std::bit_cast<std::uint32_t>(def.up_m[n]));
        const auto y10 = d::Dyadic::binary32_bits(std::bit_cast<std::uint32_t>(def.up_m[n + 1]));
        const auto y01 = d::Dyadic::binary32_bits(std::bit_cast<std::uint32_t>(def.up_m[n + def.columns]));
        const auto y11 = d::Dyadic::binary32_bits(std::bit_cast<std::uint32_t>(def.up_m[n + def.columns + 1]));
        const auto x0 = d::Dyadic::binary64(d::line(def.east_origin_m, col, def.spacing));
        const auto x1 = d::Dyadic::binary64(d::line(def.east_origin_m, col + 1, def.spacing));
        const auto z0 = d::Dyadic::binary64(d::line(def.south_origin_m, row, def.spacing));
        const auto z1 = d::Dyadic::binary64(d::line(def.south_origin_m, row + 1, def.spacing));
        for (unsigned triangle = 0; triangle < 2; ++triangle) {
          const auto p = (triangle == 0 ? y11 - y01 : y10 - y00).power2(shift);
          const auto q = (triangle == 0 ? y01 - y00 : y11 - y10).power2(shift);
          const auto denominator = dd[1] - p * dd[0] - q * dd[2];
          if (denominator.sign() <= 0) return failed(c::MissingGround::invalid_data);
          const auto numerator = y00 + p * (aa[0] - x0) + q * (aa[2] - z0) - aa[1];
          if (compare(numerator * dd[1], low_delta * denominator) < 0 || compare(numerator * dd[1], high_delta * denominator) > 0) continue;
          const auto xn = aa[0] * denominator + dd[0] * numerator;
          const auto zn = aa[2] * denominator + dd[2] * numerator;
          const auto left = x0 * denominator, right = x1 * denominator;
          const auto near = z0 * denominator, far = z1 * denominator;
          if (compare(xn, left) < 0 || compare(xn, right) >= 0 || compare(zn, near) < 0 || compare(zn, far) >= 0) continue;
          const auto diagonal = compare(zn - near, xn - left);
          if ((triangle == 0 && diagonal < 0) || (triangle == 1 && diagonal >= 0)) continue;
          if (found) return failed(c::MissingGround::invalid_data);
          accepted = {numerator, denominator, xn, zn, p, q};
          found = true;
        }
      }
    }
    if (!found) return failed(c::MissingGround::invalid_data);
    const double surface_height = d::rounded_ratio(accepted.numerator, accepted.denominator);
    const double p = accepted.p.approximate(), q = accepted.q.approximate();
    const double length = std::sqrt((p * p + 1) + q * q);
    const Vector normal_eus{-p / length, 1 / length, -q / length};
    Vector normal_ecef{};
    for (std::size_t i = 0; i < 3; ++i)
      normal_ecef[i] = (normal_eus[0] * anchor_east[i] + normal_eus[1] * anchor_up[i]) + normal_eus[2] * anchor_south[i];
    const auto local_east = east_at(query.position), local_south = south_at(query.position), local_up = up_at(query.position);
    const c::NedNormal normal{-dot(normal_ecef, local_south), dot(normal_ecef, local_east), -dot(normal_ecef, local_up)};
    if (!c::finite(normal) || normal.z >= 0 || std::abs(c::magnitude(normal) - 1) > c::unit_tolerance) return failed(c::MissingGround::invalid_data);
    const PointMm point{d::rounded_millimetres(accepted.x_numerator, accepted.denominator), d::rounded_millimetres(accepted.z_numerator, accepted.denominator)};
    const MaterialPolygon* selected = nullptr;
    for (const auto& polygon : def.polygons) {
      if (d::polygon_contains(polygon, point) && (selected == nullptr || polygon.priority > selected->priority ||
          (polygon.priority == selected->priority && polygon.id < selected->id))) selected = &polygon;
    }
    const auto& material = def.materials[selected == nullptr ? def.default_material_index : selected->material_index];
    c::GroundSample result{query.header, query.position, c::ValidGround{surface_height, normal, material.static_friction, material.dynamic_friction, material.id, storage.identity.world}};
    if (!c::valid(result)) return failed(c::MissingGround::invalid_data);
    return result;
  } catch (const d::ArithmeticFailure&) { return failed(c::MissingGround::invalid_data); }
}
} // namespace flight::ground::grid::v1
