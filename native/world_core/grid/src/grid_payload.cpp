#include "validation.hpp"
#include <flight/ground/grid_payload.hpp>
#include <array>
#include <bit>
#include <cstdint>
#include <limits>
#include <span>
#include <string>
#include <string_view>
#include <utility>

namespace flight::ground::grid::payload::v1 {
namespace d = flight::ground::grid::detail;
namespace v = flight::ground::grid::v1;
namespace {
static_assert(std::bit_cast<std::int32_t>(std::uint32_t{0xffffffffU}) == -1);
class Reader {
 public:
  explicit Reader(std::span<const std::uint8_t> source) : source_(source) {}
  void skip(std::uint64_t width) {
    require(width);
    cursor_ += width;
  }
  std::uint64_t unsigned_value(unsigned width) {
    if (width > 8) d::invalid();
    require(width);
    std::uint64_t result = 0;
    for (unsigned i = 0; i < width; ++i)
      result |= static_cast<std::uint64_t>(source_[static_cast<std::size_t>(cursor_ + i)]) << (8U * i);
    cursor_ += width;
    return result;
  }
  std::uint32_t u32() { return static_cast<std::uint32_t>(unsigned_value(4)); }
  double f64() { return std::bit_cast<double>(unsigned_value(8)); }
  std::string_view id() {
    const auto length = unsigned_value(1);
    if (length < 1 || length > 128) d::invalid();
    require(length);
    const auto* data = reinterpret_cast<const char*>(source_.data() + static_cast<std::size_t>(cursor_));
    const std::string_view text(data, static_cast<std::size_t>(length));
    if (!flight::contracts::v1::stable_id(text)) d::invalid();
    cursor_ += length;
    return text;
  }
  [[nodiscard]] bool finished() const noexcept { return cursor_ == source_.size(); }
 private:
  std::span<const std::uint8_t> source_;
  std::uint64_t cursor_{};
  void require(std::uint64_t width) const {
    if (cursor_ > source_.size() || width > source_.size() - cursor_) d::invalid();
  }
};
struct Header {
  v::Definition definition;
  std::uint32_t vertices{}, words{}, materials{}, polygons{}, polygon_vertices{};
};
Header header(Reader& reader, std::size_t actual_size) {
  constexpr std::array<std::uint8_t, 8> magic{0x46, 0x47, 0x52, 0x44, 0x4c, 0x45, 0x31, 0};
  for (const auto byte : magic) if (reader.unsigned_value(1) != byte) d::invalid();
  if (reader.u32() != payload_version || reader.u32() != 0x01020304U || reader.unsigned_value(8) != actual_size) d::invalid();
  Header h;
  auto& def = h.definition;
  def.columns = reader.u32(); def.rows = reader.u32();
  h.vertices = reader.u32(); h.words = reader.u32(); h.materials = reader.u32();
  h.polygons = reader.u32(); h.polygon_vertices = reader.u32(); def.default_material_index = reader.u32();
  def.spacing = static_cast<v::Spacing>(reader.unsigned_value(1));
  def.missing_vertices = static_cast<v::MissingVertices>(reader.unsigned_value(1));
  if (reader.unsigned_value(2) != 0 || reader.u32() != 0) d::invalid();
  def.anchor = {reader.f64(), reader.f64(), reader.f64()};
  def.east_origin_m = reader.f64(); def.south_origin_m = reader.f64();
  if (def.columns < 2 || def.columns > v::max_axis_vertices || def.rows < 2 || def.rows > v::max_axis_vertices ||
      h.materials < 1 || h.materials > v::max_materials || h.polygons > v::max_polygons || h.polygon_vertices > v::max_polygon_vertices ||
      (def.spacing != v::Spacing::metres_2 && def.spacing != v::Spacing::metres_4) || static_cast<unsigned>(def.missing_vertices) > 2) d::invalid();
  const auto n = static_cast<std::uint64_t>(def.columns) * def.rows;
  if (h.vertices != n || h.words != (n + 63) / 64) d::invalid();
  // All counts are now bounded; these uint64 products/sums cannot overflow.
  // Include minimum ID length and fixed metadata for every declared record.
  const std::uint64_t minimum_size = 104 + 4 * n + 8ULL * h.words + 18ULL * h.materials + 11ULL * h.polygons + 8ULL * h.polygon_vertices;
  if (minimum_size > actual_size) d::invalid();
  return h;
}
void preflight_body(Reader& reader, const Header& h) {
  reader.skip(4ULL * h.vertices + 8ULL * h.words);
  for (std::uint32_t i = 0; i < h.materials; ++i) { static_cast<void>(reader.id()); reader.skip(16); }
  std::uint64_t vertices = 0;
  for (std::uint32_t i = 0; i < h.polygons; ++i) {
    static_cast<void>(reader.id()); reader.skip(5);
    const auto count = reader.u32();
    if (count < 3 || count > v::max_polygon_vertices || count > h.polygon_vertices - vertices) d::invalid();
    vertices += count;
    reader.skip(8ULL * count);
  }
  if (vertices != h.polygon_vertices || !reader.finished()) d::invalid();
}
} // namespace

v::Definition decode(std::span<const std::uint8_t> bytes) {
  if (bytes.size() < 104 || bytes.size() > max_payload_bytes) d::invalid();
  Reader first(bytes);
  auto h = header(first, bytes.size());
  // Full structural cursor/record pass precedes any height/mask allocation.
  // This also rejects huge declared dimensions with a tiny body cheaply.
  preflight_body(first, h);
  auto def = std::move(h.definition);
  Reader body(bytes); body.skip(104);
  def.up_m.resize(h.vertices); def.valid_words.resize(h.words);
  def.materials.reserve(h.materials); def.polygons.reserve(h.polygons);
  for (auto& value : def.up_m) value = std::bit_cast<float>(body.u32());
  for (auto& value : def.valid_words) value = body.unsigned_value(8);
  for (std::uint32_t i = 0; i < h.materials; ++i) {
    v::Material material;
    material.id = std::string(body.id());
    material.static_friction = body.f64(); material.dynamic_friction = body.f64();
    def.materials.push_back(std::move(material));
  }
  for (std::uint32_t i = 0; i < h.polygons; ++i) {
    v::MaterialPolygon polygon;
    polygon.id = std::string(body.id()); polygon.material_index = body.u32();
    polygon.priority = static_cast<std::uint8_t>(body.unsigned_value(1));
    const auto count = body.u32();
    // Stable input is a documented borrow precondition; nevertheless retain the
    // same bounded-count checks here before allocating a second-pass record.
    if (count < 3 || count > v::max_polygon_vertices) d::invalid();
    polygon.vertices.resize(count);
    for (auto& point : polygon.vertices) {
      point.east_mm = std::bit_cast<std::int32_t>(body.u32());
      point.south_mm = std::bit_cast<std::int32_t>(body.u32());
    }
    def.polygons.push_back(std::move(polygon));
  }
  if (!body.finished()) d::invalid();
  static_cast<void>(d::validate(def));
  return def;
}
} // namespace flight::ground::grid::payload::v1
