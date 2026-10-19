cmake_minimum_required(VERSION 3.25)
add_library(flight_resident_grid STATIC
  src/validation.cpp
  src/prepared_grid.cpp
  src/grid_payload.cpp
)
add_library(flight::resident_grid ALIAS flight_resident_grid)
target_compile_features(flight_resident_grid PUBLIC cxx_std_20)
target_include_directories(flight_resident_grid PUBLIC include)
target_link_libraries(flight_resident_grid PUBLIC flight::ground_contract)
if(MSVC)
  target_compile_options(flight_resident_grid PRIVATE /permissive- /W4 /WX /fp:strict /EHsc)
else()
  target_compile_options(flight_resident_grid PRIVATE -Wall -Wextra -Wpedantic -Werror -fno-fast-math -ffp-contract=off)
endif()
