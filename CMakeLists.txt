cmake_minimum_required(VERSION 4.2.1)

#set the project name
project(
  KataglyphisCppProject
  VERSION 0.0.1
  DESCRIPTION "Lore ipsum"
  HOMEPAGE_URL "https://jonasheinle.de/"
  LANGUAGES CXX C)

set(AUTHOR "Jonas Heinle")

if(NOT DEFINED RUST_FEATURES)
  # Default to enabling Rust features when the user has not supplied a
  # preference. Use a cache variable so command-line -DRUST_FEATURES=OFF will
  # override this default without being overwritten later by the project.
  set(RUST_FEATURES
      ON
      CACHE BOOL "Enable Rust features in our project.")
else()
  # If the cache entry already exists (for example set via -DRUST_FEATURES=OFF)
  # ensure the local variable is set to the cache value so downstream code
  # sees the user's intent consistently.
  set(RUST_FEATURES
      "${RUST_FEATURES}"
      CACHE BOOL "Enable Rust features in our project." FORCE)
endif()
set(MYPROJECT_GCC_TOOLCHAIN_PATH
    ""
    CACHE PATH "Optional GCC toolchain root used by Clang and Rust tooling on Linux (for example /opt/gcc-15.2.0)")

# Corrosion and cxxbridge handling is delegated to ExternalLib/CMakeLists
# to ensure the Rust preflight (for example the Windows Cargo wrapper) is
# configured before Corrosion is made available. See ExternalLib/CMakeLists.

