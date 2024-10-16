include(FetchContent)

if(NOT ARGPARSE_VERSION)
  set(ARGPARSE_VERSION "682d4520b4bc2b646cdfcf078b2fed00b3d2da30")
endif()
message(STATUS "Fetching and configuring argparse version ${ARGPARSE_VERSION}")

set(FETCHCONTENT_QUIET TRUE)
if(STATIC_ARGPARSE)
  set(ARGPARSE_STATIC ON CACHE STRING "" FORCE)
  set(ARGPARSE_SHARED OFF CACHE STRING "" FORCE)
else()
  set(ARGPARSE_STATIC OFF CACHE STRING "" FORCE)
  set(ARGPARSE_SHARED ON CACHE STRING "" FORCE)
endif()

FetchContent_Declare(
  argparse
  GIT_REPOSITORY https://github.com/cofyc/argparse.git
  GIT_TAG ${ARGPARSE_VERSION}
  GIT_PROGRESS TRUE
  OVERRIDE_FIND_PACKAGE)
FetchContent_MakeAvailable(argparse)

if(TARGET argparse_shared)
  target_compile_options(argparse_shared PRIVATE ${COMPILE_FLAGS})
  target_link_options(argparse_shared PRIVATE "${LINK_FLAGS}")
endif()

if(TARGET argparse_static)
  target_compile_options(argparse_static PRIVATE ${COMPILE_FLAGS})
  target_link_options(argparse_static PRIVATE "${LINK_FLAGS}")
endif()
