find_package(Threads REQUIRED)
add_library(flight_interactive STATIC src/session.cpp)
add_library(flight::interactive ALIAS flight_interactive)
target_compile_features(flight_interactive PUBLIC cxx_std_20)
target_include_directories(flight_interactive PUBLIC include)
target_include_directories(flight_interactive SYSTEM PRIVATE "${FLIGHT_JSBSIM_SOURCE_ROOT}/src")
target_link_libraries(flight_interactive PUBLIC flight::fdm_jsbsim flight::ground_contract Threads::Threads PRIVATE flight::jsbsim)

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
  tests/engine/native-limits.json)
# Root supplies this only after verifying the complete selected backend closure.
if(NOT DEFINED FLIGHT_JSBSIM_SOURCE_ROOT OR NOT IS_DIRECTORY "${FLIGHT_JSBSIM_SOURCE_ROOT}/src")
  message(FATAL_ERROR "A verified selected JSBSim source root is required")
endif()
string(LENGTH "${FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256}" backend_identity_length)
if(NOT backend_identity_length EQUAL 64 OR NOT FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256 MATCHES "^[0-9a-f]+$")
  message(FATAL_ERROR "Verified JSBSim backend identity hash is required")
endif()
set(INTERACTIVE_FINGERPRINT_TEXT "verified-jsbsim-backend:${FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256}\njsbsim-build-controls:${FLIGHT_JSBSIM_BUILD_CONTROL_SHA256}\n")
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
  jsbsim-1.3.1-event-aware-coupled-midpoint-v1)
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
  target_compile_options(flight_interactive PRIVATE /W4 /WX /permissive-)
else()
  target_compile_options(flight_interactive PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()
