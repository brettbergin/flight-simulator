find_package(Threads REQUIRED)
add_library(flight_interactive STATIC src/session.cpp)
add_library(flight::interactive ALIAS flight_interactive)
target_compile_features(flight_interactive PUBLIC cxx_std_20)
target_include_directories(flight_interactive PUBLIC include)
target_include_directories(flight_interactive SYSTEM PRIVATE "${FLIGHT_DEPENDENCY_ROOT}/jsbsim/src")
target_link_libraries(flight_interactive PUBLIC flight::fdm_jsbsim flight::ground_contract Threads::Threads PRIVATE flight::jsbsim)

# Hash declared public paths and LF-normalized text, never a private prototype path.
# These six source inputs bind both the adapter and its actual scripted proof driver.
set(INTERACTIVE_SOURCE_PATHS
  native/fdm_jsbsim/interactive/src/session.cpp
  native/fdm_jsbsim/interactive/include/flight/interactive/session.hpp
  native/fdm_jsbsim/interactive/include/flight/interactive/surface.hpp
  tests/interactive/native.cpp
  tests/interactive/negatives.hpp
  native/fdm_jsbsim/interactive/src/model-pins.hpp)
set(INTERACTIVE_FINGERPRINT_TEXT "")
foreach(relative_path IN LISTS INTERACTIVE_SOURCE_PATHS)
  set(input_path "${CMAKE_SOURCE_DIR}/${relative_path}")
  file(READ "${input_path}" input_text)
  string(REPLACE "\r\n" "\n" input_text "${input_text}")
  string(SHA256 input_sha "${input_text}")
  string(APPEND INTERACTIVE_FINGERPRINT_TEXT "${relative_path}:${input_sha}\n")
  set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${input_path}")
endforeach()
string(SHA256 INTERACTIVE_SOURCE_FINGERPRINT "${INTERACTIVE_FINGERPRINT_TEXT}")
target_compile_definitions(flight_interactive PRIVATE FLIGHT_INTERACTIVE_SOURCE_SHA256="${INTERACTIVE_SOURCE_FINGERPRINT}")
if(MSVC)
  target_compile_options(flight_interactive PRIVATE /W4 /WX /permissive-)
else()
  target_compile_options(flight_interactive PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()
