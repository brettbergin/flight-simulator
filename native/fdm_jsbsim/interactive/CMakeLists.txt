find_package(Threads REQUIRED)
if(NOT TARGET flight::resident_grid)
  add_subdirectory("${CMAKE_SOURCE_DIR}/native/world_core/grid" "${CMAKE_BINARY_DIR}/native/world_core/grid")
endif()
add_library(flight_interactive STATIC src/session.cpp src/prepared_world.cpp)
set_target_properties(flight_interactive PROPERTIES CXX_SCAN_FOR_MODULES OFF)
add_library(flight::interactive ALIAS flight_interactive)
target_compile_features(flight_interactive PUBLIC cxx_std_20)
target_include_directories(flight_interactive PUBLIC include)
target_include_directories(flight_interactive PRIVATE "${CMAKE_SOURCE_DIR}/native/world_core/grid/src")
target_include_directories(flight_interactive SYSTEM PRIVATE "${FLIGHT_JSBSIM_SOURCE_ROOT}/src")
target_link_libraries(flight_interactive PUBLIC flight::fdm_jsbsim flight::ground_contract flight::resident_grid Threads::Threads PRIVATE flight::jsbsim)

# Hash declared public paths and LF-normalized text, never a private prototype path.
# Preserve the accepted wind inputs, then bind the new native cold consumer and proof.
set(INTERACTIVE_SOURCE_PATHS
  native/fdm_jsbsim/interactive/src/session.cpp
  native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp
  native/fdm_jsbsim/interactive/include/flight/interactive/surface.hpp
  tests/interactive/native.cpp
  tests/interactive/negatives.hpp
  native/fdm_jsbsim/interactive/src/model-pins.hpp
  native/fdm_jsbsim/interactive/src/piston-model-pins.hpp
  tests/engine/CMakeLists.txt
  tests/engine/loaded-library.hpp
  tests/engine/native.cpp
  tests/engine/native-mechanism.cpp
  tests/engine/native-validate.py
  tests/engine/native-generate.py
  tests/engine/native-limits.hpp
  tests/engine/native-limits.json
  native/godot_bridge/src/bridge.cpp
  native/godot_bridge/src/codec.hpp
  native/godot_bridge/src/codec.cpp
  native/godot_bridge/src/worker.hpp
  native/godot_bridge/src/worker.cpp
  native/godot_bridge/src/interactive_worker.hpp
  native/godot_bridge/src/interactive_worker.cpp
  native/godot_bridge/src/interactive_bridge.cpp
  native/godot_bridge/src/wire_numbers.hpp
  native/godot_bridge/src/wire_numbers.cpp)

# Resident-world source closure. This static format/ordered roster is the
# reviewed closed companion, not caller-selected build input. Raw manifest
# pinning is external to both hashed input sets; never embed that pin here.
set(RESIDENT_WORLD_SOURCE_PATHS
  native/world_core/grid/src/exact.hpp
  native/world_core/grid/src/validation.hpp
  native/world_core/grid/src/validation.cpp
  native/world_core/grid/src/canonical_frame.hpp
  native/world_core/grid/src/prepared_grid.cpp
  native/world_core/grid/src/grid_payload.cpp
  native/world_core/grid/include/flight/ground/prepared_grid.hpp
  native/world_core/grid/include/flight/ground/grid_payload.hpp
  native/world_core/ground/include/flight/ground/provider.hpp
  native/sim_core/contracts/include/flight/contracts/types.hpp
  native/sim_core/contracts/include/flight/contracts/boundaries.hpp
  native/sim_core/contracts/include/flight/contracts/geodesy.hpp
  native/fdm_jsbsim/interactive/include/flight/interactive/prepared_world.hpp
  native/fdm_jsbsim/interactive/src/prepared_world.cpp
  native/fdm_jsbsim/interactive/src/prepared_world_catalog.hpp
  content/world/catalog/kawo-runtime-v1.json
  native/fdm_jsbsim/include/flight/fdm/model.hpp
  native/fdm_jsbsim/include/flight/fdm/session.hpp
  native/fdm_jsbsim/include/flight/fdm/protocol.hpp
  native/fdm_jsbsim/src/model.cpp
  native/fdm_jsbsim/src/model_hashes.hpp
  native/fdm_jsbsim/src/session.cpp
  native/fdm_jsbsim/src/protocol.cpp)
