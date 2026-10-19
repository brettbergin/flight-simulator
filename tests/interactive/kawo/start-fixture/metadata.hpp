#pragma once
#include <array>
#include <cstdint>
#include <string_view>
// Fixed approved receipt transcription; not a pose or runtime world recipe.
namespace kawo_start_metadata {
inline constexpr std::uint64_t payload_bytes=25973686;
inline constexpr std::string_view payload_sha256="b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb";
inline constexpr std::uint64_t receipt_bytes=22937;
inline constexpr std::string_view receipt_sha256="cb1e0b28384aeb1c11173d991b5790a8a16e64953c2c479be6b07136c5f489f0";
inline constexpr std::array<std::uint64_t,3> anchor_words{{0x3feae5e5c184fcfdULL,0xc0010e7e83d3ed5eULL,0x0000000000000000ULL}};
inline constexpr std::array<std::uint64_t,3> end34_words{{0x406a7605675a313bULL,0x403018c6d18246bbULL,0x4084e97b3caca3caULL}};
inline constexpr std::array<std::uint64_t,3> end16_words{{0x40674099ea68006fULL,0x4034306898ca46ceULL,0xc08dddf02a91ba84ULL}};
inline constexpr std::array<std::array<std::int32_t,2>,4> footprint_mm{{{{201257,-955983}},{{170781,-955502}},{{196450,669426}},{{226926,668944}}}};
} // namespace kawo_start_metadata
