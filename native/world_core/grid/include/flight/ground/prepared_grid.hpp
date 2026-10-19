#pragma once
#include <flight/ground/provider.hpp>
#include <cstdint>
#include <memory>
#include <string>
#include <vector>

// Proposed component ABI only. No loader, payload codec, world catalog, native
// flight factory, datum conversion, simulation mutation or renderer API.
namespace flight::ground::grid::v1 {
namespace c = flight::contracts::v1;
namespace g = flight::ground::v1;
inline constexpr std::uint32_t component_version = 1;
inline constexpr int origin_quantum_exponent = -32;
inline constexpr double max_gradient_norm = 16.0;
inline constexpr double max_ray_horizontal_component = 0x1.0624dd2f1a9fcp-9;
inline constexpr double min_ray_up_component = 0x1.ffff583a53b8ep-1;
inline constexpr std::uint32_t max_axis_vertices = 8193;
inline constexpr std::uint32_t max_query_cells = 64;
inline constexpr std::uint32_t max_coverage_cells = 4096;
inline constexpr std::uint32_t max_materials = 32;
inline constexpr std::uint32_t max_polygons = 128;
inline constexpr std::uint32_t max_polygon_vertices = 4096;
inline constexpr std::uint64_t max_definition_bytes = 536870912;
inline constexpr std::uint32_t invalid_height_bits = 0x7fc00000;

enum class Spacing : std::uint8_t { metres_2 = 2, metres_4 = 4 };
enum class MissingVertices : std::uint8_t {
  not_loaded = 0, datum_unresolved = 1, invalid_data = 2
};
enum class Coverage : std::uint8_t {
  ready = 0, outside_coverage = 1, not_loaded = 2,
  datum_unresolved = 3, invalid_data = 4
};
struct PointMm { std::int32_t east_mm{}, south_mm{}; };
struct Material {
  std::string id;
  double static_friction{}, dynamic_friction{};
};
struct MaterialPolygon {
  std::string id;
  std::uint32_t material_index{};
  std::uint8_t priority{};
  std::vector<PointMm> vertices; // Implicitly closed; no repeated terminal vertex.
};
struct Definition {
  c::GeodeticPosition anchor;
  double east_origin_m{}, south_origin_m{}; // Exact multiples of 2^-32 metres.
  Spacing spacing{Spacing::metres_2};
  std::uint32_t columns{}, rows{};
  std::vector<float> up_m; // South rows, east columns; exact promoted Float32.
  std::vector<std::uint64_t> valid_words; // Vertex n -> word n/64, bit n%64.
  MissingVertices missing_vertices{MissingVertices::invalid_data};
  std::vector<Material> materials;
  std::uint32_t default_material_index{};
  std::vector<MaterialPolygon> polygons;
};
// Closed geometric rectangle. No native-motion, gear or geodetic-padding claim.
struct Rectangle {
  double east_min_m{}, south_min_m{}, east_max_m{}, south_max_m{};
};
class PreparedGrid final : public g::SurfaceProvider {
 public:
  // Owns the passed definition; caller relinquishes mutable aliases on move.
  // Throws invalid_argument for invalid definition/
  // identity, bad_alloc for allocation failure. No partially usable object.
  static std::shared_ptr<const PreparedGrid> prepare(Definition, g::Identity);
  ~PreparedGrid() override;
  PreparedGrid(const PreparedGrid&) = delete;
  PreparedGrid& operator=(const PreparedGrid&) = delete;
  g::Identity identity() const override;
  c::GroundSample sample(const g::Query&) const override;
  Coverage coverage(const Rectangle&) const noexcept;
 private:
  PreparedGrid(Definition, g::Identity);
  class Impl;
  std::unique_ptr<const Impl> impl_;
};
} // namespace flight::ground::grid::v1