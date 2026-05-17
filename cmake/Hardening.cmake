include(CheckCXXCompilerFlag)
include(${CMAKE_SOURCE_DIR}/cmake/CompilerDetection.cmake)

function(myproject_enable_hardening target)
  set(_myproject_compile_options "")
  set(_myproject_link_options "")
  set(_myproject_compile_definitions "")

  myproject_is_msvc_compiler(IS_MSVC)
  myproject_is_clang_cl(IS_CLANG_CL)
  myproject_is_unix_like_compiler(IS_UNIX_LIKE)
  myproject_is_gnu_compiler(IS_GNU)

  if(IS_MSVC OR IS_CLANG_CL)
    list(
      APPEND
      _myproject_compile_options
      /sdl
      /DYNAMICBASE
      /guard:cf)
    list(
      APPEND
      _myproject_link_options
      /NXCOMPAT
      /CETCOMPAT)

  elseif(IS_UNIX_LIKE)
    list(APPEND _myproject_compile_definitions _GLIBCXX_ASSERTIONS)
    list(
      APPEND
      _myproject_compile_options
      -U_FORTIFY_SOURCE
      -D_FORTIFY_SOURCE=3)

    check_cxx_compiler_flag(-fstack-protector-strong _myproject_stack_protector)
    if(_myproject_stack_protector)
      list(APPEND _myproject_compile_options -fstack-protector-strong)
    endif()

    check_cxx_compiler_flag(-fcf-protection _myproject_cf_protection)
    if(_myproject_cf_protection)
      list(APPEND _myproject_compile_options -fcf-protection)
    endif()

    check_cxx_compiler_flag(-fstack-clash-protection _myproject_clash_protection)
    if(_myproject_clash_protection)
      if(LINUX OR IS_GNU)
        list(APPEND _myproject_compile_options -fstack-clash-protection)
      endif()
    endif()
  endif()

  if(_myproject_compile_options)
    target_compile_options(${target} INTERFACE ${_myproject_compile_options})
  endif()

  if(_myproject_link_options)
    target_link_options(${target} INTERFACE ${_myproject_link_options})
  endif()

  if(_myproject_compile_definitions)
    target_compile_definitions(${target} INTERFACE ${_myproject_compile_definitions})
  endif()
endfunction()
