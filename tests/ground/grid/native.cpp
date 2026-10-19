#include "fixtures/test_support.hpp"
#include "fixtures/material_cases.hpp"
#include "fixtures/fp_environment_cases.hpp"
#include <functional>
#include <thread>

namespace t = grid_test;
namespace grid = flight::ground::grid::v1;
namespace c = flight::contracts::v1;
namespace g = flight::ground::v1;

// Frozen independent source oracles: tests/ground/grid/reference/source_oracles.json
// SHA256 55cb32169a5aa8d07d6008423939e30ae3fa027499f030c162a8e57bac67fc0e.
// Exact dyadic reference: tests/ground/grid/exact-admission/reference/expected-v1.json
// SHA256 3df724576eeada629a65a18c23c72abeb08937f7e8d5bae6c3d66d29bda32f3a.
// No production geometry/geodesy function computes expected values.
void geometry() {
  const double r2 = .707106781186547524400844362104849;
  const double r3 = .577350269189625764509148780501957;
  struct Case { const char* name; double east, south; std::array<float, 4> heights;
                double height; std::array<double, 3> normal; };
  const std::array<Case, 6> cases{{
    {"flat", -1, -1, {10,10,10,10}, 10, {0,0,-1}},
    {"east three fourths", -1, -1, {9.25f,10.75f,9.25f,10.75f}, 10, {0,-.6,-.8}},
    {"south three fourths", -1, -1, {9.25f,9.25f,10.75f,10.75f}, 10, {.6,0,-.8}},
    {"saddle exact diagonal", -1, -1, {0,2,2,0}, 0, {r3,r3,-r3}},
    {"saddle triangle0", -.5, -1.5, {0,2,2,0}, 1, {r3,r3,-r3}},
    {"saddle triangle1", -1.5, -.5, {0,2,2,0}, 1, {-r3,-r3,-r3}},
  }};
  for (const auto& item : cases) t::section(item.name, [&] {
    auto definition = t::flat();
    definition.east_origin_m = item.east; definition.south_origin_m = item.south;
    definition.up_m.assign(item.heights.begin(), item.heights.end());
    t::ready_altitudes(definition, item.height, item.normal);
  });
  auto edge = t::flat(3,2,-2,-1);
  edge.up_m = {10,10,12,10,10,12};
  t::ready_altitudes(edge,10,{0,-r2,-r2});
  auto vertex = t::flat(3,3,-2,-2);
  vertex.up_m = {10,10,12,10,10,12,10,10,12};
  t::ready_altitudes(vertex,10,{0,-r2,-r2});
  edge.east_origin_m = -2 + 0x1p-24;
  t::ready_altitudes(edge,10,{0,0,-1});
  edge.east_origin_m = -2 - 0x1p-24;
  t::ready_altitudes(edge,10 + 0x1p-24,{0,-r2,-r2});
  auto minimum = t::flat(); minimum.east_origin_m = 0;
  t::ready_altitudes(minimum,10,{0,0,-1});
  auto maximum = t::flat(); maximum.east_origin_m = -2;
  t::missing(*grid::PreparedGrid::prepare(maximum,t::identity()), c::MissingGround::outside_coverage);
  auto four = t::flat(2,2,-2,-2,grid::Spacing::metres_4);
  t::ready_altitudes(four,10,{0,0,-1});
  auto high = t::flat(); high.anchor.latitude_rad = 0x1.921fb54442d18p-1;
  t::ready_altitudes(high,10,{0,0,-1});
}

