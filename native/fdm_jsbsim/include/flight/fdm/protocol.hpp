#pragma once
#include "session.hpp"
#include <span>
namespace flight::fdm::transport {
struct Request { SessionConfig config; std::uint64_t duration_ticks{}; std::uint32_t sample_interval_ticks{}; std::vector<c::ControlCommand> commands; };
[[nodiscard]] Request decode(std::span<const std::uint8_t> bytes, std::filesystem::path model_root);
[[nodiscard]] std::string json(const c::AircraftSnapshot& snapshot);
[[nodiscard]] std::string json(const c::AtmosphereSample& atmosphere);
[[nodiscard]] std::string json(const c::ControlCommand& command);
[[nodiscard]] std::string json(const c::OperationalEvent& event);
[[nodiscard]] std::string json(const Initialization& initialization);
[[nodiscard]] std::string json(const DiagnosticSample& diagnostics);
} // namespace flight::fdm::transport
