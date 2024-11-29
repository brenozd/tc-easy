include(FetchContent)

set(FETCHCONTENT_QUIET TRUE)
set(BUILD_SHARED OFF CACHE STRING "" FORCE)

FetchContent_Declare(
  libbacktrace
  GIT_REPOSITORY https://github.com/brenozd/libbacktrace.git
  GIT_TAG master
  GIT_SHALLOW TRUE
  OVERRIDE_FIND_PACKAGE)

FetchContent_MakeAvailable(libbacktrace)
