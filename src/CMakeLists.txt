file(GLOB C_FILES CONFIGURE_DEPENDS *.c)
file(GLOB H_FILES CONFIGURE_DEPENDS *.h)

target_sources(tc-easy PRIVATE ${C_FILES} PUBLIC ${H_FILES})

target_include_directories(tc-easy PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
