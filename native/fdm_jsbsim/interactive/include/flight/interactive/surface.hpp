#pragma once
#include <flight/ground/provider.hpp>
#include <flight/fdm/model.hpp>
#include <bit>

// Internal numerical proof support, not a new public terrain/archive contract.
namespace flight::interactive {
namespace c = contracts::v1;
namespace v1 = flight::ground::v1;
using Vec = std::array<double, 3>;
inline double dot(Vec a, Vec b) { return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]; }
inline Vec add(Vec a, Vec b) { return {a[0]+b[0],a[1]+b[1],a[2]+b[2]}; }
inline Vec scale(Vec a,double s) { return {a[0]*s,a[1]*s,a[2]*s}; }
inline Vec subtract(Vec a,Vec b) { return add(a,scale(b,-1)); }
inline Vec vector(c::EcefPosition p) { return {p.x,p.y,p.z}; }
struct Basis {
  Vec north,east,up;
  explicit Basis(c::GeodeticPosition p) {
    const double sp=std::sin(p.latitude_rad),cp=std::cos(p.latitude_rad),sl=std::sin(p.longitude_rad),cl=std::cos(p.longitude_rad);
    north={-sp*cl,-sp*sl,cp};east={-sl,cl,0};up={cp*cl,cp*sl,sp};
  }
  Vec ned_to_ecef(c::NedNormal n) const { return add(add(scale(north,n.x),scale(east,n.y)),scale(up,-n.z)); }
  c::NedNormal ecef_to_ned(Vec n) const { return {dot(n,north),dot(n,east),-dot(n,up)}; }
};
struct SurfaceConfig {
  c::GeodeticPosition anchor{.8,-2,0};
  double slope_north{},slope_east{};
  double north_min{-20000},north_max{20000},east_min{-20000},east_max{20000};
  double seam_north{20};bool second_tile_loaded{true};
  double static_friction{.8},dynamic_friction{.6};
};
// Original prepared-data identity: version1 prefix, explicit little-endian
// binary64 in the declared field order, followed by one loaded-tile byte.
// No struct padding, locale, decimal serialization or scene identity enters it.
inline v1::Identity prepared_identity(const SurfaceConfig& config) {
  std::vector<std::uint8_t> bytes{'i','n','t','e','r','a','c','t','i','v','e','-','p','l','a','n','e','-','v','1',0};
  for(const auto value:{config.anchor.latitude_rad,config.anchor.longitude_rad,config.anchor.ellipsoid_height_m,
      config.slope_north,config.slope_east,config.north_min,config.north_max,config.east_min,config.east_max,
      config.seam_north,config.static_friction,config.dynamic_friction}) {
    const auto bits=std::bit_cast<std::uint64_t>(value);for(unsigned shift=0;shift<64;shift+=8){bytes.push_back(static_cast<std::uint8_t>(bits>>shift));}
  }
  bytes.push_back(config.second_tile_loaded?1:0);const auto digest=fdm::sha256(bytes);
  return {{"original.interactive-plane","1.0.0",digest},digest,1};
}
class AnalyticSurface : public v1::SurfaceProvider {
 public:
  AnalyticSurface(SurfaceConfig config,v1::Identity identity):config_(config),identity_(std::move(identity)),basis_(config.anchor) {
    if(!c::valid(config.anchor)||!v1::valid(identity_)||!v1::same(identity_,prepared_identity(config))||!std::isfinite(config.slope_north)||!std::isfinite(config.slope_east)||
       std::hypot(config.slope_north,config.slope_east)>.1||!std::isfinite(config.north_min)||!std::isfinite(config.north_max)||
       !std::isfinite(config.east_min)||!std::isfinite(config.east_max)||config.north_min>=config.north_max||config.east_min>=config.east_max||
       !std::isfinite(config.seam_north)||config.seam_north<=config.north_min||config.seam_north>=config.north_max||
       !std::isfinite(config.static_friction)||config.static_friction<0||config.static_friction>5||
       !std::isfinite(config.dynamic_friction)||config.dynamic_friction<0||config.dynamic_friction>config.static_friction)
      {throw std::invalid_argument("Invalid analytic proof surface");}
    anchor_=vector(*c::geodesy::to_ecef(config.anchor));
    normal_=add(add(basis_.up,scale(basis_.north,-config.slope_north)),scale(basis_.east,-config.slope_east));
    normal_=scale(normal_,1/std::sqrt(dot(normal_,normal_)));
  }
  v1::Identity identity() const override { return identity_; }
  c::GroundSample sample(const v1::Query& query) const override {
    if(!c::valid(query.position)){throw std::invalid_argument("Invalid proof surface position");}
    const auto local=coordinates(*c::geodesy::to_ecef(query.position));
    if(local.x<config_.north_min||local.x>config_.north_max||local.y<config_.east_min||local.y>config_.east_max)
      {return {query.header,query.position,c::MissingGround::outside_coverage};}
    if(!config_.second_tile_loaded&&local.x>=config_.seam_north){return {query.header,query.position,c::MissingGround::not_loaded};}
    auto base=query.position;base.ellipsoid_height_m=0;
    const auto radial=Basis(query.position).up;const double denominator=dot(normal_,radial);
    if(denominator<.9){throw std::invalid_argument("Unsupported plane-ray angle");}
    const double height=dot(normal_,subtract(anchor_,vector(*c::geodesy::to_ecef(base))))/denominator;
    return {query.header,query.position,c::ValidGround{height,Basis(query.position).ecef_to_ned(normal_),config_.static_friction,config_.dynamic_friction,"original.asphalt",identity_.world}};
  }
  c::NedDisplacement coordinates(c::EcefPosition p) const {
    const auto delta=subtract(vector(p),anchor_);return {dot(delta,basis_.north),dot(delta,basis_.east),-dot(delta,basis_.up)};
  }
  // Convex loaded coverage certificate for this immutable, congruent two-tile plane.
  // This is stronger than point sampling and is deliberately not generalized to arbitrary providers.
  bool covers(c::EcefPosition center,double radius_m) const {
    if(!c::finite(center)||!std::isfinite(radius_m)||radius_m<0){return false;}
    const auto p=coordinates(center);const double upper=config_.second_tile_loaded?config_.north_max:config_.seam_north;
    return p.x-radius_m>config_.north_min&&p.x+radius_m<upper&&p.y-radius_m>config_.east_min&&p.y+radius_m<config_.east_max;
  }
  const SurfaceConfig& config() const { return config_; }
  Vec normal_ecef() const { return normal_; }
 protected:
  SurfaceConfig config_;v1::Identity identity_;Basis basis_;Vec anchor_,normal_;
};
} // namespace flight::interactive
