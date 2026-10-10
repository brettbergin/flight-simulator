#pragma once
#include <flight/interactive/session.hpp>
#include <models/propulsion/FGPropeller.h>

namespace piston_test_selection {
#if defined(FLIGHT_PISTON_TEST_COUPLED_MIDPOINT) && FLIGHT_PISTON_TEST_COUPLED_MIDPOINT
inline constexpr const char* name = "event_aware_coupled_midpoint_v1";
inline constexpr auto session = flight::interactive::AngularMethod::event_aware_coupled_midpoint_v1;
inline constexpr auto vendor = JSBSim::FGPropeller::AngularIntegrationMethod::event_aware_coupled_midpoint_v1;
#else
inline constexpr const char* name = "event_aware_constant_power_v1";
inline constexpr auto session = flight::interactive::AngularMethod::event_aware_constant_power_v1;
inline constexpr auto vendor = JSBSim::FGPropeller::AngularIntegrationMethod::event_aware_constant_power_v1;
#endif
}