void exact_admission() {
  auto boundary = t::flat(); boundary.up_m = {0,32,0,32};
  const double r257 = .0623782861551805344936628589793326;
  t::ready_altitudes(boundary,16,{0,-16*r257,-r257});
  auto too_steep = boundary;
  too_steep.up_m[1] = too_steep.up_m[3] = t::f32(0x42000001);
  t::rejects_invalid([&] { (void)grid::PreparedGrid::prepare(too_steep,t::identity()); }, "16+2^-19 gradient rejects");
  auto former = boundary;
  former.up_m[1] = former.up_m[3] = t::f32(0x40800001);
  const double denominator = std::sqrt(87960946999297.);
  t::ready_altitudes(former,2.0000002384185791015625,{0,-8388609./denominator,-4194304./denominator});
  boundary.anchor.ellipsoid_height_m = 100;
  t::ready_altitudes(boundary,116,{0,-16*r257,-r257});
  auto exact_excess = boundary; exact_excess.up_m[0] = t::f32(0x80000001);
  // T0 norm²=256+2^-300, T1 norm²=256+2^-145+2^-300.
  t::rejects_invalid([&] { (void)grid::PreparedGrid::prepare(exact_excess,t::identity()); },
                     "subnormal exact gradient excess cannot round into acceptance");
  auto span = t::flat(513,2,-1024,0,grid::Spacing::metres_4,0);
  span.anchor.ellipsoid_height_m = 100;
  for (std::size_t row = 0; row < 2; ++row) {
    for (std::size_t i = 0; i < 512; ++i) span.up_m[row*513+i] = static_cast<float>(4*i);
    span.up_m[row*513+512] = t::f32(0x44ffff00);
  }
  t::check(span.valid_words.size() == 17 && span.valid_words.back() == 3, "1026 validity bits use16 full words plus3");
  t::ready_altitudes(span,1124,{0,-.7071067811865475244,-.7071067811865475244});
  span.up_m[0] = span.up_m[513] = t::f32(0x80000001);
  // Exact span=2048+2^-149; every facet gradient remains below16.
  t::rejects_invalid([&] { (void)grid::PreparedGrid::prepare(span,t::identity()); }, "subnormal exact span excess rejects");
}

void off_anchor() {
  for (const bool slope : {false,true}) {
    auto definition = t::flat(8193,2,-8192,-1,grid::Spacing::metres_2,0);
    if (slope) for (std::size_t row = 0; row < 2; ++row)
      for (std::size_t i = 0; i < 8193; ++i)
        definition.up_m[row*8193+i] = static_cast<float>(-8192. + 2.*static_cast<double>(i))/16.f;
    const auto provider = grid::PreparedGrid::prepare(std::move(definition),t::identity());
    for (const double altitude : {-50.,25.,1000.}) {
      if (slope) t::ready(*provider,{0,0x1p-10,altitude},392.355993578312814279,
          {0,-.0633529169771547482788,-.997991186288980078021},1e-4,1e-9);
      else t::ready(*provider,{0,0x1p-10,altitude},3.04133393022771724991,
          {0,-.000976562344779578298907,-.999999523162879692486},1e-4,1e-9);
    }
    t::missing(*provider,c::MissingGround::outside_coverage,{0,.003,25});
  }
}

