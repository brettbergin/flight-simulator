#pragma once
#include <array>
#include <bit>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>

namespace flight::ground::grid::detail {
// Private fixed-capacity arithmetic, never an input or public geometry API.
// Only the expression inventory in arithmetic-notes.md is supported. Every
// capacity failure is explicit; sample translates it to invalid_data.
struct ArithmeticFailure {};
class Dyadic {
 public:
  static constexpr std::size_t limb_count = 96;
  static Dyadic integer(std::uint64_t value) {
    Dyadic out;
    out.words_[0] = static_cast<std::uint32_t>(value);
    out.words_[1] = static_cast<std::uint32_t>(value >> 32);
    out.used_ = out.words_[1] != 0 ? 2U : (out.words_[0] != 0 ? 1U : 0U);
    out.normalize();
    return out;
  }
  static Dyadic binary64(double value) {
    const auto bits = std::bit_cast<std::uint64_t>(value);
    const auto e = static_cast<unsigned>((bits >> 52) & 0x7ffU);
    if (e == 0x7ffU) throw ArithmeticFailure{};
    const auto fraction = bits & 0x000fffffffffffffULL;
    Dyadic out = integer(e == 0 ? fraction : fraction | 0x0010000000000000ULL);
    out.exponent_ += e == 0 ? -1074 : static_cast<int>(e) - 1075;
    out.negative_ = (bits >> 63) != 0 && !out.zero();
    return out;
  }
  static Dyadic binary32_bits(std::uint32_t bits) {
    const auto e = (bits >> 23) & 0xffU;
    if (e == 0xffU) throw ArithmeticFailure{};
    Dyadic out = integer(e == 0 ? bits & 0x007fffffU : (bits & 0x007fffffU) | 0x00800000U);
    out.exponent_ += e == 0 ? -149 : static_cast<int>(e) - 150;
    out.negative_ = (bits >> 31) != 0 && !out.zero();
    return out;
  }
  [[nodiscard]] bool zero() const noexcept { return used_ == 0; }
  [[nodiscard]] bool on_lattice(int exponent) const noexcept { return zero() || exponent_ >= exponent; }
  [[nodiscard]] int sign() const noexcept { return zero() ? 0 : (negative_ ? -1 : 1); }
  [[nodiscard]] Dyadic abs() const { auto out = *this; out.negative_ = false; return out; }
  [[nodiscard]] Dyadic negated() const { auto out = *this; if (!zero()) out.negative_ = !negative_; return out; }
  [[nodiscard]] Dyadic power2(int shift) const {
    auto out = *this;
    if (shift < -4096 || shift > 4096 || out.exponent_ < -8192 - shift || out.exponent_ > 8192 - shift)
      throw ArithmeticFailure{};
    out.exponent_ += shift;
    return out;
  }
  [[nodiscard]] double approximate() const noexcept {
    if (zero()) return 0;
    std::uint64_t leading = words_[used_ - 1];
    std::size_t retained = 1;
    if (used_ > 1) { leading = (leading << 32) | words_[used_ - 2]; retained = 2; }
    const auto shift = exponent_ + static_cast<int>(32 * (used_ - retained));
    const double value = std::ldexp(static_cast<double>(leading), shift);
    return negative_ ? -value : value;
  }
  friend int compare(const Dyadic& a, const Dyadic& b) {
    if (a.sign() != b.sign()) return a.sign() < b.sign() ? -1 : 1;
    if (a.zero()) return 0;
    const int magnitude = compare_abs(a, b);
    return a.negative_ ? -magnitude : magnitude;
  }
  friend Dyadic operator+(const Dyadic& a, const Dyadic& b) {
    if (a.zero()) return b;
    if (b.zero()) return a;
    const int exponent = a.exponent_ < b.exponent_ ? a.exponent_ : b.exponent_;
    Dyadic aa = a.aligned(exponent), bb = b.aligned(exponent), out;
    out.exponent_ = exponent;
    const std::size_t count = aa.used_ > bb.used_ ? aa.used_ : bb.used_;
    if (a.negative_ == b.negative_) {
      out.negative_ = a.negative_;
      std::uint64_t carry = 0;
      for (std::size_t i = 0; i < count; ++i) {
        const auto sum = static_cast<std::uint64_t>(aa.word(i)) + bb.word(i) + carry;
        out.words_[i] = static_cast<std::uint32_t>(sum);
        carry = sum >> 32;
      }
      out.used_ = count;
      if (carry != 0) {
        if (out.used_ == limb_count) throw ArithmeticFailure{};
        out.words_[out.used_++] = static_cast<std::uint32_t>(carry);
      }
    } else {
      const int order = raw_compare(aa, bb);
      if (order == 0) return Dyadic{};
      const auto& large = order > 0 ? aa : bb;
      const auto& small = order > 0 ? bb : aa;
      out.negative_ = order > 0 ? a.negative_ : b.negative_;
      std::uint64_t borrow = 0;
      for (std::size_t i = 0; i < count; ++i) {
        const auto left = static_cast<std::uint64_t>(large.word(i));
        const auto right = static_cast<std::uint64_t>(small.word(i)) + borrow;
        out.words_[i] = static_cast<std::uint32_t>(left - right);
        borrow = left < right ? 1U : 0U;
      }
      if (borrow != 0) throw ArithmeticFailure{};
      out.used_ = count;
    }
    out.normalize();
    return out;
  }
  friend Dyadic operator-(const Dyadic& a, const Dyadic& b) { return a + b.negated(); }
  friend Dyadic operator*(const Dyadic& a, const Dyadic& b) {
    if (a.zero() || b.zero()) return Dyadic{};
    Dyadic out;
    out.exponent_ = a.exponent_ + b.exponent_;
    if (out.exponent_ < -8192 || out.exponent_ > 8192) throw ArithmeticFailure{};
    out.negative_ = a.negative_ != b.negative_;
    for (std::size_t i = 0; i < a.used_; ++i) {
      std::uint64_t carry = 0;
      for (std::size_t j = 0; j < b.used_; ++j) {
        if (i + j >= limb_count) {
          if (a.words_[i] != 0 && b.words_[j] != 0) throw ArithmeticFailure{};
          if (carry != 0) throw ArithmeticFailure{};
          continue;
        }
        const auto value = static_cast<std::uint64_t>(a.words_[i]) * b.words_[j] + out.words_[i + j] + carry;
        out.words_[i + j] = static_cast<std::uint32_t>(value);
        carry = value >> 32;
      }
      const auto next = i + b.used_;
      if (carry != 0) {
        if (next >= limb_count || out.words_[next] != 0) throw ArithmeticFailure{};
        out.words_[next] = static_cast<std::uint32_t>(carry);
      }
    }
    out.used_ = a.used_ + b.used_ < limb_count ? a.used_ + b.used_ : limb_count;
    out.normalize();
    return out;
  }
 private:
  std::array<std::uint32_t, limb_count> words_{};
  std::size_t used_{};
  int exponent_{};
  bool negative_{};
  [[nodiscard]] std::uint32_t word(std::size_t i) const noexcept { return i < used_ ? words_[i] : 0U; }
  [[nodiscard]] int width() const noexcept {
    return zero() ? 0 : static_cast<int>((used_ - 1) * 32) + 32 - std::countl_zero(words_[used_ - 1]);
  }
  static int raw_compare(const Dyadic& a, const Dyadic& b) noexcept {
    if (a.used_ != b.used_) return a.used_ < b.used_ ? -1 : 1;
    for (std::size_t i = a.used_; i != 0; --i)
      if (a.words_[i - 1] != b.words_[i - 1]) return a.words_[i - 1] < b.words_[i - 1] ? -1 : 1;
    return 0;
  }
  static int compare_abs(const Dyadic& a, const Dyadic& b) {
    if (a.zero() || b.zero()) return a.zero() ? (b.zero() ? 0 : -1) : 1;
    const int atop = a.exponent_ + a.width(), btop = b.exponent_ + b.width();
    if (atop != btop) return atop < btop ? -1 : 1;
    const int exponent = a.exponent_ < b.exponent_ ? a.exponent_ : b.exponent_;
    return raw_compare(a.aligned(exponent), b.aligned(exponent));
  }
  [[nodiscard]] Dyadic aligned(int exponent) const {
    if (exponent > exponent_) throw ArithmeticFailure{};
    const auto shift = static_cast<unsigned>(exponent_ - exponent);
    const auto whole = static_cast<std::size_t>(shift / 32U);
    const auto bits = shift % 32U;
    Dyadic out;
    out.exponent_ = exponent;
    out.negative_ = negative_;
    for (std::size_t i = 0; i < used_; ++i) {
      const auto v = static_cast<std::uint64_t>(words_[i]) << bits;
      if (i + whole >= limb_count) throw ArithmeticFailure{};
      out.words_[i + whole] |= static_cast<std::uint32_t>(v);
      if ((v >> 32) != 0) {
        if (i + whole + 1 >= limb_count) throw ArithmeticFailure{};
        out.words_[i + whole + 1] |= static_cast<std::uint32_t>(v >> 32);
      }
    }
    out.used_ = used_ + whole + (bits != 0 ? 1U : 0U);
    if (out.used_ > limb_count) out.used_ = limb_count;
    while (out.used_ != 0 && out.words_[out.used_ - 1] == 0) --out.used_;
    return out;
  }
  void normalize() noexcept {
    while (used_ != 0 && words_[used_ - 1] == 0) --used_;
    if (used_ == 0) { exponent_ = 0; negative_ = false; return; }
    std::size_t empty = 0;
    while (words_[empty] == 0) ++empty;
    if (empty != 0) {
      for (std::size_t i = empty; i < used_; ++i) words_[i - empty] = words_[i];
      used_ -= empty;
      exponent_ += static_cast<int>(32 * empty);
    }
    const auto shift = static_cast<unsigned>(std::countr_zero(words_[0]));
    if (shift != 0) {
      for (std::size_t i = 0; i < used_; ++i) {
        const std::uint32_t upper = i + 1 < used_ ? words_[i + 1] : 0U;
        words_[i] = (words_[i] >> shift) | (upper << (32U - shift));
      }
      exponent_ += static_cast<int>(shift);
      while (used_ != 0 && words_[used_ - 1] == 0) --used_;
    }
  }
};

// Exact rational -> nearest-even binary64 in the existing ground height domain.
// A guessed quotient only accelerates an exact certificate; fallback has <=63
// bit-order comparisons. It never walks nextafter without a fixed bound.
inline double rounded_ratio(const Dyadic& numerator, const Dyadic& denominator) {
  if (denominator.sign() <= 0) throw ArithmeticFailure{};
  if (compare(numerator, Dyadic::binary64(-2000) * denominator) < 0 ||
      compare(numerator, Dyadic::binary64(100000) * denominator) > 0) throw ArithmeticFailure{};
  if (numerator.zero()) return 0;
  const auto n = numerator.abs();
  const auto cap = std::bit_cast<std::uint64_t>(numerator.sign() < 0 ? 2000.0 : 100000.0);
  const auto order = [&](std::uint64_t bits) { return compare(n, denominator * Dyadic::binary64(std::bit_cast<double>(bits))); };
  std::uint64_t lower = 0;
  const double guess = n.approximate() / denominator.approximate();
  bool certified = false;
  if (std::isfinite(guess) && guess >= 0) {
    const auto seed = std::bit_cast<std::uint64_t>(guess);
    if (seed <= cap) {
      const auto lo = seed > 4 ? seed - 4 : 0;
      const auto hi = seed <= cap - 4 ? seed + 4 : cap;
      if (order(lo) >= 0 && order(hi) <= 0) {
        lower = lo;
        for (auto candidate = lo; candidate <= hi; ++candidate) {
          if (order(candidate) >= 0) lower = candidate;
          else break;
        }
        certified = true;
      }
    }
  }
  if (!certified) {
    std::uint64_t hi = cap;
    while (lower < hi) {
      const auto mid = lower + (hi - lower) / 2 + 1;
      if (order(mid) >= 0) lower = mid; else hi = mid - 1;
    }
  }
  std::uint64_t chosen = lower;
  if (order(lower) != 0 && lower < cap) {
    const auto sum = Dyadic::binary64(std::bit_cast<double>(lower)) + Dyadic::binary64(std::bit_cast<double>(lower + 1));
    const int midpoint = compare(n.power2(1), sum * denominator);
    if (midpoint > 0 || (midpoint == 0 && (lower & 1U) != 0)) chosen = lower + 1;
  }
  if (numerator.sign() < 0) chosen |= 0x8000000000000000ULL;
  return std::bit_cast<double>(chosen);
}

inline std::int32_t rounded_millimetres(const Dyadic& numerator, const Dyadic& denominator) {
  if (denominator.sign() <= 0) throw ArithmeticFailure{};
  const auto scaled = numerator.abs() * Dyadic::integer(1000);
  if (compare(scaled, denominator * Dyadic::integer(8192000)) > 0) throw ArithmeticFailure{};
  std::uint32_t low = 0, high = 8192000;
  while (low < high) {
    const auto mid = low + (high - low) / 2 + 1;
    if (compare(scaled, denominator * Dyadic::integer(mid)) >= 0) low = mid; else high = mid - 1;
  }
  if (compare(scaled.power2(1), denominator * Dyadic::integer(2ULL * low + 1)) >= 0) ++low;
  const auto value = static_cast<std::int32_t>(low);
  return numerator.sign() < 0 ? -value : value;
}
} // namespace flight::ground::grid::detail
