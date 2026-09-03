cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "status_notifier_item.cc"
  "x11_click_combo.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)
# X11 クリック補正（XTest / XRecord）。X11 でないビルドでは影響なし
# XTest/XRecord は Xtst、XFlush/XQueryPointer 等は X11 が必要
pkg_check_modules(XTST QUIET IMPORTED_TARGET xtst)
pkg_check_modules(X11LIB QUIET IMPORTED_TARGET x11)
if(XTST_FOUND)
  target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::XTST)
  if(X11LIB_FOUND)
    target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::X11LIB)
  endif()
endif()

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
