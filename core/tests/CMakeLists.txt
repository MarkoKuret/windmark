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
)

# boat and sails (WM-006)
target_sources(windmark_core_tests PRIVATE
  test_boat.cpp
)
target_link_libraries(windmark_core_tests PRIVATE windmark_core)
target_include_directories(windmark_core_tests SYSTEM PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/doctest")
target_compile_options(windmark_core_tests PRIVATE ${WINDMARK_WARNINGS})
target_compile_definitions(windmark_core_tests PRIVATE
  WINDMARK_DATA_DIR="${WINDMARK_DATA_DIR}"
  WINDMARK_VECTORS_FILE="${CMAKE_CURRENT_SOURCE_DIR}/vectors/math_vectors.txt")

add_test(NAME core_tests COMMAND windmark_core_tests)

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
