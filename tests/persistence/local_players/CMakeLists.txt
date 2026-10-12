# Original MIT. ADR026 closed test targets; no execution during configure/build.
if(NOT BUILD_TESTING OR NOT TARGET flight::local_players_core)
  message(FATAL_ERROR "Local-player tests require BUILD_TESTING and the actual production core.")
endif()
if(WIN32)
  if(NOT MSVC OR NOT FLIGHT_BUILD_LOCAL_PLAYERS OR NOT TARGET flight::local_players_windows)
    message(FATAL_ERROR "Windows local-player tests require supported MSVC and actual production storage.")
  endif()
  if(NOT FLIGHT_LOCAL_PLAYERS_QUALIFICATION_MODE MATCHES "^(off|windows)$")
    message(FATAL_ERROR "Windows cannot select codec-only storage qualification.")
  endif()
elseif(NOT CMAKE_SYSTEM_NAME STREQUAL "Linux" OR NOT CMAKE_CXX_COMPILER_ID STREQUAL "GNU"
    OR NOT FLIGHT_LOCAL_PLAYERS_QUALIFICATION_MODE STREQUAL "codec"
    OR FLIGHT_BUILD_LOCAL_PLAYERS OR FLIGHT_BUILD_LOCAL_PLAYERS_TEST_BRIDGE)
  message(FATAL_ERROR "Non-Windows storage tests require the explicit Linux/GCC pure-codec mode.")
endif()

# No optional source or substitute target. Header files are roster members too.
function(local_players_require_sources)
  foreach(source IN LISTS ARGN)
    if(NOT EXISTS "${source}" OR IS_DIRECTORY "${source}")
      message(FATAL_ERROR "Missing allocated local-player test source: ${source}")
    endif()
  endforeach()
endfunction()

function(local_players_test_flags target)
  target_compile_features(${target} PRIVATE cxx_std_20)
  target_include_directories(${target} PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4 /WX /permissive- /utf-8 /fp:strict)
    target_compile_definitions(${target} PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror
      -fno-fast-math -ffp-contract=off -frounding-math)
  endif()
endfunction()

set(codec_sources "${CMAKE_CURRENT_SOURCE_DIR}/codec.cpp")
set(codec_reference "${PROJECT_SOURCE_DIR}/tests/persistence/local_players/reference/expected-v1.json")
local_players_require_sources(${codec_sources} "${codec_reference}")
add_executable(local_players_codec_native ${codec_sources})
target_link_libraries(local_players_codec_native PRIVATE flight::local_players_core)
local_players_test_flags(local_players_codec_native)
add_test(NAME local_players_codec COMMAND "$<TARGET_FILE:local_players_codec_native>"
  --reference "${PROJECT_SOURCE_DIR}/tests/persistence/local_players/reference/expected-v1.json")

