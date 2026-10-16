# Test suite: doctest (third_party/doctest, MIT).
set(WINDMARK_DATA_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../data" CACHE PATH
    "Repository data directory (classes/, perf/) the tests load")

add_executable(windmark_core_tests
  test_main.cpp
  test_float_rules.cpp
  test_math.cpp
  test_rng.cpp
  test_table.cpp
  test_checksum.cpp
  test_json.cpp
  test_perf.cpp
  test_vmg_table.cpp
)

# boat and sails (WM-006)
target_sources(windmark_core_tests PRIVATE
  test_boat.cpp
  test_sails.cpp
  test_boat_env.cpp
  test_drift.cpp
  test_stern_probe.cpp
)
target_link_libraries(windmark_core_tests PRIVATE windmark_core)
target_include_directories(windmark_core_tests SYSTEM PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/doctest")
target_compile_options(windmark_core_tests PRIVATE ${WINDMARK_WARNINGS})
target_compile_definitions(windmark_core_tests PRIVATE
  WINDMARK_DATA_DIR="${WINDMARK_DATA_DIR}"
  WINDMARK_VECTORS_FILE="${CMAKE_CURRENT_SOURCE_DIR}/vectors/math_vectors.txt")

# The test cases of the doctest suite "long" (full races run to the close) are a ctest entry of their own with the
# label `long`: `ctest -LE long` is the quick run (it also leaves out `ai_long`), `ctest -L '^long$'` runs only them.
add_test(NAME core_tests COMMAND windmark_core_tests --test-suite-exclude=long)
add_test(NAME core_long COMMAND windmark_core_tests --test-suite=long)
set_tests_properties(core_long PROPERTIES LABELS long)

# Environment tests (wind.md, sea.md, wind_shadow.md) and their vector file writer.
target_sources(windmark_core_tests PRIVATE
  test_wind.cpp
  test_sea.cpp
  test_shadow.cpp
  test_env_vectors.cpp
)
target_compile_definitions(windmark_core_tests PRIVATE
  WINDMARK_ENV_VECTORS_FILE="${CMAKE_CURRENT_SOURCE_DIR}/vectors/env_vectors.txt")
# Venue physics file loader (data_format.md §6).
target_sources(windmark_core_tests PRIVATE
  test_venue.cpp
  test_land_index.cpp
)
# collisions (WM-008)
target_sources(windmark_core_tests PRIVATE
  test_collide.cpp
)
add_executable(windmark_gen_env_vectors ../tools/gen_env_vectors.cpp)
target_link_libraries(windmark_gen_env_vectors PRIVATE windmark_core)
target_include_directories(windmark_gen_env_vectors PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(windmark_gen_env_vectors PRIVATE ${WINDMARK_WARNINGS})

# Writes tests/vectors/math_vectors.txt from this build (run it only to regenerate the file on purpose).
add_executable(windmark_gen_vectors ../tools/gen_math_vectors.cpp)
target_link_libraries(windmark_gen_vectors PRIVATE windmark_core)
target_compile_options(windmark_gen_vectors PRIVATE ${WINDMARK_WARNINGS})

# The core library must contain no fused multiply-add instruction (conventions.md §5 rule 3).
find_program(WINDMARK_OBJDUMP NAMES llvm-objdump objdump)
if(WINDMARK_OBJDUMP)
  add_test(NAME core_no_fma
           COMMAND ${CMAKE_COMMAND} -DOBJDUMP=${WINDMARK_OBJDUMP} -DLIB=$<TARGET_FILE:windmark_core>
                   -P "${CMAKE_CURRENT_SOURCE_DIR}/check_no_fma.cmake")
endif()
# ... and calls no platform libm transcendental (conventions.md §5 rule 7).
find_program(WINDMARK_NM NAMES llvm-nm nm)
if(WINDMARK_NM)
  add_test(NAME core_no_libm
           COMMAND ${CMAKE_COMMAND} -DNM=${WINDMARK_NM} -DLIB=$<TARGET_FILE:windmark_core>
                   -P "${CMAKE_CURRENT_SOURCE_DIR}/check_no_libm.cmake")
endif()

# course files, race flow, racing rules and the world loop (WM-009)
set(WINDMARK_COURSES_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../game/data/courses" CACHE PATH
    "Course files directory (game/data/courses) the tests load")
target_sources(windmark_core_tests PRIVATE
  test_course.cpp
  test_race.cpp
  test_rules.cpp
  test_world.cpp
  test_full_race.cpp
  test_snapshot.cpp
)
target_compile_definitions(windmark_core_tests PRIVATE WINDMARK_COURSES_DIR="${WINDMARK_COURSES_DIR}")
# Front-end water renderer checks (water_render.md §9): writes the core's sea components, heights, exposure and
# puff samples as JSON for game/tests/run_water_test.sh. Read-only use of the core.
add_executable(windmark_gen_sea_render_samples ../tools/gen_sea_render_samples.cpp)
target_link_libraries(windmark_gen_sea_render_samples PRIVATE windmark_core)
target_include_directories(windmark_gen_sea_render_samples PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(windmark_gen_sea_render_samples PRIVATE ${WINDMARK_WARNINGS})
# AI skippers (WM-010): ai.md. The fast checks and scenarios run in core_tests; the long fleet races of ai.md §15
# are a separate executable and ctest entry with the label `ai_long` (ctest -L ai_long; ctest -LE ai_long skips them).
target_sources(windmark_core_tests PRIVATE
  test_ai.cpp
  test_ai_full_race.cpp  # WM-033 full AI race determinism (suite `long`)
)
add_executable(windmark_ai_race_tests test_main.cpp test_ai_race.cpp)
target_link_libraries(windmark_ai_race_tests PRIVATE windmark_core)
target_include_directories(windmark_ai_race_tests SYSTEM PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/doctest")
target_compile_options(windmark_ai_race_tests PRIVATE ${WINDMARK_WARNINGS})
target_compile_definitions(windmark_ai_race_tests PRIVATE
  WINDMARK_DATA_DIR="${WINDMARK_DATA_DIR}" WINDMARK_COURSES_DIR="${WINDMARK_COURSES_DIR}")
add_test(NAME ai_races COMMAND windmark_ai_race_tests)
set_tests_properties(ai_races PROPERTIES LABELS ai_long)
# Per-tick checksums of a headless race (AI fleet or the scripted full race) for cross-build and cross-architecture
# comparison (WM-033, tools/cross_arch_check.sh), and a per-tick cost profile of a bunched fleet.
add_executable(windmark_race_trace ../tools/race_trace.cpp)
target_link_libraries(windmark_race_trace PRIVATE windmark_core)
target_include_directories(windmark_race_trace PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_compile_options(windmark_race_trace PRIVATE ${WINDMARK_WARNINGS})
target_compile_definitions(windmark_race_trace PRIVATE
  WINDMARK_DATA_DIR="${WINDMARK_DATA_DIR}" WINDMARK_COURSES_DIR="${WINDMARK_COURSES_DIR}")
# Venue conditions and weather modes (race.md §2.1, WM-110); the C API side links the static C API archive.
target_sources(windmark_core_tests PRIVATE
  test_conditions.cpp
)
if(NOT DEFINED WINDMARK_BUILD_CAPI OR WINDMARK_BUILD_CAPI)
  add_executable(windmark_capi_tests test_main.cpp test_capi_conditions.cpp test_capi_render_time.cpp)
  target_link_libraries(windmark_capi_tests PRIVATE windmark_static)
  target_include_directories(windmark_capi_tests PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../src")
  target_include_directories(windmark_capi_tests SYSTEM PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/doctest")
  target_compile_options(windmark_capi_tests PRIVATE ${WINDMARK_WARNINGS})
  target_compile_definitions(windmark_capi_tests PRIVATE
    WINDMARK_DATA_DIR="${WINDMARK_DATA_DIR}" WINDMARK_COURSES_DIR="${WINDMARK_COURSES_DIR}")
  add_test(NAME capi_tests COMMAND windmark_capi_tests)
endif()
