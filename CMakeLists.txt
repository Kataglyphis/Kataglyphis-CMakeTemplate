cmake_minimum_required(VERSION 4.2.1)

#set the project name
project(
  KataglyphisCppProject
  VERSION 0.0.1
  DESCRIPTION "Lore ipsum"
  HOMEPAGE_URL "https://jonasheinle.de/"
  LANGUAGES CXX C)

set(AUTHOR "Jonas Heinle")

set(MYPROJECT_GCC_TOOLCHAIN_PATH
    ""
    CACHE PATH "Optional GCC toolchain root used by Clang and Rust tooling on Linux (for example /opt/gcc-15.2.0)")

include(cmake/PreventInSourceBuilds.cmake)
include(cmake/ProjectOptions.cmake)
include(cmake/MSVCRuntimeConfig.cmake)
include(cmake/RustOptions.cmake)

myproject_setup_options()

myproject_global_options()
myproject_configure_rust()

myproject_local_options()

include(cmake/SystemLibDependencies.cmake)

if(myproject_ENABLE_SANITIZER_ADDRESS)
  if(MSVC)
    # Keep STL annotation settings consistent for all targets (including gtest)
    # to avoid LNK2038 mismatches with AddressSanitizer builds.
    add_compile_definitions(_DISABLE_VECTOR_ANNOTATION _DISABLE_STRING_ANNOTATION)
    if(NOT
       CMAKE_CXX_COMPILER_ID
       STREQUAL
       "Clang")
      add_compile_options(/fsanitize=address /Zi)
      add_link_options(/INCREMENTAL:NO)
    endif()
  else()
    add_compile_options(-fsanitize=address)
    add_link_options(-fsanitize=address)
  endif()

endif()

## Coverage instrumentation is applied per-target by
## myproject_enable_coverage() in cmake/Tests.cmake (invoked from
## cmake/ProjectOptions.cmake). Avoid global add_compile_options/add_link_options
## here so instrumentation is only added to the intended interface target
## and under the explicit Debug guard implemented in that helper.

# Profile-Guided Optimization and profile/coverage control for non-Debug builds
# Provide a simple opt-in for instrumenting profile builds (PGO) and for using
# an existing merged profile (.profdata) when rebuilding with profile use.
# Typical flow:
# 1) Instrument/build/run to generate .profraw: set myproject_ENABLE_PGO=ON and
#    build RelWithDebInfo. Run workloads to produce .profraw files.
# 2) Merge raw profiles: llvm-profdata merge -sparse default.profraw -o merged.profdata
# 3) Rebuild with profile use: set myproject_PGO_PROFILE to the path to merged.profdata
#    and rebuild; the compile/link flags -fprofile-instr-use=<file> are applied.

option(myproject_ENABLE_PGO "Enable PGO instrumentation for RelWithDebInfo/Release builds" OFF)
set(myproject_PGO_PROFILE
    ""
    CACHE PATH "Path to merged PGO profile (.profdata) to use with -fprofile-instr-use")

if(CMAKE_CXX_COMPILER_ID MATCHES ".*Clang")
  # Apply PGO flags to the project interface target instead of globally so
  # that instrumentation is opt-in and only propagates to targets that opt
  # into the project's interface target. myproject_options is created in
  # myproject_local_options() so ensure it exists before applying flags.
  if(TARGET myproject_options)
    if(myproject_PGO_PROFILE)
      # If a profile path is supplied, use it for profile-guided optimizations.
      target_compile_options(myproject_options INTERFACE -fprofile-instr-use=${myproject_PGO_PROFILE})
      target_link_options(myproject_options INTERFACE -fprofile-instr-use=${myproject_PGO_PROFILE})
    elseif(myproject_ENABLE_PGO AND (CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo" OR CMAKE_BUILD_TYPE STREQUAL "Release"))
      # Instrument the build to generate runtime profiles (.profraw).
      target_compile_options(myproject_options INTERFACE -fprofile-instr-generate)
      target_link_options(myproject_options INTERFACE -fprofile-instr-generate)
    endif()
  endif()
endif()

# Ensure MSVC runtime selection is established early so FetchContent and
# subprojects inherit a consistent choice during their configure step. This
# mirrors the logic in cmake/ProjectOptions.cmake but must run before
# add_subdirectory(FetchContent consumers) so dependencies (Abseil, etc.) are
# configured with the intended runtime selection (avoids /MDd vs /MD mismatches
# when using clang-cl + AddressSanitizer).
myproject_configure_msvc_runtime()

add_subdirectory(ExternalLib)

# If the nlohmann.json module target was created, expose a compile-time macro
# so consumer module units can conditionally import the module. This lets
# translation units fall back to the header-only include if the module BMI
# cannot be used due to configuration mismatches (for example differing
# exception handling settings between provider and consumer).
if(TARGET nlohmann_json_modules)
  add_compile_definitions(NLOHMANN_JSON_MODULE_AVAILABLE=1)
endif()

# If the tomlplusplus module provider was created, expose a compile-time macro
# so module consumers can import it conditionally.
if(TARGET tomlplusplus_modules)
  add_compile_definitions(TOMLPLUSPLUS_MODULE_AVAILABLE=1)
endif()

add_subdirectory(Src)

if(BUILD_TESTING)
  include(CTest)
  enable_testing()

  if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_subdirectory(Test/commit)
    add_subdirectory(Test/compile)
    if(NOT USE_THREAD_SANITIZER)
      add_subdirectory(Test/fuzz)
    endif()
  elseif(CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    add_subdirectory(Test/perf)
  endif()
endif()

# install(
#   TARGETS ${PROJECT_NAME}
#   CONFIGURATIONS Release
#   RUNTIME DESTINATION bin)

#we keep the relative paths in the install dir
#keep in mind that install dir will be in front of this relative path...
install(DIRECTORY images/ DESTINATION images/)
install(
  FILES docs/packaging/KataglyphisCppProject.desktop
  DESTINATION usr/share/applications
  RENAME org.kataglyphis.KataglyphisCppProject.desktop)
install(
  FILES docs/packaging/KataglyphisCppProject.appdata.xml
  DESTINATION usr/share/metainfo
  RENAME org.kataglyphis.KataglyphisCppProject.appdata.xml)
install(
  FILES images/Engine_logo.png
  DESTINATION usr/share/icons/hicolor/256x256/apps
  RENAME Engine_logo.png)
install(
  FILES images/Engine_logo.png
  DESTINATION usr/share/icons/hicolor/256x256/apps
  RENAME Engine_logo)
install(
  FILES images/Engine_logo.png
  DESTINATION .
  RENAME Engine_logo.png)

include(cmake/CPackOptions.cmake)
myproject_align_all_targets_msvc_runtime()
