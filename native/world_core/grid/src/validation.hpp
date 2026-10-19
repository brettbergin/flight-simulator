#pragma once
#include "exact.hpp"
#include <flight/ground/prepared_grid.hpp>
#include <array>
#include <cstdint>

namespace flight::ground::grid::detail {
namespace v = flight::ground::grid::v1;
namespace c = flight::contracts::v1;
namespace g = flight::ground::v1;
struct Extrema { double minimum{}, maximum{}; };
struct Storage {
  v::Definition definition;
  g::Identity identity;
  Dyadic low, high;
};
// Includes the owned Definition once (inside Storage), Impl's other controls,
// and the PreparedGrid wrapper. Allocator/control-block overhead is separate.
inline constexpr std::uint64_t control_bytes = sizeof(Storage) + sizeof(v::PreparedGrid);
[[noreturn]] void invalid();
bool fp_environment() noexcept;
int finite_compare(double, double) noexcept;
Extrema validate(const v::Definition&);
double promoted_height(float) noexcept;
bool vertex_valid(const v::Definition&, std::size_t) noexcept;
bool cell_valid(const v::Definition&, std::uint32_t, std::uint32_t) noexcept;
double line(double origin, std::uint32_t index, v::Spacing spacing) noexcept;
std::uint32_t cell_index(double coordinate, double origin, std::uint32_t vertices, v::Spacing spacing) noexcept;
std::int64_t orientation(v::PointMm, v::PointMm, v::PointMm) noexcept;
bool on_segment(v::PointMm, v::PointMm, v::PointMm) noexcept;
bool polygon_contains(const v::MaterialPolygon&, v::PointMm) noexcept;
} // namespace flight::ground::grid::detail