if(WIN32)
  # These are Root-declared data, not executable discovery or a storage override.
  # Proof parent and authorization may be created AFTER configure/build, only by
  # the explicitly authorized NativeChecks supervisor. No mkdir/open/test here.
  set(FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE "" CACHE FILEPATH "Root-pinned qualification Python executable")
  set(FLIGHT_LOCAL_PLAYERS_PROOF_PARENT "" CACHE PATH "Root-declared private native-proof parent")
  set(FLIGHT_LOCAL_PLAYERS_EXECUTION_AUTHORIZATION "" CACHE FILEPATH "Root native-execution authorization output path")
  foreach(variable IN ITEMS FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE
      FLIGHT_LOCAL_PLAYERS_PROOF_PARENT FLIGHT_LOCAL_PLAYERS_EXECUTION_AUTHORIZATION)
    if("${${variable}}" STREQUAL "" OR NOT IS_ABSOLUTE "${${variable}}"
        OR "${${variable}}" MATCHES "[;\r\n]" OR "${${variable}}" MATCHES "\\$<")
      message(FATAL_ERROR "Declare an absolute literal Root qualification path: ${variable}")
    endif()
  endforeach()
  if(NOT EXISTS "${FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE}"
      OR IS_DIRECTORY "${FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE}")
    message(FATAL_ERROR "The explicitly pinned Python file is missing; no interpreter fallback.")
  endif()
  set(local_players_qualifier "${PROJECT_SOURCE_DIR}/tools/local-players/qualify.py")
  local_players_require_sources("${local_players_qualifier}")

  set(store_sources
    "${CMAKE_CURRENT_SOURCE_DIR}/native.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.hpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/faults/fault_plan.hpp")
  set(service_sources
    "${CMAKE_CURRENT_SOURCE_DIR}/service.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.hpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/faults/fault_plan.hpp")
  set(windows_sources
    "${CMAKE_CURRENT_SOURCE_DIR}/windows.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.hpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/faults/fault_plan.hpp")
  set(crash_sources
    "${CMAKE_CURRENT_SOURCE_DIR}/native.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.hpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/faults/fault_plan.hpp")
  set(crash_actor_sources
    "${CMAKE_CURRENT_SOURCE_DIR}/crash_actor.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.hpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/faults/fault_plan.hpp")
  set(lock_actor_sources
    "${CMAKE_CURRENT_SOURCE_DIR}/faults/lock_actor.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.hpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/faults/fault_plan.hpp")
  local_players_require_sources(${store_sources} ${service_sources} ${windows_sources}
    ${crash_sources} ${crash_actor_sources} ${lock_actor_sources})
  add_executable(local_players_store_native ${store_sources})
  add_executable(local_players_service_native ${service_sources})
  add_executable(local_players_windows_native ${windows_sources})
  add_executable(local_players_crash_native ${crash_sources})
  add_executable(local_players_crash_actor ${crash_actor_sources})
  add_executable(local_players_lock_actor ${lock_actor_sources})
  foreach(target IN ITEMS local_players_store_native local_players_service_native
      local_players_windows_native local_players_crash_native
      local_players_crash_actor local_players_lock_actor)
    target_link_libraries(${target} PRIVATE flight::local_players_core flight::local_players_windows)
    local_players_test_flags(${target})
  endforeach()

  # Qualifier validates exact sources, executable/actor hashes, authorization and
  # descriptor before effects; CTest discovery does not authorize native I/O.
  add_test(NAME local_players_store COMMAND "${FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE}" -I -B
    "${PROJECT_SOURCE_DIR}/tools/local-players/qualify.py" ctest --case store
    --executable "$<TARGET_FILE:local_players_store_native>"
    --proof-root "${FLIGHT_LOCAL_PLAYERS_PROOF_PARENT}"
    --execution-authorization "${FLIGHT_LOCAL_PLAYERS_EXECUTION_AUTHORIZATION}" --suite store)
  add_test(NAME local_players_service COMMAND "${FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE}" -I -B
    "${PROJECT_SOURCE_DIR}/tools/local-players/qualify.py" ctest --case service
    --executable "$<TARGET_FILE:local_players_service_native>"
    --proof-root "${FLIGHT_LOCAL_PLAYERS_PROOF_PARENT}"
    --execution-authorization "${FLIGHT_LOCAL_PLAYERS_EXECUTION_AUTHORIZATION}")
  add_test(NAME local_players_windows COMMAND "${FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE}" -I -B
    "${PROJECT_SOURCE_DIR}/tools/local-players/qualify.py" ctest --case windows
    --executable "$<TARGET_FILE:local_players_windows_native>"
    --proof-root "${FLIGHT_LOCAL_PLAYERS_PROOF_PARENT}"
    --execution-authorization "${FLIGHT_LOCAL_PLAYERS_EXECUTION_AUTHORIZATION}"
    --crash-actor "$<TARGET_FILE:local_players_crash_actor>"
    --lock-actor "$<TARGET_FILE:local_players_lock_actor>")
  add_test(NAME local_players_crash COMMAND "${FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE}" -I -B
    "${PROJECT_SOURCE_DIR}/tools/local-players/qualify.py" ctest --case crash
    --executable "$<TARGET_FILE:local_players_crash_native>"
    --proof-root "${FLIGHT_LOCAL_PLAYERS_PROOF_PARENT}"
    --execution-authorization "${FLIGHT_LOCAL_PLAYERS_EXECUTION_AUTHORIZATION}" --suite crash
    --crash-actor "$<TARGET_FILE:local_players_crash_actor>"
    --lock-actor "$<TARGET_FILE:local_players_lock_actor>")
