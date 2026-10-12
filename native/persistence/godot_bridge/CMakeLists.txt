# Original MIT. Production registration only; no flight/JSBSim/test linkage.
if(NOT WIN32 OR NOT MSVC OR NOT FLIGHT_BUILD_LOCAL_PLAYERS OR NOT FLIGHT_BUILD_GODOT_BINDINGS)
  message(FATAL_ERROR "The production storage extension requires explicit Windows/MSVC storage and bindings.")
endif()
set(local_players_bridge_sources src/local_players.hpp src/local_players.cpp src/register_types.cpp)
foreach(source IN LISTS local_players_bridge_sources)
  if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
    message(FATAL_ERROR "Missing allocated production storage bridge source: ${source}")
  endif()
endforeach()
# Capture the actual INNER link invocation, after CMake appends manifest flags.
# This directory-scoped rule retains the pinned MSVC manifest supervisor. A
# LINKER_LAUNCHER outside vs_link_dll would only witness the supervisor command.
if(NOT CMAKE_VERSION VERSION_EQUAL "3.31.8" OR NOT CMAKE_GENERATOR STREQUAL "Ninja")
  message(FATAL_ERROR "Storage link witnesses require the pinned CMake 3.31.8 Ninja rule.")
endif()
set(FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE "" CACHE FILEPATH "Root-pinned qualification Python executable")
set(FLIGHT_LOCAL_PLAYERS_LINK_PLAN "" CACHE FILEPATH "Root-declared independently admitted direct-link plan")
set(FLIGHT_LOCAL_PLAYERS_LINK_PLAN_DIGEST_FILE "" CACHE FILEPATH "Root-declared postcompile direct-link plan digest file")
set(FLIGHT_LOCAL_PLAYERS_LINK_RECEIPTS "" CACHE PATH "Root-declared existing private link-receipt parent")
foreach(variable IN ITEMS FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE
    FLIGHT_LOCAL_PLAYERS_LINK_PLAN FLIGHT_LOCAL_PLAYERS_LINK_PLAN_DIGEST_FILE FLIGHT_LOCAL_PLAYERS_LINK_RECEIPTS)
  if("${${variable}}" STREQUAL "" OR NOT IS_ABSOLUTE "${${variable}}"
      OR "${${variable}}" MATCHES "[;\r\n\"]" OR "${${variable}}" MATCHES "[<>]")
    message(FATAL_ERROR "Declare an absolute literal Root link-witness path: ${variable}")
  endif()
endforeach()
if(NOT EXISTS "${FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE}"
    OR IS_DIRECTORY "${FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE}")
  message(FATAL_ERROR "Missing explicitly pinned qualification interpreter.")
endif()
set(local_players_qualifier "${PROJECT_SOURCE_DIR}/tools/local-players/qualify.py")
if(NOT EXISTS "${local_players_qualifier}" OR IS_DIRECTORY "${local_players_qualifier}")
  message(FATAL_ERROR "Missing allocated local-player build-witness source.")
endif()
get_property(local_players_global_link_launcher GLOBAL PROPERTY RULE_LAUNCH_LINK)
get_property(local_players_directory_link_launcher DIRECTORY PROPERTY RULE_LAUNCH_LINK)
if(NOT "${CMAKE_CXX_LINKER_LAUNCHER}" STREQUAL ""
    OR NOT "${local_players_global_link_launcher}" STREQUAL ""
    OR NOT "${local_players_directory_link_launcher}" STREQUAL "")
  message(FATAL_ERROR "An outer link launcher cannot substitute for the direct-link witness.")
endif()
string(REGEX MATCHALL "<CMAKE_LINKER>" local_players_linker_slots "${CMAKE_CXX_CREATE_SHARED_LIBRARY}")
list(LENGTH local_players_linker_slots local_players_linker_slot_count)
if(NOT local_players_linker_slot_count EQUAL 1
    OR NOT CMAKE_CXX_CREATE_SHARED_LIBRARY MATCHES " -E vs_link_dll .* -- <CMAKE_LINKER> ")
  message(FATAL_ERROR "Unexpected pinned MSVC shared-library command template.")
endif()
set(local_players_inner_launcher
  "\"${FLIGHT_LOCAL_PLAYERS_PYTHON_EXECUTABLE}\" -I -B \"${local_players_qualifier}\" launch-link --plan \"${FLIGHT_LOCAL_PLAYERS_LINK_PLAN}\" --plan-digest-file \"${FLIGHT_LOCAL_PLAYERS_LINK_PLAN_DIGEST_FILE}\" --receipt-root \"${FLIGHT_LOCAL_PLAYERS_LINK_RECEIPTS}\" -- <CMAKE_LINKER>")
string(REPLACE "<CMAKE_LINKER>" "${local_players_inner_launcher}"
  CMAKE_CXX_CREATE_SHARED_LIBRARY "${CMAKE_CXX_CREATE_SHARED_LIBRARY}")
# Plan/digest files bind actual prerequisite archive bytes. Root compiles and
# admits prerequisites, then exclusively creates these files before building
# this final shared-library target. There is no second configure/cache edit.
# The digest file binds integrity; native execution has separate authorization.
# CMake neither manufactures evidence nor launches native code.
add_library(flight_local_players_bridge SHARED ${local_players_bridge_sources})
get_property(local_players_target_link_launcher TARGET flight_local_players_bridge PROPERTY RULE_LAUNCH_LINK)
get_property(local_players_target_cxx_launcher TARGET flight_local_players_bridge PROPERTY CXX_LINKER_LAUNCHER)
if(NOT "${local_players_target_link_launcher}" STREQUAL ""
    OR NOT "${local_players_target_cxx_launcher}" STREQUAL "")
  message(FATAL_ERROR "Storage target cannot substitute an outer link launcher.")
endif()
target_include_directories(flight_local_players_bridge PRIVATE src)
target_link_libraries(flight_local_players_bridge PRIVATE godot::cpp flight::local_players_core flight::local_players_windows)
target_compile_features(flight_local_players_bridge PRIVATE cxx_std_20)
target_compile_definitions(flight_local_players_bridge PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_compile_options(flight_local_players_bridge PRIVATE /W4 /WX /permissive- /utf-8)
# Direct Variant numeric admission preserves the same strict validator route.
set_property(SOURCE src/local_players.cpp APPEND PROPERTY COMPILE_OPTIONS /fp:strict)
set_target_properties(flight_local_players_bridge PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS OFF)
target_link_options(flight_local_players_bridge PRIVATE "/MAP:${CMAKE_BINARY_DIR}/local-players-storage-link.map" /INCREMENTAL:NO)
