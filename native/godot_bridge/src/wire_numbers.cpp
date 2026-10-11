#include "wire_numbers.hpp"
#include <bit>
#include <cfenv>
#include <charconv>
#include <cstdint>
#include <limits>
#include <system_error>
#include <utility>
#if defined(_M_X64) || defined(__x86_64__)
#include <immintrin.h>
#define FLIGHT_WIRE_NUMBERS_X64 1
#else
#define FLIGHT_WIRE_NUMBERS_X64 0
#endif

namespace flight::bridge::wire_numbers {
namespace {
static_assert(sizeof(double)==8 && std::numeric_limits<double>::is_iec559 &&
  std::numeric_limits<double>::radix==2 && std::numeric_limits<double>::digits==53 &&
  std::numeric_limits<double>::max_exponent==1024 && std::numeric_limits<double>::min_exponent==-1021);
constexpr std::uint64_t sign_mask = UINT64_C(0x8000000000000000);
constexpr std::uint64_t exponent_mask = UINT64_C(0x7ff0000000000000);

struct Decimal {
  bool negative{};
  bool zero{true};
};

bool digit(char value) { return value>='0' && value<='9'; }

bool grammar(std::string_view token, Decimal& decimal) {
  // No prefix conversion, locale digits, whitespace, NUL or non-ASCII escape.
  std::size_t i=0;
  if(token.empty()) return false;
  if(token[i]=='-') { decimal.negative=true; if(++i==token.size()) return false; }
  if(token[i]=='0') {
    ++i;
  } else {
    if(token[i]<'1'||token[i]>'9') return false;
    do { decimal.zero=decimal.zero && token[i]=='0'; ++i; } while(i<token.size() && digit(token[i]));
  }
  if(i<token.size() && token[i]=='.') {
    const auto first=++i;
    while(i<token.size() && digit(token[i])) { decimal.zero=decimal.zero && token[i]=='0'; ++i; }
    if(i==first) return false;
  }
  if(i<token.size() && (token[i]=='e'||token[i]=='E')) {
    ++i;
    if(i<token.size() && (token[i]=='+'||token[i]=='-')) ++i;
    const auto first=i;
    while(i<token.size() && digit(token[i])) ++i;
    if(i==first) return false;
  }
  return i==token.size();
}

TokenResult failure(const char* error) { return {false,error,{}}; }

// Control modes are never changed to make a token work. This opt-in utility
// supports strict binary64 x64/SSE evaluation, nearest rounding, gradual
// underflow and masked exceptions. Unsupported modes reject before conversion.
bool supported_environment() {
#if FLIGHT_WIRE_NUMBERS_X64
  const auto csr=_mm_getcsr();
  return std::fegetround()==FE_TONEAREST && (csr & 0xe040U)==0 &&
    (csr & 0x1f80U)==0x1f80U;
#else
  return false;
#endif
}

class SavedEnvironment final {
 public:
  SavedEnvironment() {
#if FLIGHT_WIRE_NUMBERS_X64
    csr_=_mm_getcsr();
#endif
    pending_=std::fegetenv(&environment_)==0;
  }
  SavedEnvironment(const SavedEnvironment&)=delete;
  SavedEnvironment& operator=(const SavedEnvironment&)=delete;
  ~SavedEnvironment() { if(pending_) (void)restore(); }
  bool captured() const { return pending_; }
  bool restore() {
    if(!pending_) return false;
    // Restore caller sticky status as well as the identical admitted controls.
    // fesetenv is not used to select a conversion mode.
    const bool restored=std::fesetenv(&environment_)==0;
#if FLIGHT_WIRE_NUMBERS_X64
    _mm_setcsr(csr_);
#endif
    pending_=false;
    return restored;
  }
 private:
  std::fenv_t environment_{};
  bool pending_{};
#if FLIGHT_WIRE_NUMBERS_X64
  unsigned int csr_{};
#endif
};
}

TokenResult decode_binary64(std::span<const std::string_view> tokens) {
  if(tokens.size()>max_tokens) return failure("Numeric batch exceeds token limit");
  std::size_t combined=0;
  std::vector<Decimal> decimals;
  decimals.reserve(tokens.size());
  for(const auto token:tokens) {
    if(token.size()>max_token_bytes || token.size()>max_combined_bytes-combined)
      return failure("Numeric text exceeds byte limit");
    combined+=token.size();
    Decimal decimal;
    if(!grammar(token,decimal)) return failure("Invalid whole JSON numeric token");
    decimals.push_back(decimal);
  }
  if(tokens.empty()) return {true,"",{}};
  if(!supported_environment()) return failure("Unsupported numeric floating-point environment");
  // Allocate before capturing FP state; conversion below uses only fixed slots.
  std::vector<double> values(tokens.size());
  SavedEnvironment environment;
  if(!environment.captured()) return failure("Numeric floating-point snapshot unavailable");
  const char* error=nullptr;
  for(std::size_t i=0;i<tokens.size();++i) {
    const auto token=tokens[i];
    const auto parsed=std::from_chars(token.data(),token.data()+token.size(),values[i],std::chars_format::general);
    if(parsed.ec!=std::errc{} || parsed.ptr!=token.data()+token.size()) {
      error="Numeric conversion failed or outside binary64 range"; break;
    }
    const auto bits=std::bit_cast<std::uint64_t>(values[i]);
    if((bits & exponent_mask)==exponent_mask) { error="Numeric conversion is not finite"; break; }
    const bool zero=(bits & ~sign_mask)==0;
    const bool negative=(bits & sign_mask)!=0;
    if(negative!=decimals[i].negative) { error="Numeric conversion changed sign"; break; }
    if(zero!=decimals[i].zero) { error="Nonzero numeric underflow or invalid zero conversion"; break; }
  }
  const bool controls_preserved=supported_environment();
  if(!environment.restore()) return failure("Numeric floating-point restoration unavailable");
  if(!controls_preserved) return failure("Numeric conversion changed floating-point controls");
  if(error) return failure(error);
  return {true,"",std::move(values)};
}
}

