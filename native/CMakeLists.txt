cmake_minimum_required(VERSION 3.14)

project(offline_chat_native)

set(CMAKE_BUILD_TYPE Release)

# Add llama.cpp subdirectory
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
add_compile_options(-O3)
add_compile_options(-D__ARM_NEON)
add_compile_options(-D__ARM_FEATURE_FMA)
add_compile_options(-fno-finite-math-only)
set(LLAMA_OPENMP OFF)
set(LLAMA_BUILD_COMMON OFF)
set(LLAMA_BUILD_TESTS OFF)
set(LLAMA_BUILD_EXAMPLES OFF)
set(LLAMA_BUILD_SERVER OFF)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
add_subdirectory(llama.cpp)

# Remove -Ofast if it was added by llama.cpp, as it breaks ggml-cpu
string(REPLACE "-Ofast" "-O3" CMAKE_C_FLAGS "${CMAKE_C_FLAGS}")
string(REPLACE "-Ofast" "-O3" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")

add_library(offline_chat_native SHARED
    llm_wrapper.cpp
)

target_include_directories(offline_chat_native PRIVATE
    llama.cpp/include
)

# Link against llama and threads
find_package(Threads REQUIRED)
target_link_libraries(offline_chat_native PRIVATE llama Threads::Threads)
target_compile_definitions(offline_chat_native PRIVATE _GNU_SOURCE)
