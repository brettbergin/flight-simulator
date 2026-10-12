// Original MIT. Finite owned native IO; paths never establish store authority.
#pragma once
#include "flight/local_players/store_access.hpp"

namespace flight::local_players {
enum class StoreFile : std::uint8_t { main,wal,shm,journal };
inline constexpr std::string_view store_file_names[]={"players.sqlite3","players.sqlite3-wal","players.sqlite3-shm","players.sqlite3-journal"};
inline constexpr std::uint64_t store_file_caps[]={268435456,67108864,8388608,8388608};
struct FileInfo {bool present{};std::uint64_t bytes{};FileIdentity identity{};};
struct FileSet {std::array<FileInfo,4> files{};};
struct RecoverySet {
 FixedText<32> id;FixedText<20> created_utc;
 FixedText<4096> retained_root,work_root;
 FileSet source{};std::array<std::array<char,64>,4> hashes{};bool complete{};
};
struct ExportReceipt {
 FixedText<32> operation_id;FixedText<4096> target,temporary;
 enum class Outcome : std::uint8_t { saved,not_saved,recovery_required } outcome{Outcome::not_saved};
 enum class Step : std::uint8_t { read,encode,create,write,flush,verify_temp,move,verify_target,done } phase{Step::read};
 std::int8_t installed{0};bool has_bytes_hash{};std::uint64_t bytes{};
 std::array<char,64> sha256{};
 bool has_snapshot{};FixedText<32> player_id;U64 preferences_revision{};std::uint16_t practice_count{};
};
struct RecoverySummary {
 FixedText<32> id;FixedText<20> created_utc;
 bool complete{},has_utc{},has_manifest_hash{};
 std::uint64_t bytes{};std::array<char,64> manifest_hash{};
};
struct NativeContext {
 QualificationObserver* observer{};
 std::uint64_t service{},request{};JobKind kind{};
 // Shared before/after occurrence per actual call. Array indexes are phase*5+scope.
 std::array<std::uint64_t,75>* occurrences{};
 // Borrowed from the immutable charged RequestHeader, valid through this job.
 std::string_view request_id{};
 std::uint64_t next(Phase,Scope) noexcept;
 void event(NativeObservation) const;
};
// Internal sole-worker scope. TLS retains only a borrowed scalar pointer; every
// variable temporary is placement-owned by the supplied charged96KiB region.
class NativeOperationScope {
 public:
  NativeOperationScope(NativeContext&,std::span<char>,class FileSystem&) noexcept;
  ~NativeOperationScope();
  NativeOperationScope(const NativeOperationScope&)=delete;
  static NativeOperationScope* current() noexcept;
  void* push(std::size_t bytes,std::size_t alignment);
  std::size_t mark() const noexcept {return used_;}
  void pop(std::size_t mark) noexcept;
  NativeContext& context() const noexcept {return *context_;}
  class FileSystem& filesystem() const noexcept {return *filesystem_;}
 private:
  NativeOperationScope* previous_{};NativeContext* context_{};
  class FileSystem* filesystem_{};std::span<char> storage_;std::size_t used_{};
};
class FileSystem {
 public:
  virtual ~FileSystem()=default;
  virtual FileSystem* relocate(void* charged_storage) noexcept=0;
  // Called only by the sole worker after accepted start. Lock remains owned by
  // this object through actual join; close_worker_handles never releases it.
  virtual Error acquire_root(bool management,NativeContext&)=0;
  virtual std::string_view root() const noexcept=0;
  virtual Error random_id(FixedText<32>&) noexcept=0;
  virtual Error utc(FixedText<20>&) noexcept=0;
  virtual std::string_view owner_run_id() const noexcept=0;
  virtual Error inspect_sources(FileSet&)=0;
  virtual Error snapshot(const FileSet&,RecoverySet&,std::span<std::byte> io,
                         CodecWorkspace,NativeContext&)=0;
  virtual Error recheck_original(const RecoverySet&,std::span<std::byte> io)=0;
  virtual Error remove_work(RecoverySet&)=0;
  virtual Error reserve_new_database(FileIdentity&)=0;
  // Checked creation-handle retirement precedes raw SQLite opening.
  virtual Error release_reserved_database_for_sqlite(const FileIdentity& expected)=0;
  // Borrowed SQLite MAIN handle: never close, duplicate, cache or write it.
  virtual Error verify_reserved_database(const FileIdentity& expected,
                                         void* borrowed_sqlite_main_handle)=0;
  virtual Error sqlite_uri(std::string_view physical_root,FixedText<12288>&)=0;
  virtual Error list_recovery(std::span<RecoverySummary>,std::size_t&,CodecWorkspace)=0;
  virtual Error delete_recovery(std::span<const FixedText<32>>,Writer&,CodecWorkspace,
                                std::span<std::byte> io,NativeContext&)=0;
  virtual Error export_new(std::string_view target,std::string_view payload,
                           ExportReceipt&,std::span<std::byte> io,NativeContext&)=0;
  virtual Error wal_pressure(std::uint64_t& bytes)=0;
  virtual bool close_worker_handles() noexcept=0;
  virtual bool release_lock_after_join() noexcept=0;
  virtual bool has_worker_handles() const noexcept=0;
  virtual bool has_lock() const noexcept=0;
  // Failed actual close remains owned and prevents a successful join receipt.
  virtual void retain_failed_handle(void* handle,bool find_handle) noexcept=0;
};
bool write_export_receipt(Writer&,const ExportReceipt&) noexcept;
} // namespace flight::local_players
