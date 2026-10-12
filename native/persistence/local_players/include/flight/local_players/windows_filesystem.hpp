// Original MIT. Windows-only fixed KnownFolder policy and observed NTFS IO.
#pragma once
#include "flight/local_players/filesystem.hpp"

namespace flight::local_players {
class WindowsFileSystem final : public FileSystem {
 public:
  // Initializes opaque in-place production state, never an arbitrary root.
  static StoreAccess production() noexcept;
  ~WindowsFileSystem() override;
  FileSystem* relocate(void*) noexcept override;
  static Error resolve_known_folder(FixedText<4096>&) noexcept; // read-only
  Error acquire_root(bool,NativeContext&) override;
  std::string_view root() const noexcept override {return root_.view();}
  Error random_id(FixedText<32>&) noexcept override;
  Error utc(FixedText<20>&) noexcept override;
  std::string_view owner_run_id() const noexcept override;
  Error inspect_sources(FileSet&) override;
  Error snapshot(const FileSet&,RecoverySet&,std::span<std::byte>,CodecWorkspace,NativeContext&) override;
  Error recheck_original(const RecoverySet&,std::span<std::byte>) override;
  Error remove_work(RecoverySet&) override;
  Error reserve_new_database(FileIdentity&) override;
  Error release_reserved_database_for_sqlite(const FileIdentity& expected) override;
  Error verify_reserved_database(const FileIdentity& expected,
                                 void* borrowed_sqlite_main_handle) override;
  Error sqlite_uri(std::string_view,FixedText<12288>&) override;
  Error list_recovery(std::span<RecoverySummary>,std::size_t&,CodecWorkspace) override;
  Error delete_recovery(std::span<const FixedText<32>>,Writer&,CodecWorkspace,std::span<std::byte>,NativeContext&) override;
  Error export_new(std::string_view,std::string_view,ExportReceipt&,std::span<std::byte>,NativeContext&) override;
  Error wal_pressure(std::uint64_t&) override;
  bool close_worker_handles() noexcept override;
  bool release_lock_after_join() noexcept override;
  bool has_worker_handles() const noexcept override;
  bool has_lock() const noexcept override {return lock_!=nullptr;}
  void retain_failed_handle(void*,bool) noexcept override;
 private:
  WindowsFileSystem() noexcept=default;
  FixedText<4096> root_{};FileIdentity root_identity_{},parent_identity_{};
  std::array<void*,4> guards_{};
  void* lock_{};void* new_database_{};
  std::array<void*,32> failed_handles_{};std::array<bool,32> failed_find_{};
  bool unretained_handle_{}; // capacity failure can never be a successful join
  std::array<char,24576> metadata_{};std::array<std::byte,8192> metadata_io_{};
  CodecWorkspace worker_codec_{}; // borrowed charged workspace, worker-only
  FileIdentity work_directory_identity_{},work_intent_identity_{};
  std::array<char,64> work_intent_hash_{};
  bool management_origin_{};
  bool isolated_{};FixedText<32> test_nonce_{};
  FixedText<4096> test_parent_{};
  FileIdentity test_sentinel_identity_{};
  std::array<char,64> test_sentinel_sha256_{};
  // Minting is implemented exclusively by the separately linked test factory.
  friend class testing::TestRootFactory;friend class StoreAccess;
};
} // namespace flight::local_players
