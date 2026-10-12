// Original MIT. Opaque provenance and observation-only native qualification seam.
#pragma once
#include "flight/local_players/records.hpp"
#include <utility>

namespace flight::local_players {
class FileSystem;
class WindowsFileSystem;
class Store;
class Service;
namespace testing { class TestRootFactory; }
enum class Origin : std::uint8_t { production, isolated_test };
enum class Phase : std::uint8_t {
 before_open,before_begin,row_write,before_commit,after_commit,rollback,postverify,
 publish_ack,checkpoint,export_create,export_write,export_flush,export_move,
 export_verify_target,recovery_copy
};
enum class Scope : std::uint8_t { service,qualification_copy,original,export_file,recovery };
enum class Edge : std::uint8_t { before,after };
enum class AllocationCategory : std::uint8_t { control,request,terminal,delivery,workspace,export_spool };
enum class FileRole : std::uint8_t { target,temp,main,wal,shm,journal };
enum class IoKind : std::uint8_t { not_applicable,read,write };
struct FileIdentity {
 std::uint64_t volume_serial{};
 std::array<std::byte,16> file_id{};
 std::uint32_t links{}; bool valid{};
 friend bool operator==(const FileIdentity&,const FileIdentity&)=default;
};
struct NativeObservation {
 Phase phase{}; Scope scope{}; Edge edge{}; JobKind kind{};
 std::uint64_t service_ordinal{},request_ordinal{},occurrence{};
 // Optional observations use explicit presence, never fabricated zero values.
 bool has_result{}; std::int32_t sqlite_result{};
 bool autocommit{}; std::uint8_t txn_state{}; std::uint16_t verified_rows{};
 std::uint8_t pending{},undelivered{};
 bool has_win32_error{}; std::uint32_t win32_error{};
 bool has_requested{},has_completed{}; std::uint32_t requested{},completed{};
 bool owned_handle{}; std::int8_t installed{-1};
 FileIdentity identity{}; std::uint32_t chunk_index{};FileRole role{};IoKind io_kind{};
};
struct AllocationObservation {
 AllocationCategory category{};std::uint64_t service_ordinal{},request_ordinal{},ordinal{};
 std::uint32_t requested{},rounded{},reserved_pages{},live_pages{};
};
struct ReservationObservation {
 enum class Action:std::uint8_t {claim,release,share,unshare} action{};
 AllocationCategory category{};std::uint64_t service_ordinal{},request_ordinal{},allocation_ordinal{};
 std::uint32_t requested{},rounded{},reserved_pages{},live_pages{};
};
// Only a separately linked test factory may install this observer. Callbacks
// cannot substitute SQL/Win32 values; the named synthetic flush exception below
// skips that operation only. Allocation refusal occurs before claims.
class QualificationObserver {
 public:
  virtual ~QualificationObserver()=default;
  virtual void observe(const NativeObservation&)=0;
  virtual bool allow_allocation(const AllocationObservation&)=0;
  // Observation AFTER the actual bounded page/credit change, never permission.
  // Called after releasing the queue mutex. Null shipping observer has no call.
  virtual void observe_reservation(const ReservationObservation&) {}
  // Test-only one-shot selected-connection request, consumed only from SQLite's
  // actual progress callback during a statement. A request is not evidence that
  // interruption occurred: the actual statement return/transaction is recorded.
  virtual bool take_sqlite_interrupt_request() noexcept {return false;}
  // Accepted isolated-test-only synthetic stage refusal. True skips only the
  // selected export flush; no OS return value is fabricated. Shipping is null.
  virtual bool take_export_flush_refusal_request() noexcept {return false;}
};
class StoreAccess {
 public:
  StoreAccess(StoreAccess&&) noexcept;
  StoreAccess& operator=(StoreAccess&&) noexcept;
  ~StoreAccess();
  StoreAccess(const StoreAccess&)=delete;
  StoreAccess& operator=(const StoreAccess&)=delete;
  bool valid() const noexcept;
  bool isolated_test() const noexcept {return valid()&&origin_==Origin::isolated_test;}
 private:
  StoreAccess() noexcept=default;
  // The platform object and root/identity data occupy charged control bytes.
  // No heap-owning platform pimpl is hidden behind this pointer.
  alignas(16) std::array<std::byte,49152> platform_{};
  FileSystem* filesystem_{};QualificationObserver* observer_{};
  Origin origin_{Origin::production};
  std::uint64_t service_ordinal_{};
  // Failed pre-arena create leaves this token unconsumed; retries retain actual
  // control/workspace attempt ordinals rather than reusing a denied ordinal.
  std::array<std::uint64_t,6> allocation_ordinals_{};
  friend class WindowsFileSystem;friend class testing::TestRootFactory;
  friend class Store;friend class Service;
};
} // namespace flight::local_players
