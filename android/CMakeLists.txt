cmake_minimum_required(VERSION 3.10.2)
project(chart_engine LANGUAGES CXX)

add_library(
  chart_engine
  SHARED
  src/main/cpp/chart_engine.cpp
  src/main/cpp/viewport_engine.cpp
  src/main/cpp/chart_engine_jni.cpp
)

set_target_properties(
  chart_engine
  PROPERTIES
    OUTPUT_NAME "chart_engine"
    CXX_STANDARD 17
    CXX_STANDARD_REQUIRED ON
)

find_library(log-lib log)
find_library(gles-lib GLESv3)

target_link_libraries(
  chart_engine
  PRIVATE
  ${log-lib}
  ${gles-lib}
)

target_include_directories(
  chart_engine
  PRIVATE
  ${CMAKE_CURRENT_SOURCE_DIR}/src/main/cpp
)
