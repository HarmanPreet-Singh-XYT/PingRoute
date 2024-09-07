cmake_minimum_required(VERSION 3.10)

# Project name
project(network_library C)

# Set C standard
set(CMAKE_C_STANDARD 99)

# Include directories
include_directories(${CMAKE_SOURCE_DIR})

# Add source files
set(SOURCE_FILES network.c)

# Create a shared library
add_library(network SHARED ${SOURCE_FILES})

# Set library version (optional)
set_target_properties(network PROPERTIES VERSION 1.0.0 SOVERSION 1)
