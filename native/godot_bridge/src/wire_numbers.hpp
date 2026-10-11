#pragma once
// Original MIT. Private numeric seam; no Godot API or session dependency.
#include <cstddef>
#include <span>
#include <string>
#include <string_view>
#include <vector>

namespace flight::bridge::wire_numbers {
inline constexpr std::size_t max_tokens = 8192;
inline constexpr std::size_t max_token_bytes = 2048;
inline constexpr std::size_t max_combined_bytes = 1048576;

struct TokenResult {
  bool ok{};
  std::string error;
  // Failure always has an empty vector; the Godot adapter publishes null.
  std::vector<double> value;
};

// Whole-batch grammar/bounds, exact source-token conversion and atomic result.
// Standalone tests compile the same cpp with FLIGHT_WIRE_NUMBERS_CORE_ONLY=1.
TokenResult decode_binary64(std::span<const std::string_view> tokens);
}

namespace flight::bridge {
// Called only by the actual GDExtension SCENE initializer.
void register_wire_numbers();
}
