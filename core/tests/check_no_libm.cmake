# Fails when the core library calls a platform libm transcendental (conventions.md §5 rule 7: they come from §6,
# wm_math.h, never from libm, whose results differ between platforms). The exact functions (sqrt, fabs, floor,
# ceil, nearbyint, ldexp, fmin, fmax, lround) are allowed, and cbrt, which sea.md §2 uses in double precision for a
# server-side load-time constant (the wind-sea period).
execute_process(COMMAND "${NM}" -u "${LIB}" OUTPUT_VARIABLE syms RESULT_VARIABLE rc ERROR_VARIABLE err)
if(NOT rc EQUAL 0)
  message(FATAL_ERROR "nm failed: ${err}")
endif()
string(REPLACE "\n" ";" syms "${syms}")
set(hits "")
foreach(s IN LISTS syms)
  string(STRIP "${s}" s)
  # Mach-O prefixes C symbols with an underscore; Apple's sincos helpers are __sincos(f)_stret.
  if(s MATCHES "^_?(sin|cos|tan|asin|acos|atan|atan2|sinh|cosh|tanh|asinh|acosh|atanh|exp|exp2|expm1|log|log2|log10|log1p|pow|hypot|erf|erfc|tgamma|lgamma|fmod|remainder|sincos|_sincosf?_stret)[fl]?$")
    list(APPEND hits "${s}")
  endif()
endforeach()
list(LENGTH syms n)
if(n LESS 5)
  message(FATAL_ERROR "symbol list unexpectedly short; is ${LIB} the core library?")
endif()
if(hits)
  list(REMOVE_DUPLICATES hits)
  message(FATAL_ERROR "platform libm calls in the core library: ${hits} (use the wm_* functions of math/wm_math.h)")
endif()
message(STATUS "no libm transcendentals in ${LIB}")
