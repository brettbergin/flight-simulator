#pragma once
#include "analytic_surface.hpp"
#include <flight/fdm/session.hpp>

// Internal, caller-thread numerical proof seam. This is not Session/v2 or a
// supported aircraft-package interface. #20 must ratify unified low-speed intake.
namespace flight::ground::proof {
inline constexpr std::size_t fixture_bytes=2275;
inline constexpr std::string_view fixture_sha256="c546dc4791fc830e6f656b13c7a564322d51fba8f46b43da10af3d2f7ff041a1";
struct GroundControls { double steering{},left_brake{},right_brake{}; };
struct GroundInitial { double clearance_m{1.05},forward_mps{},down_mps{};bool align_to_slope{}; };
enum class StepStatus { completed, coverage_blocked, discarded };
struct ContactDiagnostics {
  std::array<double,3> compression_m{},compression_rate_mps{},static_friction{},dynamic_friction{};
  std::size_t queries{};
};
class GroundExecutive final {
 public:
  GroundExecutive(std::filesystem::path models,std::shared_ptr<const AnalyticSurface> surface,std::uint32_t hz,GroundInitial initial);
  ~GroundExecutive();
  GroundExecutive(const GroundExecutive&)=delete;GroundExecutive& operator=(const GroundExecutive&)=delete;
  StepStatus step(GroundControls controls);
  const c::AircraftSnapshot& latest() const;
  const ContactDiagnostics& diagnostics() const;
  GroundControls held() const;
  bool live() const;
 private:
  class Impl;std::unique_ptr<Impl> impl_;
};
struct RuntimeInfo {std::string loaded_library_path,version,compiler;};
RuntimeInfo runtime_info();
// Private output formatting for accepted AircraftSnapshot/v1, with contacts.
std::string snapshot_json(const c::AircraftSnapshot& snapshot);
} // namespace flight::ground::proof
