#pragma once
#include <flight/interactive/surface.hpp>
#include <flight/ground/prepared_grid.hpp>
#include <filesystem>
#include <memory>
#include <optional>
#include <span>

namespace flight::interactive {
// Internal closed selection. No caller-created SurfaceProvider or pose crosses
// the bridge. Historical synthetic defaults and Config.surface stay intact.
enum class WorldChoice { original_synthetic, kawo_prototype_v1 };
struct PreparedWorldTestAccess;
class PreparedWorld final {
 public:
  class Readiness final {
   public:
    Readiness(const Readiness&)=default;
    Readiness& operator=(const Readiness&)=default;
   private:
    friend class PreparedWorld;
    friend struct PreparedWorldTestAccess;
    Readiness()=default;
    const PreparedWorld* owner_{};
    Vec center_{};
    ground::grid::v1::Rectangle rectangle_{};
  };
  ~PreparedWorld();
  PreparedWorld(const PreparedWorld&)=delete;
  PreparedWorld& operator=(const PreparedWorld&)=delete;
  std::shared_ptr<const v1::SurfaceProvider> provider() const;
  v1::Identity identity() const;
  c::GeodeticPosition anchor() const;
  c::GeodeticPosition start_position() const;
  Vec start_rpy() const;
  // The nine words follow the independently frozen actual vendor XML-unit
  // conversion, not the ideal-metre toy fixture. Actual loaded arms are checked.
  static std::array<c::BodyPosition,3> nominal_arms();
  bool bound_to(const std::filesystem::path& admitted_model_root) const;
  Vec project(c::EcefPosition) const;
  std::optional<Readiness> certify(c::EcefPosition completed_cg) const;
  bool allows(const Readiness&,c::GeodeticPosition actual_query) const noexcept;
  bool motion_within(c::EcefPosition previous,c::EcefPosition next,double limit_m) const noexcept;
 private:
  friend std::shared_ptr<const PreparedWorld> load_kawo_world(const std::filesystem::path&);
  friend struct PreparedWorldTestAccess;
  class Impl;
  explicit PreparedWorld(std::unique_ptr<const Impl>);
  std::unique_ptr<const Impl> impl_;
  struct Ray {Vec a,d;};
  static Ray ray(c::GeodeticPosition anchor,c::GeodeticPosition query);
  static ground::grid::v1::Rectangle rectangle(Vec center);
  static bool distance_within(Vec a,Vec b,double limit);
  static bool support_within(const Ray&,double minimum,double maximum,const ground::grid::v1::Rectangle&);
  static void check_json(std::string_view,std::size_t depth,std::size_t values);
  static std::string digest(std::span<const std::uint8_t>);
};
// Trusted native-only admission from a fixed sibling of the admitted model
// directory. Owns all verified bytes and immutable prepared grid through join.
std::shared_ptr<const PreparedWorld> load_kawo_world(const std::filesystem::path& admitted_model_root);
} // namespace flight::interactive
