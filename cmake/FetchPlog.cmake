include(FetchContent)

FetchContent_Declare(
  plog
  GIT_REPOSITORY https://github.com/SergiusTheBest/plog.git
  GIT_TAG 1.1.10
  GIT_SHALLOW TRUE
  OVERRIDE_FIND_PACKAGE)

FetchContent_MakeAvailable(plog)
