#include "fixtures/test_support.hpp"
#include "exact.hpp" // Root-approved PRIVATE src include for this target only.

// Private qualification, not a public test API or a second geometry consumer.
// Fixed mathematical expectations precede execution and do not use implementation
// outputs. Material half-mm oracle lives in reference/material-oracles.json.
namespace t = grid_test;
namespace detail = flight::ground::grid::detail;
using D = detail::Dyadic;

void millimetres() {
  struct RationalCase { std::uint64_t numerator,denominator; std::int32_t positive; };
  const std::array<RationalCase,3> fractions{{
    {1,2000,1},
    {68719476611ULL,137438953472000ULL,0},
    {68719476861ULL,137438953472000ULL,1}
  }};
  // Exact +/-1/2000m and neighbors +/-2^-40m: denominator125*2^40,
  // central numerator2^36, neighbors differ by125. Nearest-mm ties go away0.
  for(const auto& item:fractions){
    const auto n=D::integer(item.numerator),d=D::integer(item.denominator);
    t::check(detail::rounded_millimetres(n,d)==item.positive,"private rational positive half-mm/neighbor");
    t::check(detail::rounded_millimetres(n.negated(),d)==-item.positive,"private rational negative half-mm/neighbor");
  }
  struct RawCase { std::uint64_t bits; std::int32_t expected; };
  const std::array<RawCase,8> raw{{
    {0x3fb0000000000000ULL,63}, {0xbfb0000000000000ULL,-63},
    {0x3fafffffffffffffULL,62}, {0x3fb0000000000001ULL,63},
    {0xbfafffffffffffffULL,-62}, {0xbfb0000000000001ULL,-63},
    {0x3f726e978d4fdf3bULL,4}, {0xbf726e978d4fdf3bULL,-4}
  }};
  // +/-1/16m is +/-62.5mm exactly. The immediate binary64 neighbors preserve
  // their own side. Anti-double-round word3f726e978d4fdf3b is M/2^60,
  // M=5188146770730811: 2000*M=9*2^60-784, strictly below4.5mm.
  // A rounded double multiply by1000 can manufacture the tie; exact answer is4.
  for(const auto& item:raw){
    const auto n=D::binary64(std::bit_cast<double>(item.bits));
    t::check(detail::rounded_millimetres(n,D::integer(1))==item.expected,
             "private raw binary64 mm tie/neighbor/anti-double-round");
  }
}

void ratio_rounding() {
  const auto expect=[](const D& n,const D& d,std::uint64_t positive,std::uint64_t negative,std::string_view label){
    t::check(t::bits(detail::rounded_ratio(n,d))==positive,label);
    t::check(t::bits(detail::rounded_ratio(n.negated(),d))==negative,label);
  };
  expect(D::integer(1),D::integer(3),0x3fd5555555555555ULL,0xbfd5555555555555ULL,
         "private exact1/3 nearest-even raw result");
  constexpr std::uint64_t two53=std::uint64_t{1}<<53;
  // Adjacent binary64 values above1 differ by2^-52. Both inputs are exact
  // midpoints: lower/even1 wins first; upper/even raw...002 wins second.
  expect(D::integer(two53+1),D::integer(two53),0x3ff0000000000000ULL,0xbff0000000000000ULL,
         "private midpoint keeps even lower significand");
  expect(D::integer(two53+3),D::integer(two53),0x3ff0000000000002ULL,0xbff0000000000002ULL,
         "private midpoint selects even upper significand");
  // Half the minimum subnormal rounds to signed zero;1.5 minimum subnormals
  // rounds to even raw2. Construct the exact rational without an underflowing
  // host double literal. Negative nonzero numerator preserves negative-zero sign.
  expect(D::integer(1).power2(-1075),D::integer(1),0,0x8000000000000000ULL,
         "private half-minsub rounds to signed even zero");
  expect(D::integer(3).power2(-1075),D::integer(1),2,0x8000000000000002ULL,
         "private subnormal midpoint rounds to even raw2");
}

int main() {
  t::section("private exact material mm arithmetic",millimetres);
  t::section("private exact ratio nearest-even output",ratio_rounding);
  return t::finish("Resident grid PRIVATE arithmetic qualification");
}
