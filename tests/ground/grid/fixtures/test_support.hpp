#pragma once
#include <flight/ground/prepared_grid.hpp>
#include <array>
#include <bit>
#include <cmath>
#include <cstdint>
#include <exception>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <variant>
#include <vector>

// Independent test construction only. No production encoder/geometry helpers.
namespace grid_test {
namespace c = flight::contracts::v1;
namespace g = flight::ground::v1;
namespace grid = flight::ground::grid::v1;
inline int checks = 0;
inline int failures = 0;
inline void check(bool result, std::string_view label) {
  ++checks;
  if (!result) { ++failures; std::cerr << "FAIL: " << label << '\n'; }
}
template<class F> void section(std::string_view label, F&& action) {
  try { action(); }
  catch (const std::exception& error) {
    ++checks; ++failures;
    std::cerr << "FAIL: unexpected exception in " << label << ": " << error.what() << '\n';
  } catch (...) { check(false, label); }
}
template<class F> void rejects_invalid(F&& action, std::string_view label) {
  bool rejected = false;
  try { action(); }
  catch (const std::invalid_argument&) { rejected = true; }
  catch (const std::exception& error) {
    ++checks; ++failures;
    std::cerr << "FAIL: wrong exception for " << label << ": " << error.what() << '\n';
    return;
  } catch (...) { check(false, label); return; }
  check(rejected, label);
}
inline float f32(std::uint32_t word) { return std::bit_cast<float>(word); }
inline std::uint32_t bits(float value) { return std::bit_cast<std::uint32_t>(value); }
inline std::uint64_t bits(double value) { return std::bit_cast<std::uint64_t>(value); }
inline bool near(double actual, double expected, double tolerance) {
  return std::isfinite(actual) && std::abs(actual - expected) <= tolerance;
}
inline g::Identity identity() {
  return {{"synthetic-grid", "0.1.0-prototype", std::string(64, 'a')}, std::string(64, 'b'), 1};
}
inline void all_valid(grid::Definition& definition) {
  const auto count = definition.up_m.size();
  definition.valid_words.assign((count + 63U) / 64U, std::numeric_limits<std::uint64_t>::max());
  if (count % 64U != 0U) definition.valid_words.back() = (std::uint64_t{1} << (count % 64U)) - 1U;
}
inline grid::Definition flat(std::uint32_t columns = 2, std::uint32_t rows = 2,
                             double east = -1, double south = -1,
                             grid::Spacing spacing = grid::Spacing::metres_2, float height = 10) {
  grid::Definition definition;
  definition.anchor = {0, 0, 0};
  definition.east_origin_m = east; definition.south_origin_m = south;
  definition.spacing = spacing; definition.columns = columns; definition.rows = rows;
  definition.up_m.assign(static_cast<std::size_t>(columns) * rows, height);
  all_valid(definition);
  definition.materials = {{"synthetic-default", .6, .4}};
  return definition;
}
inline g::Query query(c::GeodeticPosition position = {0, 0, 25},
                      std::uint64_t tick = std::numeric_limits<std::uint64_t>::max()) {
  return {{{tick}, "grid-session"}, position};
}
inline void echo(const c::GroundSample& sample, const g::Query& requested) {
  check(c::valid(sample), "sample satisfies existing GroundSample contract");
  check(sample.header.tick == requested.header.tick && sample.header.session_id == requested.header.session_id,
        "all tick bits and session echoed exactly");
  check(bits(sample.position.latitude_rad) == bits(requested.position.latitude_rad)
        && bits(sample.position.longitude_rad) == bits(requested.position.longitude_rad)
        && bits(sample.position.ellipsoid_height_m) == bits(requested.position.ellipsoid_height_m),
        "requested geodetic raw doubles echoed exactly");
}
inline void ready(const grid::PreparedGrid& provider, c::GeodeticPosition position,
                   double height, std::array<double, 3> normal,
                   double height_tolerance = 1e-10, double normal_tolerance = 1e-12,
                   std::string_view material = "synthetic-default", double sf = .6, double df = .4) {
  const auto requested = query(position);
  const auto sample = provider.sample(requested);
  echo(sample, requested);
  const auto* ground = std::get_if<c::ValidGround>(&sample.sample);
  check(ground != nullptr, "expected ready ground");
  if (!ground) return;
  check(near(ground->surface_height_m, height, height_tolerance), "independent ellipsoid surface height");
  check(near(ground->normal_ned.x, normal[0], normal_tolerance)
        && near(ground->normal_ned.y, normal[1], normal_tolerance)
        && near(ground->normal_ned.z, normal[2], normal_tolerance), "independent owning-facet query NED normal");
  check(ground->normal_ned.z < 0, "normal has negative NED down");
  check(ground->material_id == material && ground->static_friction == sf && ground->dynamic_friction == df,
        "material ID and friction copied exactly");
  check(g::same(ground->world, identity().world), "sample copies exact prepared world ContentRef");
}
inline void ready_altitudes(const grid::Definition& definition, double height,
                             std::array<double, 3> normal) {
  const auto provider = grid::PreparedGrid::prepare(definition, identity());
  for (const double altitude : {-50., 25., 1000.})
    ready(*provider, {definition.anchor.latitude_rad, definition.anchor.longitude_rad, altitude}, height, normal);
}
inline void missing(const grid::PreparedGrid& provider, c::MissingGround expected,
                     c::GeodeticPosition position = {0, 0, 25}) {
  const auto requested = query(position);
  const auto sample = provider.sample(requested);
  echo(sample, requested);
  const auto* reason = std::get_if<c::MissingGround>(&sample.sample);
  check(reason != nullptr && *reason == expected, "exact missing reason without invented ready fields");
}
inline int finish(std::string_view label) {
  std::cout << label << ": " << checks << " checks, " << failures << " failures\n";
  return failures == 0 ? 0 : 1;
}
} // namespace grid_test