void missing_and_coverage() {
  for (const auto reason : {grid::MissingVertices::not_loaded,grid::MissingVertices::datum_unresolved,grid::MissingVertices::invalid_data}) {
    const auto expected = reason == grid::MissingVertices::not_loaded ? c::MissingGround::not_loaded
      : reason == grid::MissingVertices::datum_unresolved ? c::MissingGround::datum_unresolved : c::MissingGround::invalid_data;
    const auto coverage_reason = reason == grid::MissingVertices::not_loaded ? grid::Coverage::not_loaded
      : reason == grid::MissingVertices::datum_unresolved ? grid::Coverage::datum_unresolved : grid::Coverage::invalid_data;
    auto definition = t::flat(4,2,-3,-1);
    definition.up_m = {0,0,t::f32(0x7fc00000),2,2,2,0,0};
    definition.valid_words = {0xfb}; definition.missing_vertices = reason;
    const auto provider = grid::PreparedGrid::prepare(definition,t::identity());
    t::missing(*provider,expected);
    t::check(provider->coverage({0,0,0,0}) == coverage_reason, "coverage maps supplied missing reason");
    auto converse = t::flat(3,2,-2,-1);
    converse.up_m[0] = t::f32(0x7fc00000); converse.valid_words = {0x3e}; converse.missing_vertices = reason;
    const auto valid_right = grid::PreparedGrid::prepare(converse,t::identity());
    t::ready(*valid_right,{0,0,25},10,{0,0,-1});
    auto endpoint = t::flat(3,2,-2,-1);
    endpoint.up_m[2] = endpoint.up_m[5] = t::f32(0x7fc00000);
    endpoint.valid_words = {0x1b}; endpoint.missing_vertices = reason;
    const auto cells = grid::PreparedGrid::prepare(endpoint,t::identity());
    t::check(cells->coverage({-1,-.5,-.125,.5}) == grid::Coverage::ready, "rectangle remains in valid cell");
    t::check(cells->coverage({-1,-.5,0,.5}) == coverage_reason, "closed maximum on internal edge owns next cell");
  }
  const auto flat = grid::PreparedGrid::prepare(t::flat(),t::identity());
  t::check(flat->coverage({-1,-1,-1,-1}) == grid::Coverage::ready, "coverage outer minimum included");
  t::check(flat->coverage({1,0,1,0}) == grid::Coverage::outside_coverage, "coverage outer maximum excluded");
  t::check(flat->coverage({0,0,-1,0}) == grid::Coverage::invalid_data, "reversed rectangle rejects");
  const double inf = std::numeric_limits<double>::infinity();
  t::check(flat->coverage({0,0,inf,0}) == grid::Coverage::invalid_data, "nonfinite rectangle rejects");
  const auto wide = grid::PreparedGrid::prepare(t::flat(66,66,-64,-64),t::identity());
  t::check(wide->coverage({-64,-64,63,63}) == grid::Coverage::ready, "4096 owning coverage cells admitted");
  t::check(wide->coverage({-64,-64,64,63}) == grid::Coverage::invalid_data, "4160 coverage cells exceed4096 budget");
}

void malformed_definitions() {
  using Edit = std::function<void(grid::Definition&)>;
  const std::vector<std::pair<const char*,Edit>> cases{
    {"spacing enum",[](auto& d){d.spacing=static_cast<grid::Spacing>(3);}},
    {"missing enum",[](auto& d){d.missing_vertices=static_cast<grid::MissingVertices>(255);}},
    {"short axis",[](auto& d){d.columns=1;}}, {"long axis",[](auto& d){d.rows=8194;}},
    {"height count",[](auto& d){d.up_m.pop_back();}}, {"mask count",[](auto& d){d.valid_words.clear();}},
    {"mask padding",[](auto& d){d.valid_words[0]=0x1f;}},
    {"valid NaN",[](auto& d){d.up_m[0]=t::f32(0x7fc00000);}},
    {"valid Inf",[](auto& d){d.up_m[0]=t::f32(0x7f800000);}},
    {"height upper range",[](auto& d){d.up_m[0]=t::f32(0x45800001);}},
    {"height lower range",[](auto& d){d.up_m[0]=-1001;}},
    {"all invalid",[](auto& d){d.up_m.assign(4,t::f32(0x7fc00000));d.valid_words[0]=0;}},
    {"invalid sentinel payload",[](auto& d){d.up_m[0]=t::f32(0x7fc00001);d.valid_words[0]=0xe;}},
    {"invalid finite sentinel",[](auto& d){d.valid_words[0]=0xe;}},
    {"origin quantum",[](auto& d){d.east_origin_m=.1;}},
    {"origin endpoint range",[](auto& d){d.east_origin_m=8192;}},
    {"nonfinite anchor",[](auto& d){d.anchor.latitude_rad=std::numeric_limits<double>::infinity();}},
    {"anchor altitude range",[](auto& d){d.anchor.ellipsoid_height_m=10001;}},
    {"no materials",[](auto& d){d.materials.clear();}},
    {"material default index",[](auto& d){d.default_material_index=1;}},
    {"material invalid ID",[](auto& d){d.materials[0].id="Invalid";}},
    {"duplicate material ID",[](auto& d){d.materials.push_back(d.materials[0]);}},
    {"negative friction",[](auto& d){d.materials[0].dynamic_friction=-.1;}},
    {"friction order",[](auto& d){d.materials[0].dynamic_friction=1;}},
    {"friction nonfinite",[](auto& d){d.materials[0].static_friction=std::numeric_limits<double>::quiet_NaN();}},
  };
  for (const auto& [name,edit] : cases) {
    auto definition=t::flat(); edit(definition);
    t::rejects_invalid([&]{(void)grid::PreparedGrid::prepare(definition,t::identity());},name);
  }
  for (const auto& bad_identity : {g::Identity{{"Bad","0.1.0",std::string(64,'a')},std::string(64,'b'),1},
       g::Identity{{"synthetic-grid","latest",std::string(64,'a')},std::string(64,'b'),1},
       g::Identity{{"synthetic-grid","0.1.0",std::string(64,'a')},"unhashed",1},
       g::Identity{{"synthetic-grid","0.1.0",std::string(64,'a')},std::string(64,'b'),0}})
    t::rejects_invalid([&]{(void)grid::PreparedGrid::prepare(t::flat(),bad_identity);},"invalid prepared Identity");
  const auto provider=grid::PreparedGrid::prepare(t::flat(),t::identity());
  t::rejects_invalid([&]{auto q=t::query();q.header.session_id="Invalid";(void)provider->sample(q);},"invalid query session");
  t::rejects_invalid([&]{auto q=t::query();q.position.latitude_rad=2;(void)provider->sample(q);},"invalid query latitude");
}

