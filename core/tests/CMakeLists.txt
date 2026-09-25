# Test suite: doctest (third_party/doctest, MIT).
add_executable(windmark_core_tests
  test_main.cpp
  test_float_rules.cpp
)
target_link_libraries(windmark_core_tests PRIVATE windmark_core)
target_include_directories(windmark_core_tests SYSTEM PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/doctest")
target_compile_options(windmark_core_tests PRIVATE ${WINDMARK_WARNINGS})

add_test(NAME core_tests COMMAND windmark_core_tests)


# The core library must contain no fused multiply-add instruction (conventions.md §5 rule 3).
find_program(WINDMARK_OBJDUMP NAMES llvm-objdump objdump)
if(WINDMARK_OBJDUMP)
  add_test(NAME core_no_fma
           COMMAND ${CMAKE_COMMAND} -DOBJDUMP=${WINDMARK_OBJDUMP} -DLIB=$<TARGET_FILE:windmark_core>
                   -P "${CMAKE_CURRENT_SOURCE_DIR}/check_no_fma.cmake")
endif()
