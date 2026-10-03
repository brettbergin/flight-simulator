#pragma once
#include <filesystem>
#include <span>
#include <string>
#include <cstdint>
namespace flight::fdm {
// Original first-party SHA-256 implementation. No engine/parser dependency.
[[nodiscard]] std::string sha256(std::span<const std::uint8_t> bytes);
// Exact allowlisted XML byte sizes and SHA-256, before JSBSim parses any file.
// Symlinks/reparse targets outside the fixed root are rejected.
void verify_original_model(const std::filesystem::path& root);
} // namespace flight::fdm
