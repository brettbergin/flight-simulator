// Original MIT. Single-worker SQLite repository. No caller path SQL interface.
#pragma once
#include "flight/local_players/filesystem.hpp"
#include <atomic>
struct sqlite3;

namespace flight::local_players {
enum class ResultState : std::uint8_t { read,committed,no_change,failed,uncertain,recovery_required };
struct RepositoryResult {
 ResultState state{ResultState::failed};Error error{Error::none};
 U64 commit_sequence{};bool has_sequence{};
 std::uint32_t value_bytes{};
 bool read_only{},unavailable{},qualified{};
};
struct WorkingMemory {
 CodecWorkspace codec;
 std::span<char> row;std::span<std::byte> io;
 std::span<char> hash_scratch; // contiguous65536 hash +32768 metadata, worker only
 // acquire/release is a nonblocking shared parse/encode workspace lease.
 std::atomic_flag* codec_lease{};
};
class Store {
 public:
  Store(StoreAccess&,WorkingMemory) noexcept;
  ~Store();
  Store(const Store&)=delete;Store& operator=(const Store&)=delete;
  RepositoryResult start(bool management,Writer& terminal,NativeContext&);
  RepositoryResult execute(std::string_view owned_request,Writer& terminal,
                           std::span<char> export_spool,NativeContext&);
  // Internal effect-aware unexpected-failure receipt; no new public DTO/API.
  RepositoryResult recover_unexpected(JobKind,Writer&,NativeContext&) noexcept;
  // A queued request not begun after observer loss. Pure owned-request decode;
  // no SQLite, filesystem effect or synthetic deletion/installation observation.
  RepositoryResult fail_unstarted(JobKind,std::string_view,Writer&,NativeContext&) noexcept;
  // Actual sqlite3_close plus real platform handle closure, not a state label.
  bool close() noexcept;
  bool qualified() const noexcept {return qualified_;}
  bool read_only() const noexcept {return read_only_;}
  void disable_writes() noexcept {read_only_=true;}
  bool management() const noexcept {return management_;}
 private:
  // Sole Service worker binds its running slot's already-reserved D scratch;
  // this never changes the public Service/Admission/boundary interface.
  friend class Service;
  StoreAccess& access_;WorkingMemory memory_;
  sqlite3* db_{};bool qualified_{},read_only_{},management_{};
  U64 sequence_{};FixedText<32> store_id_{};
  Error open(std::string_view root,Scope,NativeContext&,bool fresh,
             const FileIdentity* fresh_identity=nullptr);
  Error configure(bool fresh);
  Error qualify(Writer&,NativeContext&,Scope=Scope::original);
  Error initialize(Writer&,NativeContext&);
  RepositoryResult transact(RequestView,Writer&,std::span<char>,NativeContext&);
  RepositoryResult read(RequestView,Writer&,std::span<char>,NativeContext&);
  RepositoryResult interrupt_previous(Writer&,NativeContext&);
  Error checkpoint(NativeContext&);
};
} // namespace flight::local_players
