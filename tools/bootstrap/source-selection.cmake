# Verified source selection. Root includes this after
# the ordinary pristine dependency receipt loop and before JSBSim add_subdirectory.
option(FLIGHT_USE_EVENT_AWARE_JSBSIM "Compatibility selection of ADR014 held-power source" OFF)
set(FLIGHT_JSBSIM_VARIANT "" CACHE STRING "Explicit JSBSim source: upstream, event-aware-constant-power-v1, event-aware-coupled-midpoint-v1; empty preserves the legacy selector")
set_property(CACHE FLIGHT_JSBSIM_VARIANT PROPERTY STRINGS "" upstream event-aware-constant-power-v1 event-aware-coupled-midpoint-v1)
set(FLIGHT_JSBSIM_SOURCE_BUNDLE_ROOT "" CACHE PATH "Complete reviewed corresponding-source bundle root (contains vendor)")
set(selected_variant "${FLIGHT_JSBSIM_VARIANT}")
if(selected_variant STREQUAL "")
  if(FLIGHT_USE_EVENT_AWARE_JSBSIM)
    set(selected_variant event-aware-constant-power-v1)
  else()
    set(selected_variant upstream)
  endif()
elseif(NOT selected_variant MATCHES "^(upstream|event-aware-constant-power-v1|event-aware-coupled-midpoint-v1)$")
  message(FATAL_ERROR "Unknown closed JSBSim source variant")
elseif(FLIGHT_USE_EVENT_AWARE_JSBSIM AND NOT selected_variant STREQUAL "event-aware-constant-power-v1")
  message(FATAL_ERROR "Conflicting JSBSim source variant and legacy held-power selector")
endif()
set(FLIGHT_JSBSIM_HAS_EVENT_API OFF)
set(FLIGHT_JSBSIM_HAS_COUPLED_API OFF)
find_package(Python3 3.12 REQUIRED COMPONENTS Interpreter)
set(FLIGHT_JSBSIM_SOURCE_ROOT "${FLIGHT_DEPENDENCY_ROOT}/jsbsim")
set(JSBSIM_SOURCE_SELECTOR_SCRIPT "${CMAKE_SOURCE_DIR}/tools/bootstrap/source-variant.py")
set(JSBSIM_SOURCE_SELECTOR_ARGUMENTS --source-root "${FLIGHT_JSBSIM_SOURCE_ROOT}")
if(NOT selected_variant STREQUAL "upstream")
  if(NOT FLIGHT_JSBSIM_SOURCE_BUNDLE_ROOT)
    message(FATAL_ERROR "Modified builds require a verified complete source bundle root")
  endif()
  set(FLIGHT_JSBSIM_HAS_EVENT_API ON)
  set(FLIGHT_JSBSIM_SOURCE_ROOT "${FLIGHT_JSBSIM_SOURCE_BUNDLE_ROOT}/vendor")
  if(selected_variant STREQUAL "event-aware-coupled-midpoint-v1")
    set(FLIGHT_JSBSIM_HAS_COUPLED_API ON)
    set(JSBSIM_SOURCE_SELECTOR_SCRIPT "${CMAKE_SOURCE_DIR}/tools/bootstrap/coupled-source-variant.py")
    set(JSBSIM_SOURCE_SELECTOR_ARGUMENTS --coupled-midpoint --source-root "${FLIGHT_JSBSIM_SOURCE_ROOT}")
  else()
    set(JSBSIM_SOURCE_SELECTOR_ARGUMENTS --event-aware --source-root "${FLIGHT_JSBSIM_SOURCE_ROOT}")
  endif()
endif()
execute_process(COMMAND "${Python3_EXECUTABLE}"
  "${JSBSIM_SOURCE_SELECTOR_SCRIPT}" ${JSBSIM_SOURCE_SELECTOR_ARGUMENTS}
  RESULT_VARIABLE JSBSIM_SOURCE_VERIFY_STATUS OUTPUT_VARIABLE JSBSIM_SOURCE_VERIFICATION
  ERROR_VARIABLE JSBSIM_SOURCE_VERIFY_ERROR OUTPUT_STRIP_TRAILING_WHITESPACE)
if(NOT JSBSIM_SOURCE_VERIFY_STATUS EQUAL 0)
  message(FATAL_ERROR "JSBSim source selection rejected: ${JSBSIM_SOURCE_VERIFY_ERROR}")
