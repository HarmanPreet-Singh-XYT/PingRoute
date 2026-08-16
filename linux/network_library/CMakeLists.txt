cmake_minimum_required(VERSION 3.10)

# Project name
project(network_library C)

# Set C standard
set(CMAKE_C_STANDARD 99)

# Include directories
include_directories(${CMAKE_SOURCE_DIR})

# Add source files
set(SOURCE_FILES network.c)

# Shared library — kept for Windows / macOS FFI.
add_library(network SHARED ${SOURCE_FILES})
set_target_properties(network PROPERTIES VERSION 1.0.0 SOVERSION 1)

# Standalone helper executable for Linux privilege separation.
# The main Flutter process has no special capabilities; this binary gets
# CAP_NET_RAW set on it at install time (snap/flatpak handle it via their
# own sandboxing interfaces; deb postinst runs setcap; developers run it once
# manually: sudo setcap cap_net_raw+ep <path>/pingroute-net).
add_executable(pingroute-net network_helper_main.c ${SOURCE_FILES})
target_compile_options(pingroute-net PRIVATE -O2)
