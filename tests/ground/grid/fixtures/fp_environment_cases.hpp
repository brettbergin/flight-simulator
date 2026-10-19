#pragma once
#include "test_support.hpp"
#include <cfenv>

#if defined(_M_X64) || defined(__x86_64__) || (defined(_M_IX86_FP) && _M_IX86_FP >= 2) || (defined(__i386__) && defined(__SSE2__))
#include <xmmintrin.h>
#define GRID_TEST_HAS_MXCSR 1
#else
#define GRID_TEST_HAS_MXCSR 0
#endif

namespace grid_fp_cases {
namespace t = grid_test;
namespace grid = flight::ground::grid::v1;

// Test-thread-only state. Restore the complete saved fenv and finally exact MXCSR,
// including exception flags, rounding, FTZ and DAZ, even when a tested call throws.
class RestoreEnvironment final {
 public:
  RestoreEnvironment() noexcept : captured_(std::fegetenv(&saved_) == 0) {
#if GRID_TEST_HAS_MXCSR
    saved_csr_ = _mm_getcsr();
#endif
  }
  ~RestoreEnvironment() noexcept {
    if (captured_) (void)std::fesetenv(&saved_);
#if GRID_TEST_HAS_MXCSR
    _mm_setcsr(saved_csr_);
#endif
  }
  RestoreEnvironment(const RestoreEnvironment&) = delete;
  RestoreEnvironment& operator=(const RestoreEnvironment&) = delete;
  bool captured() const noexcept { return captured_; }
 private:
  std::fenv_t saved_{};
  bool captured_{};
#if GRID_TEST_HAS_MXCSR
  unsigned saved_csr_{};
#endif
};

inline void run() {
  RestoreEnvironment restore_caller;
  t::check(restore_caller.captured(),"capture complete caller FP environment");
  if (!restore_caller.captured()) return;
  const bool nearest = std::fesetround(FE_TONEAREST) == 0;
  t::check(nearest,"establish test-local nearest rounding");
  if (!nearest) return;
  std::shared_ptr<const grid::PreparedGrid> upward_provider;
  {
    RestoreEnvironment restore_nearest;
    t::check(restore_nearest.captured(),"capture nearest environment before upward admission");
    if (!restore_nearest.captured()) return;
    const bool upward = std::fesetround(FE_UPWARD) == 0;
    t::check(upward && std::fegetround() == FE_UPWARD,"FE_UPWARD is active on test thread");
    if (!upward) return;
    // Closed Definition admission has no caller-FENV precondition.
    upward_provider = grid::PreparedGrid::prepare(t::flat(),t::identity());
  }
  t::check(std::fegetround() == FE_TONEAREST,"restore nearest before known sample");
  t::check(upward_provider != nullptr,"upward admission returns a provider");
  if (!upward_provider) return;
  t::ready(*upward_provider,{0,0,25},10,{0,0,-1});

#if GRID_TEST_HAS_MXCSR
  const auto zero_origin = grid::PreparedGrid::prepare(t::flat(2,2,0,0),t::identity());
  const unsigned csr_before = _mm_getcsr();
  {
    RestoreEnvironment restore_simd;
    t::check(restore_simd.captured(),"capture environment before scoped FTZ/DAZ");
    if (!restore_simd.captured()) return;
    _mm_setcsr(_mm_getcsr() | 0x8040U); // FTZ bit15 and DAZ bit6, this thread only.
    t::check((_mm_getcsr() & 0x8040U) == 0x8040U,"scoped x86 FTZ and DAZ enabled");
    const double tiny = std::bit_cast<double>(std::uint64_t{1});
    const double negative_tiny = std::bit_cast<double>(std::uint64_t{0x8000000000000001ULL});
    auto invalid_origin = t::flat();
    invalid_origin.east_origin_m = tiny;
    t::rejects_invalid([&]{(void)grid::PreparedGrid::prepare(invalid_origin,t::identity());},
                       "DAZ cannot turn raw DoubleMin origin into valid lattice zero");
    auto invalid_friction = t::flat();
    invalid_friction.materials[0].static_friction = 0;
    invalid_friction.materials[0].dynamic_friction = tiny;
    t::rejects_invalid([&]{(void)grid::PreparedGrid::prepare(invalid_friction,t::identity());},
                       "DAZ cannot erase exact dynamic-friction excess over static0");
    t::check(zero_origin->coverage({tiny,0,0,0}) == grid::Coverage::invalid_data,
             "raw positive DoubleMin minimum above0 maximum is reversed under DAZ");
    t::check(zero_origin->coverage({negative_tiny,0,0,0}) == grid::Coverage::outside_coverage,
             "raw negative DoubleMin is outside zero-origin coverage under DAZ");
    t::check(zero_origin->coverage({tiny,0,tiny,0}) == grid::Coverage::ready,
             "positive DoubleMin point lies inside coverage under DAZ");
    t::check(zero_origin->coverage({0,0,0,0}) == grid::Coverage::ready,
             "positive zero outer minimum remains included under DAZ");
    t::check(zero_origin->coverage({-0.0,-0.0,-0.0,-0.0}) == grid::Coverage::ready,
             "negative zero outer minimum remains included under DAZ");
  }
  t::check(_mm_getcsr() == csr_before,"restore all saved MXCSR bits after scoped FTZ/DAZ cases");
  t::check(std::fegetround() == FE_TONEAREST,"restore standard rounding after SIMD cases");
#else
  std::cout << "SKIP: FTZ/DAZ cases require guarded x86 SSE2 MXCSR access\n";
#endif
  // Caller environment restores on exit before the later concurrency group runs.
}
} // namespace grid_fp_cases
#undef GRID_TEST_HAS_MXCSR
