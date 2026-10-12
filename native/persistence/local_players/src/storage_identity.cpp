#include "flight/local_players/storage_identity.hpp"

#ifndef FLIGHT_LOCAL_PLAYERS_COMPONENT_SHA256
#error "Reviewed local-player component identity must be generated before build"
#endif
#ifndef FLIGHT_LOCAL_PLAYERS_BUILD_CONTROL_SHA256
#error "Reviewed local-player build-control identity must be generated before build"
#endif
#ifndef FLIGHT_LOCAL_PLAYERS_CONTRACT_SHA256
#error "Reviewed local-player contract identity must be generated before build"
#endif

namespace flight::local_players {
namespace {

// Original MIT. Syntax checks supplement independent source/build qualification;
// the compiled values are never used to manufacture their own expected identity.
constexpr bool lower_sha256(std::string_view value) noexcept {
    if (value.size() != 64) return false;
    for (const char digit : value) {
        if (!((digit >= '0' && digit <= '9') || (digit >= 'a' && digit <= 'f'))) {
            return false;
        }
    }
    return true;
}

constexpr std::string_view component{FLIGHT_LOCAL_PLAYERS_COMPONENT_SHA256};
constexpr std::string_view controls{FLIGHT_LOCAL_PLAYERS_BUILD_CONTROL_SHA256};
constexpr std::string_view contracts{FLIGHT_LOCAL_PLAYERS_CONTRACT_SHA256};
static_assert(lower_sha256(component), "Invalid component fingerprint");
static_assert(lower_sha256(controls), "Invalid build-control fingerprint");
static_assert(lower_sha256(contracts), "Invalid contract fingerprint");

} // namespace

StorageIdentity storage_identity() noexcept {
    return {"flight-local-players-component-v1", component, controls, contracts};
}

} // namespace flight::local_players
