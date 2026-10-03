#pragma once
#include "types.hpp"
#include <algorithm>

namespace flight::contracts::v1::geodesy {
// WGS84 reference ellipsoid, NGA defining constants. No geoid/MSL conversion here.
inline constexpr double semi_major_m = 6378137.0;
inline constexpr double inverse_flattening = 298.257223563;
inline constexpr double flattening = 1.0 / inverse_flattening;
inline constexpr double eccentricity_squared = flattening * (2.0 - flattening);
inline constexpr double semi_minor_m = semi_major_m * (1.0 - flattening);
inline std::optional<EcefPosition> to_ecef(GeodeticPosition p) noexcept {
  if (!valid(p)) return std::nullopt;
  const double s = std::sin(p.latitude_rad), c = std::cos(p.latitude_rad);
  const double n = semi_major_m / std::sqrt(1.0 - eccentricity_squared * s * s);
  return EcefPosition{(n + p.ellipsoid_height_m) * c * std::cos(p.longitude_rad),
    (n + p.ellipsoid_height_m) * c * std::sin(p.longitude_rad),
    (n * (1.0 - eccentricity_squared) + p.ellipsoid_height_m) * s};
}
inline std::optional<GeodeticPosition> from_ecef(EcefPosition p) noexcept {
  if (!finite(p)) return std::nullopt;
  const double radial = std::hypot(p.x, p.y);
  if (radial < 1e-9) {
    if (std::abs(p.z) < semi_minor_m - 2000) return std::nullopt;
    const GeodeticPosition result{std::copysign(pi / 2, p.z), 0, std::abs(p.z) - semi_minor_m};
    return valid(result) ? std::optional{result} : std::nullopt;
  }
  double latitude = std::atan2(p.z, radial * (1.0 - eccentricity_squared));
  for (int i = 0; i < 16; ++i) {
    const double s = std::sin(latitude), n = semi_major_m / std::sqrt(1.0 - eccentricity_squared * s * s);
    const double next = std::atan2(p.z + eccentricity_squared * n * s, radial);
    if (std::abs(next - latitude) < 1e-14) { latitude = next; break; }
    latitude = next;
  }
  const double s = std::sin(latitude), c = std::cos(latitude), n = semi_major_m / std::sqrt(1.0 - eccentricity_squared * s * s);
  // Dot along ellipsoid normal avoids height/cos(latitude) instability at poles.
  const double height = radial * c + p.z * s - n * (1.0 - eccentricity_squared * s * s);
  const GeodeticPosition result{latitude, std::atan2(p.y, p.x), height};
  return valid(result) ? std::optional{result} : std::nullopt;
}
inline std::optional<NedDisplacement> ecef_delta_to_ned(EcefPosition point, EcefPosition anchor, GeodeticPosition origin) noexcept {
  if (!finite(point) || !finite(anchor) || !valid(origin)) return std::nullopt;
  const double x = point.x - anchor.x, y = point.y - anchor.y, z = point.z - anchor.z;
  const double sp = std::sin(origin.latitude_rad), cp = std::cos(origin.latitude_rad), sl = std::sin(origin.longitude_rad), cl = std::cos(origin.longitude_rad);
  return NedDisplacement{-sp * cl * x - sp * sl * y + cp * z, -sl * x + cl * y, -cp * cl * x - cp * sl * y - sp * z};
}
} // namespace flight::contracts::v1::geodesy