# Auto-detect custom GCC toolchain for Clang on Linux to avoid workflow env setup
if(UNIX
   AND NOT APPLE
   AND MYPROJECT_GCC_TOOLCHAIN_PATH
   AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
  set(_GCC_TOOLCHAIN_ROOT "${MYPROJECT_GCC_TOOLCHAIN_PATH}")
  set(_GCC_TOOLCHAIN_LIB "${_GCC_TOOLCHAIN_ROOT}/lib64")
  if(NOT EXISTS "${_GCC_TOOLCHAIN_LIB}")
    set(_GCC_TOOLCHAIN_LIB "${_GCC_TOOLCHAIN_ROOT}/lib")
  endif()

  if(EXISTS "${_GCC_TOOLCHAIN_LIB}")
    message(STATUS "Using GCC toolchain at ${_GCC_TOOLCHAIN_ROOT} for Clang")
    string(APPEND CMAKE_C_FLAGS " --gcc-toolchain=${_GCC_TOOLCHAIN_ROOT}")
    string(APPEND CMAKE_CXX_FLAGS " --gcc-toolchain=${_GCC_TOOLCHAIN_ROOT}")
    string(APPEND CMAKE_EXE_LINKER_FLAGS
           " -L${_GCC_TOOLCHAIN_LIB} -Wl,-rpath,${_GCC_TOOLCHAIN_LIB} --gcc-toolchain=${_GCC_TOOLCHAIN_ROOT}")
    string(APPEND CMAKE_SHARED_LINKER_FLAGS
           " -L${_GCC_TOOLCHAIN_LIB} -Wl,-rpath,${_GCC_TOOLCHAIN_LIB} --gcc-toolchain=${_GCC_TOOLCHAIN_ROOT}")
  else()
    message(WARNING "GCC toolchain found at ${_GCC_TOOLCHAIN_ROOT}, but no lib or lib64 dir exists.")
  endif()
endif()

if(RUST_FEATURES)
  message(STATUS "Rust features are enabled.")
  if(MSVC)
    message(STATUS "On a windows machine you must use MSVC or clang-cl when integrating rust features.")
  endif()
else()
  message(STATUS "Rust features are disabled.")
  message(
    STATUS "Your are going to use a non MSVC/clang-cl compiler on windows. Therefore no rust integration possible.")
endif()

include(cmake/PreventInSourceBuilds.cmake)
include(cmake/ProjectOptions.cmake)

myproject_setup_options()

myproject_global_options()

message(STATUS "About to call the local options function.")
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
  else()
    message(STATUS "PGO requested but myproject_options target not available; skipping PGO flags.")
  endif()
endif()

# Ensure MSVC runtime selection is established early so FetchContent and
# subprojects inherit a consistent choice during their configure step. This
# mirrors the logic in cmake/ProjectOptions.cmake but must run before
# add_subdirectory(FetchContent consumers) so dependencies (Abseil, etc.) are
# configured with the intended runtime selection (avoids /MDd vs /MD mismatches
# when using clang-cl + AddressSanitizer).
if(MSVC)
  # Default to release DLL runtime unless overridden below.
  set(_initial_runtime "MultiThreadedDLL")
  # If a user explicitly set CMAKE_BUILD_TYPE and address sanitizer via cache
  # variables, prefer forcing a runtime that satisfies ASan requirements.
  if(DEFINED CMAKE_BUILD_TYPE
     AND DEFINED myproject_ENABLE_SANITIZER_ADDRESS
     AND CMAKE_CXX_COMPILER_ID STREQUAL "Clang"
     AND CMAKE_BUILD_TYPE STREQUAL "Debug"
     AND myproject_ENABLE_SANITIZER_ADDRESS)
    set(_initial_runtime "MultiThreadedDLL")
  elseif(DEFINED CMAKE_BUILD_TYPE AND CMAKE_BUILD_TYPE STREQUAL "Debug")
    set(_initial_runtime "MultiThreadedDebugDLL")
  endif()

  # Force into cache so FetchContent consumers see this value at configure time.
  set(CMAKE_MSVC_RUNTIME_LIBRARY
      "${_initial_runtime}"
      CACHE STRING "MSVC runtime library" FORCE)
  message(STATUS "Top-level: enforcing CMAKE_MSVC_RUNTIME_LIBRARY=${_initial_runtime}")
endif()

add_subdirectory(ExternalLib)

# Enable maximum Corrosion/Cargo verbosity by default so CI and local builds
# produce detailed Rust/Cargo logs for debugging integration issues.
set(CORROSION_VERBOSE_OUTPUT
    ON
    CACHE BOOL "Enables verbose output from Corrosion and Cargo" FORCE)
option(ENABLE_RUST_CXXBRIDGE "Enable generation of the CXX bridge for Rust crates" ON)

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
  message(STATUS "BUILD_TESTING is ON - enabling CTest.")
else()
  message(STATUS "BUILD_TESTING is OFF - skipping CTest enablement.")
endif()

if(BUILD_TESTING)
  message(STATUS "Tests are enabled.!")
  if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    add_subdirectory(Test/commit)
    add_subdirectory(Test/compile)
    if(NOT USE_THREAD_SANITIZER)
      add_subdirectory(Test/fuzz)
      message(STATUS "Building test suites: commit, compile, fuzz (Debug)")
    else()
      message(STATUS "Building test suites: commit, compile (Debug, fuzz disabled for ThreadSanitizer)")
    endif()
  elseif(CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
    add_subdirectory(Test/perf)
    message(STATUS "Building test suite: perf (RelWithDebInfo)")
  else()
    message(
      STATUS
        "Skipping test suites for CMAKE_BUILD_TYPE='${CMAKE_BUILD_TYPE}'. Use Debug for commit/compile/fuzz or RelWithDebInfo for perf."
    )
  endif()
else()
  message(STATUS "Tests are disabled.!")
endif()

#for correct library output needed
install(
  TARGETS ${PROJECT_NAME}
  CONFIGURATIONS Release
  RUNTIME DESTINATION bin)

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

# Final exhaustive alignment of all targets to the desired MSVC runtime selection.
# This runs after all subdirectories (ExternalLib, Src, Tests) have been added,
# ensuring that every target in the project is correctly aligned to avoid
# /failifmismatch and iterator-debug-level LNK2038 linker errors.
if(MSVC)
  # Re-derive the concrete desired runtime from the cache variable
  set(_desired_runtime "${CMAKE_MSVC_RUNTIME_LIBRARY}")
  if(_desired_runtime MATCHES "\\$<")
    if(CMAKE_BUILD_TYPE STREQUAL "Debug")
      string(
        REPLACE "$<$<CONFIG:Debug>:Debug>"
                "Debug"
                _desired_runtime
                "${_desired_runtime}")
    else()
      string(
        REPLACE "$<$<CONFIG:Debug>:Debug>"
                ""
                _desired_runtime
                "${_desired_runtime}")
    endif()
  endif()

  function(get_all_targets_recursive _result _dir)
    get_property(
      _subdirs
      DIRECTORY "${_dir}"
      PROPERTY SUBDIRECTORIES)
    foreach(_subdir IN LISTS _subdirs)
      get_all_targets_recursive(${_result} "${_subdir}")
    endforeach()
    get_property(
      _targets
      DIRECTORY "${_dir}"
      PROPERTY BUILDSYSTEM_TARGETS)
    set(${_result}
        ${${_result}} ${_targets}
        PARENT_SCOPE)
  endfunction()

  set(_all_targets "")
  get_all_targets_recursive(_all_targets "${CMAKE_CURRENT_SOURCE_DIR}")
  list(REMOVE_DUPLICATES _all_targets)

  foreach(_t IN LISTS _all_targets)
    # Align target property
    get_target_property(_current_runtime ${_t} MSVC_RUNTIME_LIBRARY)
    if(NOT _current_runtime
       OR _current_runtime STREQUAL "NOTFOUND"
       OR _current_runtime MATCHES "\\$<"
       OR NOT
          "${_current_runtime}"
          STREQUAL
          "${_desired_runtime}")
      # message(STATUS "Exhaustive alignment: setting target ${_t} MSVC_RUNTIME_LIBRARY to ${_desired_runtime}")
      set_target_properties(${_t} PROPERTIES MSVC_RUNTIME_LIBRARY "${_desired_runtime}")
    endif()

    # Align iterator debugging compile definition
    get_target_property(_cur_defs ${_t} COMPILE_DEFINITIONS)
    if(NOT _cur_defs OR _cur_defs MATCHES "-NOTFOUND$")
      set(_cur_defs "")
    endif()
    set(_new_defs ${_cur_defs})
    if("${_desired_runtime}" STREQUAL "MultiThreadedDLL")
      list(APPEND _new_defs "_ITERATOR_DEBUG_LEVEL=0")
    elseif("${_desired_runtime}" STREQUAL "MultiThreadedDebugDLL")
      list(APPEND _new_defs "_ITERATOR_DEBUG_LEVEL=2")
    endif()
    list(REMOVE_DUPLICATES _new_defs)
    set_target_properties(${_t} PROPERTIES COMPILE_DEFINITIONS "${_new_defs}")

    # Exhaustively strip explicit runtime flags from all relevant properties
    foreach(_prop COMPILE_OPTIONS INTERFACE_COMPILE_OPTIONS)
      get_target_property(_opts ${_t} ${_prop})
      if(_opts
         AND NOT
             _opts
             MATCHES
             "-NOTFOUND$")
        set(_filt)
        foreach(_o IN LISTS _opts)
          if(NOT
             (_o MATCHES "^[/-]M(T|D)(d)?$"
              OR _o MATCHES "^-clang:-M(T|D)(d)?$"
              OR _o MATCHES ".*:-M(T|D)(d)?$"))
            list(APPEND _filt "${_o}")
          endif()
        endforeach()
        set_property(TARGET ${_t} PROPERTY ${_prop} ${_filt})
      endif()
    endforeach()

    get_target_property(_flags ${_t} COMPILE_FLAGS)
    if(_flags
       AND NOT
           _flags
           MATCHES
           "-NOTFOUND$")
      string(
        REPLACE " "
                ";"
                _flist
                "${_flags}")
      set(_filt)
      foreach(_f IN LISTS _flist)
        if(NOT
           (_f MATCHES "^[/-]M(T|D)(d)?$"
            OR _f MATCHES "^-clang:-M(T|D)(d)?$"
            OR _f MATCHES ".*:-M(T|D)(d)?$"))
          list(APPEND _filt "${_f}")
        endif()
      endforeach()
      string(
        JOIN
        " "
        _final
        ${_filt})
      set_target_properties(${_t} PROPERTIES COMPILE_FLAGS "${_final}")
    endif()
  endforeach()
endif()
