# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(FlEasyTier LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "FlEasyTier")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

function(fleasytier_read_flutter_define DEFINE_NAME OUT_VAR)
  set(${OUT_VAR} "" PARENT_SCOPE)
  set(FLEASYTIER_GENERATED_CONFIG
    "${CMAKE_CURRENT_SOURCE_DIR}/flutter/ephemeral/generated_config.cmake"
  )
  if(NOT EXISTS "${FLEASYTIER_GENERATED_CONFIG}")
    return()
  endif()

  file(READ "${FLEASYTIER_GENERATED_CONFIG}" FLEASYTIER_GENERATED_CONFIG_CONTENT)
  string(REGEX MATCH "\"DART_DEFINES=([^\"]*)\"" FLEASYTIER_DART_DEFINES_LINE
    "${FLEASYTIER_GENERATED_CONFIG_CONTENT}"
  )
  if(NOT FLEASYTIER_DART_DEFINES_LINE)
    return()
  endif()

  set(FLEASYTIER_DART_DEFINES "${CMAKE_MATCH_1}")
  string(REPLACE "," ";" FLEASYTIER_DART_DEFINES_LIST "${FLEASYTIER_DART_DEFINES}")
  foreach(FLEASYTIER_DART_DEFINE ${FLEASYTIER_DART_DEFINES_LIST})
    execute_process(
      COMMAND powershell
        -NoProfile
        -ExecutionPolicy Bypass
        -Command
        "[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${FLEASYTIER_DART_DEFINE}'))"
      OUTPUT_VARIABLE FLEASYTIER_DART_DEFINE_DECODED
      OUTPUT_STRIP_TRAILING_WHITESPACE
      ERROR_QUIET
    )
    if(FLEASYTIER_DART_DEFINE_DECODED MATCHES "^${DEFINE_NAME}=(.*)$")
      set(${OUT_VAR} "${CMAKE_MATCH_1}" PARENT_SCOPE)
      return()
    endif()
  endforeach()
endfunction()

fleasytier_read_flutter_define("FLEASYTIER_ENABLE_YY_THUNKS" FLEASYTIER_ENABLE_YY_THUNKS_FROM_DART_DEFINE)

set(FLEASYTIER_ENABLE_YY_THUNKS OFF)
if(FLEASYTIER_ENABLE_YY_THUNKS_FROM_DART_DEFINE)
  string(TOUPPER "${FLEASYTIER_ENABLE_YY_THUNKS_FROM_DART_DEFINE}" FLEASYTIER_ENABLE_YY_THUNKS_VALUE)
  if(FLEASYTIER_ENABLE_YY_THUNKS_VALUE STREQUAL "1" OR
     FLEASYTIER_ENABLE_YY_THUNKS_VALUE STREQUAL "TRUE" OR
     FLEASYTIER_ENABLE_YY_THUNKS_VALUE STREQUAL "ON" OR
     FLEASYTIER_ENABLE_YY_THUNKS_VALUE STREQUAL "YES")
    set(FLEASYTIER_ENABLE_YY_THUNKS ON)
  endif()
endif()
set(
  FLEASYTIER_ENABLE_YY_THUNKS
  ${FLEASYTIER_ENABLE_YY_THUNKS}
  CACHE BOOL "Enable YY-Thunks for Windows 7 compatibility" FORCE
)
set(FLEASYTIER_YY_THUNKS_VERSION "1.1.9" CACHE STRING "YY-Thunks package version")

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

if(FLEASYTIER_ENABLE_YY_THUNKS)
  if(CMAKE_SIZEOF_VOID_P EQUAL 8)
    set(FLEASYTIER_YY_THUNKS_ARCH "x64")
  elseif(CMAKE_SIZEOF_VOID_P EQUAL 4)
    set(FLEASYTIER_YY_THUNKS_ARCH "x86")
  else()
    message(FATAL_ERROR "YY-Thunks only provides x86/x64 support.")
  endif()

  set(FLEASYTIER_YY_THUNKS_ROOT "${PROJECT_BINARY_DIR}/yy-thunks/${FLEASYTIER_YY_THUNKS_VERSION}")
  set(FLEASYTIER_YY_THUNKS_PACKAGE "${FLEASYTIER_YY_THUNKS_ROOT}/YY-Thunks.${FLEASYTIER_YY_THUNKS_VERSION}.nupkg")
  set(FLEASYTIER_YY_THUNKS_EXTRACT_DIR "${FLEASYTIER_YY_THUNKS_ROOT}/package")
  set(FLEASYTIER_YY_THUNKS_OBJ
    "${FLEASYTIER_YY_THUNKS_EXTRACT_DIR}/build/native/objs/${FLEASYTIER_YY_THUNKS_ARCH}/YY_Thunks_for_Win7.obj"
  )

  if(NOT EXISTS "${FLEASYTIER_YY_THUNKS_OBJ}")
    file(MAKE_DIRECTORY "${FLEASYTIER_YY_THUNKS_ROOT}")
    if(NOT EXISTS "${FLEASYTIER_YY_THUNKS_PACKAGE}")
      file(
        DOWNLOAD
        "https://api.nuget.org/v3-flatcontainer/yy-thunks/${FLEASYTIER_YY_THUNKS_VERSION}/yy-thunks.${FLEASYTIER_YY_THUNKS_VERSION}.nupkg"
        "${FLEASYTIER_YY_THUNKS_PACKAGE}"
        STATUS FLEASYTIER_YY_THUNKS_DOWNLOAD_STATUS
        SHOW_PROGRESS
      )
      list(GET FLEASYTIER_YY_THUNKS_DOWNLOAD_STATUS 0 FLEASYTIER_YY_THUNKS_DOWNLOAD_CODE)
      list(GET FLEASYTIER_YY_THUNKS_DOWNLOAD_STATUS 1 FLEASYTIER_YY_THUNKS_DOWNLOAD_MESSAGE)
      if(NOT FLEASYTIER_YY_THUNKS_DOWNLOAD_CODE EQUAL 0)
        message(FATAL_ERROR
          "Failed to download YY-Thunks ${FLEASYTIER_YY_THUNKS_VERSION}: "
          "${FLEASYTIER_YY_THUNKS_DOWNLOAD_MESSAGE}"
        )
      endif()
    endif()

    file(MAKE_DIRECTORY "${FLEASYTIER_YY_THUNKS_EXTRACT_DIR}")
    execute_process(
      COMMAND ${CMAKE_COMMAND} -E tar xvf "${FLEASYTIER_YY_THUNKS_PACKAGE}"
      WORKING_DIRECTORY "${FLEASYTIER_YY_THUNKS_EXTRACT_DIR}"
      COMMAND_ERROR_IS_FATAL ANY
    )
  endif()

  if(NOT EXISTS "${FLEASYTIER_YY_THUNKS_OBJ}")
    message(FATAL_ERROR
      "YY-Thunks Win7 object file was not found at ${FLEASYTIER_YY_THUNKS_OBJ}"
    )
  endif()

  function(fleasytier_enable_yy_thunks TARGET_NAME)
    if(TARGET "${TARGET_NAME}")
      target_link_libraries("${TARGET_NAME}" PRIVATE "${FLEASYTIER_YY_THUNKS_OBJ}")
    endif()
  endfunction()
