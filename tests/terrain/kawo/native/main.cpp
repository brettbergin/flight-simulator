#include "validation.hpp"
#include "reference/selected_controls_v1.hpp"
#include <array>
#include <bit>
#include <exception>
#include <iomanip>
#include <iostream>
#include <stdexcept>
#include <string_view>

int main(int argc, char** argv) {
  try {
    if (argc != 5) throw std::invalid_argument("usage: kawo_payload_validator --payload ABSOLUTE_FILE --observed-payload-sha256 LOWERHEX64");
    const std::array<std::string_view, 4> tokens{{argv[1], argv[2], argv[3], argv[4]}};
    const auto args = kawo_validation::arguments(tokens);
    const auto bytes = kawo_validation::read_payload(args.payload);
    const auto report = kawo_validation::validate(bytes, args.observed_payload_sha256);
    std::cout << std::setprecision(17)
              << "kind=kawo_standalone_native_payload_qualification\n"
              << "passed=true\ncompiler_product_acceptance=false\nworld_runtime_admission=false\n"
              << "identity_scope=qualification_only_not_installed_world_package\n"
              << "observed_payload_sha256_source=external_root_driver_not_native_computation\n"
              << "observed_payload_sha256=" << args.observed_payload_sha256 << '\n'
              << "payload_bytes=" << report.payload_bytes << '\n'
              << "source_fixture_sha256=" << kawo_selected_reference_v1::source_fixture_sha256 << '\n'
              << "source_result_sha256=" << kawo_selected_reference_v1::source_result_sha256 << '\n'
              << "qualification_content_id=" << report.qualification_identity.world.id << '\n'
              << "qualification_content_sha256=" << report.qualification_identity.world.sha256 << '\n'
              << "selected_word_checks=81\nrunway_ring_checks=2\nendpoint_queries=" << report.observations.size() << '\n';
    for (const auto& row : report.observations) {
      const std::string prefix = "end." + row.designator + (row.query_height_m == 0 ? ".at0m." : ".at1000m.");
      std::cout << prefix << "surface_ellipsoid_h_m=" << row.ground.surface_height_m << '\n'
                << prefix << "expected_ellipsoid_h_m=" << row.expected_ellipsoid_height_m << '\n'
                << prefix << "signed_error_m=" << row.ground.surface_height_m - row.expected_ellipsoid_height_m << '\n'
                << prefix << "surface_h_word=" << std::hex << std::setw(16) << std::setfill('0')
                << std::bit_cast<std::uint64_t>(row.ground.surface_height_m) << std::dec << std::setfill(' ') << '\n'
                << prefix << "normal_ned=" << row.ground.normal_ned.x << ',' << row.ground.normal_ned.y << ',' << row.ground.normal_ned.z << '\n'
                << prefix << "material_id=" << row.ground.material_id << '\n';
    }
    std::cout << "limits=actual_native_decode_prepare_and_selected_four_end_correspondence_only_no_source_accuracy_or_flight\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "kawo_native_validation_failed=" << error.what() << '\n';
    return 1;
  }
}
