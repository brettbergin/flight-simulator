// Original MIT. Test-only native capability and observation controller ABI.
#pragma once
#include "flight/local_players/windows_filesystem.hpp"
#include "faults/fault_plan.hpp"
#include <condition_variable>
#include <mutex>
#include <optional>
#include <thread>

namespace flight::local_players::testing {
enum class TestError : std::uint8_t {
 none,unsupported,invalid_descriptor,descriptor_hash,untrusted_prerequisite,
 path,identity,sentinel,capacity,invalid_plan,invalid_observation,overflow,
 duplicate_action,out_of_order,release,timeout,parent,unmatched_action,interrupt_unconsumed
};
class TestRootFactory;
class TrustedRoots {
 public:
  // Move only with no concurrent factory/use of either context. Existing
  // destination high-water mark is retained as well as source history.
  TrustedRoots(TrustedRoots&&) noexcept;TrustedRoots& operator=(TrustedRoots&&) noexcept;
  ~TrustedRoots();TrustedRoots(const TrustedRoots&)=delete;
  TrustedRoots& operator=(const TrustedRoots&)=delete;
  bool valid() const noexcept {return error_==TestError::none;}
  TestError error() const noexcept {return error_;}
  // No concurrent external use/move. Serializes with mint, invalidates new
  // admission, preserves mint history and failed leases for explicit retry.
  bool retire() noexcept;
 private:
  TrustedRoots() noexcept=default;
  TestError error_{TestError::untrusted_prerequisite};
  FixedText<4096> source_,parent_,product_;
  FileIdentity source_id_{},parent_id_{};
  // Fixed test-owned successful-mint ledger; never reset by disposal/move.
  mutable std::uint64_t last_successful_mint_{};
  mutable std::mutex mint_mutex_;
  void* source_handle_{};void* parent_handle_{};
  friend class TestRootFactory;
};
class Capability {
 public:
  Capability(Capability&&) noexcept;Capability& operator=(Capability&&) noexcept;
  ~Capability();Capability(const Capability&)=delete;
  Capability& operator=(const Capability&)=delete;
  bool valid() const noexcept {return error_==TestError::none&&access_.has_value();}
  TestError error() const noexcept {return error_;}
  std::string_view descriptor_sha256() const noexcept {return {digest_.data(),digest_.size()};}
  std::string_view nonce() const noexcept {return nonce_.view();}
  // Move the token into actual Service; retain this Capability's leases until
  // that Service is observed closed/joined. No auto-close/positive join here.
  std::optional<StoreAccess> take_access() noexcept;
  // Explicit POST-JOIN release; this does not inspect/invent a Service join.
  void release_leases_after_join() noexcept;
  // Actor-only checked retirement of an UNCONSUMED token. Never joins a
  // Service; refuses after take_access(), retains failed leases for retry.
  bool retire_unconsumed() noexcept;
 private:
  Capability() noexcept=default;
  TestError error_{TestError::invalid_descriptor};
  std::optional<StoreAccess> access_;
  FixedText<32> nonce_;std::array<char,64> digest_{};
  void* root_handle_{};void* parent_handle_{};void* sentinel_handle_{};
  bool access_taken_{},released_{};
  friend class TestRootFactory;
};
class TestRootFactory final {
 public:
  // Separate read-only prerequisite. Only this function resolves KnownFolder;
  // it creates no directory/store and performs no SQLite/worker operation.
  static TrustedRoots prepare_prerequisite(std::string_view trusted_source_root,
                                          std::string_view declared_proof_parent) noexcept;
  static Capability admit_bytes(std::string_view descriptor_utf8,
                                 std::string_view expected_sha256,
                                 const TrustedRoots&,QualificationObserver*,
                                 std::uint64_t service_ordinal) noexcept;
  // Ordinary bounded descriptor file, exact SHA; descriptor belongs to Root's
  // sibling evidence, OUTSIDE the selected run root. No command/path fallback.
  static Capability admit_file(std::string_view descriptor_path,
                                std::string_view expected_sha256,
                                const TrustedRoots&,QualificationObserver*,
                                std::uint64_t service_ordinal) noexcept;
};
struct ObservedEvent {
 std::uint64_t sequence{};std::uint32_t pid{};bool allocation{},admitted{};
 NativeObservation operation{};AllocationObservation charge{};
};
struct CounterState {
 bool occupied{},pending{};std::uint64_t service{},request{},occurrence{};
 JobKind kind{};Phase phase{};Scope scope{};
 bool allocation{};AllocationCategory category{};
};
struct Arrival {bool present{};std::uint32_t pid{},action_ordinal{};Selector selector{};};
// Driver owns stable plan/sites and these fixed test buffers through actual
// join. No observer record is allocated in service's32MiB arena or dropped.
class TestController final : public QualificationObserver {
 public:
  TestController(std::string_view nonce,const FaultPlan&,
                 std::span<ObservedEvent>,std::span<CounterState>) noexcept;
  ~TestController() override;
  TestController(const TestController&)=delete;TestController& operator=(const TestController&)=delete;
  void observe(const NativeObservation&) override;
  bool allow_allocation(const AllocationObservation&) override;
  bool take_sqlite_interrupt_request() noexcept override;
  Arrival wait_arrived(std::uint32_t action_ordinal,std::uint32_t timeout_ms);
  // Native owner-thread controller/actor transports a closed RELEASE record.
  // nonce/PID/action must match current ARRIVED; foreign/early/repeat rejects.
  bool release_bytes(std::string_view framed_record_payload) noexcept;
  void abort() noexcept;
  TestError error() const noexcept;
  bool finish() noexcept;
  std::size_t event_count() const noexcept;
  bool copy_event(std::size_t,ObservedEvent&) const noexcept;
  bool write_event(std::size_t,Writer&) const noexcept;
 private:
  bool append_locked(ObservedEvent&) noexcept;
  bool operation_counter_locked(const NativeObservation&) noexcept;
  bool allocation_counter_locked(const AllocationObservation&) noexcept;
  bool run_action(std::unique_lock<std::mutex>&,const Selector&);
  bool wait_parent_death(std::unique_lock<std::mutex>&);
  void fail_locked(TestError) noexcept;
  FixedText<32> nonce_;FaultPlan plan_;
  std::span<ObservedEvent> records_;std::span<CounterState> counters_;
  std::size_t used_{},next_action_{};
  std::uint32_t pid_{};void* parent_process_{};
  TestError error_{TestError::none};Arrival arrived_{};
  bool released_{},interrupt_pending_{},stopping_{};
  std::thread::id interrupt_thread_{};
  mutable std::mutex mutex_;std::condition_variable cv_;
};
} // namespace flight::local_players::testing