set(RESIDENT_WORLD_CONTROL_PATHS
  native/world_core/grid/CMakeLists.txt
  native/world_core/ground/CMakeLists.txt
  native/sim_core/contracts/CMakeLists.txt
  tools/interactive-preview/world-catalog.mjs)
function(flight_resident_component_file relative out_sha out_size)
  set(input_path "${CMAKE_SOURCE_DIR}/${relative}")
  if(NOT EXISTS "${input_path}" OR IS_DIRECTORY "${input_path}" OR IS_SYMLINK "${input_path}")
    message(FATAL_ERROR "Resident component input is not an ordinary file: ${relative}")
  endif()
  file(REAL_PATH "${input_path}" real_input)
  cmake_path(NORMAL_PATH input_path OUTPUT_VARIABLE normalized_input)
  if(NOT real_input STREQUAL normalized_input)
    message(FATAL_ERROR "Resident component input alias: ${relative}")
  endif()
  file(SIZE "${input_path}" raw_size)
  if(raw_size GREATER 4194304)
    message(FATAL_ERROR "Resident component text input exceeds4MiB: ${relative}")
  endif()
  file(READ "${input_path}" input_text)
  string(REPLACE "\r\n" "\n" input_text "${input_text}")
  string(SHA256 input_sha "${input_text}")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${input_path}")
  set(${out_sha} "${input_sha}" PARENT_SCOPE)
  set(${out_size} "${raw_size}" PARENT_SCOPE)
endfunction()
set(resident_manifest_path "${CMAKE_SOURCE_DIR}/native/world_core/resident_world/component-v1.json")
if(NOT EXISTS "${resident_manifest_path}" OR IS_DIRECTORY "${resident_manifest_path}" OR IS_SYMLINK "${resident_manifest_path}")
  message(FATAL_ERROR "The reviewed resident component manifest is required")
endif()
file(REAL_PATH "${resident_manifest_path}" resident_manifest_real)
cmake_path(NORMAL_PATH resident_manifest_path OUTPUT_VARIABLE resident_manifest_normal)
file(SIZE "${resident_manifest_path}" resident_manifest_size)
if(NOT resident_manifest_real STREQUAL resident_manifest_normal OR resident_manifest_size GREATER 65536)
  message(FATAL_ERROR "Invalid resident component manifest path/size")
endif()
file(READ "${resident_manifest_path}" resident_manifest_raw)
# Reconstruct one exact canonical ASCII JSON document instead of accepting a
# permissive JSON parser's duplicate keys, numeric coercion or unknown members.
# This checked manifest is LF/no-BOM; any changed formatting is unreviewed too.
set(resident_expected "{\n  \"schema\": \"ResidentWorldComponent/v1\",\n  \"sources\": [")
set(RESIDENT_WORLD_FINGERPRINT_TEXT "resident-world-component-v1\n")
set(resident_total_bytes 0)
foreach(group IN ITEMS source control)
  if(group STREQUAL "source")
    set(resident_paths ${RESIDENT_WORLD_SOURCE_PATHS})
  else()
    string(APPEND resident_expected "\n  ],\n  \"controls\": [")
    set(resident_paths ${RESIDENT_WORLD_CONTROL_PATHS})
  endif()
  set(resident_separator "\n")
  foreach(relative IN LISTS resident_paths)
    flight_resident_component_file("${relative}" input_sha input_size)
    math(EXPR resident_total_bytes "${resident_total_bytes} + ${input_size}")
    if(resident_total_bytes GREATER 16777216)
      message(FATAL_ERROR "Resident component text closure exceeds16MiB")
    endif()
    string(APPEND RESIDENT_WORLD_FINGERPRINT_TEXT "${group}:${relative}:${input_sha}\n")
    string(APPEND resident_expected "${resident_separator}    {\n      \"path\": \"${relative}\",\n      \"sha256\": \"${input_sha}\"\n    }")
    set(resident_separator ",\n")
  endforeach()
endforeach()
string(APPEND resident_expected "\n  ]\n}\n")
if(NOT resident_manifest_raw STREQUAL resident_expected)
  message(FATAL_ERROR "Resident component manifest differs from the exact reviewed closed roster/current LF source bytes")
