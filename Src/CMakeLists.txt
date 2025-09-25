# update current positions
set(PROJECT_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}/)
set(PROJECT_INCLUDE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/)
set(EXTERNAL_LIB_SRC_DIR ${CMAKE_CURRENT_SOURCE_DIR}../ExternalLib/)

include(cmake/filters/SetProjectFilters.cmake)
include(cmake/SetSourceGroups.cmake)

file(GLOB_RECURSE KataglyphisCppProject_SOURCES "*.cpp")
file(GLOB_RECURSE KataglyphisCppProject_HEADERS "*.hpp")

if(RUST_FEATURES)

  corrosion_import_crate(
    MANIFEST_PATH rusty_code/Cargo.toml
  )
  if(WIN32)
    corrosion_set_env_vars(
              rusty_code
              CXXFLAGS=/EHsc
    )
  else()
   corrosion_set_env_vars(
              rusty_code
              CXXFLAGS=-fexceptions
    ) 
  endif()
  

  corrosion_add_cxxbridge(
    rusty_bridge
    CRATE
    rusty_code
    FILES
    lib.rs
    )
  
endif()

# add the executable
add_executable(${PROJECT_NAME})

if(RUST_FEATURES)
  target_compile_definitions(${PROJECT_NAME} PRIVATE USE_RUST=1)
else()
  target_compile_definitions(${PROJECT_NAME} PRIVATE USE_RUST=0)
endif()

# Treat MSVC or clang-cl on Windows the same way
if(WIN32 AND (MSVC OR (CMAKE_CXX_COMPILER_ID STREQUAL "Clang"
                       AND DEFINED CMAKE_CXX_COMPILER_FRONTEND_VARIANT
                       AND CMAKE_CXX_COMPILER_FRONTEND_VARIANT STREQUAL "MSVC")))
  target_compile_definitions(
    ${PROJECT_NAME}
    PRIVATE
      RELATIVE_RESOURCE_PATH="/../../Resources/"
      RELATIVE_INCLUDE_PATH="/../../Src/"
  )
else()
  target_compile_definitions(
    ${PROJECT_NAME}
    PRIVATE
      RELATIVE_RESOURCE_PATH="/../Resources/"
      RELATIVE_INCLUDE_PATH="/../Src/"
  )
endif()


configure_file(KataglyphisCppProjectConfig.hpp.in "${CMAKE_CURRENT_SOURCE_DIR}/KataglyphisCppProjectConfig.hpp")

target_sources(
  ${PROJECT_NAME}
  PUBLIC ${KataglyphisCppProject_SOURCES}
  PUBLIC FILE_SET
         HEADERS
         BASE_DIRS
         ${PROJECT_INCLUDE_DIR}
         FILES
         ${KataglyphisCppProject_HEADERS})

target_link_libraries(
  ${PROJECT_NAME}
  PUBLIC ${CMAKE_DL_LIBS}
         Threads::Threads
         # enable compiler warnings
         myproject_warnings
         # enable sanitizers
         myproject_options
  PRIVATE GSL spdlog::spdlog nlohmann_json::nlohmann_json)

if(RUST_FEATURES)
  target_link_libraries(${PROJECT_NAME} PUBLIC rusty_code)
endif()
