#pragma once
#include <flight/fdm/protocol.hpp>
#include <array>
#include <variant>

// Private P1 experiment, not a supported product save format or public contract.
namespace flight::reconstruction::proof {
namespace c = contracts::v1;
namespace f = fdm;
using Bytes = std::vector<std::uint8_t>;
// Host computes actual executable/library, contract set, adapter source, model,
// compiler and library version identity. The host is trusted; packets are not.
using Identity = std::array<std::string, 7>;
struct Registration { std::string source_id; c::Authority authority; };
using Input = std::variant<Registration, c::ControlCommand, c::SessionControl>;
struct Admission { c::Tick received_after_tick; Input input; };
struct Recipe {
  Identity identity;
  Bytes initial_request;
  c::Tick checkpoint_tick;
  std::vector<Admission> admissions;
};
[[nodiscard]] Bytes read_bounded(const std::filesystem::path& path);
void write_checked(const std::filesystem::path& path, std::span<const std::uint8_t> bytes);
[[nodiscard]] Identity read_identity(std::span<const std::uint8_t> bytes);
[[nodiscard]] Bytes encode(const Recipe& recipe);
// Integrity and exact expected identity checked BEFORE model parse or stepping.
[[nodiscard]] Recipe decode(std::span<const std::uint8_t> bytes, const Identity& expected);
[[nodiscard]] f::SessionConfig configuration(const Recipe& recipe, const std::filesystem::path& model_root);
void admit(f::Session& session, const Admission& input);
void validate(const Recipe& recipe);
} // namespace flight::reconstruction::proof