else()
  message(STATUS "Local-player Linux scope: codec only; four Windows storage gates unavailable.")
endif()

if(FLIGHT_BUILD_LOCAL_PLAYERS_TEST_BRIDGE)
  if(NOT WIN32 OR NOT MSVC OR NOT BUILD_TESTING OR NOT FLIGHT_BUILD_LOCAL_PLAYERS
      OR NOT FLIGHT_BUILD_GODOT_BINDINGS OR NOT TARGET godot::cpp
      OR NOT TARGET flight::local_players_windows)
    message(FATAL_ERROR "Test bridge requires explicit Windows production storage, testing and actual Godot bindings.")
  endif()
  if(NOT DEFINED FLIGHT_LOCAL_PLAYERS_TEST_PACKAGE_DIRECTORY
      OR "${FLIGHT_LOCAL_PLAYERS_TEST_PACKAGE_DIRECTORY}" STREQUAL ""
      OR NOT IS_ABSOLUTE "${FLIGHT_LOCAL_PLAYERS_TEST_PACKAGE_DIRECTORY}"
      OR "${FLIGHT_LOCAL_PLAYERS_TEST_PACKAGE_DIRECTORY}" MATCHES "[;\r\n]"
      OR "${FLIGHT_LOCAL_PLAYERS_TEST_PACKAGE_DIRECTORY}" MATCHES "\\$<")
    message(FATAL_ERROR "Select an explicit absolute literal isolated test package; no production staging fallback.")
  endif()
  # This declaration does not prove physical isolation. Root's package/descriptor
  # admission checks identities and exclusions before loading the test resource.
  # Keep normal build outputs; Root stages the test DLL/resource separately.
  set(test_bridge_sources
    "${PROJECT_SOURCE_DIR}/native/persistence/godot_bridge/src/local_players.hpp"
    "${PROJECT_SOURCE_DIR}/native/persistence/godot_bridge/src/local_players.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.hpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_capability.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/test_bridge.cpp")
  local_players_require_sources(${test_bridge_sources}
    "${CMAKE_CURRENT_SOURCE_DIR}/local_players_test.gdextension")
  add_library(flight_local_players_test_bridge SHARED ${test_bridge_sources})
  target_include_directories(flight_local_players_test_bridge PRIVATE
    "${PROJECT_SOURCE_DIR}/native/persistence/godot_bridge/src")
  target_link_libraries(flight_local_players_test_bridge PRIVATE
    godot::cpp flight::local_players_core flight::local_players_windows)
  local_players_test_flags(flight_local_players_test_bridge)
  # Set here too: source properties in the production bridge's directory do not
  # apply to this independently compiled copy of the SAME admission source.
  set_property(SOURCE "${PROJECT_SOURCE_DIR}/native/persistence/godot_bridge/src/local_players.cpp"
    APPEND PROPERTY COMPILE_OPTIONS /fp:strict)
  set_target_properties(flight_local_players_test_bridge PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS OFF)
endif()

