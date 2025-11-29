cmake_minimum_required(VERSION 3.14)

project(offline_chat_native)

set(CMAKE_BUILD_TYPE Release)

# Add llama.cpp subdirectory
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(LLAMA_BUILD_COMMON OFF)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
add_subdirectory(llama.cpp)

add_library(offline_chat_native SHARED
    llm_wrapper.cpp
)

target_include_directories(offline_chat_native PRIVATE
    llama.cpp/include
)

# Link against llama
target_link_libraries(offline_chat_native PRIVATE llama)