endif()
string(JSON FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256 GET "${JSBSIM_SOURCE_VERIFICATION}" backend_identity_sha256)
string(JSON FLIGHT_JSBSIM_SOURCE_VARIANT GET "${JSBSIM_SOURCE_VERIFICATION}" source_variant)
string(JSON FLIGHT_JSBSIM_SOURCE_ROOT GET "${JSBSIM_SOURCE_VERIFICATION}" source_root)
file(TO_CMAKE_PATH "${FLIGHT_JSBSIM_SOURCE_ROOT}" FLIGHT_JSBSIM_SOURCE_ROOT)
string(LENGTH "${FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256}" JSBSIM_BACKEND_HASH_LENGTH)
if(NOT JSBSIM_BACKEND_HASH_LENGTH EQUAL 64 OR NOT FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256 MATCHES "^[0-9a-f]+$")
  message(FATAL_ERROR "Source selector returned an invalid backend identity")
endif()
file(GLOB_RECURSE JSBSIM_SELECTED_SOURCE_INPUTS CONFIGURE_DEPENDS "${FLIGHT_JSBSIM_SOURCE_ROOT}/*")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
  "${CMAKE_SOURCE_DIR}/tools/bootstrap/source-selection.cmake"
  "${CMAKE_SOURCE_DIR}/tools/bootstrap/source-variant.py"
  "${CMAKE_SOURCE_DIR}/tools/bootstrap/coupled-source-variant.py"
  "${CMAKE_SOURCE_DIR}/tools/bootstrap/bootstrap.py"
  "${CMAKE_SOURCE_DIR}/third_party/patches/jsbsim/event-aware-constant-power-v1/identity.json"
  "${CMAKE_SOURCE_DIR}/tools/export/jsbsim-event-aware/materialize.py"
  "${CMAKE_SOURCE_DIR}/tools/export/jsbsim-event-aware/verify.py"
  ${JSBSIM_SELECTED_SOURCE_INPUTS})
if(FLIGHT_JSBSIM_HAS_COUPLED_API)
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${CMAKE_SOURCE_DIR}/third_party/patches/jsbsim/event-aware-coupled-midpoint-v1/identity.json"
    "${CMAKE_SOURCE_DIR}/tools/export/jsbsim-coupled-midpoint/materialize.py"
    "${CMAKE_SOURCE_DIR}/tools/export/jsbsim-coupled-midpoint/verify.py")
  add_compile_definitions(FLIGHT_JSBSIM_COUPLED_MIDPOINT_SHAFT=1)
endif()
if(FLIGHT_JSBSIM_HAS_EVENT_API)
  file(GLOB_RECURSE JSBSIM_BUNDLE_INPUTS CONFIGURE_DEPENDS "${FLIGHT_JSBSIM_SOURCE_BUNDLE_ROOT}/*")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${JSBSIM_BUNDLE_INPUTS})
  # Consumers guard the new vendor API so OFF still builds against pristine
  # headers and rejects an event-aware request before executive allocation.
  add_compile_definitions(FLIGHT_JSBSIM_EVENT_AWARE_SHAFT=1)
endif()

set(FLIGHT_JSBSIM_STRICT_FP_OPTIONS "")
if(FLIGHT_JSBSIM_HAS_EVENT_API)
  if(MSVC)
    set(FLIGHT_JSBSIM_STRICT_FP_OPTIONS /fp:strict)
  elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    set(FLIGHT_JSBSIM_STRICT_FP_OPTIONS -fno-fast-math -ffp-contract=off -frounding-math)
  else()
    message(FATAL_ERROR "ADR014 source has no reviewed strict flags for this compiler")
  endif()
endif()

# The archived wrapper does not identify the consuming project's build controls.
# Bind their actual LF-normalized text and selected cache/compiler configuration
# separately; both native fingerprints append this checked build-control hash.
set(JSBSIM_BUILD_CONTROL_PATHS
  CMakeLists.txt CMakePresets.json third_party/dependencies.lock.json
  tools/bootstrap/source-selection.cmake tools/bootstrap/source-variant.py
  tools/bootstrap/coupled-source-variant.py
  tools/bootstrap/build.ps1 tools/bootstrap/bootstrap.py
  native/fdm_jsbsim/CMakeLists.txt native/fdm_jsbsim/ground/CMakeLists.txt
  native/fdm_jsbsim/interactive/CMakeLists.txt tests/fdm/CMakeLists.txt
  native/fdm_jsbsim/interactive/native_identity.gd.in)
