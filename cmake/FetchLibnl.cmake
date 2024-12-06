include(ExternalProject)
include(FetchContent)

find_program(MAKE NAMES make gmake nmake REQUIRED)
find_program(AUTORECONF NAMES autoreconf REQUIRED)

if(CMAKE_CROSSCOMPILING)
  set(LIBNL_INSTALL_DIR ${CMAKE_SYSROOT})
  set(SYSROOT_FLAG --sysroot=${CMAKE_SYSROOT})
else()
  set(LIBNL_INSTALL_DIR ${FETCHCONTENT_BASE_DIR}/libnl-build)
  set(SYSROOT_FLAG "")
endif()

set(ENV{CC} "${CMAKE_C_COMPILER}")
set(ENV{CXX} "${CMAKE_CXX_COMPILER}")
set(ENV{LD} "${CMAKE_LINKER}")

ExternalProject_Add(
  libnl-ext
  GIT_REPOSITORY https://github.com/thom311/libnl.git
  GIT_TAG libnl3_11_0
  GIT_SHALLOW TRUE
  PREFIX ${FETCHCONTENT_BASE_DIR}
  SOURCE_DIR ${FETCHCONTENT_BASE_DIR}/libnl-src
  BINARY_DIR ${FETCHCONTENT_BASE_DIR}/libnl-build
  STAMP_DIR ${FETCHCONTENT_BASE_DIR}/libnl-subbuild/stamps
  LOG_DIR ${FETCHCONTENT_BASE_DIR}/libnl-subbuild/logs
  TMP_DIR ${FETCHCONTENT_BASE_DIR}/libnl-subbuild/tmp
  CONFIGURE_COMMAND cd ${FETCHCONTENT_BASE_DIR}/libnl-src && ./autogen.sh && ./configure ${SYSROOT_FLAG}
                    --prefix=${FETCHCONTENT_BASE_DIR}/libnl-build
  BUILD_COMMAND cd ${FETCHCONTENT_BASE_DIR}/libnl-src && ${MAKE} 
  INSTALL_COMMAND cd ${FETCHCONTENT_BASE_DIR}/libnl-src && ${MAKE} install
  UPDATE_COMMAND "")

if(STATIC_LIBNL)
  add_library(libnl STATIC IMPORTED)
  set_target_properties(libnl PROPERTIES IMPORTED_LOCATION ${FETCHCONTENT_BASE_DIR}/libnl-build/lib/libnl-3.a
                                         INTERFACE_INCLUDE_DIRECTORIES ${FETCHCONTENT_BASE_DIR}/libnl-build/include/libnl3)
  add_library(libnl-route STATIC IMPORTED)
  set_target_properties(
    libnl-route PROPERTIES IMPORTED_LOCATION ${FETCHCONTENT_BASE_DIR}/libnl-build/lib/libnl-route-3.a
                           INTERFACE_INCLUDE_DIRECTORIES ${FETCHCONTENT_BASE_DIR}/libnl-build/include/libnl3)
else()
  add_library(libnl SHARED IMPORTED)
  set_target_properties(libnl PROPERTIES IMPORTED_LOCATION ${FETCHCONTENT_BASE_DIR}/libnl-build/lib/libnl-3.so
                                         INTERFACE_INCLUDE_DIRECTORIES ${FETCHCONTENT_BASE_DIR}/libnl-build/include/libnl3)
  add_library(libnl-route STATIC IMPORTED)
  set_target_properties(
    libnl-route PROPERTIES IMPORTED_LOCATION ${FETCHCONTENT_BASE_DIR}/libnl-build/lib/libnl-route-3.so
                           INTERFACE_INCLUDE_DIRECTORIES ${FETCHCONTENT_BASE_DIR}/libnl-build/include/libnl3)
endif()
add_dependencies(libnl libnl-ext)
add_dependencies(libnl-route libnl-ext)

file(MAKE_DIRECTORY ${FETCHCONTENT_BASE_DIR}/libnl-build/include/libnl3/ ${FETCHCONTENT_BASE_DIR}/libnl-build/lib/)
