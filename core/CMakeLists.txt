cmake_minimum_required(VERSION 3.20)
project(windmark_core LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

option(WINDMARK_BUILD_TESTS "Build the core test suite" ON)
option(WINDMARK_WERROR "Treat warnings as errors" OFF)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")
include(WindmarkFloatRules)   # target windmark_float_rules (conventions.md §5)

add_library(windmark_core STATIC
  src/base/fp_env.cpp
  src/math/wm_math.cpp
  src/math/rng.cpp
  src/table/table.cpp
  src/state/checksum.cpp
  src/state/sha256.cpp
  src/data/json.cpp
  src/data/load_error.cpp
  src/data/table_reader.cpp
  src/data/perf.cpp
  src/data/boat_class.cpp
)

# Environment: wind, current, sea, wind shadow (wind.md, sea.md, wind_shadow.md).
target_sources(windmark_core PRIVATE
  src/wind/grid.cpp
  src/wind/wind.cpp
  src/sea/sea.cpp
  src/shadow/shadow.cpp
)

# Venue physics file (data_format.md §6) into the environment structs.
target_sources(windmark_core PRIVATE
  src/data/venue.cpp
)

# boat and sails (WM-006): boat.md, sails.md
target_sources(windmark_core PRIVATE
  src/boat/hull_sampling.cpp
  src/boat/boat.cpp
  src/sails/sails.cpp
)
# course files, race flow, racing rules and the world loop (WM-009): courses.md, race.md, rules.md
target_sources(windmark_core PRIVATE
  src/course/geometry.cpp
  src/course/course.cpp
  src/course/course_resolve.cpp
)
target_include_directories(windmark_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src")
# PUBLIC: every target that links the core (tests, server, engine bindings) builds with the same float rules.
target_link_libraries(windmark_core PUBLIC windmark_float_rules)
target_compile_options(windmark_core PRIVATE ${WINDMARK_WARNINGS})

if(WINDMARK_BUILD_TESTS)
  enable_testing()
  add_subdirectory(tests)
endif()
