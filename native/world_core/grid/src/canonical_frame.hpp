#pragma once
#include <flight/contracts/geodesy.hpp>
#include <array>
#include <cmath>
#include <optional>

// Private shared operand construction only. This moves the accepted core's
// exact binary64 expression grouping/anchor-angle case without a public ABI.
// Callers check the supported FENV first; do not cache frames at preparation.
namespace flight::ground::grid::detail::canonical_frame {
namespace c=flight::contracts::v1;
using Vector=std::array<double,3>;
inline double dot(const Vector& a,const Vector& b) noexcept {return (a[0]*b[0]+a[1]*b[1])+a[2]*b[2];}
inline Vector east_at(c::GeodeticPosition p) noexcept {return {-std::sin(p.longitude_rad),std::cos(p.longitude_rad),0};}
inline Vector up_at(c::GeodeticPosition p) noexcept {
  const auto cp=std::cos(p.latitude_rad);
  return {cp*std::cos(p.longitude_rad),cp*std::sin(p.longitude_rad),std::sin(p.latitude_rad)};
}
inline Vector south_at(c::GeodeticPosition p) noexcept {
  const auto sp=std::sin(p.latitude_rad);
  return {sp*std::cos(p.longitude_rad),sp*std::sin(p.longitude_rad),-std::cos(p.latitude_rad)};
}
struct Frame {c::GeodeticPosition anchor;c::EcefPosition anchor_ecef;Vector east,up,south;};
struct Ray {Vector a,direction;};
inline std::optional<Frame> make(c::GeodeticPosition anchor) {
  const auto anchor_ecef=c::geodesy::to_ecef(anchor);if(!anchor_ecef)return std::nullopt;
  return Frame{anchor,*anchor_ecef,east_at(anchor),up_at(anchor),south_at(anchor)};
}
inline std::optional<Ray> query_ray(const Frame& frame,c::GeodeticPosition position) {
  Vector a{},direction{};
  if(position.latitude_rad==frame.anchor.latitude_rad&&position.longitude_rad==frame.anchor.longitude_rad) {
    a={0,-frame.anchor.ellipsoid_height_m,0};direction={0,1,0};
  }else {
    auto angular=position;angular.ellipsoid_height_m=0;
    const auto point=c::geodesy::to_ecef(angular);if(!point)return std::nullopt;
    const Vector displacement{point->x-frame.anchor_ecef.x,point->y-frame.anchor_ecef.y,point->z-frame.anchor_ecef.z};
    a={dot(displacement,frame.east),dot(displacement,frame.up),dot(displacement,frame.south)};
    const auto up=up_at(angular);
    direction={dot(up,frame.east),dot(up,frame.up),dot(up,frame.south)};
  }
  for(std::size_t i=0;i<3;++i)if(!std::isfinite(a[i])||!std::isfinite(direction[i]))return std::nullopt;
  return Ray{a,direction};
}
} // namespace flight::ground::grid::detail::canonical_frame