#if !defined(FLIGHT_WIRE_NUMBERS_CORE_ONLY) || !FLIGHT_WIRE_NUMBERS_CORE_ONLY
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <exception>

namespace flight::bridge {
namespace {
godot::Dictionary number_failure(const char* error) {
  godot::Dictionary result;
  result[godot::String("ok")]=false;
  result[godot::String("error")]=godot::String::utf8(error);
  result[godot::String("value")]=godot::Variant();
  return result;
}
}

class FlightWireNumbers final : public godot::RefCounted {
  GDCLASS(FlightWireNumbers,godot::RefCounted)
 protected:
  static void _bind_methods() {
    godot::ClassDB::bind_method(godot::D_METHOD("decode_binary64","tokens"),&FlightWireNumbers::decode_binary64);
  }
 public:
  godot::Dictionary decode_binary64(godot::Variant input) {
    try {
      if(input.get_type()!=godot::Variant::ARRAY) return number_failure("Numeric tokens require an exact Array");
      const godot::Array tokens=input;
      if(tokens.size()>static_cast<int64_t>(wire_numbers::max_tokens)) return number_failure("Numeric batch exceeds token limit");
      std::size_t combined=0;
      // Complete type/length/ASCII admission precedes any std::from_chars call.
      for(int64_t i=0;i<tokens.size();++i) {
        const godot::Variant token=tokens[i];
        if(token.get_type()!=godot::Variant::STRING) return number_failure("Every numeric token requires an exact String");
        const godot::String text=token;
        const auto length=text.length();
        if(length>static_cast<int64_t>(wire_numbers::max_token_bytes) ||
          static_cast<std::size_t>(length)>wire_numbers::max_combined_bytes-combined)
          return number_failure("Numeric text exceeds byte limit");
        for(int64_t j=0;j<length;++j) if(text[j]>127) return number_failure("Numeric tokens require ASCII text");
        combined+=static_cast<std::size_t>(length);
      }
      std::vector<std::string> storage;
      storage.reserve(static_cast<std::size_t>(tokens.size()));
      for(int64_t i=0;i<tokens.size();++i) {
        const godot::String text=tokens[i];
        std::string ascii(static_cast<std::size_t>(text.length()),'\0');
        for(int64_t j=0;j<text.length();++j) ascii[static_cast<std::size_t>(j)]=static_cast<char>(text[j]);
        storage.push_back(std::move(ascii));
      }
      std::vector<std::string_view> views;
      views.reserve(storage.size());
      for(const auto& text:storage) views.push_back(text);
      const auto converted=wire_numbers::decode_binary64(views);
      if(!converted.ok) return number_failure(converted.error.c_str());
      godot::Array values;
      if(values.resize(static_cast<int64_t>(converted.value.size()))!=0)
        return number_failure("Numeric result allocation unavailable");
      for(std::size_t i=0;i<converted.value.size();++i) values[static_cast<int64_t>(i)]=converted.value[i];
      godot::Dictionary result;
      result[godot::String("ok")]=true;
      result[godot::String("error")]=godot::String();
      result[godot::String("value")]=values;
      return result;
    } catch(const std::exception&) {
      return number_failure("Numeric batch allocation or conversion unavailable");
    }
  }
};

void register_wire_numbers() { godot::ClassDB::register_class<FlightWireNumbers>(); }
}
#endif
