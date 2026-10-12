// Original MIT. Closed ADR026 records; no native-flight authority is inferred.
#pragma once
#include "flight/local_players/codec.hpp"
#include <array>
#include <initializer_list>

namespace flight::local_players {
inline constexpr std::size_t max_players=8, max_practices=2000, max_outstanding=16;
inline constexpr std::size_t max_record=8192, max_preferences=614400, max_message=655360;
inline constexpr std::string_view schema_fingerprint="cbd00b3fe47b400e79635ed901d195abfe133a4131d5001feac8e3eedeb0562f";
inline constexpr std::string_view codec_fingerprint="47711d41be89e233efe3c42e8f2cedd33f729e6e0e2c9a78a6026454022b0538";
template<std::size_t N> struct FixedText {
  std::array<char,N+1> data{}; std::uint32_t size{};
  std::string_view view() const noexcept { return {data.data(),size}; }
  bool assign(std::string_view s) noexcept {
    if(s.size()>N) return false;
    for(std::size_t i=0;i<s.size();++i) data[i]=s[i];
    size=static_cast<std::uint32_t>(s.size()); data[size]=0; return true;
  }
  bool from(DocumentView d,std::uint32_t n) noexcept {
    std::size_t used=0; if(!copy_string(d,n,std::span<char>(data.data(),N),used))return false;
    size=static_cast<std::uint32_t>(used);data[size]=0;return true;
  }
};
struct U64 {
  std::array<char,21> digits{}; std::uint8_t size{};
  std::string_view view() const noexcept { return {digits.data(),size}; }
  static bool parse(std::string_view,U64&,bool positive=false) noexcept;
  static int compare(const U64&,const U64&) noexcept;
  static bool increment(const U64&,U64&) noexcept;
  static bool subtract(const U64&,const U64&,U64&) noexcept;
};
bool valid_utc(std::string_view) noexcept;
bool valid_player_name(std::string_view) noexcept;
bool valid_local_absolute_path(std::string_view) noexcept;
Error closed(DocumentView,std::uint32_t,std::initializer_list<std::string_view>) noexcept;
Error validate_source(DocumentView,std::uint32_t) noexcept;
Error validate_player(DocumentView,std::uint32_t) noexcept;
Error validate_practice(DocumentView,std::uint32_t,bool summary=false) noexcept;
Error validate_preferences(DocumentView,std::uint32_t,bool restore_tags=false,
                           std::span<JsonCell> mutable_cells={}) noexcept;
// In BOTH restore modes, supply the same backing cells as DocumentView when
// mutation is needed. restore=false normalizes admitted integral FLOAT enums to
// INT; continuous INT/FLOAT branches/bits are unchanged. restore=true accepts
// INT enums and restores FLOAT tags only at their declared numeric paths.
// No mutable span while a conversion is needed returns out_of_memory; callers
// must never supply a separate non-aliasing destination and expect d to update.
// Adapter constructs actual INT/FLOAT cells, after ordinary keycode roundtrip.
// Core repeats full closed schema/parity checks; it never takes a valid=true flag.
Error validate_preset(DocumentView,std::uint32_t,int version,bool restore_tags=false,
                      std::span<JsonCell> mutable_cells={}) noexcept;
Error validate_audio(DocumentView,std::uint32_t,bool restore_tags=false,
                     std::span<JsonCell> mutable_cells={}) noexcept;
enum class JobKind : std::uint8_t {
  start,start_management,list_players,create_player,load_player,rename_player,
  save_preferences,begin_practice,observe_practice,end_practice,link_archive,
  list_practice,load_practice,prune_practice,delete_player,export_player,
  list_recovery,delete_recovery
};
std::string_view kind_name(JobKind) noexcept;
bool parse_kind(std::string_view,JobKind&) noexcept;
struct RequestView { JobKind kind{}; DocumentView document{}; std::uint32_t payload{no_cell}; };
Error validate_request(DocumentView,RequestView&,bool restore_tags=false,
                       std::span<JsonCell> mutable_cells={}) noexcept;
// Canonical exact envelope. Output and decoded payload are different owned spans.
// encode expects already-normalized typed enums: validate_preferences with its
// owned mutable backing span first. No caller-owned mutation is hidden here.
Error encode_preferences(DocumentView,std::uint32_t,Writer&,std::span<char> payload) noexcept;
ParseResult decode_preferences(std::string_view,CodecWorkspace,std::span<char> payload) noexcept;
} // namespace flight::local_players
