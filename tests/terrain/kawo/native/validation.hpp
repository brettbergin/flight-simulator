#pragma once
#include <flight/ground/grid_payload.hpp>
#include <filesystem>
#include <span>
#include <string>
#include <string_view>
#include <vector>

// Test/qualification harness only. Not a runtime world/pack or Session API.
namespace kawo_validation {
namespace c = flight::contracts::v1;
namespace g = flight::ground::v1;
namespace grid = flight::ground::grid::v1;
struct Arguments {
  std::filesystem::path payload;
  std::string observed_payload_sha256;
};
struct Observation {
  std::string designator;
  double query_height_m{}, expected_ellipsoid_height_m{};
  c::ValidGround ground;
};
struct Report {
  std::uint64_t payload_bytes{};
  g::Identity qualification_identity;
  std::vector<Observation> observations;
};
Arguments arguments(std::span<const std::string_view> values);
std::vector<std::uint8_t> read_payload(const std::filesystem::path& path);
g::Identity qualification_identity(std::string_view observed_payload_sha256);
void check_definition(const grid::Definition& definition);
void check_sample(const c::GroundSample& sample, const g::Query& requested,
                  const g::Identity& identity, double expected_ellipsoid_height_m);
Report validate(std::span<const std::uint8_t> payload, std::string_view observed_payload_sha256);
} // namespace kawo_validation
