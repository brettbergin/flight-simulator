#include <flight/ground/prepared_grid.hpp>
#include <chrono>
#include <cstdint>
#include <exception>
#include <iomanip>
#include <iostream>
#include <string>
#include <utility>
#include <variant>
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <psapi.h>
#endif

namespace {
namespace grid = flight::ground::grid::v1;
namespace ground = flight::ground::v1;
namespace contracts = flight::contracts::v1;
using Clock = std::chrono::steady_clock;
double milliseconds(Clock::time_point before, Clock::time_point after) {
  return std::chrono::duration<double, std::milli>(after - before).count();
}
void memory(const char* phase) {
#if defined(_WIN32)
  PROCESS_MEMORY_COUNTERS_EX counters{};
  counters.cb = static_cast<DWORD>(sizeof(counters));
  if (GetProcessMemoryInfo(GetCurrentProcess(), reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters), static_cast<DWORD>(sizeof(counters))) != 0) {
    std::cout << phase << ".working_set_bytes=" << static_cast<std::uint64_t>(counters.WorkingSetSize) << '\n'
              << phase << ".process_peak_working_set_bytes=" << static_cast<std::uint64_t>(counters.PeakWorkingSetSize) << '\n'
              << phase << ".private_commit_bytes=" << static_cast<std::uint64_t>(counters.PrivateUsage) << '\n';
  } else {
    std::cout << phase << ".memory=unavailable_windows_api_error_" << GetLastError() << '\n';
  }
#else
  std::cout << phase << ".memory=unavailable_on_this_platform\n";
#endif
}
} // namespace

int main() {
  try {
    constexpr std::uint32_t columns = 3073, rows = 2049;
    constexpr std::uint64_t vertices = static_cast<std::uint64_t>(columns) * rows;
    constexpr std::uint64_t words = (vertices + 63) / 64;
    constexpr std::uint32_t sample_calls = 64, coverage_calls = 1024;
    std::cout << std::setprecision(12)
              << "kind=private_synthetic_resident_grid_resource_observation\n"
              << "columns=" << columns << "\nrows=" << rows << "\nspacing_m=4\n"
              << "vertices=" << vertices << "\nvalid_words=" << words << '\n'
              << "logical_height_and_mask_bytes=" << 4 * vertices + 8 * words << '\n'
              << "allocation_count=not_instrumented\n";
    memory("baseline");

    const auto allocation_begin = Clock::now();
    grid::Definition definition;
    definition.anchor = {0, 0, 100};
    definition.east_origin_m = -6144;
    definition.south_origin_m = -4096;
    definition.spacing = grid::Spacing::metres_4;
    definition.columns = columns; definition.rows = rows;
    definition.up_m.assign(static_cast<std::size_t>(vertices), 0.0F);
    definition.valid_words.assign(static_cast<std::size_t>(words), ~std::uint64_t{0});
    if constexpr (vertices % 64 != 0) definition.valid_words.back() = (std::uint64_t{1} << (vertices % 64)) - 1;
    definition.missing_vertices = grid::MissingVertices::invalid_data;
    definition.materials.push_back({"synthetic.resource", 0.8, 0.6});
    definition.default_material_index = 0;
    const auto allocation_end = Clock::now();
    std::cout << "allocate_and_initialize_elapsed_ms=" << milliseconds(allocation_begin, allocation_end) << '\n';
    memory("allocated");

    ground::Identity identity{{"synthetic.resource-grid", "1.0.0", std::string(64, 'a')}, std::string(64, 'b'), 1};
    const auto prepare_begin = Clock::now();
    const auto prepared = grid::PreparedGrid::prepare(std::move(definition), std::move(identity));
    const auto prepare_end = Clock::now();
    std::cout << "prepare_elapsed_ms=" << milliseconds(prepare_begin, prepare_end) << '\n';
    memory("prepared");

    std::uint32_t valid_samples = 0, missing_samples = 0;
    double checksum = 0;
    const auto sample_begin = Clock::now();
    for (std::uint32_t i = 0; i < sample_calls; ++i) {
      ground::Query query;
      query.header.session_id = "synthetic-resource-observer";
      query.header.tick.value = i;
      //32 exact-anchor queries and32 actual off-anchor normal-ray queries.
      query.position.latitude_rad = (i % 2 == 0) ? 0 : 0x1p-13;
      query.position.longitude_rad = (i % 2 == 0) ? 0 : 0x1p-12;
      query.position.ellipsoid_height_m = i % 3 == 0 ? -50 : (i % 3 == 1 ? 25 : 1000);
      const auto result = prepared->sample(query);
      if (const auto* value = std::get_if<contracts::ValidGround>(&result.sample)) {
        ++valid_samples;
        checksum += value->surface_height_m + value->normal_ned.z;
      } else {
        ++missing_samples;
      }
    }
    const auto sample_end = Clock::now();
    std::cout << "sample_calls=" << sample_calls << "\nvalid_samples=" << valid_samples << "\nmissing_samples=" << missing_samples << '\n'
              << "sample_loop_elapsed_ms=" << milliseconds(sample_begin, sample_end) << '\n'
              << "sample_loop_mean_us=" << 1000 * milliseconds(sample_begin, sample_end) / sample_calls << '\n'
              << "sample_height_normal_checksum=" << checksum << '\n';

    std::uint32_t ready = 0, other = 0;
    const auto coverage_begin = Clock::now();
    for (std::uint32_t i = 0; i < coverage_calls; ++i) {
      const double east = -2048 + static_cast<double>(i % 32) * 128;
      const double south = -1024 + static_cast<double>((i / 32) % 32) * 64;
      if (prepared->coverage({east - 40, south - 40, east + 40, south + 40}) == grid::Coverage::ready) ++ready;
      else ++other;
    }
    const auto coverage_end = Clock::now();
    std::cout << "coverage_calls=" << coverage_calls << "\ncoverage_ready=" << ready << "\ncoverage_other=" << other << '\n'
              << "coverage_loop_elapsed_ms=" << milliseconds(coverage_begin, coverage_end) << '\n'
              << "coverage_loop_mean_us=" << 1000 * milliseconds(coverage_begin, coverage_end) / coverage_calls << '\n';
    memory("observed");
    std::cout << "limits=single_process_observation_not_a_realtime_or_geographic_acceptance\n"
              << "timing_scope=end_to_end_loops_including_query_construction_and_return_copies\n"
              << "memory_scope=whole_process_snapshots_and_lifetime_peak_not_owned_capacity\n";
    return valid_samples == sample_calls && ready == coverage_calls ? 0 : 1;
  } catch (const std::exception& error) {
    std::cerr << "resource_observer_failed=" << error.what() << '\n';
    return 1;
  }
}
