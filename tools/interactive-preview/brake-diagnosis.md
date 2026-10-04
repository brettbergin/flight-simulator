# Synthetic brake diagnosis

Original MIT diagnostic for [issue #108](https://github.com/brettbergin/flight-simulator/issues/108). It links the existing accepted native libraries; it does not change a model, solver, runtime API or aircraft state directly. All inputs are synthetic `scenario.proof` commands. No pilot profile, user flight log or real-aircraft calibration data is included.

The [exact probe source](brake-diagnosis.cpp) produced these [13 retained outcomes](../../docs/evidence/P1/brake-diagnosis.ndjson) at 120 Hz/seed 42, with the unchanged [ADR 006 model and world](../../docs/decisions/006-interactive-prototype.md). Ground trials visibly settle for 600 ticks, accelerate to 10/20/30 m/s, then compare released/half/full brakes with throttle zero. One 20 m/s trial retains full throttle. Three trials copy the accepted scripted flight until touchdown, changing only rollout brake fraction. No state injection, implicit ground snap or hidden throttle reduction occurs.

Stop means actual speed below 0.1 m/s and all three native WOW flags true. Ground runs cap at 60 seconds; flight rollout caps at 120 seconds. A non-stop result remains a non-stop. Horizontal distance sums actual completed-tick movements in the prepared tangent frame. Sparse snapshot/CSV diagnostics are written beside each outcome when reproduced; these are test artifacts only.

Full brakes stopped the 10/20/30 m/s ground trials in 13.21/51.87/118.77 m. Half brakes took 23.62/92.09/208.41 m. Released brakes travelled 563.83/1047.09/1475.73 m after 60 seconds and remained moving. Full throttle at 20 m/s extended the full-brake stop to 110.15 m. Scripted touchdown at 51.998 m/s took 400.15 m with full brakes, 667.80 m with half brakes, and did not stop within 120 seconds with released brakes. This proves connected, load-dependent prototype braking in these tests, not C172 stopping performance. The scripted touchdown is beyond the rendered runway's north end; it is a solver-transition test, not airport/pattern acceptance.

Native mains use LEFT/RIGHT brake groups; the nose has no brake. JSBSim's bogey longitudinal force cap uses rolling coefficient plus brake fraction times the static-minus-rolling difference: released/half/full coefficients are 0.01/0.405/0.8. Normal load and solved wheel force remain authoritative; residual lift and load transfer reduce braking capacity at high speed. The idealized turbine has 100 N source-derived steady idle thrust and actual spool-down; throttle zero is not instantaneous zero thrust.

## Reproduce using an existing native build

Use the [pinned bootstrap](../bootstrap/README.md) prerequisites/compiler environment and an already built `.local/build/native-release`. This recipe builds only one diagnostic translation unit. It does not rebuild native dependencies or change repository CMake. On Windows use an x64 MSVC v143 developer shell matching the existing dynamic-CRT build. The CMake recipe also describes Linux library discovery; only the recorded Windows run is claimed here.

Save the following as ignored `.local/brake-diagnosis/CMakeLists.txt`:

~~~cmake
cmake_minimum_required(VERSION 3.31)
project(SyntheticBrakeDiagnosis LANGUAGES CXX)
set(REPO "" CACHE PATH "Repository root")
set(NATIVE_BUILD "" CACHE PATH "Existing accepted native build")
set(CMAKE_MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
foreach(component flight_interactive flight_fdm_jsbsim JSBSim)
  find_library(LIB_${component} NAMES ${component}
    PATHS "${NATIVE_BUILD}/lib" "${NATIVE_BUILD}/bin"
    NO_DEFAULT_PATH REQUIRED)
endforeach()
find_package(Threads REQUIRED)
add_executable(brake_diagnosis "${REPO}/tools/interactive-preview/brake-diagnosis.cpp")
target_compile_features(brake_diagnosis PRIVATE cxx_std_20)
target_include_directories(brake_diagnosis PRIVATE
  "${REPO}/native/fdm_jsbsim/interactive/include"
  "${REPO}/native/fdm_jsbsim/include"
  "${REPO}/native/sim_core/contracts/include"
  "${REPO}/native/world_core/ground/include")
target_link_libraries(brake_diagnosis PRIVATE ${LIB_flight_interactive}
  ${LIB_flight_fdm_jsbsim} ${LIB_JSBSim} Threads::Threads ${CMAKE_DL_LIBS})
set_target_properties(brake_diagnosis PROPERTIES
  BUILD_RPATH "${NATIVE_BUILD}/bin")
if(MSVC)
  target_compile_options(brake_diagnosis PRIVATE /W4 /WX /permissive-)
  add_custom_command(TARGET brake_diagnosis POST_BUILD
    COMMAND "${CMAKE_COMMAND}" -E copy_if_different
      "${NATIVE_BUILD}/bin/JSBSim.dll" "$<TARGET_FILE_DIR:brake_diagnosis>/JSBSim.dll")
endif()
~~~

From the repository root, using PowerShell and the pinned tools:

~~~powershell
$diagnosticRepo = (Get-Location).Path
$diagnosticCmake = Join-Path $diagnosticRepo '.local/toolchain/cmake/bin/cmake'
$diagnosticNinja = Join-Path $diagnosticRepo '.local/toolchain/ninja/ninja'
& $diagnosticCmake -S .local/brake-diagnosis -B .local/brake-diagnosis/build -G Ninja `
  '-DCMAKE_BUILD_TYPE=Release' "-DCMAKE_MAKE_PROGRAM=$diagnosticNinja" `
  "-DREPO=$diagnosticRepo" "-DNATIVE_BUILD=$diagnosticRepo/.local/build/native-release"
& $diagnosticCmake --build .local/brake-diagnosis/build
# On Linux omit the .exe suffix. Runtime CRT must match the existing Windows build.
New-Item -ItemType Directory -Force .local/brake-diagnosis/results | Out-Null
$env:JSBSIM_DEBUG = '0'
& .local/brake-diagnosis/build/brake_diagnosis.exe `
  native/fdm_jsbsim/models/original-interactive .local/brake-diagnosis/results
$diagnosticRows = Get-Content .local/brake-diagnosis/results/summary.ndjson |
  ForEach-Object { ConvertFrom-Json $_ }
if ($diagnosticRows.Count -ne 13 -or
    @($diagnosticRows | Where-Object {
      $_.source_fingerprint -ne '35cf7b603d99b9accb123405f7569a901ed9e28d32110acbc296b376facd6416' -or
      $_.world_sha256 -ne '04bff5a0bcf3509990f6276b2548a28268f57fc96d218a7ca51cab1990ec1ff5'
    }).Count -ne 0) { throw 'Diagnostic model/world/source receipt mismatch' }
~~~

Native initialization verifies the frozen inventory/XML and prepared world before allocating the executive. Use the compiler/build receipts for the linked libraries; checking a printed fingerprint alone does not replace library provenance. Reject a different compiled fingerprint when comparing to this retained packet. Exact outcomes across another compiler/platform are not promised.

Recorded Windows source SHA-256: `54d8c4a8b39c55f116982b1a75b12a70479d138719f81ebefcb6d6bba74d51dc`; Captured Windows 13-row NDJSON byte SHA-256 (CRLF): `387a89e0a2ef64c666a67a65c222eb5a7d27d157c65af0fbefc780904b2e1875`; repository LF-normalized SHA-256: `5d79e633465c22c01d9d961fe5ed0d58768bb6613a58d369a41b137087e0a4c9`. Newline normalization does not change the 13 JSON records. Private diagnostic executable SHA-256: `a527b5f5f8ca48568aae0fc5fa9d00fe31349b5e85f3cdf67372a5c59b2a1358`; linked JSBSim DLL: `269ebc60feaf8bc9fdd2f2761a46eb5eb06427623f33c67055f21ca65e705150`. Compiler MSVC 19.40.33813.0, JSBSim 1.3.1, CMake 3.31.8/Ninja 1.13.1. Build/run took 5.22 wall seconds after correcting private diagnostic type names. Source/model parameters were never retuned.