endif()
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${resident_manifest_path}")
string(SHA256 RESIDENT_WORLD_COMPONENT_SHA256 "${RESIDENT_WORLD_FINGERPRINT_TEXT}")
file(WRITE "${CMAKE_BINARY_DIR}/resident-world-component-fingerprint.txt"
  "${RESIDENT_WORLD_COMPONENT_SHA256}\n${RESIDENT_WORLD_FINGERPRINT_TEXT}")

# Root supplies this only after verifying the complete selected backend closure.
if(NOT DEFINED FLIGHT_JSBSIM_SOURCE_ROOT OR NOT IS_DIRECTORY "${FLIGHT_JSBSIM_SOURCE_ROOT}/src")
  message(FATAL_ERROR "A verified selected JSBSim source root is required")
endif()
string(LENGTH "${FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256}" backend_identity_length)
if(NOT backend_identity_length EQUAL 64 OR NOT FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256 MATCHES "^[0-9a-f]+$")
  message(FATAL_ERROR "Verified JSBSim backend identity hash is required")
endif()
set(INTERACTIVE_FINGERPRINT_TEXT "verified-jsbsim-backend:${FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256}\njsbsim-build-controls:${FLIGHT_JSBSIM_BUILD_CONTROL_SHA256}\nresident-world-component:${RESIDENT_WORLD_COMPONENT_SHA256}\n")
foreach(relative_path IN LISTS INTERACTIVE_SOURCE_PATHS)
  set(input_path "${CMAKE_SOURCE_DIR}/${relative_path}")
  file(READ "${input_path}" input_text)
  string(REPLACE "\r\n" "\n" input_text "${input_text}")
  string(SHA256 input_sha "${input_text}")
  string(APPEND INTERACTIVE_FINGERPRINT_TEXT "${relative_path}:${input_sha}\n")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${input_path}")
endforeach()
string(SHA256 INTERACTIVE_SOURCE_FINGERPRINT "${INTERACTIVE_FINGERPRINT_TEXT}")
file(WRITE "${CMAKE_BINARY_DIR}/interactive-source-fingerprint.txt" "${INTERACTIVE_SOURCE_FINGERPRINT}\n${INTERACTIVE_FINGERPRINT_TEXT}")
# ADR016: this is a build-side expectation, qualified independently by staging.
# Keep generated output outside the source/hash inputs to avoid an identity cycle.
set(interactive_identity_variants
  jsbsim-1.3.1-upstream
  jsbsim-1.3.1-event-aware-constant-power-v1
  jsbsim-1.3.1-event-aware-coupled-midpoint-v1
  jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2)
if(NOT FLIGHT_JSBSIM_SOURCE_VARIANT IN_LIST interactive_identity_variants)
  message(FATAL_ERROR "Generated native identity requires a reviewed source variant")
endif()
foreach(identity_variable FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256
    FLIGHT_JSBSIM_BUILD_CONTROL_SHA256 INTERACTIVE_SOURCE_FINGERPRINT)
  if(NOT DEFINED ${identity_variable})
    message(FATAL_ERROR "Generated native identity requires ${identity_variable}")
  endif()
  string(LENGTH "${${identity_variable}}" identity_length)
  if(NOT identity_length EQUAL 64 OR NOT "${${identity_variable}}" MATCHES "^[0-9a-f]+$")
    message(FATAL_ERROR "Generated native identity requires lowercase SHA256: ${identity_variable}")
  endif()
endforeach()
configure_file("${CMAKE_CURRENT_SOURCE_DIR}/native_identity.gd.in"
  "${CMAKE_BINARY_DIR}/native-identity.gd" @ONLY NEWLINE_STYLE LF)

target_compile_definitions(flight_interactive PRIVATE FLIGHT_INTERACTIVE_SOURCE_SHA256="${INTERACTIVE_SOURCE_FINGERPRINT}")
if(MSVC)
  target_compile_options(flight_interactive PRIVATE /W4 /WX /permissive- /fp:strict)
else()
  target_compile_options(flight_interactive PRIVATE -Wall -Wextra -Wpedantic -Werror -fno-fast-math -ffp-contract=off -frounding-math)
endif()
