# ADR024 frozen17 scalar consumer. Parent selects the exact reviewed v2 backend.
if(NOT FLIGHT_JSBSIM_SOURCE_VARIANT STREQUAL "jsbsim-1.3.1-event-aware-coupled-midpoint-local-window-v2")
  message(FATAL_ERROR "Local-window references require the reviewed v2 source variant")
endif()
if(NOT IS_ABSOLUTE "${REFERENCE_REPOSITORY_ROOT}")
  message(FATAL_ERROR "Provide absolute REFERENCE_REPOSITORY_ROOT")
endif()
if(NOT Python3_EXECUTABLE)
  message(FATAL_ERROR "Pinned Python3 interpreter must be selected by parent")
endif()
set(reference_generated "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(reference_inputs)
foreach(name
    third_party/patches/jsbsim/event-aware-coupled-midpoint-v1/vendor/src/models/propulsion/FGPropeller.cpp
    third_party/patches/jsbsim/event-aware-coupled-midpoint-v1/vendor/src/models/propulsion/FGPropeller.h
    third_party/patches/jsbsim/event-aware-coupled-midpoint-local-window-v2/vendor/src/models/propulsion/FGPropeller.cpp
    third_party/patches/jsbsim/event-aware-coupled-midpoint-local-window-v2/vendor/src/models/propulsion/FGPropeller.h
    docs/evidence/P3/piston-local-window-reference/expected.json
    docs/evidence/P3/piston-local-window-reference/generate.py
    docs/evidence/P3/piston-local-window-reference/README.md
    docs/evidence/P3/piston-local-window-reference/manifest.json
    docs/decisions/024-certified-local-decay-window.md
    tests/engine/shaft-method/probes/driver.template.cpp
    tests/engine/shaft-method/coupled-midpoint-v1/references.json
    tests/engine/shaft-method/coupled-midpoint-v1/native_fixture.py
    docs/decisions/015-source-law-coupled-shaft.md)
  list(APPEND reference_inputs "${REFERENCE_REPOSITORY_ROOT}/${name}")
endforeach()
add_custom_command(OUTPUT "${reference_generated}/driver.cpp"
    "${reference_generated}/immutable_helpers.inc" "${reference_generated}/candidate_helpers.inc"
    "${reference_generated}/source-binding.json"
  COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/prepare.py"
    --repo-root "${REFERENCE_REPOSITORY_ROOT}" --output "${reference_generated}"
  DEPENDS ${reference_inputs} "${CMAKE_CURRENT_SOURCE_DIR}/prepare.py"
    "${CMAKE_CURRENT_SOURCE_DIR}/driver.template.cpp" "${CMAKE_CURRENT_SOURCE_DIR}/CMakeLists.txt"
  VERBATIM)
add_executable(piston_local_window_native "${reference_generated}/driver.cpp")
target_include_directories(piston_local_window_native SYSTEM PRIVATE "${reference_generated}")
set_target_properties(piston_local_window_native PROPERTIES
  CXX_STANDARD 17 CXX_STANDARD_REQUIRED YES CXX_EXTENSIONS NO)
if(MSVC)
  target_compile_options(piston_local_window_native PRIVATE /W4 /WX /fp:strict /Zc:__cplusplus /wd4505 /wd4702)
else()
  target_compile_options(piston_local_window_native PRIVATE -Wall -Wextra -Werror
    -fno-fast-math -ffp-contract=off -frounding-math -Wno-unused-function)
endif()
add_test(NAME piston_local_window_native_references COMMAND piston_local_window_native)
set_tests_properties(piston_local_window_native_references PROPERTIES TIMEOUT 120)
