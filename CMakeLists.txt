cmake_minimum_required(VERSION 3.21)

file(READ ${CMAKE_CURRENT_SOURCE_DIR}/version.json _v)
string(JSON _major GET "${_v}" major)
string(JSON _minor GET "${_v}" minor)
project(astraOS
    VERSION ${_major}.${_minor}.0
    DESCRIPTION "Welcome to astraOS"
    LANGUAGES C CXX
)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
include(AstraVersion)
set(ASTRA_BUILD_TYPE "userdebug" CACHE STRING "Build flavour reported in build.prop (user, userdebug, eng)")

option(ASTRA_BUILD_CORE "Build init and the boot animation (Linux only)" ON)
option(ASTRA_BUILD_UI "Build the Qt based frameworks, SysBoard, services and apps" ON)
option(ASTRA_STATIC_INIT "Link init statically (required when it is used as the ramdisk /init)" OFF)
option(ASTRA_BUILD_TESTS "Build the test suite" ON)

set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# Everything is installed relative to the root of the target filesystem:
#   cmake --install build --prefix out/root   (development tree)
#   DESTDIR=<rootfs> cmake --install build --prefix /   (device images)
set(ASTRA_BIN_DIR system/bin)
set(ASTRA_LIB_DIR system/lib)
set(ASTRA_QML_DIR system/framework/qml)
set(ASTRA_ETC_DIR system/etc)
set(CMAKE_INSTALL_RPATH_USE_LINK_PATH ON)

find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(ASTRA_APKGTOOL ${CMAKE_CURRENT_SOURCE_DIR}/tools/apkgtool/apkgtool.py)

if(ASTRA_BUILD_TESTS)
    enable_testing()
endif()

if(ASTRA_BUILD_CORE)
    add_subdirectory(core/init)
    add_subdirectory(core/bootanimation)
endif()
add_subdirectory(core/rootdir)

if(ASTRA_BUILD_UI)
    find_package(Qt6 6.5 REQUIRED COMPONENTS
        Core Gui Network Qml Quick QuickControls2 WaylandCompositor)
    qt_standard_project_setup(REQUIRES 6.5)
    set(ASTRA_QML_OUTPUT ${CMAKE_BINARY_DIR}/qml)

    add_subdirectory(frameworks/libastra)
    add_subdirectory(frameworks/animation)
    add_subdirectory(frameworks/qml)
    add_subdirectory(frameworks/runtime)
    add_subdirectory(services/astrad)
    add_subdirectory(services/adud)
    add_subdirectory(sysboard)
    add_subdirectory(apps)
endif()

if(ASTRA_BUILD_TESTS)
    add_subdirectory(tests)
endif()
