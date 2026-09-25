// Floating-point environment checks (conventions.md §5 rules 2-5).
#pragma once

namespace wm {

// True when the FP environment is the one the core requires: round to nearest even, denormals neither flushed
// on output (FTZ) nor treated as zero on input (DAZ). Host engines sometimes enable FTZ/DAZ for speed.
bool fp_env_ok();

// a*b + c as written, compiled under the core's float rules. With contraction enabled the compiler would emit
// one fused multiply-add here; the test suite calls it with inputs where the fused and the separately rounded
// results differ.
float fp_probe_mul_add(float a, float b, float c);

}  // namespace wm

// Debug builds check the environment at the start of every tick.
#ifndef NDEBUG
#include <cassert>
#define WM_DEBUG_CHECK_FP_ENV() assert(::wm::fp_env_ok() && "FP environment: need round-to-nearest, no FTZ/DAZ")
#else
#define WM_DEBUG_CHECK_FP_ENV() ((void)0)
#endif
