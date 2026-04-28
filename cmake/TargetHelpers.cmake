include_guard(GLOBAL)
include(${CMAKE_SOURCE_DIR}/cmake/CompilerDetection.cmake)

function(myproject_set_deployment_paths target)
    myproject_is_msvc_compiler(IS_MSVC)
    myproject_is_clang_cl(IS_CLANG_CL)

    if(WIN32 AND IS_MSVC)
        target_compile_definitions(${target} PRIVATE RELATIVE_RESOURCE_PATH="/../../Resources/"
                                                          RELATIVE_INCLUDE_PATH="/../../Src/")
    else()
        target_compile_definitions(${target} PRIVATE RELATIVE_RESOURCE_PATH="/../Resources/"
                                                          RELATIVE_INCLUDE_PATH="/../Src/")
    endif()
endfunction()

function(myproject_enable_msvc_exceptions target visibility)
    myproject_is_msvc_compiler(IS_MSVC)
    myproject_is_clang_cl(IS_CLANG_CL)

    if(IS_MSVC OR IS_CLANG_CL)
        target_compile_options(${target} ${visibility} /EHsc)
    endif()
endfunction()

function(myproject_link_project_libraries target)
    target_link_libraries(${target} PUBLIC
        ${CMAKE_DL_LIBS}
        Threads::Threads
        myproject_warnings
        myproject_options
    )
endfunction()
