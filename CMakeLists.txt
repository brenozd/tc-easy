cmake_minimum_required(VERSION 3.22 FATAL_ERROR)
set(CMAKE_C_STANDARD 99)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

option(STATIC_ARGPARSE "Statically build/link argparse" ON)
option(STATIC_LIBNL "Statically build/link libnl" ON)

project(tc-easy LANGUAGES C)
list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

include(CheckCompileOptions)

add_executable(tc-easy "${CMAKE_SOURCE_DIR}/src/main.c")
target_compile_options(tc-easy PRIVATE ${COMPILE_FLAGS})
target_link_options(tc-easy PRIVATE ${LINK_OPTIONS})

include(FetchLibnl)
include(FetchLibbacktrace)
target_link_libraries(tc-easy PRIVATE backtrace libnl libnl-route) 

include(FetchArgparse)
if(STATIC_ARGPARSE)
  target_link_libraries(tc-easy PRIVATE argparse_static)
else()
  target_link_libraries(tc-easy PRIVATE argparse_shared)
endif()

add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/src")

add_custom_command(
    OUTPUT "${PROJECT_SOURCE_DIR}/compile_commands.json"
    COMMAND ${CMAKE_COMMAND} -E create_symlink
            "${CMAKE_BINARY_DIR}/compile_commands.json"
            "${PROJECT_SOURCE_DIR}/compile_commands.json"
    DEPENDS "${CMAKE_BINARY_DIR}/compile_commands.json"
    COMMENT "Creating symlink for compile_commands.json in project source directory"
)
add_custom_target(
    SymlinkCompileCommands ALL
    DEPENDS "${PROJECT_SOURCE_DIR}/compile_commands.json"
)
