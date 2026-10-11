// Original MIT. Production conversion core only: no Godot API before initialization.
#include "wire_numbers.hpp"
#include "reference_cases.hpp"
#include <array>
#include <bit>
#include <cfenv>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <limits>
#include <locale>
#include <sstream>
#include <string>
#include <vector>
#if defined(_M_X64) || defined(__x86_64__)
#include <xmmintrin.h>
#define WIRE_TEST_X64 1
#endif

namespace core = flight::bridge::wire_numbers;
namespace {
int failed = 0;
int checks = 0;
void check(bool ok, const std::string& label) {
    ++checks;
    if (!ok) { ++failed; std::cerr << "FAIL " << label << '\n'; }
}
std::uint64_t bits(double value) { return std::bit_cast<std::uint64_t>(value); }
struct Environment {
    fenv_t saved{};
    int rounding = std::fegetround();
    int exceptions = std::fetestexcept(FE_ALL_EXCEPT);
#ifdef WIRE_TEST_X64
    unsigned mxcsr = _mm_getcsr();
#endif
    Environment() { check(std::fegetenv(&saved) == 0, "test_environment_snapshot"); }
    bool same() const {
        bool equal = std::fegetround() == rounding && std::fetestexcept(FE_ALL_EXCEPT) == exceptions;
#ifdef WIRE_TEST_X64
        equal = equal && _mm_getcsr() == mxcsr;
#endif
        return equal;
    }
    ~Environment() {
        std::fesetenv(&saved);
#ifdef WIRE_TEST_X64
        _mm_setcsr(mxcsr);
#endif
    }
};
core::TokenResult one(std::string_view token) {
    const std::array<std::string_view, 1> batch{token};
    return core::decode_binary64(batch);
}
bool closed_failure(const core::TokenResult& result) {
    return !result.ok && !result.error.empty() && result.error.size() <= 256 && result.value.empty();
}
void reference() {
    std::vector<std::string_view> positives;
    std::vector<std::uint64_t> wanted;
    for (const auto& item : wire_reference::cases) {
        Environment before;
        const auto result = one(item.token);
        check(before.same(), std::string(item.id) + "_caller_state_preserved");
        if (item.ok) {
            check(result.ok && result.error.empty() && result.value.size() == 1 &&
                bits(result.value.front()) == item.bits, std::string(item.id) + "_exact_bits");
            positives.push_back(item.token); wanted.push_back(item.bits);
        } else { check(closed_failure(result), std::string(item.id) + "_atomic_rejection"); }
    }
    auto batch = core::decode_binary64(positives);
    bool exact = batch.ok && batch.error.empty() && batch.value.size() == wanted.size();
    if (exact) for (std::size_t i = 0; i < wanted.size(); ++i) exact = exact && bits(batch.value[i]) == wanted[i];
    check(exact, "frozen_finite_batch_order_bits");
    for (std::size_t at : {std::size_t{0}, positives.size() / 2, positives.size()}) {
        auto invalid = positives; invalid.insert(invalid.begin() + static_cast<std::ptrdiff_t>(at), "1e999");
        check(closed_failure(core::decode_binary64(invalid)), "invalid_batch_no_partial_prefix");
    }
    auto empty = core::decode_binary64({});
    check(empty.ok && empty.error.empty() && empty.value.empty(), "empty_batch");
}
void bounds() {
    std::vector<std::string_view> count(8192, "0");
    check(core::decode_binary64(count).ok, "inclusive_8192_tokens");
    count.push_back("0"); check(closed_failure(core::decode_binary64(count)), "reject_8193_tokens");
    const std::string longest = "0." + std::string(2046, '0');
    check(one(longest).ok, "inclusive_2048_token_bytes");
    check(closed_failure(one(longest + "0")), "reject_2049_token_bytes");
    count.assign(512, longest);
    auto full = core::decode_binary64(count);
    check(full.ok && full.value.size() == 512, "inclusive_1048576_combined_bytes");
    count.push_back("0"); check(closed_failure(core::decode_binary64(count)), "reject_1048577_combined_bytes");
    for (const std::string& token : std::array<std::string, 9>{" 0", "0 ", std::string("0\0", 2), "0x1", "NaN", "Infinity", "1_0", "1true", "\xD9\xA1"}) {
        check(closed_failure(one(token)), "whole_ascii_grammar_rejection");
    }
}
void formatter_roundtrips() {
    Environment formatter_state;
    // Formatter-only supplement matches the native max_digits10/classic expression.
    // It is not an aircraft serializer qualification for arbitrary untyped values.
    std::vector<std::uint64_t> patterns{0, 1, 2, 0x000fffffffffffffULL, 0x0010000000000000ULL, 0x7fefffffffffffffULL};
    for (std::uint64_t exponent = 1; exponent < 2047; ++exponent) {
        const auto boundary = exponent << 52;
        patterns.push_back(boundary - 1); patterns.push_back(boundary); patterns.push_back(boundary + 1);
        patterns.push_back(boundary | 0x0005555555555555ULL);
    }
    for (auto pattern : patterns) for (auto sign : {0ULL, 0x8000000000000000ULL}) {
        const auto expected = pattern | sign;
        const auto value = std::bit_cast<double>(expected);
        std::ostringstream text;
        text.imbue(std::locale::classic()); text << std::setprecision(std::numeric_limits<double>::max_digits10) << value;
        const auto result = one(text.str());
        check(result.ok && result.error.empty() && result.value.size() == 1 && bits(result.value.front()) == expected, "formatter_17_digit_boundary_roundtrip");
    }
}
void environments() {
    for (int flag : {FE_INVALID, FE_INEXACT}) {
        Environment restore;
        check(std::feraiseexcept(flag) == 0, "seed_owned_sticky_status");
        Environment before;
        for (auto token : {"0.059999999999999998", "1e999", "1e-999", "+1"}) {
            const auto result = one(token);
            check(before.same(), "supported_success_error_preserves_caller_status");
            check(token[0] == '0' ? result.ok : closed_failure(result), "status_seeded_result");
        }
    }
    for (int rounding : {FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO}) {
        Environment restore;
        if (std::fesetround(rounding) != 0) { check(false, "required_rounding_probe_available"); continue; }
        Environment before;
        check(closed_failure(one("0.06")) && before.same(), "unsupported_rounding_rejects_without_mutation");
        check(core::decode_binary64({}).ok && before.same(), "empty_batch_unsupported_environment_unchanged");
    }
#ifdef WIRE_TEST_X64
    for (unsigned flag : {0x40U, 0x8000U}) {
        Environment restore; _mm_setcsr(_mm_getcsr() | flag); Environment before;
        check(closed_failure(one("0.06")) && before.same(), "unsupported_DAZ_FTZ_rejects_unchanged");
    }
    {
        Environment restore;
        std::feclearexcept(FE_ALL_EXCEPT);
        _mm_setcsr((_mm_getcsr() & ~0x3fU) & ~0x80U); // Unmask invalid; no FP test arithmetic here.
        Environment before;
        check(closed_failure(one("0.06")) && before.same(), "unsupported_unmasked_SSE_rejects_unchanged");
    }
#endif
}
}
int main() {
    static_assert(std::numeric_limits<double>::is_iec559 && sizeof(double) == 8);
    Environment original;
    // Tests do not alter mode to enable the product. Qualification requires this launch domain.
    check(std::fegetround() == FE_TONEAREST, "launch_round_to_nearest");
#ifdef WIRE_TEST_X64
    check((_mm_getcsr() & 0xe040U) == 0 && (_mm_getcsr() & 0x1f80U) == 0x1f80U, "launch_masked_SSE_no_DAZ_FTZ");
#else
    check(false, "required_x64_domain");
#endif
    if (failed == 0) { reference(); bounds(); formatter_roundtrips(); environments(); }
    check(original.same(), "all_owned_environment_probes_restored");
    std::cout << "WIRE_NUMBERS_NATIVE " << checks << ' ' << failed << '\n';
    return failed == 0 ? 0 : 1;
}
