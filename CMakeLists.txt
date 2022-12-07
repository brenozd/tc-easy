cmake_minimum_required(VERSION 3.0.0)

enable_language(C)
set(CMAKE_C_STANDARD 11)

project(tc-easy VERSION 0.1.0)

include(CTest)
enable_testing()

add_executable(tc-easy src/main.c)

set(CPACK_PROJECT_NAME ${PROJECT_NAME})
set(CPACK_PROJECT_VERSION ${PROJECT_VERSION})
include(CPack)

# tc_api
include_directories(${CMAKE_CURRENT_SOURCE_DIR}/src/tc_api/)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/src/tc_api/)

target_link_libraries(tc-easy tc-api)