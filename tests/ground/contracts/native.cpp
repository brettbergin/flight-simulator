#include <flight/ground/provider.hpp>
#include <functional>
#include <iostream>

namespace g = flight::ground::v1;
namespace c = flight::contracts::v1;
int checks = 0, failures = 0;
void check(bool value, const char* label) { ++checks; if (!value) { ++failures; std::cerr << "FAIL: " << label << '\n'; } }
template<class F> void rejects(F action, const char* label) {
  bool rejected = false; try { action(); } catch (const std::exception&) { rejected = true; } check(rejected, label);
}
class Provider final : public g::SurfaceProvider {
 public:
  mutable g::Identity metadata{{"synthetic-ground", "0.1.0-prototype", std::string(64, 'a')}, std::string(64, 'b'), 1};
  mutable std::size_t calls{};
  std::function<void(c::GroundSample&)> edit;
  bool mutate_identity{};
  bool throw_query{};
  g::Identity identity() const override { return metadata; }
  c::GroundSample sample(const g::Query& query) const override {
    ++calls;
    if (throw_query) throw std::runtime_error("Original exception fixture");
    c::GroundSample result{query.header, query.position, c::ValidGround{1000, {0, 0, -1}, .8, .6, "synthetic-pavement", metadata.world}};
    if (edit) edit(result);
    if (mutate_identity) ++metadata.generation;
    return result;
  }
};
int main() {
  const c::SampleHeader header{{9007199254740993ULL}, "ground-session"};
  const c::GeodeticPosition position{.8, -2, 1001};
  auto provider = std::make_shared<Provider>();
  g::Boundary boundary(provider, header, 2);
  const auto sample = boundary.sample(position);
  check(sample.header.tick == header.tick && sample.header.session_id == header.session_id, "All tick bits and session survive provider query");
  const auto& ground = std::get<c::ValidGround>(sample.sample);
  check(ground.surface_height_m == 1000 && ground.normal_ned.z == -1 && ground.static_friction == .8 && ground.dynamic_friction == .6,
        "Stationary ellipsoid height/upward NED normal/friction retain exact meaning");
  check(g::same(ground.world, boundary.identity().world), "Ground response bound to prepared content identity");
  (void)boundary.sample(position);
  rejects([&] { (void)boundary.sample(position); }, "Budget overflow rejected before provider callback");
  check(provider->calls == 2 && boundary.query_count() == 2, "Budget exhaustion does not invoke provider or increment count");
  for (const auto missing : {c::MissingGround::outside_coverage, c::MissingGround::not_loaded, c::MissingGround::datum_unresolved, c::MissingGround::invalid_data}) {
    auto source = std::make_shared<Provider>(); source->edit = [missing](auto& value) { value.sample = missing; };
    g::Boundary view(source, header);
    check(std::get<c::MissingGround>(view.sample(position).sample) == missing, "Missing status retained with no fabricated height/force");
  }
  const std::vector<std::function<void(c::GroundSample&)>> bad_responses{
    [](auto& s) { s.header.tick = {1}; }, [](auto& s) { s.header.session_id = "other-session"; },
    [](auto& s) { s.position.longitude_rad += 1e-8; }, [](auto& s) { s.position.ellipsoid_height_m += .001; },
    [](auto& s) { std::get<c::ValidGround>(s.sample).surface_height_m = std::numeric_limits<double>::quiet_NaN(); },
    [](auto& s) { std::get<c::ValidGround>(s.sample).normal_ned = {0, 0, -2}; },
    [](auto& s) { std::get<c::ValidGround>(s.sample).normal_ned = {0, 0, 1}; },
    [](auto& s) { std::get<c::ValidGround>(s.sample).normal_ned = {1, 0, 0}; },
    [](auto& s) { std::get<c::ValidGround>(s.sample).dynamic_friction = 1; },
    [](auto& s) { std::get<c::ValidGround>(s.sample).static_friction = -1; },
    [](auto& s) { std::get<c::ValidGround>(s.sample).world.sha256 = std::string(64, 'c'); },
    [](auto& s) { std::get<c::ValidGround>(s.sample).material_id = "Unreviewed"; },
    [](auto& s) { s.sample = static_cast<c::MissingGround>(255); }
  };
  for (const auto& edit : bad_responses) {
    auto source = std::make_shared<Provider>(); source->edit = edit; g::Boundary view(source, header);
    rejects([&] { (void)view.sample(position); }, "Malformed or mismatched response rejected before contact use");
  }
  rejects([&] { g::Boundary invalid(nullptr, header); }, "Null provider rejected");
  rejects([&] { g::Boundary invalid(provider, {{0}, "Invalid"}); }, "Invalid session rejected");
  rejects([&] { g::Boundary invalid(provider, header, 0); }, "Zero query capacity rejected");
  rejects([&] { g::Boundary invalid(provider, header, 4097); }, "Unbounded query capacity rejected");
  for (const auto& edit : std::vector<std::function<void(g::Identity&)>>{
    [](auto& id) { id.world.id = "Bad"; }, [](auto& id) { id.world.version = "latest"; },
    [](auto& id) { id.world.sha256 = std::string(64, 'A'); }, [](auto& id) { id.prepared_surface_sha256 = "unhashed"; },
    [](auto& id) { id.generation = 0; }
  }) {
    auto source = std::make_shared<Provider>(); edit(source->metadata);
    rejects([&] { g::Boundary invalid(source, header); }, "Invalid prepared identity rejected");
  }
  {
    auto source = std::make_shared<Provider>(); g::Boundary view(source, header);
    source->metadata.generation = 2;
    rejects([&] { (void)view.sample(position); }, "Provider changed between queries rejected");
    check(source->calls == 0, "Changed identity rejected before callback");
  }
  {
    auto source = std::make_shared<Provider>(); source->mutate_identity = true; g::Boundary view(source, header);
    rejects([&] { (void)view.sample(position); }, "Provider changing identity within callback rejected");
  }
  {
    auto source = std::make_shared<Provider>(); source->throw_query = true; g::Boundary view(source, header);
    rejects([&] { (void)view.sample(position); }, "Provider exception fails current boundary");
    source->throw_query = false;
    rejects([&] { (void)view.sample(position); }, "Failed boundary cannot be reused after exception disappears");
    check(view.failed() && source->calls == 1 && view.query_count() == 1, "Exception consumes bounded attempt without a second provider call");
  }
  {
    auto source = std::make_shared<Provider>(); g::Boundary view(source, header);
    auto invalid_position = position; invalid_position.latitude_rad = std::numeric_limits<double>::infinity();
    rejects([&] { (void)view.sample(invalid_position); }, "Nonfinite query rejected before callback");
    check(source->calls == 0, "Invalid query cannot trigger provider work");
    g::Boundary lifetime_view(source, header);
    std::weak_ptr<Provider> alive = source; source.reset();
    check(!alive.expired() && c::valid(lifetime_view.sample(position)), "Boundary owns provider lifetime through final query");
  }
  check(g::version("1.2.3") && g::version("0.1.0-prototype") && !g::version("1.2") && !g::version("1.2.3-") && !g::version("1.2.3+untracked"),
        "Version grammar matches existing bounded wire contract");
  std::cout << "Ground provider " << checks << " checks, " << failures << " failures\n";
  return failures ? 1 : 0;
}
