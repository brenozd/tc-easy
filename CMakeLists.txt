cmake_minimum_required(VERSION 3.30 FATAL_ERROR)
set(CMAKE_C_STANDARD 99)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(tc-easy LANGUAGES C)
list(APPEND CMAKE_MODULE_PATH "${PROJECT_SOURCE_DIR}/cmake")

include(CheckCompileOptions)

add_executable(tc-easy "${CMAKE_SOURCE_DIR}/src/main.c")
target_compile_options(tc-easy PRIVATE ${COMPILE_FLAGS})
target_link_options(tc-easy PRIVATE ${LINK_OPTIONS})
