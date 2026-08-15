cmake_minimum_required(VERSION 3.10.2)

project("network" C)

add_library(
    network
    SHARED
    network.c
)

find_library(
    log-lib
    log
)

target_link_libraries(
    network
    ${log-lib}
)
