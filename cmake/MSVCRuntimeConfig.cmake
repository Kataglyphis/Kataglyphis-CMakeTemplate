# This module centralizes MSVC runtime library and iterator debug level configuration.
# It ensures consistency across the project and its external dependencies.

macro(myproject_configure_msvc_runtime)
  if(MSVC)
    # Determine the desired runtime based on build type and AddressSanitizer status.
    set(_initial_runtime "MultiThreadedDLL") # Default to release DLL runtime

    if(DEFINED CMAKE_BUILD_TYPE AND CMAKE_BUILD_TYPE STREQUAL "Debug")
      if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang" AND myproject_ENABLE_SANITIZER_ADDRESS)
        # clang-cl + ASan in Debug: use release DLL runtime (/MD) so ASan can link.
        set(_initial_runtime "MultiThreadedDLL")
        message(STATUS "clang-cl + ASan: forcing MSVC runtime selection to MultiThreadedDLL (/MD) to satisfy ASan requirements")
      else()
        # Normal Debug builds: use debug DLL runtime (/MDd).
        set(_initial_runtime "MultiThreadedDebugDLL")
      endif()
    endif()

    # Force into cache so FetchContent consumers see this value at configure time.
    set(CMAKE_MSVC_RUNTIME_LIBRARY
        "${_initial_runtime}"
        CACHE STRING "MSVC runtime library" FORCE)
    message(STATUS "Top-level: enforcing CMAKE_MSVC_RUNTIME_LIBRARY=${_initial_runtime}")

    # Set iterator debugging level based on the determined runtime.
    if("${_initial_runtime}" STREQUAL "MultiThreadedDLL")
      add_compile_definitions(_ITERATOR_DEBUG_LEVEL=0)
    elseif("${_initial_runtime}" STREQUAL "MultiThreadedDebugDLL")
      add_compile_definitions(_ITERATOR_DEBUG_LEVEL=2)
    endif()
  endif()
endmacro()

function(myproject_align_all_targets_msvc_runtime)
  if(MSVC)
    set(_desired_runtime "${CMAKE_MSVC_RUNTIME_LIBRARY}")

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
endfunction()