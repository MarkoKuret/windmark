# Headless example of the C API: a race from the spawn to the results, twice, and a free-sailing boat.
enable_language(C)
add_executable(windmark_race_example race_example.c)
target_link_libraries(windmark_race_example PRIVATE windmark)
set_target_properties(windmark_race_example PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
if(NOT MSVC)
  target_link_libraries(windmark_race_example PRIVATE m)
  target_compile_options(windmark_race_example PRIVATE -Wall -Wextra -ffp-contract=off)
endif()
if(WINDMARK_BUILD_TESTS)
  add_test(NAME capi_race_example
           COMMAND windmark_race_example "${WINDMARK_DATA_DIR}" "${WINDMARK_COURSES_DIR}")
endif()
