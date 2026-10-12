#pragma once

#include <string_view>

namespace flight::local_players {

// Original MIT. Views refer only to immutable compiled literals.
// Reading this value never opens a root, database, thread or Godot object.
struct StorageIdentity final {
    std::string_view schema;
    std::string_view component_fingerprint;
    std::string_view build_control_sha256;
    std::string_view contract_sha256;
};

[[nodiscard]] StorageIdentity storage_identity() noexcept;

} // namespace flight::local_players
