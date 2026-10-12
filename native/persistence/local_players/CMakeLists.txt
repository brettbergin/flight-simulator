# Original MIT. Closed ADR026 production core; test factories never enter it.
find_package(Threads REQUIRED)
set(local_players_core_sources
  include/flight/local_players/records.hpp
  src/records.cpp
  include/flight/local_players/codec.hpp
  src/codec.cpp
  include/flight/local_players/filesystem.hpp
  include/flight/local_players/store_access.hpp
  include/flight/local_players/store.hpp
  src/store.cpp
  include/flight/local_players/service.hpp
  src/service.cpp
  include/flight/local_players/storage_identity.hpp
  src/storage_identity.cpp)
foreach(source IN LISTS local_players_core_sources)
  if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
    message(FATAL_ERROR "Missing allocated local-player core source: ${source}")
  endif()
endforeach()
add_library(flight_local_players_core STATIC ${local_players_core_sources})
add_library(flight::local_players_core ALIAS flight_local_players_core)
target_include_directories(flight_local_players_core PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(flight_local_players_core PUBLIC flight::sqlite Threads::Threads)
target_compile_features(flight_local_players_core PUBLIC cxx_std_20)

# The runner emits this output from independently reconstructed source identity
# AFTER the single configure/cache freeze and BEFORE compilation. It is not a
# source-fingerprint input. Missing output fails the build; no fallback digest.
set(local_players_identity_header "${CMAKE_BINARY_DIR}/local-players-generated/compiled_identity.hpp")
set_property(SOURCE src/storage_identity.cpp APPEND PROPERTY OBJECT_DEPENDS "${local_players_identity_header}")
if(MSVC)
  target_compile_options(flight_local_players_core PRIVATE /W4 /WX /permissive- /utf-8)
  set_property(SOURCE src/records.cpp src/codec.cpp APPEND PROPERTY COMPILE_OPTIONS /fp:strict)
  set_property(SOURCE src/storage_identity.cpp APPEND PROPERTY COMPILE_OPTIONS "/FI${local_players_identity_header}")
else()
  target_compile_options(flight_local_players_core PRIVATE -Wall -Wextra -Wpedantic -Werror)
  set_property(SOURCE src/records.cpp src/codec.cpp APPEND PROPERTY COMPILE_OPTIONS -fno-fast-math -ffp-contract=off -frounding-math)
  set_property(SOURCE src/storage_identity.cpp APPEND PROPERTY COMPILE_OPTIONS -include "${local_players_identity_header}")
endif()

if(FLIGHT_BUILD_LOCAL_PLAYERS)
  if(NOT WIN32 OR NOT MSVC)
    message(FATAL_ERROR "The local-player filesystem adapter requires Windows and supported MSVC.")
  endif()
  set(local_players_windows_sources
    include/flight/local_players/windows_filesystem.hpp
    src/windows_filesystem.cpp)
  foreach(source IN LISTS local_players_windows_sources)
    if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/${source}")
      message(FATAL_ERROR "Missing allocated Windows storage source: ${source}")
    endif()
  endforeach()
  add_library(flight_local_players_windows STATIC ${local_players_windows_sources})
  add_library(flight::local_players_windows ALIAS flight_local_players_windows)
  target_include_directories(flight_local_players_windows PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/include")
  target_link_libraries(flight_local_players_windows PUBLIC flight::local_players_core Shell32 Ole32 Bcrypt)
  target_compile_features(flight_local_players_windows PUBLIC cxx_std_20)
  target_compile_definitions(flight_local_players_windows PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
  target_compile_options(flight_local_players_windows PRIVATE /W4 /WX /permissive- /utf-8)
endif()
