#include "validation.hpp"
#include "../../../ground/grid/codec/fixtures/literal_payloads.hpp"
#include <array>
#include <cmath>
#include <exception>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <string_view>
#include <utility>
#include <variant>

// Isolated synthetic harness controls. These are not accepted KAWO terrain.
namespace {
namespace v = kawo_validation;
int checks = 0, failures = 0;
void check(bool ok, std::string_view label) {
  ++checks;
  if (!ok) { ++failures; std::cerr << "FAIL: " << label << '\n'; }
}
template<class F> void accepted(F&& action, std::string_view label) {
  try { action(); check(true, label); }
  catch (const std::exception& error) { check(false, label); std::cerr << error.what() << '\n'; }
}
template<class F> void refused(F&& action, std::string_view label) {
  try { action(); check(false, label); }
  catch (const std::invalid_argument&) { check(true, label); }
  catch (const std::exception& error) { check(false, label); std::cerr << "wrong exception: " << error.what() << '\n'; }
}
} // namespace

int main() {
  const std::string observed(64, 'a');
  const std::array<std::string_view, 4> tokens{{"--payload", "/synthetic/not-opened.fgrd", "--observed-payload-sha256", observed}};
  accepted([&] {
    const auto args = v::arguments(tokens);
    check(args.observed_payload_sha256 == observed, "external digest preserved without native hash claim");
  }, "exact argument shape accepted without opening file");
  refused([&] { (void)v::arguments(std::span<const std::string_view>(tokens.data(), 3)); }, "missing argument refuses");
  auto changed = tokens;
  changed[2] = "--payload";
  refused([&] { (void)v::arguments(changed); }, "repeated option refuses");
  changed = tokens; changed[3] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
  refused([&] { (void)v::arguments(changed); }, "uppercase hash refuses");
  refused([&] { (void)v::read_payload("relative.fgrd"); }, "relative payload path refuses before I/O");
  refused([&] { (void)v::qualification_identity("not-a-digest"); }, "malformed qualification surface hash refuses");

  // The independent codec literal is valid generic terrain. The added KAWO
  // admission must reject it, rather than relabel any decodable grid as KAWO.
  accepted([&] {
    const auto definition = flight::ground::grid::payload::v1::decode(grid_codec_literals::golden_a);
    refused([&] { v::check_definition(definition); }, "generic codec literal is not KAWO product");
  }, "generic literal really decoded before KAWO-profile refusal");

  const auto identity = v::qualification_identity(observed);
  const v::g::Query requested{{{7}, "synthetic.kawo-harness-control"}, {0.5, -1.0, 0.0}};
  const auto good = [&] {
    return v::c::GroundSample{requested.header, requested.position,
      v::c::ValidGround{10.0, {0.0, 0.0, -1.0}, 0.8, 0.6, "original.terrain-prototype", identity.world}};
  };
  accepted([&] { v::check_sample(good(), requested, identity, 10.0); }, "independent synthetic sample baseline");
  for (const double sign : {-1.0, 1.0}) {
    auto sample = good();
    auto& ground = std::get<v::c::ValidGround>(sample.sample);
    ground.surface_height_m = 10.0 + sign * 0x1p-10;
    accepted([&] { v::check_sample(sample, requested, identity, 10.0); }, "fixed endpoint tolerance inclusive boundary");
    ground.surface_height_m = std::nextafter(ground.surface_height_m,
      sign > 0 ? std::numeric_limits<double>::infinity() : -std::numeric_limits<double>::infinity());
    refused([&] { v::check_sample(sample, requested, identity, 10.0); }, "one outward ULP beyond fixed endpoint tolerance refuses");
  }
  auto sample = good(); sample.sample = v::c::MissingGround::invalid_data;
  refused([&] { v::check_sample(sample, requested, identity, 10.0); }, "missing native ground is never height zero");
  sample = good(); sample.header.tick.value = 8;
  refused([&] { v::check_sample(sample, requested, identity, 10.0); }, "wrong query header refuses");
  sample = good(); sample.position.ellipsoid_height_m = -0.0;
  refused([&] { v::check_sample(sample, requested, identity, 10.0); }, "position echo requires signed-zero bits");
  sample = good(); std::get<v::c::ValidGround>(sample.sample).world.sha256 = std::string(64, 'b');
  refused([&] { v::check_sample(sample, requested, identity, 10.0); }, "well-shaped wrong ContentRef still refuses");
  sample = good(); std::get<v::c::ValidGround>(sample.sample).material_id = "synthetic.other-material";
  refused([&] { v::check_sample(sample, requested, identity, 10.0); }, "well-shaped unadmitted material refuses");
  sample = good(); std::get<v::c::ValidGround>(sample.sample).normal_ned.z = 1.0;
  refused([&] { v::check_sample(sample, requested, identity, 10.0); }, "unit downward normal refuses");
  sample = good(); std::get<v::c::ValidGround>(sample.sample).static_friction = std::nextafter(0.8, 1.0);
  refused([&] { v::check_sample(sample, requested, identity, 10.0); }, "one-bit coefficient change refuses");
  sample = good(); std::get<v::c::ValidGround>(sample.sample).surface_height_m = std::numeric_limits<double>::quiet_NaN();
  refused([&] { v::check_sample(sample, requested, identity, 10.0); }, "nonfinite observed native h refuses");
  refused([&] { v::check_sample(good(), requested, identity, std::numeric_limits<double>::quiet_NaN()); }, "nonfinite expected h refuses");
  std::cout << "scope=synthetic_harness_refusals_not_actual_payload_acceptance\nchecks=" << checks << "\nfailures=" << failures << '\n';
  return failures == 0 ? 0 : 1;
}
