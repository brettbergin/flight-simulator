#pragma once
#include <array>
#include <cstdint>

// Original MIT mechanical transcription of independently frozen data.
// Selected reference only: not full-grid, geographic or runtime acceptance.
// Integer constants are IEEE bit patterns; no provider/producer algorithms.
namespace kawo_selected_reference_v1 {
inline constexpr char source_fixture_sha256[] = "ed63fb9a14cff9db1ab5dbd6ae0637d62591da9acfed43077f804155a7744cb2";
inline constexpr std::uint64_t source_fixture_bytes = 756727ULL;
inline constexpr char source_result_sha256[] = "ae5f2a5840d96470193b4e8d8ec586f22333ad0d06216f8fdc616d489cc1135d";
inline constexpr char source_launch_sha256[] = "807512fb65c824414390bfb188f912ce2cbcf53a26c13a2a09d0fa38f47dd88e";

struct SelectedVertex { std::uint32_t row, column, height_f32_word; };
struct Endpoint {
  const char* designator;
  std::uint64_t latitude_rad_word, longitude_rad_word;
  std::uint64_t surface_ellipsoid_height_m_word, eus_m_words[3];
};
struct RunwayRing { const char* id; std::int32_t vertices_mm[4][2]; };

// Frozen source key order (lexical row:column), deliberately not numeric sort.
inline constexpr std::array<SelectedVertex, 81> selected_vertices{{
  {0U, 0U, 0xc186b8c6U},
  {0U, 1536U, 0xc0daf5ddU},
  {0U, 3072U, 0x42320e7aU},
  {1000U, 1353U, 0x418c54f8U},
  {1000U, 1354U, 0x418caf24U},
  {1000U, 1355U, 0x418d1a95U},
  {1000U, 1356U, 0x418d2698U},
  {1024U, 0U, 0x420e971bU},
  {1024U, 1536U, 0x418a86e6U},
  {1024U, 3072U, 0x42e2a1afU},
  {1024U, 900U, 0x41693094U},
  {1024U, 901U, 0x41698c9bU},
  {1024U, 902U, 0x4169ddcdU},
  {1024U, 903U, 0x4169d103U},
  {1158U, 1565U, 0x4182a58dU},
  {1158U, 1566U, 0x41828f54U},
  {1158U, 1567U, 0x41825b19U},
  {1158U, 1568U, 0x418252feU},
  {1159U, 1565U, 0x4182af7aU},
  {1159U, 1566U, 0x41829ad4U},
  {1159U, 1567U, 0x41828539U},
  {1159U, 1568U, 0x41827eb0U},
  {1160U, 1565U, 0x41828242U},
  {1160U, 1566U, 0x41828dd3U},
  {1160U, 1567U, 0x4182ade3U},
  {1160U, 1568U, 0x4182a0ceU},
  {1161U, 1565U, 0x418219a9U},
  {1161U, 1566U, 0x41827cf0U},
  {1161U, 1567U, 0x4182b0b3U},
  {1161U, 1568U, 0x4182ab30U},
  {1190U, 1587U, 0x4180c1ddU},
  {1190U, 1588U, 0x4180d768U},
  {1190U, 1589U, 0x4180f15bU},
  {1190U, 1590U, 0x4180ff5dU},
  {1191U, 1587U, 0x4180bb21U},
  {1191U, 1588U, 0x4180d5cbU},
  {1191U, 1589U, 0x4180d962U},
  {1191U, 1590U, 0x4180cdf5U},
  {1192U, 1587U, 0x41812042U},
  {1192U, 1588U, 0x418127d3U},
  {1192U, 1589U, 0x418099a1U},
  {1192U, 1590U, 0x4181185bU},
  {1193U, 1587U, 0x41809f5eU},
  {1193U, 1588U, 0x418079bfU},
  {1193U, 1589U, 0x418025acU},
  {1193U, 1590U, 0x41811d4fU},
  {2048U, 0U, 0x43183748U},
  {2048U, 1536U, 0x40b540ccU},
  {2048U, 3072U, 0x43045c7eU},
  {783U, 1581U, 0x41a02663U},
  {783U, 1582U, 0x41a05686U},
  {783U, 1583U, 0x41a07d44U},
  {783U, 1584U, 0x41a0b4d4U},
  {784U, 1581U, 0x41a09aeeU},
  {784U, 1582U, 0x41a0faabU},
  {784U, 1583U, 0x41a0fc49U},
  {784U, 1584U, 0x41a1482bU},
  {785U, 1581U, 0x41a11c50U},
  {785U, 1582U, 0x41a158e8U},
  {785U, 1583U, 0x41a1a148U},
  {785U, 1584U, 0x41a1c4d7U},
  {786U, 1581U, 0x41a1764cU},
  {786U, 1582U, 0x41a1bbc5U},
  {786U, 1583U, 0x41a1fbd7U},
  {786U, 1584U, 0x41a1fb44U},
  {787U, 1581U, 0x41a1a9a5U},
  {787U, 1582U, 0x41a21573U},
  {787U, 1583U, 0x41a229acU},
  {787U, 1584U, 0x41a2308bU},
  {997U, 1353U, 0x418c5f05U},
  {997U, 1354U, 0x418c8d91U},
  {997U, 1355U, 0x418c9f53U},
  {997U, 1356U, 0x418cc4c2U},
  {998U, 1353U, 0x418c7342U},
  {998U, 1354U, 0x418c7adbU},
  {998U, 1355U, 0x418ca67fU},
  {998U, 1356U, 0x418cf5adU},
  {999U, 1353U, 0x418c5e57U},
  {999U, 1354U, 0x418c7141U},
  {999U, 1355U, 0x418cfd97U},
  {999U, 1356U, 0x418d4440U},
}};

inline constexpr std::array<Endpoint, 4> endpoints{{
  {"11", 0x3feae607b1b95463ULL, 0xc0010ed7d5958039ULL, 0x40319efadbb54deaULL, {0xc086b12eeae4f733ULL, 0x4031943432d4d4d0ULL, 0xc059c96b29d0b17aULL}},
  {"29", 0x3feae533926e7645ULL, 0xc0010e6f5d1e47efULL, 0x4030590bd62d295aULL, {0x405ecc29b04c4d5cULL, 0x403052daf7061e27ULL, 0x4080ea6c4e052b6dULL}},
  {"16", 0x3feae7205c6e4a93ULL, 0xc0010e67a163ca7fULL, 0x40344374340e028cULL, {0x40674099ea68006fULL, 0x4034306898ca46ceULL, 0xc08dddf02a91ba84ULL}},
  {"34", 0x3feae50979b60032ULL, 0xc0010e647ada5460ULL, 0x403022abdb29eb37ULL, {0x406a7605675a313bULL, 0x403018c6d18246bbULL, 0x4084e97b3caca3caULL}},
}};

inline constexpr std::array<RunwayRing, 2> runway_rings{{
  {"kawo.runway.11-29", {{-719239, -112253}, {-733057, -94042}, {116281, 550408}, {130099, 532197}}},
  {"kawo.runway.16-34", {{201257, -955983}, {170781, -955502}, {196450, 669426}, {226926, 668944}}},
}};
} // namespace kawo_selected_reference_v1
