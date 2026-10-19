add_executable(interactive_tests native.cpp)
target_compile_features(interactive_tests PRIVATE cxx_std_20)
target_link_libraries(interactive_tests PRIVATE flight::interactive)
if(MSVC)
  target_compile_options(interactive_tests PRIVATE /W4 /WX /permissive-)
else()
  target_compile_options(interactive_tests PRIVATE -Wall -Wextra -Wpedantic -Werror)
endif()
set(INTERACTIVE_MODELS "${CMAKE_SOURCE_DIR}/native/fdm_jsbsim/models/original-interactive")
set(INTERACTIVE_EVIDENCE "${CMAKE_BINARY_DIR}/interactive-proof")
file(MAKE_DIRECTORY "${INTERACTIVE_EVIDENCE}")
add_test(NAME interactive_loop COMMAND interactive_tests "${INTERACTIVE_MODELS}" "${INTERACTIVE_EVIDENCE}/ctest-ground")
add_test(NAME interactive_negative_readback COMMAND interactive_tests "${INTERACTIVE_MODELS}" "${INTERACTIVE_EVIDENCE}/ctest-checks" negatives)
# ADR027: actual closed old/new start matrix and independent PARK1 pose/gear.
# Pristine qualifies legacy only and asserts both piston recipes reject.
add_test(NAME interactive_apron_starts COMMAND interactive_tests
  "${INTERACTIVE_MODELS}" "${INTERACTIVE_EVIDENCE}/ctest-apron" apron
  "${CMAKE_SOURCE_DIR}/native/fdm_jsbsim/models/original-piston-prop")
set_tests_properties(interactive_loop interactive_negative_readback interactive_apron_starts
  PROPERTIES ENVIRONMENT "JSBSIM_DEBUG=0" TIMEOUT 120)

# Closed KAWO runtime checks; retained source pose is independent of Session.
add_executable(kawo_readiness kawo/readiness.cpp)
target_link_libraries(kawo_readiness PRIVATE flight::interactive)
target_include_directories(kawo_readiness PRIVATE "${CMAKE_SOURCE_DIR}/native/world_core/grid/src")
add_executable(kawo_journey kawo/journey.cpp
  "${CMAKE_SOURCE_DIR}/native/godot_bridge/src/interactive_worker.cpp")
target_include_directories(kawo_journey PRIVATE "${CMAKE_SOURCE_DIR}/native/godot_bridge/src")
target_link_libraries(kawo_journey PRIVATE flight::interactive)
target_compile_definitions(kawo_journey PRIVATE
  KAWO_START_REFERENCE_HEADER="${CMAKE_CURRENT_SOURCE_DIR}/kawo/start-fixture/reference.hpp")
foreach(target kawo_readiness kawo_journey)
  if(MSVC)
    target_compile_options(${target} PRIVATE /W4 /WX /permissive- /fp:strict /EHsc)
  else()
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic -Werror -fno-fast-math -ffp-contract=off)
  endif()
endforeach()
# Separate ordinary engineering-test payload; never the user's installed game.
set(KAWO_PROOF_PAYLOAD "${INTERACTIVE_EVIDENCE}/kawo-payload")
foreach(relative inventory.json
    aircraft/original-interactive/original-interactive.xml
    engine/original-synthetic-thrust.xml engine/original-synthetic-direct.xml)
  get_filename_component(directory "${KAWO_PROOF_PAYLOAD}/models/${relative}" DIRECTORY)
  file(MAKE_DIRECTORY "${directory}")
  configure_file("${INTERACTIVE_MODELS}/${relative}"
    "${KAWO_PROOF_PAYLOAD}/models/${relative}" COPYONLY)
endforeach()
file(MAKE_DIRECTORY "${KAWO_PROOF_PAYLOAD}/worlds/kawo-prototype-v1")
foreach(name world.json ground.fgrd airport.json dossier.json compile-receipt.json start-ready34.json NOTICE.txt)
  configure_file("${CMAKE_SOURCE_DIR}/content/world/airports/kawo/runtime-v1/${name}"
    "${KAWO_PROOF_PAYLOAD}/worlds/kawo-prototype-v1/${name}" COPYONLY)
endforeach()
add_test(NAME kawo_readiness COMMAND kawo_readiness)
add_test(NAME kawo_startup COMMAND kawo_journey actual "${KAWO_PROOF_PAYLOAD}/models" 0)
add_test(NAME kawo_ground_contact COMMAND kawo_journey actual "${KAWO_PROOF_PAYLOAD}/models" 240)
set_tests_properties(kawo_readiness kawo_startup kawo_ground_contact
  PROPERTIES ENVIRONMENT "JSBSIM_DEBUG=0" TIMEOUT 120)
