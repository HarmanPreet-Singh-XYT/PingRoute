cmake_minimum_required(VERSION 3.10)

# Set the project name and version
project(NetworkLib VERSION 1.0 LANGUAGES C)

# Include the header files
include_directories(${CMAKE_CURRENT_SOURCE_DIR})

# Add the library to be built
add_library(network SHARED network.c)

# Set the output name of the library
set_target_properties(network PROPERTIES OUTPUT_NAME "network")

# Specify the export file (network.def)
set_target_properties(network PROPERTIES LINK_FLAGS "/DEF:${CMAKE_CURRENT_SOURCE_DIR}/network.def")

# Link necessary libraries for Windows networking
target_link_libraries(network ws2_32 iphlpapi)
