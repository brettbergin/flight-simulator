// Original MIT. ADR026 bounded, flat, caller-owned codec storage.
#pragma once
#include <array>
#include <atomic>
#include <bit>
#include <cstddef>
#include <cstdint>
#include <span>
#include <string_view>

namespace flight::local_players {
enum class Error : std::uint8_t {
  none, wrong_thread, invalid_state, invalid_request, invalid_type, invalid_record,
  payload_limit, queue_full, out_of_memory, not_found, identity_conflict,
  revision_conflict, source_mismatch, tick_regression, invalid_transition,
  player_limit, history_limit, active_practice, counter_exhausted, store_locked,
  root_unavailable, unsupported_version, foreign_store, corrupt_store,
  recovery_required, recovery_limit, snapshot_failed, storage_full, busy, io_error,
  worker_lost, commit_unknown, verification_failed, target_exists, path_rejected,
  file_create_failed, file_write_failed, file_flush_failed, file_verify_failed,
  file_recovery_required
};
std::string_view error_name(Error) noexcept;
enum class ValueKind : std::uint8_t { null, boolean, integer, real, string, array, object };
inline constexpr std::uint32_t no_cell = UINT32_MAX;
// One cell per VALUE, never a separate cell per object key. String/key offsets
// refer to UTF8 JSON token interiors; escapes are decoded by StringCursor.
struct JsonCell {
  std::uint64_t scalar{};
  std::uint32_t offset{}, length{}, first{no_cell}, next{no_cell}, key_offset{};
  std::uint16_t key_length{};
  ValueKind kind{ValueKind::null};
  std::uint8_t flags{}; // bit0: string/key-free typed source string is literal UTF8.
};
static_assert(sizeof(JsonCell) == 32);
struct DocumentView {
  std::string_view bytes;
  std::span<const JsonCell> cells;
  std::uint32_t root{no_cell};
  const JsonCell* at(std::uint32_t n) const noexcept;
  std::uint32_t member(std::uint32_t object, std::string_view ascii_key) const noexcept;
  std::uint32_t size(std::uint32_t container) const noexcept;
  bool string_is(std::uint32_t node, std::string_view utf8) const noexcept;
  bool key_is(std::uint32_t node, std::string_view utf8) const noexcept;
};
struct Limits { std::size_t bytes{655360}, values{30000}, depth{12}, scalars{1024}, string_bytes{4096}; };
struct ParseResult { Error error{Error::none}; DocumentView value{}; explicit operator bool() const noexcept { return error==Error::none; } };
// Strict RFC8259; integer JSON tokens only. Real values are restored from tags
// ONLY after schema-position validation. No decimal float parser participates.
// Duplicate table needs 65536 pairs of uint32_t (524288 bytes), leased from
// the existing canonical workspace during parsing; no separate allocation.
ParseResult parse_json(std::string_view, std::span<JsonCell>, std::span<std::byte> duplicate_workspace, Limits={}) noexcept;
// Borrowed scalar cursor; decoding owns no variable string buffer.
struct StringCursor {
 std::string_view source;std::size_t position{};bool literal{},good{true};
 bool next(std::uint32_t&) noexcept;
};
StringCursor string_cursor(DocumentView,std::uint32_t,bool key=false) noexcept;
bool string_metrics(DocumentView,std::uint32_t,std::size_t& bytes,std::size_t& scalars) noexcept;
bool valid_utf8(std::string_view, std::size_t* scalar_count=nullptr) noexcept;
bool copy_string(DocumentView, std::uint32_t, std::span<char>, std::size_t&) noexcept;
bool copy_key(DocumentView, std::uint32_t, std::span<char>, std::size_t&) noexcept;
bool equal_values(DocumentView, std::uint32_t, DocumentView, std::uint32_t) noexcept;
// Adapter capture is a preorder tree of literal UTF8 cells, root0, with no
// unreachable cells/aliases/cycles. Check structure before schema traversal.
// max_members17 is the closed record domain (Practice17, preset joy_axis14),
// not a reduced generic JSON scanner limit. Oversized objects reject before
// duplicate pair comparisons; each admitted comparison set has <=17 members.
Error validate_capture(DocumentView, Limits={}, std::size_t max_members=17) noexcept;

class Writer {
 public:
  explicit Writer(std::span<char> out) noexcept : out_(out), limit_(out.size()) {}
  // Same canonical traversal, checked sizing only; does not access output bytes.
  static Writer measure(std::size_t limit) noexcept { return Writer(limit); }
  bool raw(std::string_view) noexcept;
  bool character(char) noexcept;
  bool string(std::string_view) noexcept;
  bool string(DocumentView, std::uint32_t) noexcept;
  bool integer(std::int64_t) noexcept;
  bool binary64(double) noexcept;
  bool value(DocumentView, std::uint32_t, bool tagged_reals=true) noexcept;
  std::span<char> storage() const noexcept { return out_; }
  std::string_view bytes() const noexcept { return counting_?std::string_view{}:std::string_view{out_.data(), used_}; }
  std::size_t size() const noexcept { return used_; }
  bool good() const noexcept { return good_; }
  void reset() noexcept { used_=0; good_=true; }
 private:
  explicit Writer(std::size_t limit) noexcept : limit_(limit),counting_(true) {}
  std::span<char> out_; std::size_t used_{},limit_{}; bool good_{true},counting_{};
};
struct Replacement { std::string_view key, canonical_value; };
// Overrides are exact existing keys, unique; no key insertion/removal here.
bool rewrite_object(Writer&, DocumentView, std::uint32_t,
                    std::span<const Replacement>) noexcept;
struct Sha256 {
  Sha256() noexcept;
  void update(std::span<const std::byte>) noexcept;
  void update(std::string_view s) noexcept { update(std::as_bytes(std::span(s.data(),s.size()))); }
  std::array<std::byte,32> finish() noexcept;
 private:
  std::array<std::uint32_t,8> state_{};
  std::array<std::byte,64> block_{};
  std::uint64_t bytes_{}; std::size_t used_{};
  void compress() noexcept;
};
std::array<char,64> sha256_hex(std::string_view) noexcept;
bool lower_hex(std::string_view, std::size_t) noexcept;
bool decode_binary64_tag(DocumentView, std::uint32_t, double&) noexcept;
bool finite_binary64(double) noexcept;
// This workspace is provided by the Service's permanently charged regions.
// No implicit heap fallback, and no owned DocumentView beyond its lease.
struct CodecWorkspace { std::span<JsonCell> cells; std::span<char> text; std::atomic_flag* lease{}; };
} // namespace flight::local_players
