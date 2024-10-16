include(CheckCompilerFlag)
include(CheckLinkerFlag)

set(COMPILE_FLAGS "")
set(LINK_FLAGS "")

function(check_and_add_compiler_flags flags_list)
  set(supported_flags)
  foreach(flag ${flags_list})
    string(REPLACE ";" "_" flag_var ${flag})
    check_compiler_flag(C "${flag}" "HAVE_FLAG_${flag_var}")
    if(HAVE_FLAG_${flag_var})
      list(APPEND supported_flags ${flag})
    endif()
  endforeach()
  set(COMPILE_FLAGS
      ${supported_flags}
      PARENT_SCOPE)
endfunction()

function(check_and_add_linker_flags flags_list)
  set(supported_flags)
  foreach(flag ${flags_list})
    string(REPLACE ";" "_" flag_var ${flag})
    check_linker_flag(C "${flag}" "HAVE_LINKER_FLAG_${flag_var}")
    if(HAVE_LINKER_FLAG_${flag_var})
      list(APPEND supported_flags ${flag})
    endif()
  endforeach()
  set(LINK_FLAGS
      ${supported_flags}
      PARENT_SCOPE)
endfunction()

set(GENERAL_COMPILE_FLAGS
    # Enable warnings for constructs often associated with defects
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#enable-additional-format-function-warnings
    -Wall
    -Wextra
    # Enable additional format function warnings
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#enable-additional-format-function-warnings
    -Wformat=2
    -Wformat-security
    # Enable implicit conversion warnings
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#enable-implicit-conversion-warnings
    -Wconversion
    -Wsign-conversion
    # Enable warning about trampolines that require executable stacks
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#enable-warning-about-trampolines-that-require-executable-stacks
    -Wtrampolines
    # Warn about implicit fallthrough in switch statements
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#warn-about-implicit-fallthrough-in-switch-statements
    -Wimplicit-fallthrough
    # Treat obsolete C constructs as errors
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#-Werror=implicit
    -Werror=implicit
    -Werror=incompatible-pointer-types
    -Werror=int-conversion)

# Flags enabled only on Release Mode
set(RELEASE_COMPILE_FLAGS
    # Keeps only relevant symbols available to the library users
    -fvisibility=hidden
    -fvisibility-inlines-hidden
    -ffunction-sections
    -fdata-sections
    # Enable code instrumentation of control-flow transfers to increase program
    # security by checking that target addresses of control-flow transfer
    # instructions are valid
    # https://gcc.gnu.org/onlinedocs/gcc/Instrumentation-Options.html#index-fcf-protection
    -fcf-protection=full
    # Enable run-time checks for stack-based buffer overflows
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#enable-run-time-checks-for-stack-based-buffer-overflows
    -fstack-protector-strong
    # Build as position-independent code
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#build-as-position-independent-code
    -pie
    -fPIE
    # Enable run-time checks for variable-size stack allocation validity
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#enable-run-time-checks-for-variable-size-stack-allocation-validity
    -fstack-clash-protection
    # Enable strict flexible arrays
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#enable-strict-flexible-arrays
    -fstrict-flex-arrays=3
    # Precondition checks for C++ standard library calls
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#precondition-checks-for-c-standard-library-calls
    -D_GLIBCXX_ASSERTIONS
    # Do not delete null pointer checks
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#do-not-delete-null-pointer-checks
    -fno-delete-null-pointer-checks
    # Integer overflow may occur
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#integer-overflow-may-occur
    -fno-strict-overflow
    # Do not assume strict aliasing
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#do-not-assume-strict-aliasing
    -fno-strict-aliasing
    # Perform trivial auto variable initialization
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#perform-trivial-auto-variable-initialization
    -ftrivial-auto-var-init=zero
    # Enable exception propagation to harden multi-threaded C code
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#enable-exception-propagation-to-harden-multi-threaded-c-code
    -fexceptions
    # Fortify sources for unsafe libc usage and buffer overflows
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#fortify-sources-for-unsafe-libc-usage-and-buffer-overflows
    -U_FORTIFY_SOURCE
    -D_FORTIFY_SOURCE=3)

set(RELEASE_LINKER_FLAGS
    -Wl,-z,relro,-z,now
    # Enable data execution prevention
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#enable-data-execution-prevention
    -Wl,-z,noexecstack
    # Restrict dlopen calls to shared objects
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#restrict-dlopen-calls-to-shared-objects
    -Wl,-z,nodlopen
    # Allow linker to omit libraries specified on the command line to link
    # against if they are not used
    # https://best.openssf.org/Compiler-Hardening-Guides/Compiler-Options-Hardening-Guide-for-C-and-C++.html#allow-linker-to-omit-libraries-specified-on-the-command-line-to-link-against-if-they-are-not-used
    -Wl,--as-needed
    -Wl,--no-copy-dt-needed-entries)

# Flags enabled only on Debug Mode
set(DEBUG_COMPILE_FLAGS -g3 -Og -fno-omit-frame-pointer
                        -fno-optimize-sibling-calls -fno-common)
set(DEBUG_LINKER_FLAGS "-rdynamic")

set(CONFIG_COMPILE_FLAGS ${GENERAL_COMPILE_FLAGS})
set(CONFIG_LINKER_FLAGS ${GENERAL_LINKER_FLAGS})

if(NOT CMAKE_BUILD_TYPE EQUAL "Debug")
  list(APPEND CONFIG_COMPILE_FLAGS ${RELEASE_COMPILE_FLAGS})
  list(APPEND CONFIG_LINKER_FLAGS ${RELEASE_LINKER_FLAGS})
elseif(CMAKE_BUILD_TYPE STREQUAL "Debug")
  list(APPEND CONFIG_COMPILE_FLAGS ${DEBUG_COMPILE_FLAGS})
  list(APPEND CONFIG_LINKER_FLAGS ${DEBUG_LINKER_FLAGS})
else()
  message(
    WARNING
      "Unknown build type: ${CMAKE_BUILD_TYPE}. Using Debug flags by default.")
  list(APPEND CONFIG_COMPILE_FLAGS ${DEBUG_COMPILE_FLAGS})
  list(APPEND CONFIG_LINKER_FLAGS ${DEBUG_LINKER_FLAGS})
endif()

check_and_add_compiler_flags("${CONFIG_COMPILE_FLAGS}")
check_and_add_linker_flags("${CONFIG_LINKER_FLAGS}")

message(STATUS "Compile flags for ${CMAKE_BUILD_TYPE}: ${COMPILE_FLAGS}")
message(STATUS "Linker flags for ${CMAKE_BUILD_TYPE}: ${LINK_FLAGS}")
