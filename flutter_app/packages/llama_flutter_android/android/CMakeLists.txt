cmake_minimum_required(VERSION 3.22.1)

project(llama_jni)

# Set C++17
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Android 15 16KB page size compliance
set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-z,max-page-size=16384")
set(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -Wl,-z,max-page-size=16384")

# ARM64 optimizations — TalkTome : ciblé pour le Galaxy S24 Ultra
# (Snapdragon 8 Gen 3, armv9 : dotprod + i8mm + fp16). Le paquet d'origine
# compilait en armv8-a simple, SANS ces instructions : la multiplication des
# poids quantifiés tombait sur le chemin lent (plusieurs fois plus lent).
# ⚠️ Un téléphone sans i8mm (avant ~2022) planterait au chargement du modèle.
if(ANDROID_ABI STREQUAL "arm64-v8a")
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -O3")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3")
    set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
    set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+i8mm+fp16" CACHE STRING "" FORCE)
endif()
set(CMAKE_BUILD_TYPE Release CACHE STRING "" FORCE)

# llama.cpp options
set(GGML_OPENMP ON CACHE BOOL "")
set(GGML_CPU_REPACK ON CACHE BOOL "")
set(GGML_VULKAN OFF CACHE BOOL "Enable Vulkan GPU backend")
set(GGML_STATIC OFF CACHE BOOL "Build as shared library")
set(BUILD_SHARED_LIBS ON CACHE BOOL "Build shared libraries")

# Disable unused features
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "Disable tests")
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "Disable examples")
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "Disable server")

# Add llama.cpp
add_subdirectory(src/main/cpp/llama.cpp)

# JNI wrapper library - simplified without common library
add_library(llama_jni SHARED
    src/main/cpp/jni_wrapper.cpp
)

find_library(VULKAN_LIB vulkan)

target_link_libraries(llama_jni
    llama
    android
    log
    ${VULKAN_LIB}
)

target_include_directories(llama_jni PRIVATE
    src/main/cpp/llama.cpp/include
    src/main/cpp/llama.cpp/ggml/include
)
