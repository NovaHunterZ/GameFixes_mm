cmake_minimum_required(VERSION 3.14)
project(dynlibutils CXX)

if(UNIX AND NOT APPLE)
    set(LINUX TRUE)
endif()

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_STATIC_LIBRARY_PREFIX "")

set(DYNLIBUTILS_SOURCES
    src/module.cpp
)

add_library(dynlibutils STATIC ${DYNLIBUTILS_SOURCES})

target_include_directories(dynlibutils PUBLIC include)

set_target_properties(dynlibutils PROPERTIES
    POSITION_INDEPENDENT_CODE ON
)

if(LINUX)
    target_compile_options(dynlibutils PRIVATE
        -mfpmath=sse -msse -fno-strict-aliasing
        -fno-threadsafe-statics -fvisibility=hidden
        -Wall -Wno-uninitialized -Wno-switch -Wno-unused
        -Wno-non-virtual-dtor -Wno-overloaded-virtual
        -Wno-invalid-offsetof -Wno-reorder
    )
    target_compile_definitions(dynlibutils PRIVATE
        _LINUX POSIX LINUX GNUC COMPILER_GCC PLATFORM_64BITS X64BITS
        _FILE_OFFSET_BITS=64 _GLIBCXX_USE_CXX11_ABI=0
    )
elseif(WIN32)
    target_compile_definitions(dynlibutils PRIVATE
        COMPILER_MSVC COMPILER_MSVC64 _WIN32 _WINDOWS
        _CRT_SECURE_NO_WARNINGS _CRT_SECURE_NO_DEPRECATE _CRT_NONSTDC_NO_DEPRECATE
    )
    target_compile_options(dynlibutils PRIVATE /utf-8 /permissive-)
endif()
