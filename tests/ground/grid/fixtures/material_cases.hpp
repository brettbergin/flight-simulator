#pragma once
#include "test_support.hpp"

// Hand corpus: tests/ground/grid/reference/material-oracles.json, source-authored
// before implementation. Exact integer rings; no polygon algorithm in these tests.
namespace grid_material_cases {
namespace t = grid_test;
namespace grid = flight::ground::grid::v1;
using Ring = std::vector<grid::PointMm>;
inline Ring cover() { return {{-800,-800},{-800,800},{800,800},{800,-800}}; }
inline Ring exclude() { return {{100,100},{100,700},{700,700},{700,100}}; }
inline Ring edge() { return {{0,-600},{0,600},{600,600},{600,-600}}; }
inline Ring vertex() { return {{0,0},{0,600},{600,600},{600,0}}; }
inline Ring concave_cover() { return {{-800,-800},{-800,800},{800,800},{800,200},{200,200},{200,-800}}; }
inline Ring notch() { return {{-800,-800},{-800,800},{800,800},{800,-800},{200,-800},{200,200},{-200,200},{-200,-800}}; }
inline Ring forward_collinear() { return {{-600,-600},{-600,0},{-600,600},{600,600},{600,-600}}; }
inline grid::MaterialPolygon polygon(std::string id, std::uint32_t material, std::uint8_t priority, Ring ring) {
  return {std::move(id), material, priority, std::move(ring)};
}
inline void set_materials(grid::Definition& definition) {
  definition.materials = {{"synthetic-default",.75,.5},{"synthetic-pavement",1,.625},{"synthetic-grass",.5,.25}};
}
inline void run() {
  struct Case { const char* label; std::vector<grid::MaterialPolygon> polygons; std::size_t selected; };
  const std::vector<Case> cases{
    {"default no polygons",{},0},
    {"excluded polygon",{polygon("outside",1,255,exclude())},0},
    {"convex cover",{polygon("pavement",1,0,cover())},1},
    {"boundary edge included",{polygon("edge",1,0,edge())},1},
    {"boundary vertex included",{polygon("vertex",2,0,vertex())},2},
    {"concave cover",{polygon("concave",2,0,concave_cover())},2},
    {"concave notch excluded",{polygon("notched",2,0,notch())},0},
    {"forward collinear accepted",{polygon("collinear",1,0,forward_collinear())},1},
    {"priority before ID",{polygon("a-low",1,0,cover()),polygon("z-high",2,255,cover())},2},
    {"ASCII tie later winner",{polygon("b-grass",2,7,cover()),polygon("a-pavement",1,7,edge())},1},
    {"ASCII tie earlier winner",{polygon("a-pavement",1,7,edge()),polygon("b-grass",2,7,cover())},1},
  };
  for (const auto& item : cases) t::section(item.label,[&] {
    auto definition=t::flat();set_materials(definition);definition.polygons=item.polygons;
    const auto expected=definition.materials[item.selected];
    const auto provider=grid::PreparedGrid::prepare(definition,t::identity());
    t::ready(*provider,{0,0,25},10,{0,0,-1},1e-10,1e-12,expected.id,expected.static_friction,expected.dynamic_friction);
  });
  struct Rejected { const char* label; Ring ring; };
  const std::vector<Rejected> rejected{
    {"positive winding",{{-600,-600},{600,-600},{600,600},{-600,600}}},
    {"negative nonzero area self-intersection",{{-600,-600},{300,-600},{-600,600},{600,600}}},
    {"adjacent collinear overlap",{{-600,-600},{-600,600},{-600,0},{600,0},{600,-600}}},
    {"duplicate nonterminal vertex",{{-600,-600},{-600,600},{600,600},{600,-600},{-600,600}}},
    {"repeated closing vertex",{{-600,-600},{-600,600},{600,600},{600,-600},{-600,-600}}},
    {"zero area",{{-600,0},{0,0},{600,0}}},
    {"point outside mm range",{{-8192001,-600},{-8192001,600},{600,600},{600,-600}}},
  };
  for(const auto& item:rejected) {
    auto definition=t::flat();definition.polygons={polygon("bad-ring",0,0,item.ring)};
    t::rejects_invalid([&]{(void)grid::PreparedGrid::prepare(definition,t::identity());},item.label);
  }
  {
    auto definition=t::flat();definition.polygons={polygon("duplicate",0,0,cover()),polygon("duplicate",0,1,edge())};
    t::rejects_invalid([&]{(void)grid::PreparedGrid::prepare(definition,t::identity());},"duplicate polygon ID");
    definition.polygons={polygon("wrong-index",1,0,cover())};
    t::rejects_invalid([&]{(void)grid::PreparedGrid::prepare(definition,t::identity());},"polygon material index");
  }
  for(const auto reason:{grid::MissingVertices::not_loaded,grid::MissingVertices::datum_unresolved,grid::MissingVertices::invalid_data}) {
    auto definition=t::flat(4,2,-3,-1);set_materials(definition);
    definition.up_m[2]=t::f32(0x7fc00000);definition.valid_words={0xfb};definition.missing_vertices=reason;
    definition.polygons={polygon("covering",1,255,cover())};
    const auto expected=reason==grid::MissingVertices::not_loaded?t::c::MissingGround::not_loaded
      :reason==grid::MissingVertices::datum_unresolved?t::c::MissingGround::datum_unresolved:t::c::MissingGround::invalid_data;
    t::missing(*grid::PreparedGrid::prepare(definition,t::identity()),expected);
  }
}
} // namespace grid_material_cases
