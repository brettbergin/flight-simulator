# Source extraction only during build. No native or reference numerical execution.
if(NOT FLIGHT_JSBSIM_HAS_COUPLED_API)
  message(FATAL_ERROR "Coupled probes require the verified schema3 backend")
endif()
set(FLIGHT_COUPLED_PROBE_EXECUTION_RATIFICATION "" CACHE FILEPATH
  "Separate explicit unit execution identity; created after strict compilation")
if(NOT IS_ABSOLUTE "${FLIGHT_COUPLED_PROBE_EXECUTION_RATIFICATION}")
  message(FATAL_ERROR "Coupled build requires an explicit absolute unit authorization path")
endif()
set(probe_generated "${CMAKE_CURRENT_BINARY_DIR}/generated")
set(probe_inputs)
foreach(name CMakeLists.txt prepare.py driver.template.cpp library-probe.cpp chronology-probe.cpp
    terminal-retention.cpp validate.py test_validate.py legacy_compare.py source-chronology.py
    run.py test_portable.py README.md probe-manifest.json)
  list(APPEND probe_inputs "${CMAKE_CURRENT_SOURCE_DIR}/${name}")
endforeach()
set(probe_vendor_inputs
  "${FLIGHT_JSBSIM_SOURCE_ROOT}/src/models/propulsion/FGPropeller.cpp"
  "${FLIGHT_JSBSIM_SOURCE_ROOT}/src/models/propulsion/FGPropeller.h"
  "${FLIGHT_JSBSIM_SOURCE_ROOT}/src/models/propulsion/FGPiston.cpp"
  "${FLIGHT_JSBSIM_SOURCE_ROOT}/src/FGJSBBase.h"
  "${FLIGHT_JSBSIM_SOURCE_ROOT}/src/models/FGPropulsion.cpp")
add_custom_command(OUTPUT
  "${probe_generated}/driver.cpp" "${probe_generated}/extraction-binding.json"
  "${probe_generated}/source-manifest.json" "${probe_generated}/chronology-source-evidence.json"
  COMMAND "${Python3_EXECUTABLE}" -B "${CMAKE_CURRENT_SOURCE_DIR}/prepare.py"
    --vendor-root "${FLIGHT_JSBSIM_SOURCE_ROOT}" --template-root "${CMAKE_CURRENT_SOURCE_DIR}"
    --repo-root "${CMAKE_SOURCE_DIR}" --build-root "${CMAKE_BINARY_DIR}" --output "${probe_generated}"
  DEPENDS ${probe_inputs} ${probe_vendor_inputs}
    "${CMAKE_SOURCE_DIR}/tests/engine/loaded-library.hpp"
    "${CMAKE_SOURCE_DIR}/native/fdm_jsbsim/interactive/src/session.cpp"
    "${CMAKE_BINARY_DIR}/jsbsim-source-build-manifest.txt"
    "${CMAKE_BINARY_DIR}/interactive-source-fingerprint.txt"
  VERBATIM)
add_executable(coupled_kernel_probe "${probe_generated}/driver.cpp")
add_executable(coupled_library_probe library-probe.cpp)
add_executable(coupled_chronology_probe chronology-probe.cpp)
add_executable(coupled_terminal_retention terminal-retention.cpp)
foreach(target coupled_library_probe coupled_chronology_probe coupled_terminal_retention)
  target_link_libraries(${target} PRIVATE flight::jsbsim ${CMAKE_DL_LIBS})
  target_include_directories(${target} PRIVATE "${CMAKE_SOURCE_DIR}/tests/engine")
  target_include_directories(${target} SYSTEM PRIVATE "${FLIGHT_JSBSIM_SOURCE_ROOT}/src")
  target_compile_features(${target} PRIVATE cxx_std_20)
endforeach()
target_link_libraries(coupled_terminal_retention PRIVATE flight::interactive)
# Exact production helpers use C++17; explicitly override the parent C++20 mode.
set_target_properties(coupled_kernel_probe PROPERTIES
  CXX_STANDARD 17 CXX_STANDARD_REQUIRED YES CXX_EXTENSIONS NO)
foreach(target coupled_kernel_probe coupled_library_probe coupled_chronology_probe coupled_terminal_retention)
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4 /WX /fp:strict /Zc:__cplusplus)
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra -Werror -fno-fast-math -ffp-contract=off -frounding-math)
  endif()
endforeach()
if(MSVC)
  # Unused retained helpers and noreturn fallback in the verbatim extraction.
  target_compile_options(coupled_kernel_probe PRIVATE /wd4505 /wd4702)
else()
  target_compile_options(coupled_kernel_probe PRIVATE -Wno-unused-function)
endif()
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/coupled-probes-config.json" CONTENT
"{\n\
  \"schema\": \"coupled-probe-config-v1\",\n\
  \"repository_root\": \"${CMAKE_SOURCE_DIR}\",\n\
  \"build_root\": \"${CMAKE_BINARY_DIR}\",\n\
  \"vendor_root\": \"${FLIGHT_JSBSIM_SOURCE_ROOT}\",\n\
  \"source_manifest\": \"${probe_generated}/source-manifest.json\",\n\
  \"model_root\": \"${CMAKE_SOURCE_DIR}/native/fdm_jsbsim/models/original-piston-prop\",\n\
  \"kernel\": \"$<TARGET_FILE:coupled_kernel_probe>\",\n\
  \"library\": \"$<TARGET_FILE:coupled_library_probe>\",\n\
  \"chronology\": \"$<TARGET_FILE:coupled_chronology_probe>\",\n\
  \"terminal\": \"$<TARGET_FILE:coupled_terminal_retention>\",\n\
  \"dll\": \"$<TARGET_FILE:libJSBSim>\"\n\
}\n")
add_test(NAME coupled_shaft_math COMMAND "${Python3_EXECUTABLE}" -B
  "${CMAKE_CURRENT_SOURCE_DIR}/run.py" math)
set_tests_properties(coupled_shaft_math PROPERTIES TIMEOUT 120 FIXTURES_SETUP coupled_math)
add_test(NAME coupled_shaft_native COMMAND "${Python3_EXECUTABLE}" -B
  "${CMAKE_CURRENT_SOURCE_DIR}/run.py" execute
  --config "${CMAKE_BINARY_DIR}/coupled-probes-config.json"
  --ratification "${FLIGHT_COUPLED_PROBE_EXECUTION_RATIFICATION}"
  --output-root "${CMAKE_BINARY_DIR}/coupled-unit-proof")
set_tests_properties(coupled_shaft_native PROPERTIES TIMEOUT 180
  ENVIRONMENT "JSBSIM_DEBUG=0" FIXTURES_REQUIRED coupled_math FIXTURES_SETUP coupled_native)
# The parent adds the physical test's requirement in its registration directory.