void materials() { grid_material_cases::run(); }
void lifetime() {
  auto definition=t::flat();
  const auto provider=grid::PreparedGrid::prepare(definition,t::identity());
  definition.up_m.assign(4,100); definition.materials[0].id="changed";
  t::ready(*provider,{0,0,-0.0},10,{0,0,-1});
  auto copied_id=provider->identity();copied_id.world.id="changed";
  t::check(g::same(provider->identity(),t::identity()),"identity return is owned copy");
  auto copied_sample=provider->sample(t::query());
  std::get<c::ValidGround>(copied_sample.sample).material_id="changed";
  t::ready(*provider,{0,0,25},10,{0,0,-1});
  auto retained=grid::PreparedGrid::prepare(t::flat(),t::identity());
  const std::weak_ptr<const grid::PreparedGrid> weak=retained;
  g::Boundary boundary(retained,t::query().header);
  retained.reset();
  t::check(!weak.expired() && c::valid(boundary.sample({0,0,25})),"Boundary retains real provider after sole caller releases it");
  std::array<bool,4> outcomes{};
  std::array<std::jthread,4> workers;
  for (std::size_t i=0;i<workers.size();++i) workers[i]=std::jthread([&,i]{
    try {
      bool ok=true;
      for(int j=0;j<16;++j) {
        const auto result=provider->sample(t::query());
        const auto* ready=std::get_if<c::ValidGround>(&result.sample);
        ok=ok && c::valid(result) && ready && ready->surface_height_m==10;
      }
      outcomes[i]=ok;
    } catch(...) {outcomes[i]=false;}
  });
  for(auto& worker:workers)worker.join();
  for(const bool ok:outcomes)t::check(ok,"independent concurrent const provider queries remain stable");
}

int main() {
  static_assert(noexcept(std::declval<const grid::PreparedGrid&>().coverage(grid::Rectangle{})));
  t::section("geometry",geometry);
  t::section("exact admission",exact_admission);
  t::section("off-anchor",off_anchor);
  t::section("missing and coverage",missing_and_coverage);
  t::section("malformed definitions",malformed_definitions);
  t::section("materials",materials);
  t::section("FP environment admission",grid_fp_cases::run);
  t::section("lifetime/concurrency",lifetime);
  return t::finish("Resident grid independent native");
}