# Source-only export/admission declarations; generation launches no tests.
if(WIN32 AND FLIGHT_LOCAL_PLAYERS_QUALIFICATION_MODE STREQUAL "windows")
  if(NOT CMAKE_VERSION VERSION_EQUAL "3.31.8" OR NOT CMAKE_GENERATOR STREQUAL "Ninja"
      OR NOT FLIGHT_BUILD_LOCAL_PLAYERS_TEST_BRIDGE)
    message(FATAL_ERROR "Full storage test policy requires pinned Ninja/MSVC and the SAME Boundary test bridge.")
  endif()
  foreach(variable IN ITEMS FLIGHT_LOCAL_PLAYERS_TEST_COMPILE_INDEX
      FLIGHT_LOCAL_PLAYERS_TEST_COMPILE_INDEX_DIGEST_FILE FLIGHT_LOCAL_PLAYERS_TEST_COMPILE_RECEIPTS
      FLIGHT_LOCAL_PLAYERS_TEST_LINK_INDEX FLIGHT_LOCAL_PLAYERS_TEST_LINK_INDEX_DIGEST_FILE
      FLIGHT_LOCAL_PLAYERS_TEST_LINK_RECEIPTS)
    set(${variable} "" CACHE FILEPATH "Root-declared independently planned test invocation path")
    if("${${variable}}" STREQUAL "" OR NOT IS_ABSOLUTE "${${variable}}"
        OR "${${variable}}" MATCHES "[;\r\n\"]" OR "${${variable}}" MATCHES "[<>]")
      message(FATAL_ERROR "Declare an absolute literal test witness path: ${variable}")
    endif()
  endforeach()
  function(lp_test_json output value)
    if("${value}" MATCHES "[\r\n\t]" OR "${value}" MATCHES "\\$<")
      message(FATAL_ERROR "Unsupported literal in test policy.")
    endif()
    string(REPLACE "\\" "\\\\" escaped "${value}")
    string(REPLACE "\"" "\\\"" escaped "${escaped}")
    set(${output} "\"${escaped}\"" PARENT_SCOPE)
  endfunction()
  function(lp_test_array output)
    set(result "[")
    set(separator "")
    foreach(value IN LISTS ARGN)
      lp_test_json(encoded "${value}")
      string(APPEND result "${separator}${encoded}")
      set(separator ",")
    endforeach()
    string(APPEND result "]")
    set(${output} "${result}" PARENT_SCOPE)
  endfunction()
  function(lp_test_generated_array output expression)
    set(${output} "[$<$<BOOL:${expression}>:\"$<JOIN:${expression},\",\">\">]" PARENT_SCOPE)
  endfunction()
  get_property(global_launcher GLOBAL PROPERTY RULE_LAUNCH_LINK)
  get_property(directory_launcher DIRECTORY PROPERTY RULE_LAUNCH_LINK)
  if(NOT "${CMAKE_CXX_COMPILER_LAUNCHER}${CMAKE_CXX_LINKER_LAUNCHER}${global_launcher}${directory_launcher}" STREQUAL "")
    message(FATAL_ERROR "Unreviewed outer test launcher.")
  endif()
  set(test_compile_launcher "${FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE}" -I -B
    "${local_players_qualifier}" launch-planned-compile
    --plan-index "${FLIGHT_LOCAL_PLAYERS_TEST_COMPILE_INDEX}"
    --plan-index-digest-file "${FLIGHT_LOCAL_PLAYERS_TEST_COMPILE_INDEX_DIGEST_FILE}"
    --receipt-root "${FLIGHT_LOCAL_PLAYERS_TEST_COMPILE_RECEIPTS}" --)
  # The slot lies INSIDE the pinned manifest supervisor. An outer launcher
  # would observe cmake.exe rather than the real linker and cannot qualify.
  set(test_inner_launcher
    "\"${FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE}\" -I -B \"${local_players_qualifier}\" launch-planned-link --plan-index \"${FLIGHT_LOCAL_PLAYERS_TEST_LINK_INDEX}\" --plan-index-digest-file \"${FLIGHT_LOCAL_PLAYERS_TEST_LINK_INDEX_DIGEST_FILE}\" --receipt-root \"${FLIGHT_LOCAL_PLAYERS_TEST_LINK_RECEIPTS}\" -- <CMAKE_LINKER>")
  foreach(pair IN ITEMS "CMAKE_CXX_LINK_EXECUTABLE;vs_link_exe" "CMAKE_CXX_CREATE_SHARED_LIBRARY;vs_link_dll")
    list(GET pair 0 rule)
    list(GET pair 1 supervisor)
    string(REGEX MATCHALL "<CMAKE_LINKER>" slots "${${rule}}")
    list(LENGTH slots count)
    if(NOT count EQUAL 1 OR NOT "${${rule}}" MATCHES " -E ${supervisor} .* -- <CMAKE_LINKER> ")
      message(FATAL_ERROR "Unexpected pinned inner test link rule: ${rule}")
    endif()
    lp_test_json(original_rule_${supervisor} "${${rule}}")
    string(REPLACE "<CMAKE_LINKER>" "${test_inner_launcher}" ${rule} "${${rule}}")
  endforeach()
  string(TOUPPER "${CMAKE_BUILD_TYPE}" config_upper)
  separate_arguments(language_link_tokens WINDOWS_COMMAND "${CMAKE_CXX_LINK_FLAGS}")
  separate_arguments(console_tokens WINDOWS_COMMAND "${CMAKE_CXX_CREATE_CONSOLE_EXE}")
  lp_test_array(language_link_json ${language_link_tokens})
  lp_test_array(console_json ${console_tokens})
  set(targets_json "[")
  set(target_separator "")
  foreach(target IN ITEMS local_players_codec_native local_players_store_native
      local_players_service_native local_players_windows_native local_players_crash_native
      local_players_crash_actor local_players_lock_actor flight_local_players_test_bridge)
    get_property(target_launcher TARGET ${target} PROPERTY CXX_COMPILER_LAUNCHER)
    get_property(target_link_launcher TARGET ${target} PROPERTY CXX_LINKER_LAUNCHER)
    if(NOT "${target_launcher}${target_link_launcher}" STREQUAL "")
      message(FATAL_ERROR "Unexpected existing target-local test launcher.")
    endif()
    set_property(TARGET ${target} PROPERTY CXX_COMPILER_LAUNCHER "${test_compile_launcher}")
    set_property(TARGET ${target} PROPERTY CXX_SCAN_FOR_MODULES OFF)
    get_property(debug_is_set TARGET ${target} PROPERTY MSVC_DEBUG_INFORMATION_FORMAT SET)
    if(NOT debug_is_set)
      set_property(TARGET ${target} PROPERTY MSVC_DEBUG_INFORMATION_FORMAT "${CMAKE_MSVC_DEBUG_INFORMATION_FORMAT_DEFAULT}")
    endif()
    set_property(TARGET ${target} PROPERTY COMPILE_PDB_NAME "${target}")
    set_property(TARGET ${target} PROPERTY COMPILE_PDB_NAME_${config_upper} "${target}")
    set_property(TARGET ${target} PROPERTY COMPILE_PDB_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/local-players-compiler-pdb/${target}")
    set_property(TARGET ${target} PROPERTY COMPILE_PDB_OUTPUT_DIRECTORY_${config_upper} "${CMAKE_BINARY_DIR}/local-players-compiler-pdb/${target}")
    # Explicit default output declarations make the EXE /implib operand
    # independently derivable too, even though a non-exporting EXE produces no
    # import-library file. It is not a required positive output for an EXE.
    set_target_properties(${target} PROPERTIES ARCHIVE_OUTPUT_NAME "${target}"
      ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib" PDB_NAME "${target}"
      PDB_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
    file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/local-players-compiler-pdb/${target}")
    get_target_property(target_type ${target} TYPE)
    if(target_type STREQUAL "SHARED_LIBRARY")
      set(manifest_id 2)
      set(link_flags "${CMAKE_SHARED_LINKER_FLAGS}")
      set(config_link_flags "${CMAKE_SHARED_LINKER_FLAGS_${config_upper}}")
      set(export_define "${target}_EXPORTS")
      set(import_library "\"$<TARGET_LINKER_FILE:${target}>\"")
      set(console_options "[]")
    elseif(target_type STREQUAL "EXECUTABLE")
      set(manifest_id 1)
      set(link_flags "${CMAKE_EXE_LINKER_FLAGS}")
      set(config_link_flags "${CMAKE_EXE_LINKER_FLAGS_${config_upper}}")
      set(export_define "")
      set(import_library "\"${CMAKE_BINARY_DIR}/lib/${target}.lib\"")
      set(console_options "${console_json}")
    else()
      message(FATAL_ERROR "Unallocated test target kind.")
    endif()
    target_link_options(${target} PRIVATE "/MAP:${CMAKE_BINARY_DIR}/local-players-test-${target}.map" /INCREMENTAL:NO)
    separate_arguments(global_link_tokens WINDOWS_COMMAND "${link_flags}")
    separate_arguments(config_link_tokens WINDOWS_COMMAND "${config_link_flags}")
    lp_test_array(global_link_json ${global_link_tokens})
    lp_test_array(config_link_json ${config_link_tokens})
    lp_test_generated_array(link_options_json "$<TARGET_PROPERTY:${target},LINK_OPTIONS>")
    get_target_property(source_list ${target} SOURCES)
    set(sources_json "[")
    set(source_separator "")
    foreach(source IN LISTS source_list)
      if(NOT source MATCHES "\\.cpp$")
        continue()
      endif()
      cmake_path(ABSOLUTE_PATH source BASE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}" NORMALIZE OUTPUT_VARIABLE absolute_source)
      get_source_file_property(source_options "${absolute_source}" COMPILE_OPTIONS)
      if(source_options STREQUAL "NOTFOUND")
        set(source_options "")
      endif()
      lp_test_json(source_json "${absolute_source}")
      lp_test_array(source_options_json ${source_options})
      string(APPEND sources_json "${source_separator}{\"path\":${source_json},\"options\":${source_options_json}}")
      set(source_separator ",")
    endforeach()
    string(APPEND sources_json "]")
    lp_test_generated_array(defines_json "$<TARGET_PROPERTY:${target},COMPILE_DEFINITIONS>")
    lp_test_generated_array(includes_json "$<TARGET_PROPERTY:${target},INCLUDE_DIRECTORIES>")
    lp_test_generated_array(options_json "$<TARGET_PROPERTY:${target},COMPILE_OPTIONS>")
    if(target_type STREQUAL "SHARED_LIBRARY")
      lp_test_generated_array(system_json "$<TARGET_PROPERTY:godot-cpp,INTERFACE_INCLUDE_DIRECTORIES>")
    else()
      set(system_json "[]")
    endif()
    lp_test_json(export_json "${export_define}")
    set(link_json "{\"kind\":\"${target_type}\",\"output\":\"$<TARGET_FILE:${target}>\",\"import_library\":${import_library},\"link_pdb\":\"$<TARGET_PDB_FILE:${target}>\",\"map\":\"${CMAKE_BINARY_DIR}/local-players-test-${target}.map\",\"global_flags\":${global_link_json},\"configuration_flags\":${config_link_json},\"language_flags\":${language_link_json},\"console_options\":${console_options},\"target_options\":${link_options_json},\"manifest_inputs\":[],\"supervisor_appended_options\":[\"/MANIFEST:EMBED,ID=${manifest_id}\"]}")
    string(APPEND targets_json "${target_separator}{\"target\":\"${target}\",\"language\":\"CXX\",\"defines\":${defines_json},\"includes\":${includes_json},\"system_includes\":${system_json},\"options\":${options_json},\"export_define\":${export_json},\"msvc_runtime\":\"$<TARGET_GENEX_EVAL:${target},$<TARGET_PROPERTY:${target},MSVC_RUNTIME_LIBRARY>>\",\"cxx_modules\":\"OFF\",\"debug_information_format\":\"$<TARGET_GENEX_EVAL:${target},$<TARGET_PROPERTY:${target},MSVC_DEBUG_INFORMATION_FORMAT>>\",\"compiler_pdb\":\"${CMAKE_BINARY_DIR}/local-players-compiler-pdb/${target}/${target}.pdb\",\"output\":\"$<TARGET_FILE:${target}>\",\"sources\":${sources_json},\"link\":${link_json}}")
    set(target_separator ",")
  endforeach()
  string(APPEND targets_json "]")
  # Language/configuration token arrays are independently exported by the
  # production parent after this subdirectory returns, from the same configure.
  # Test policy binds its raw production policy pin before plans are written.
  file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/local-players-test-policy-$<CONFIG>.json"
    CONTENT "{\"schema\":\"LocalPlayersTestCompilePolicy/v1\",\"configuration\":\"$<CONFIG>\",\"production_policy\":\"${CMAKE_BINARY_DIR}/local-players-compile-policy-$<CONFIG>.json\",\"executable_rule\":${original_rule_vs_link_exe},\"shared_rule\":${original_rule_vs_link_dll},\"targets\":${targets_json}}\n")
  set_tests_properties(local_players_codec PROPERTIES TIMEOUT 120)
  set_tests_properties(local_players_store PROPERTIES TIMEOUT 1200)
  set_tests_properties(local_players_service PROPERTIES TIMEOUT 900)
  set_tests_properties(local_players_windows PROPERTIES TIMEOUT 900)
  set_tests_properties(local_players_crash PROPERTIES TIMEOUT 7200)
endif()
