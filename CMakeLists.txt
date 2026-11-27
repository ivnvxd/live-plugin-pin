cmake_minimum_required(VERSION 3.25)
project(LivePluginPin VERSION 0.1.0 LANGUAGES C CXX OBJCXX)

set(SMTG_ENABLE_VST3_PLUGIN_EXAMPLES OFF CACHE BOOL "" FORCE)
set(SMTG_ENABLE_VSTGUI_SUPPORT OFF CACHE BOOL "" FORCE)
set(SMTG_CREATE_PLUGIN_LINK OFF CACHE BOOL "" FORCE)
set(SMTG_RUN_VST_VALIDATOR OFF CACHE BOOL "" FORCE)
set(VST3_SDK_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../vst3sdk" CACHE PATH "Steinberg VST3 SDK")
add_subdirectory("${VST3_SDK_DIR}" vst3sdk)

add_library(LivePluginPin MODULE LivePluginPin.mm "${VST3_SDK_DIR}/public.sdk/source/main/macmain.cpp")
target_include_directories(LivePluginPin PRIVATE "${VST3_SDK_DIR}")
target_compile_features(LivePluginPin PRIVATE cxx_std_17)
target_compile_definitions(LivePluginPin PRIVATE PLUGIN_VERSION="${PROJECT_VERSION}")
target_compile_options(LivePluginPin PRIVATE "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")
target_link_libraries(LivePluginPin PRIVATE sdk "-framework AppKit")
set_target_properties(LivePluginPin PROPERTIES
    PREFIX ""
    SUFFIX ""
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/Live Plugin Pin.vst3/Contents/MacOS"
)
configure_file(Info.plist.in "${CMAKE_BINARY_DIR}/Live Plugin Pin.vst3/Contents/Info.plist" @ONLY)
