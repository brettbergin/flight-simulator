#pragma once
#include <array>
#include <cstdint>
#include <string_view>
// Copied from frozen pure-author stdout, never from RunIC.
namespace kawo_start_reference {
inline constexpr std::string_view payload_sha256 = "b2c53308fdc427900d84b541aff51ba66cbb71bc483fcee0ea16d067dbd15cfb";
inline constexpr std::string_view receipt_sha256 = "cb1e0b28384aeb1c11173d991b5790a8a16e64953c2c479be6b07136c5f489f0";
inline constexpr std::string_view author_output_sha256 = "1f6a464c85a9a01e5314d4eb71ba652ba00931006d89f16412ccdf5c0453b4f2";
inline constexpr std::array<std::uint64_t,3> cg_geodetic_words{0x3feae52a6390f3a0ULL,0xc0010e64ac784f63ULL,0x403193788d200000ULL};
inline constexpr std::array<std::uint64_t,3> cg_ecef_words{0xc1414f47d727068fULL,0xc14b88b2858e30dcULL,0x415209a0cb7369baULL};
inline constexpr std::array<std::uint64_t,3> cg_eus_words{0x406a4379eb0199a4ULL,0x40318c13cbdb6414ULL,0x4081c994c953fe06ULL};
inline constexpr std::array<std::uint64_t,3> rpy_words{0x3f4be2a41f12eeebULL,0x3f72315a7b2f55d3ULL,0x401911d825cb66dfULL};
inline constexpr std::array<std::uint64_t,9> body_to_ned_words{0x3feffee6e7c31fa6ULL,0x3f9023ffeff1a649ULL,0x3f7222b240351813ULL,0xbf9022f843ec2183ULL,0x3feffefab4626671ULL,0xbf4e2ce59d3cb6eaULL,0xbf7231568f9e649fULL,0x3f4be291dfe8aaafULL,0x3fefffea8df91671ULL};
inline constexpr std::array<std::array<std::uint64_t,3>,3> nominal_arm_words{{{0x4000000000687420ULL,0x0000000000000000ULL,0x3ff0000000687420ULL},{0xbff0000000687420ULL,0xbff4cccccd5496f6ULL,0x3ff0000000687420ULL},{0xbff0000000687420ULL,0x3ff4cccccd5496f6ULL,0x3ff0000000687420ULL}}};
inline constexpr std::array<std::array<std::uint64_t,3>,3> wheel_ecef_words{{{0xc1414f4747e98b62ULL,0xc14b88b199e81b57ULL,0x415209a0f1c3da02ULL},{0xc1414f48685cb7dfULL,0xc14b88b2377f001eULL,0x415209a0703d617aULL},{0xc1414f474c77e2c9ULL,0xc14b88b2e521b170ULL,0x415209a071e24e66ULL}}};
inline constexpr std::array<std::string_view,3> wheel_materials{"original.asphalt","original.asphalt","original.asphalt"};
} // namespace kawo_start_reference