else()
  function(fleasytier_enable_yy_thunks TARGET_NAME)
  endfunction()
endif()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")
fleasytier_enable_yy_thunks(${BINARY_NAME})

set(REPO_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(EASYTIER_EMBED_DIR "${PROJECT_BINARY_DIR}/embedded")
set(EASYTIER_CORE_FILE "${EASYTIER_EMBED_DIR}/easytier-core.exe")
set(EASYTIER_BUNDLE_SOURCE_DIR
  "${REPO_ROOT_DIR}/third_party/EasyTier/easytier/third_party/x86_64"
)

if(NOT EXISTS "${EASYTIER_BUNDLE_SOURCE_DIR}")
  message(FATAL_ERROR
    "EasyTier bundled runtime directory was not found at ${EASYTIER_BUNDLE_SOURCE_DIR}"
  )
endif()

file(GLOB EASYTIER_BUNDLE_SOURCE_FILES "${EASYTIER_BUNDLE_SOURCE_DIR}/*")
if(NOT EASYTIER_BUNDLE_SOURCE_FILES)
  message(FATAL_ERROR
    "EasyTier bundled runtime directory is empty: ${EASYTIER_BUNDLE_SOURCE_DIR}"
  )
endif()

set(EASYTIER_BUNDLE_OUTPUT_FILES "")
foreach(EASYTIER_BUNDLE_SOURCE_FILE IN LISTS EASYTIER_BUNDLE_SOURCE_FILES)
  get_filename_component(EASYTIER_BUNDLE_FILE_NAME "${EASYTIER_BUNDLE_SOURCE_FILE}" NAME)
  list(APPEND EASYTIER_BUNDLE_OUTPUT_FILES
    "${EASYTIER_EMBED_DIR}/${EASYTIER_BUNDLE_FILE_NAME}"
  )
endforeach()

add_custom_command(
  OUTPUT "${EASYTIER_CORE_FILE}" ${EASYTIER_BUNDLE_OUTPUT_FILES}
  COMMAND powershell
    -NoProfile
    -ExecutionPolicy Bypass
    -File "${REPO_ROOT_DIR}/tool/prepare_easytier.ps1"
    -RepoRoot "${REPO_ROOT_DIR}"
    -OutputDir "${EASYTIER_EMBED_DIR}"
  DEPENDS
    "${REPO_ROOT_DIR}/tool/prepare_easytier.ps1"
    "${REPO_ROOT_DIR}/third_party/EasyTier/.git"
    ${EASYTIER_BUNDLE_SOURCE_FILES}
  COMMENT "Building bundled easytier-core and embedding EasyTier x86_64 runtime files"
  VERBATIM
)

add_custom_target(embedded_easytier ALL
  DEPENDS "${EASYTIER_CORE_FILE}" ${EASYTIER_BUNDLE_OUTPUT_FILES}
)

add_dependencies(${BINARY_NAME} embedded_easytier)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)

foreach(plugin ${FLUTTER_PLUGIN_LIST})
  fleasytier_enable_yy_thunks(${plugin}_plugin)
endforeach()

foreach(ffi_plugin ${FLUTTER_FFI_PLUGIN_LIST})
  fleasytier_enable_yy_thunks(${ffi_plugin}_plugin)
endforeach()


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
# Make the "install" step default, as it's required to run.
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)

install(FILES "${EASYTIER_CORE_FILE}" DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)
foreach(EASYTIER_BUNDLE_OUTPUT_FILE IN LISTS EASYTIER_BUNDLE_OUTPUT_FILES)
  install(FILES "${EASYTIER_BUNDLE_OUTPUT_FILE}" DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
endforeach()
