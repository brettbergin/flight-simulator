// Original MIT. Fixed charged arena, immutable FIFO results and real worker join.
#pragma once
#include "flight/local_players/store.hpp"
#include <memory>
#include <thread>

namespace flight::local_players {
enum class ServiceState : std::uint8_t { new_service,opening,ready,closing,closed,read_only,unavailable };
struct Admission {bool accepted{};Error error{Error::none};FixedText<32> request_id{};};
struct Status {
 ServiceState state{};Error error{Error::none};std::uint8_t pending{},undelivered{};
 bool writer_alive{},has_root{},has_store_version{};FixedText<4096> resolved_root;
};
// Delivery is two-phase: successful caller-owned DTO construction precedes
// acknowledge. A failed conversion leaves the same immutable terminal queued.
struct DeliveryView {std::string_view bytes;std::uint64_t lease{};};
// Owner-thread-only borrowed capture. No caller pointer or Variant crosses into
// the worker. Service supplies its charged workspace and repeats all validation.
class AdmissionSource {
 public:
  virtual ~AdmissionSource()=default;
  // Exact outer Dictionary/String-key/String-kind/Dictionary-payload admission,
  // in the accepted precedence, without deep traversal or source mutation.
  virtual Error outer_kind(JobKind&) const noexcept=0;
  // Flat preorder root0. Every cell.flags=1; strings/keys are literal scalar-valid
  // UTF8 in text, with checked offsets. No owned buffers or validity flag. This
  // call may only fill supplied spans and return a view wholly contained in them.
  virtual Error capture(std::span<JsonCell> cells,std::span<char> text,
                        DocumentView&) const noexcept=0;
};
class Service {
 public:
  // Construct the Service itself and all native Control inside one32MiB arena.
  // Root's empty Godot wrapper keeps only its owner identity and nullable handle.
  // Null means no arena/worker/root effect; the caller remains new and may retry.
  static Service* create(StoreAccess&&) noexcept;
  // Owner only. Frees only actual closed or never-accepted/no-handle new service.
  // False preserves all storage; never frees/detaches a live/unjoined worker.
  static bool destroy(Service*) noexcept;
  // Internal SCENE teardown registry: intrusive links are arena-owned, not a
  // wrapper-side pool. Owner-preflight ALL registered services before mutation.
  // begin requests drain only; try returns true only for actual joined/quiescent
  // services. False/timeout never licenses unloading a live worker's component.
  static bool begin_shutdown_registered() noexcept;
  static bool try_join_registered() noexcept;
  Service(const Service&)=delete;Service& operator=(const Service&)=delete;
  Admission start(bool management=false) noexcept;
  Admission submit(const AdmissionSource&) noexcept;
  bool status(Status&) const noexcept;
  bool begin_shutdown() noexcept;
  bool try_join() noexcept;
  // Owner only. One outstanding BATCH of up to limit borrowed views; lifetime
  // ends on whole-batch acknowledge or abandon. Those calls consume exactly the
  // batch atomically: invalid/partial/duplicate/stale/foreign leases change none.
  // Owner-boundary poll validates actual INT1..16 before calling.
  bool peek(std::uint8_t limit,std::span<DeliveryView>,std::uint8_t& count) noexcept;
  bool acknowledge(std::span<const std::uint64_t> leases) noexcept;
  bool abandon(std::span<const std::uint64_t> leases) noexcept;
 private:
  explicit Service(std::byte* arena) noexcept;
  ~Service()=default;
  struct Control;
  std::byte* arena_{};Control* control_{};
  std::thread::id owner_;
  Service* registry_previous_{};Service* registry_next_{};bool registered_{};
  bool is_owner() const noexcept {return std::this_thread::get_id()==owner_;}
  static void work(Control*,std::byte*) noexcept;
  Admission admit(JobKind,DocumentView,std::size_t canonical_bytes) noexcept;
};
} // namespace flight::local_players
