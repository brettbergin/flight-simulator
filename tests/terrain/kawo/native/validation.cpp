#include "validation.hpp"
#include "reference/selected_controls_v1.hpp"
#include <array>
#include <bit>
#include <cmath>
#include <fstream>
#include <limits>
#include <stdexcept>
#include <utility>
#include <variant>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#endif

namespace kawo_validation {
namespace ref = kawo_selected_reference_v1;
namespace payload_codec = flight::ground::grid::payload::v1;
namespace {
constexpr std::uint32_t columns = 3073, rows = 2049;
constexpr std::uint64_t vertices = 6296577, valid_words = 98385;
constexpr std::uint64_t static_friction_word = 0x3fe999999999999aULL;
constexpr std::uint64_t dynamic_friction_word = 0x3fe3333333333333ULL;
void require(bool ok, std::string_view label) {
  if (!ok) throw std::invalid_argument(std::string(label));
}
std::uint64_t bits(double value) { return std::bit_cast<std::uint64_t>(value); }
bool friction(double sf, double df) {
  return bits(sf) == static_friction_word && bits(df) == dynamic_friction_word;
}
void ordinary(const std::filesystem::path& input) {
  require(input.is_absolute(), "payload path must be absolute");
#if defined(_WIN32)
  const auto& name = input.native();
  require(name.size() >= 3 && name[1] == L':' && (name[2] == L'\\' || name[2] == L'/')
          && name.find(L':', 2) == std::wstring::npos, "ordinary drive path required");
#endif
  auto cursor = input;
  while (!cursor.empty()) {
    const auto status = std::filesystem::symlink_status(cursor);
    require(!std::filesystem::is_symlink(status), "symlink payload ancestor refused");
#if defined(_WIN32)
    const DWORD attrs = GetFileAttributesW(cursor.c_str());
    require(attrs != INVALID_FILE_ATTRIBUTES && (attrs & FILE_ATTRIBUTE_REPARSE_POINT) == 0,
            "missing/reparse payload ancestor refused");
#endif
    const auto parent = cursor.parent_path();
    if (parent == cursor) break;
    cursor = parent;
  }
  require(std::filesystem::is_regular_file(input), "regular payload file required");
}
} // namespace

Arguments arguments(std::span<const std::string_view> values) {
  require(values.size() == 4 && values[0] == "--payload"
          && values[2] == "--observed-payload-sha256", "exact payload/hash arguments required");
  require(!values[1].empty() && values[1].find('\0') == std::string_view::npos,
          "nonempty payload path required");
  require(g::hash(values[3]), "external observed payload SHA256 must be lowercase hex64");
  return {std::filesystem::path(std::string(values[1])), std::string(values[3])};
}

std::vector<std::uint8_t> read_payload(const std::filesystem::path& input) {
  ordinary(input);
  const auto length = std::filesystem::file_size(input);
  require(length > 0 && length <= payload_codec::max_payload_bytes, "payload file size outside codec bound");
  std::ifstream stream(input, std::ios::binary);
  require(stream.is_open(), "cannot open payload");
  std::vector<std::uint8_t> bytes(static_cast<std::size_t>(length));
  stream.read(reinterpret_cast<char*>(bytes.data()), static_cast<std::streamsize>(bytes.size()));
  require(stream.gcount() == static_cast<std::streamsize>(bytes.size()), "payload short read");
  require(stream.peek() == std::char_traits<char>::eof() && !stream.bad(), "payload changed/trailing read");
  return bytes;
}

g::Identity qualification_identity(std::string_view observed_payload_sha256) {
  require(g::hash(observed_payload_sha256), "invalid external observed payload hash");
  // The test ContentRef names the frozen reference, never an installed WorldPackage.
  g::Identity result{{"qualification.kawo-selected-reference", "1.0.0", ref::source_fixture_sha256},
                     std::string(observed_payload_sha256), 1};
  require(g::valid(result), "invalid qualification-only identity");
  return result;
}

void check_definition(const grid::Definition& definition) {
  require(definition.columns == columns && definition.rows == rows
          && definition.spacing == grid::Spacing::metres_4, "wrong KAWO grid dimensions/spacing");
  require(bits(definition.anchor.latitude_rad) == 0x3feae5e5c184fcfdULL
          && bits(definition.anchor.longitude_rad) == 0xc0010e7e83d3ed5eULL
          && bits(definition.anchor.ellipsoid_height_m) == 0, "wrong fixed anchor bits");
  require(definition.east_origin_m == -6144 && definition.south_origin_m == -4096,
          "wrong fixed grid origins");
  require(definition.up_m.size() == vertices && definition.valid_words.size() == valid_words,
          "wrong full-grid buffer counts");
  require(definition.missing_vertices == grid::MissingVertices::invalid_data,
          "wrong compiler missing-vertex policy");
  for (std::size_t i = 0; i < definition.valid_words.size(); ++i) {
    const auto expected = i + 1 == definition.valid_words.size() ? std::uint64_t{1}
                                                               : ~std::uint64_t{0};
    require(definition.valid_words[i] == expected, "compiler grid is not all-valid with zero padding");
  }
  require(definition.materials.size() == 2 && definition.default_material_index == 0,
          "wrong compiler material roster/default");
  const std::array<std::string_view, 2> material_ids{{"original.terrain-prototype", "original.asphalt"}};
  for (std::size_t i = 0; i < material_ids.size(); ++i)
    require(definition.materials[i].id == material_ids[i]
            && friction(definition.materials[i].static_friction, definition.materials[i].dynamic_friction),
            "wrong original material identity/friction bits");
  require(definition.polygons.size() == ref::runway_rings.size(), "wrong runway polygon count");
  for (std::size_t i = 0; i < ref::runway_rings.size(); ++i) {
    const auto& polygon = definition.polygons[i];
    const auto& expected = ref::runway_rings[i];
    require(polygon.id == expected.id && polygon.priority == 100 && polygon.material_index == 1
            && polygon.vertices.size() == 4, "wrong ordered runway polygon profile");
    for (std::size_t j = 0; j < 4; ++j)
      require(polygon.vertices[j].east_mm == expected.vertices_mm[j][0]
              && polygon.vertices[j].south_mm == expected.vertices_mm[j][1],
              "runway mm ring differs from independent reference");
  }
  for (const auto& selected : ref::selected_vertices) {
    const auto index = static_cast<std::size_t>(selected.row) * columns + selected.column;
    require(index < definition.up_m.size()
            && std::bit_cast<std::uint32_t>(definition.up_m[index]) == selected.height_f32_word,
            "selected final Float32 word differs from independent reference");
  }
}

void check_sample(const c::GroundSample& sample, const g::Query& requested,
                  const g::Identity& identity, double expected_ellipsoid_height_m) {
  require(g::valid(identity) && c::valid(requested.position)
          && c::stable_id(requested.header.session_id), "invalid qualification query/identity");
  require(c::valid(sample), "invalid native GroundSample");
  require(sample.header.tick == requested.header.tick
          && sample.header.session_id == requested.header.session_id, "native header mismatch");
  require(bits(sample.position.latitude_rad) == bits(requested.position.latitude_rad)
          && bits(sample.position.longitude_rad) == bits(requested.position.longitude_rad)
          && bits(sample.position.ellipsoid_height_m) == bits(requested.position.ellipsoid_height_m),
          "native query position bit mismatch");
  const auto* ground = std::get_if<c::ValidGround>(&sample.sample);
  require(ground != nullptr, "native endpoint returned missing ground");
  require(g::same(ground->world, identity.world), "native qualification ContentRef mismatch");
  require(ground->normal_ned.z < 0, "native normal is not upward");
  require((ground->material_id == "original.terrain-prototype" || ground->material_id == "original.asphalt")
          && friction(ground->static_friction, ground->dynamic_friction), "native material/friction mismatch");
  require(std::isfinite(expected_ellipsoid_height_m)
          && std::abs(ground->surface_height_m - expected_ellipsoid_height_m) <= 0x1p-10,
          "native endpoint ellipsoid h exceeds fixed 1/1024m tolerance");
}

Report validate(std::span<const std::uint8_t> payload, std::string_view observed_payload_sha256) {
  Report report{static_cast<std::uint64_t>(payload.size()), qualification_identity(observed_payload_sha256), {}};
  auto definition = payload_codec::decode(payload);
  check_definition(definition);
  const auto prepared = grid::PreparedGrid::prepare(std::move(definition), report.qualification_identity);
  require(g::same(prepared->identity(), report.qualification_identity), "prepared identity mismatch");
  const c::SampleHeader header{{0}, "qualification.kawo-native-validation"};
  g::Boundary boundary(prepared, header, 8);
  report.observations.reserve(8);
  for (const auto& endpoint : ref::endpoints) {
    const double latitude = std::bit_cast<double>(endpoint.latitude_rad_word);
    const double longitude = std::bit_cast<double>(endpoint.longitude_rad_word);
    const double expected = std::bit_cast<double>(endpoint.surface_ellipsoid_height_m_word);
    c::ValidGround first_ground;
    for (const double altitude : {0.0, 1000.0}) {
      const c::GeodeticPosition position{latitude, longitude, altitude};
      const g::Query query{header, position};
      const auto sample = boundary.sample(position);
      check_sample(sample, query, report.qualification_identity, expected);
      const auto& ground = std::get<c::ValidGround>(sample.sample);
      if (altitude == 0) first_ground = ground;
      else require(bits(ground.surface_height_m) == bits(first_ground.surface_height_m)
                   && bits(ground.normal_ned.x) == bits(first_ground.normal_ned.x)
                   && bits(ground.normal_ned.y) == bits(first_ground.normal_ned.y)
                   && bits(ground.normal_ned.z) == bits(first_ground.normal_ned.z)
                   && ground.material_id == first_ground.material_id,
                   "native surface geometry/material depends on query altitude");
      report.observations.push_back({endpoint.designator, altitude, expected, ground});
    }
  }
  require(!boundary.failed() && boundary.query_count() == 8
          && g::same(prepared->identity(), report.qualification_identity), "native boundary/identity retirement mismatch");
  return report;
}
} // namespace kawo_validation