set(JSBSIM_BUILD_CONTROL_TEXT "")
foreach(relative_path IN LISTS JSBSIM_BUILD_CONTROL_PATHS)
  set(control_path "${CMAKE_SOURCE_DIR}/${relative_path}")
  file(READ "${control_path}" control_text)
  string(REPLACE "\r\n" "\n" control_text "${control_text}")
  string(SHA256 control_sha "${control_text}")
  string(APPEND JSBSIM_BUILD_CONTROL_TEXT "${relative_path}:${control_sha}\n")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${control_path}")
endforeach()
string(JOIN " " FLIGHT_JSBSIM_STRICT_FP_FLAGS ${FLIGHT_JSBSIM_STRICT_FP_OPTIONS})
string(TOUPPER "${CMAKE_BUILD_TYPE}" JSBSIM_BUILD_TYPE_UPPER)
set(JSBSIM_CONFIGURATION_FLAG_VARIABLE "CMAKE_CXX_FLAGS_${JSBSIM_BUILD_TYPE_UPPER}")
string(APPEND JSBSIM_BUILD_CONTROL_TEXT
  "source_variant:${FLIGHT_JSBSIM_SOURCE_VARIANT}\n"
  "backend_identity:${FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256}\n"
  "compiler:${CMAKE_CXX_COMPILER_ID}-${CMAKE_CXX_COMPILER_VERSION}\n"
  "generator:${CMAKE_GENERATOR}\n"
  "build_type:${CMAKE_BUILD_TYPE}\n"
  "cxx_flags:${CMAKE_CXX_FLAGS}\n"
  "configuration_flags:${${JSBSIM_CONFIGURATION_FLAG_VARIABLE}}\n"
  "msvc_runtime:${CMAKE_MSVC_RUNTIME_LIBRARY}\n"
  "declared_strict_fp_flags:${FLIGHT_JSBSIM_STRICT_FP_FLAGS}\n")
string(SHA256 FLIGHT_JSBSIM_BUILD_CONTROL_SHA256 "${JSBSIM_BUILD_CONTROL_TEXT}")
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/jsbsim-source-build-manifest.txt" CONTENT
"Source variant: ${FLIGHT_JSBSIM_SOURCE_VARIANT}
Selected source root: ${FLIGHT_JSBSIM_SOURCE_ROOT}
Backend identity SHA256: ${FLIGHT_JSBSIM_BACKEND_IDENTITY_SHA256}
Build controls SHA256: ${FLIGHT_JSBSIM_BUILD_CONTROL_SHA256}
Compiler: ${CMAKE_CXX_COMPILER_ID} ${CMAKE_CXX_COMPILER_VERSION}
Generator: ${CMAKE_GENERATOR}
Build configuration: $<CONFIG>
Common CXX flags: ${CMAKE_CXX_FLAGS}
Selected configuration CXX flags: ${${JSBSIM_CONFIGURATION_FLAG_VARIABLE}}
MSVC runtime: ${CMAKE_MSVC_RUNTIME_LIBRARY}
Declared modified-source strict FP flags: ${FLIGHT_JSBSIM_STRICT_FP_FLAGS}
Actual compiler commands must be inspected before numerical execution.
")

# Root invokes this immediately after add_subdirectory(selected-root) creates
# libJSBSim and its Propulsion object target. The historical OFF route keeps
# its existing compiler options.
function(flight_apply_jsbsim_source_flags)
  if(FLIGHT_JSBSIM_HAS_EVENT_API)
    if(NOT TARGET Propulsion)
      message(FATAL_ERROR "Pinned JSBSim Propulsion compilation target is missing")
    endif()
    get_target_property(propulsion_kind Propulsion TYPE)
    if(NOT propulsion_kind STREQUAL "OBJECT_LIBRARY")
      message(FATAL_ERROR "Pinned JSBSim Propulsion must be an object library")
    endif()
    set_property(SOURCE "${FLIGHT_JSBSIM_SOURCE_ROOT}/src/models/propulsion/FGPropeller.cpp"
      TARGET_DIRECTORY Propulsion APPEND PROPERTY COMPILE_OPTIONS ${FLIGHT_JSBSIM_STRICT_FP_OPTIONS})
    if(FLIGHT_JSBSIM_HAS_COUPLED_API)
      set_property(SOURCE "${FLIGHT_JSBSIM_SOURCE_ROOT}/src/models/propulsion/FGPiston.cpp"
        TARGET_DIRECTORY Propulsion APPEND PROPERTY COMPILE_OPTIONS ${FLIGHT_JSBSIM_STRICT_FP_OPTIONS})
    endif()
  endif()
endfunction()
