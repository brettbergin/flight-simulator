#pragma once
#include <flight/contracts/boundaries.hpp>
#include <memory>

namespace flight::ground::v1 {
namespace c = contracts::v1;
inline constexpr std::uint32_t provider_api_version = 1;
// In-process API only: no new wire schema or change to GroundSample/v1.
struct Identity {
  c::ContentRef world;
  std::string prepared_surface_sha256;
  std::uint64_t generation{1};
};
inline bool same(const c::ContentRef& a, const c::ContentRef& b) noexcept {
  return a.id == b.id && a.version == b.version && a.sha256 == b.sha256;
}
inline bool same(const Identity& a, const Identity& b) noexcept {
  return same(a.world, b.world) && a.prepared_surface_sha256 == b.prepared_surface_sha256 && a.generation == b.generation;
}
inline bool hash(std::string_view value) noexcept {
  if (value.size() != 64) return false;
  for (const char ch : value) if (!((ch >= '0' && ch <= '9') || (ch >= 'a' && ch <= 'f'))) return false;
  return true;
}
// Same bounded version grammar as the existing wire ContentRef.
inline bool version(std::string_view value) noexcept {
  if (value.empty() || value.size() > 64) return false;
  std::size_t offset = 0;
  for (int component = 0; component < 3; ++component) {
    const auto start = offset;
    while (offset < value.size() && value[offset] >= '0' && value[offset] <= '9') ++offset;
    if (offset == start) return false;
    if (component < 2 && (offset == value.size() || value[offset++] != '.')) return false;
  }
  if (offset == value.size()) return true;
  if (value[offset++] != '-' || offset == value.size()) return false;
  for (; offset < value.size(); ++offset) {
    const char ch = value[offset];
    if (!((ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '.' || ch == '-')) return false;
  }
  return true;
}
inline bool valid(const Identity& identity) noexcept {
  return c::stable_id(identity.world.id) && version(identity.world.version) && hash(identity.world.sha256) &&
    hash(identity.prepared_surface_sha256) && identity.generation != 0;
}
struct Query { c::SampleHeader header; c::GeodeticPosition position; };
// Height fields only, stationary relative to Earth/ECEF. No moving decks,
// vertical walls, overhangs, engine pointers, I/O or hidden worker at this seam.
class SurfaceProvider {
 public:
  virtual ~SurfaceProvider() = default;
  [[nodiscard]] virtual Identity identity() const = 0;
  [[nodiscard]] virtual c::GroundSample sample(const Query& query) const = 0;
};
// A caller-thread owned boundary keeps the immutable provider alive. It does not
// step physics; every sample is checked before a consumer can use its forces.
class Boundary final {
 public:
  Boundary(std::shared_ptr<const SurfaceProvider> provider, c::SampleHeader target, std::size_t query_limit = 256)
      : provider_(std::move(provider)), target_(std::move(target)), query_limit_(query_limit) {
    if (!provider_ || !c::stable_id(target_.session_id) || query_limit_ == 0 || query_limit_ > 4096)
      throw std::invalid_argument("Invalid ground boundary configuration");
    identity_ = provider_->identity();
    if (!valid(identity_)) throw std::invalid_argument("Invalid prepared ground identity");
  }
  [[nodiscard]] const Identity& identity() const noexcept { return identity_; }
  [[nodiscard]] std::size_t query_count() const noexcept { return query_count_; }
  [[nodiscard]] bool failed() const noexcept { return failed_; }
  [[nodiscard]] c::GroundSample sample(c::GeodeticPosition position) {
    if (failed_) throw std::invalid_argument("Failed ground boundary cannot be reused");
    failed_ = true; // Exceptions/invalid responses poison this boundary, including identity exceptions.
    if (!c::valid(position) || query_count_ == query_limit_ || !same(identity_, provider_->identity()))
      throw std::invalid_argument("Invalid/out-of-budget/changed ground query");
    ++query_count_;
    const Query query{target_, position};
    auto result = provider_->sample(query);
    if (!same(identity_, provider_->identity()) || !c::valid(result) || result.header.tick != target_.tick ||
        result.header.session_id != target_.session_id || result.position.latitude_rad != position.latitude_rad ||
        result.position.longitude_rad != position.longitude_rad || result.position.ellipsoid_height_m != position.ellipsoid_height_m)
      throw std::invalid_argument("Ground response identity/location/boundary mismatch");
    if (const auto* ground = std::get_if<c::ValidGround>(&result.sample)) {
      if (!same(ground->world, identity_.world) || ground->normal_ned.z >= 0)
        throw std::invalid_argument("Wrong world or unsupported non-height-field ground normal");
    } else if (static_cast<unsigned>(std::get<c::MissingGround>(result.sample)) > static_cast<unsigned>(c::MissingGround::invalid_data)) {
      throw std::invalid_argument("Unknown missing-ground status");
    }
    failed_ = false;
    return result;
  }
 private:
  std::shared_ptr<const SurfaceProvider> provider_;
  c::SampleHeader target_;
  Identity identity_;
  std::size_t query_limit_, query_count_{};
  bool failed_{};
};
} // namespace flight::ground::v1
