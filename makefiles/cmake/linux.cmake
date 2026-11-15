# Linux settings -- CMake twin of makefiles/ambuild/linux.ambuild.

# The SDK's Linux defines (_LINUX, POSIX, stricmp=strcasecmp, ...) and libraries
# come from s2sdk-manifests' linux.cmake, through s2sdk::s2sdk.
add_definitions(
    -D_FILE_OFFSET_BITS=64
)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -D_snprintf=snprintf")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wall -Wno-uninitialized -Wno-switch -Wno-unused")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-non-virtual-dtor -Wno-overloaded-virtual")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-conversion-null -Wno-write-strings")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -Wno-invalid-offsetof -Wno-reorder")

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mfpmath=sse -msse -fno-strict-aliasing")
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fno-threadsafe-statics -fvisibility=hidden")

set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -static-libstdc++")
# Link libgcc_eh statically if the compiler has it. The gcc-14 in the Steam
# Runtime doesn't ship it, so only ask for it when it's actually there.
execute_process(
    COMMAND ${CMAKE_CXX_COMPILER} -print-file-name=libgcc_eh.a
    OUTPUT_VARIABLE PLUGIN_LIBGCC_EH
    OUTPUT_STRIP_TRAILING_WHITESPACE
    ERROR_QUIET
)
if (IS_ABSOLUTE "${PLUGIN_LIBGCC_EH}" AND EXISTS "${PLUGIN_LIBGCC_EH}")
    set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -lgcc_eh")
endif ()
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,--exclude-libs=libprotobuf.a")

set(LINK_LIBRARIES
    s2sdk::s2sdk
    dynlibutils
)

# Export only CreateInterface -- the same version script AMBuild links with
# (makefiles/ambuild/linux.ambuild).
set(PLUGIN_EXPORT_MAP ${CMAKE_CURRENT_LIST_DIR}/../ExportMap)
list(APPEND PLUGIN_LINK_OPTIONS "-Wl,--version-script=${PLUGIN_EXPORT_MAP}")
list(APPEND PLUGIN_LINK_DEPENDS ${PLUGIN_EXPORT_MAP})
