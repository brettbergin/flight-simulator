find_package(Threads REQUIRED)
add_library(flight_interactive STATIC src/session.cpp)
add_library(flight::interactive ALIAS flight_interactive)
target_compile_features(flight_interactive PUBLIC cxx_std_20)
target_include_directories(flight_interactive PUBLIC include)
target_include_directories(flight_interactive SYSTEM PRIVATE "${FLIGHT_DEPENDENCY_ROOT}/jsbsim/src")
target_link_libraries(flight_interactive PUBLIC flight::fdm_jsbsim flight::ground_contract Threads::Threads PRIVATE flight::jsbsim)

# Hash declared public paths and LF-normalized text, never a private prototype path.
# Keep the accepted six paths, then explicitly bind new profile/bridge/test dependencies.
set(INTERACTIVE_SOURCE_PATHS
  native/fdm_jsbsim/interactive/src/session.cpp
  native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp
  native/fdm_jsbsim/interactive/include/flight/interactive/surface.hpp
  tests/interactive/native.cpp
  tests/interactive/negatives.hpp
  native/fdm_jsbsim/interactive/src/model-pins.hpp
  CMakeLists.txt
  native/fdm_jsbsim/CMakeLists.txt
  native/fdm_jsbsim/include/flight/fdm/model.hpp
  native/fdm_jsbsim/include/flight/fdm/protocol.hpp
  native/fdm_jsbsim/include/flight/fdm/session.hpp
  native/fdm_jsbsim/interactive/CMakeLists.txt
  native/fdm_jsbsim/interactive/src/piston-model-pins.hpp
  native/fdm_jsbsim/src/model.cpp
  native/fdm_jsbsim/src/protocol.cpp
  native/fdm_jsbsim/src/session.cpp
  native/godot_bridge/CMakeLists.txt
  native/godot_bridge/src/bridge.cpp
  native/godot_bridge/src/codec.cpp
  native/godot_bridge/src/codec.hpp
  native/godot_bridge/src/interactive_bridge.cpp
  native/godot_bridge/src/interactive_worker.cpp
  native/godot_bridge/src/interactive_worker.hpp
  native/godot_bridge/src/worker.cpp
  native/godot_bridge/src/worker.hpp
  native/sim_core/contracts/include/flight/contracts/boundaries.hpp
  native/sim_core/contracts/include/flight/contracts/geodesy.hpp
  native/sim_core/contracts/include/flight/contracts/types.hpp
  native/world_core/ground/include/flight/ground/provider.hpp
  tests/engine/CMakeLists.txt
  tests/engine/native-generate.py
  tests/engine/native-limits.hpp
  tests/engine/native-limits.json
  tests/engine/native-mechanism.cpp
  tests/engine/native-validate.py
  tests/engine/native.cpp
  tests/engine/reference/expected-v3.json
  tests/engine/reference/generate.py
  tests/engine/reference/reference-manifest-v3.json
  third_party/dependencies.lock.json)
get_filename_component(INTERACTIVE_REPOSITORY_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
set(INTERACTIVE_FINGERPRINT_TEXT "")
foreach(relative_path IN LISTS INTERACTIVE_SOURCE_PATHS)
  set(input_path "${INTERACTIVE_REPOSITORY_ROOT}/${relative_path}")
  file(READ "${input_path}" input_text)
  string(REPLACE "\r\n" "\n" input_text "${input_text}")
  string(SHA256 input_sha "${input_text}")
  string(APPEND INTERACTIVE_FINGERPRINT_TEXT "${relative_path}:${input_sha}\n")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${input_path}")
endforeach()
string(SHA256 INTERACTIVE_SOURCE_FINGERPRINT "${INTERACTIVE_FINGERPRINT_TEXT}")
file(WRITE "${CMAKE_BINARY_DIR}/interactive-source-fingerprint.txt" "${INTERACTIVE_SOURCE_FINGERPRINT}\n${INTERACTIVE_FINGERPRINT_TEXT}")
target_compile_definitions(flight_interactive PRIVATE FLIGHT_INTERACTIVE_SOURCE_SHA256="${INTERACTIVE_SOURCE_FINGERPRINT}")
if(MSVC)
  target_compile_options(flight_interactive PRIVATE /W4 /WX /permissive-)
else()
  target_compile_options(flight_interactive PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()
