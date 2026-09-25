# Float rules of docs/specs/conventions.md §5: IEEE binary32, round to nearest, one rounding per operation,
# no fused multiply-add, no fast-math, no x87, denormals kept.
#
# Everything is attached to the INTERFACE target `windmark_float_rules`, which windmark_core links PUBLIC, so
# any target that links the core compiles its own sources under the same rules.

# Refuse global flags that break the rules. They would apply to every target, ours included.
foreach(_flags_var CMAKE_CXX_FLAGS CMAKE_CXX_FLAGS_DEBUG CMAKE_CXX_FLAGS_RELEASE
                   CMAKE_CXX_FLAGS_RELWITHDEBINFO CMAKE_CXX_FLAGS_MINSIZEREL)
  if("${${_flags_var}}" MATCHES "(-ffast-math|-Ofast|-funsafe-math-optimizations|-ffp-contract=fast|-ffp-contract=on|/fp:fast|/fp:contract)")
    message(FATAL_ERROR "${_flags_var} contains '${CMAKE_MATCH_1}', which breaks the core's float rules "
                        "(docs/specs/conventions.md §5)")
  endif()
endforeach()

add_library(windmark_float_rules INTERFACE)

if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  target_compile_options(windmark_float_rules INTERFACE
    -fno-fast-math                    # no reassociation, no finite-math or reciprocal shortcuts
    -fno-unsafe-math-optimizations
    -fno-associative-math
    -fno-reciprocal-math
    -fno-finite-math-only             # NaN and infinity keep their IEEE meaning
    -fsigned-zeros
    -ffp-contract=off                 # no a*b+c fused into one rounding (ARM64 compilers fuse by default)
  )
  if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    # Only matters on x87, but states the intent: every float operation rounds to binary32.
    target_compile_options(windmark_float_rules INTERFACE -fexcess-precision=standard)
  endif()
  # 32-bit x86: SSE2 scalar float, never x87.
  if(CMAKE_SIZEOF_VOID_P EQUAL 4 AND CMAKE_SYSTEM_PROCESSOR MATCHES "^(i.86|x86|X86|AMD64|x86_64)$")
    target_compile_options(windmark_float_rules INTERFACE -mfpmath=sse -msse2)
  endif()
elseif(MSVC)
  # /fp:precise without /fp:contract keeps products and sums separately rounded (VS 2022 and later).
  target_compile_options(windmark_float_rules INTERFACE /fp:precise)
  if(CMAKE_SIZEOF_VOID_P EQUAL 4)
    target_compile_options(windmark_float_rules INTERFACE /arch:SSE2)
  endif()
else()
  message(WARNING "Unknown compiler ${CMAKE_CXX_COMPILER_ID}: set its no-contraction, no-fast-math flags by hand")
endif()

# Warnings for the core's own sources. -Wdouble-promotion catches a float silently computed in double.
if(CMAKE_CXX_COMPILER_ID MATCHES "Clang|GNU")
  set(WINDMARK_WARNINGS -Wall -Wextra -Wpedantic -Wshadow -Wdouble-promotion -Wfloat-conversion)
  if(WINDMARK_WERROR)
    list(APPEND WINDMARK_WARNINGS -Werror)
  endif()
elseif(MSVC)
  set(WINDMARK_WARNINGS /W4)
  if(WINDMARK_WERROR)
    list(APPEND WINDMARK_WARNINGS /WX)
  endif()
endif()
