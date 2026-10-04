# The Windmark GDExtension: SailShape (sail deformation, sail_visuals.md), SheetRopes (the running sheets, §11.3), the wakes (sea_wakes.h, water_render.md §5) and CoreSim over the core's C API (core/include/windmark.h), for Godot 4.6.
# Build with build.sh (it fetches the pinned godot-cpp); the library and windmark.gdextension go to game/bin/.
cmake_minimum_required(VERSION 3.22)
project(windmark_godot LANGUAGES C CXX)

if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

set(WINDMARK_GODOT_CPP_DIR "${CMAKE_CURRENT_SOURCE_DIR}/third_party/godot-cpp" CACHE PATH "godot-cpp checkout")
set(GODOTCPP_API_VERSION "4.6" CACHE STRING "Godot API version" FORCE)
add_subdirectory("${WINDMARK_GODOT_CPP_DIR}" godot-cpp)

# The core and its C API, built under the core's float rules (conventions.md §5): windmark_static links
# windmark_core, which carries windmark_float_rules to everything that links it.
set(WINDMARK_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WINDMARK_BUILD_CAPI ON CACHE BOOL "" FORCE)
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../../core" core)

add_library(windmark_godot SHARED src/register_types.cpp src/core_sim.cpp src/sail_shape.cpp src/sea_wakes.cpp src/boat_shadow.cpp src/sheet_ropes.cpp)
target_link_libraries(windmark_godot PRIVATE godot-cpp windmark_static)
get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
set(WINDMARK_GODOT_BIN "${CMAKE_CURRENT_SOURCE_DIR}/../bin")
set_target_properties(windmark_godot PROPERTIES
  CXX_STANDARD 20
  CXX_EXTENSIONS OFF
  CXX_VISIBILITY_PRESET hidden
  VISIBILITY_INLINES_HIDDEN ON
  POSITION_INDEPENDENT_CODE ON
  PREFIX "lib"
  OUTPUT_NAME "windmark_godot${GODOTCPP_SUFFIX}"
  LIBRARY_OUTPUT_DIRECTORY "$<1:${WINDMARK_GODOT_BIN}>"
  RUNTIME_OUTPUT_DIRECTORY "$<1:${WINDMARK_GODOT_BIN}>")
if(APPLE)
  set_target_properties(windmark_godot PROPERTIES SUFFIX ".dylib")
endif()
configure_file(windmark.gdextension "${WINDMARK_GODOT_BIN}/windmark.gdextension" COPYONLY)
