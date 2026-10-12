// Original MIT. ADR026 owner boundary shared by shipping and isolated tests.
#pragma once
#include "flight/local_players/service.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <thread>

namespace flight::local_players::bridge {
// This small Godot-owned control is outside the native arena. It contains no
// request, receipt, path, token, collection, worker or allocation fallback.
// A test RefCounted forwards to this SAME boundary after its capability factory
// produces StoreAccess. There is no production ClassDB configuration entry.
class LocalPlayersBoundary final {
 public:
  enum class Origin : unsigned char { production, isolated_test };
  explicit LocalPlayersBoundary(Origin origin=Origin::production) noexcept;
  ~LocalPlayersBoundary();
  LocalPlayersBoundary(const LocalPlayersBoundary&)=delete;
  LocalPlayersBoundary& operator=(const LocalPlayersBoundary&)=delete;
  // Internal test-only composition seam, never bound. Consumes the token now,
  // only on successful arena allocation. No 49KiB token is retained for retry.
  bool configure_test_access(StoreAccess&&) noexcept;
  godot::Dictionary start(bool management=false);
  godot::Dictionary submit(const godot::Variant&);
  godot::Variant poll(const godot::Variant& maximum);
  godot::Variant status() const;
  bool begin_shutdown() noexcept;
  bool try_join() noexcept;
 private:
  bool owner() const noexcept;
  const std::thread::id owner_;
  Service* service_{};
  const Origin origin_;
  bool closing_{},closed_{};
};

class LocalPlayers final : public godot::RefCounted {
  GDCLASS(LocalPlayers,godot::RefCounted)
 public:
  godot::Dictionary start();
  godot::Dictionary start_management();
  godot::Dictionary submit(const godot::Variant& request);
  // Variant is intentional: ClassDB must not coerce FLOAT/bool into INT.
  godot::Variant poll(const godot::Variant& maximum=godot::Variant(std::int64_t{8}));
  godot::Variant status() const;
  bool begin_shutdown();
  bool try_join();
  // Internal pre-unload coordinator only; never a ClassDB method. False is
  // NOT permission to unload. Root must establish owner-driven joins first.
  static bool close_all() noexcept;
 protected:
  static void _bind_methods();
 private:
  LocalPlayersBoundary boundary_;
};
} // namespace flight::local_players::bridge
