#pragma once
#include <flight/ground/prepared_grid.hpp>
#include <cstdint>
#include <span>

// Proposed pure byte-codec seam. No file/world/runtime admission.
namespace flight::ground::grid::payload::v1 {
inline constexpr std::uint32_t payload_version = 1;
inline constexpr std::uint64_t max_payload_bytes = 276946836;
[[nodiscard]] flight::ground::grid::v1::Definition decode(
    std::span<const std::uint8_t> bytes);
} // namespace flight::ground::grid::payload::v1
