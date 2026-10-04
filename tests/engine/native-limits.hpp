#pragma once
#include <flight/interactive/session.hpp>
#include <array>
namespace piston_fixture {
struct Phase {unsigned second;flight::interactive::c::PilotAxes axes;std::array<bool,4> switches;};
inline constexpr const char* limits_sha="9b667d4b61e47e94af1eed20701119bd72d6de63e6eac28b8597ab44ae6d9feb";
inline constexpr std::array<Phase,10> phases{{
  {0,{0,0,0,0,0,1,1,0},{false,false,false,true}},
  {1,{0,0,0,0.14999999999999999,1,1,1,0},{true,true,true,true}},
  {8,{0,0,0,0.14999999999999999,1,1,1,0},{true,true,false,true}},
  {13,{0,0,0,0.34999999999999998,1,1,1,0},{true,true,false,true}},
  {17,{0,0,0,0.34999999999999998,1,1,1,0},{false,true,false,true}},
  {21,{0,0,0,0.34999999999999998,1,1,1,0},{true,false,false,true}},
  {25,{0,0,0,0.34999999999999998,1,1,1,0},{true,true,false,true}},
  {29,{0,0,0,0.14999999999999999,1,0,0,0},{true,true,false,true}},
  {39,{0,0,0,0,1,1,1,0},{true,true,false,true}},
  {51,{0,0,0,0,0,1,1,0},{true,true,false,true}},
}};
inline constexpr std::array<const char*,4> switch_ids{"engine.ignition_left","engine.ignition_right","engine.starter","fuel.feed"};
}
