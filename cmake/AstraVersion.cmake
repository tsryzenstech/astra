# astraOS versioning (see docs/VERSIONING.md)
#
#   <major>.<minor><channel letter>   e.g. 0.1d = 0.1 on the "delta" channel
#
# The build number is the number of commits in the history, so it only grows
# along a branch: OTA servers compare build numbers, never version strings.

file(READ ${CMAKE_SOURCE_DIR}/version.json _astra_version_json)
string(JSON ASTRA_VERSION_MAJOR GET "${_astra_version_json}" major)
string(JSON ASTRA_VERSION_MINOR GET "${_astra_version_json}" minor)
string(JSON ASTRA_CHANNEL GET "${_astra_version_json}" channel)
string(JSON ASTRA_CODENAME GET "${_astra_version_json}" codename)
string(JSON ASTRA_API_LEVEL GET "${_astra_version_json}" api_level)

set(_astra_channel_letters alpha a beta b delta d stable "")
list(FIND _astra_channel_letters "${ASTRA_CHANNEL}" _idx)
if(_idx LESS 0)
    message(FATAL_ERROR "version.json: unknown channel '${ASTRA_CHANNEL}' (alpha, beta, delta, stable)")
endif()
math(EXPR _idx "${_idx} + 1")
list(LENGTH _astra_channel_letters _len)
if(_idx LESS _len)
    list(GET _astra_channel_letters ${_idx} ASTRA_CHANNEL_LETTER)
else()
    set(ASTRA_CHANNEL_LETTER "")
endif()
set(ASTRA_VERSION "${ASTRA_VERSION_MAJOR}.${ASTRA_VERSION_MINOR}${ASTRA_CHANNEL_LETTER}")

find_package(Git QUIET)
set(ASTRA_BUILD_NUMBER 0)
set(ASTRA_GIT_HASH "unknown")
if(GIT_FOUND AND EXISTS ${CMAKE_SOURCE_DIR}/.git)
    execute_process(COMMAND ${GIT_EXECUTABLE} rev-list --count HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} OUTPUT_VARIABLE ASTRA_BUILD_NUMBER
        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    execute_process(COMMAND ${GIT_EXECUTABLE} rev-parse --short=10 HEAD
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR} OUTPUT_VARIABLE ASTRA_GIT_HASH
        OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
    if(NOT ASTRA_BUILD_NUMBER)
        set(ASTRA_BUILD_NUMBER 0)
    endif()
endif()
# Overridable by release builds (e.g. CI passing the store's build counter).
set(ASTRA_BUILD_NUMBER "${ASTRA_BUILD_NUMBER}" CACHE STRING "Monotonic build number used by OTA updates")

string(TIMESTAMP ASTRA_BUILD_DATE "%Y%m%d" UTC)
string(TIMESTAMP ASTRA_BUILD_EPOCH "%s" UTC)
set(ASTRA_BUILD_ID "ASTRA.${ASTRA_VERSION}.${ASTRA_BUILD_DATE}.${ASTRA_BUILD_NUMBER}")
set(ASTRA_OTA_URL "https://raw.githubusercontent.com/tsryzenstech/astra-ota/main" CACHE STRING "Base URL of the OTA update manifests")
set(ASTRA_MARKET_URL "https://raw.githubusercontent.com/tsryzenstech/astra-market/main/index.json" CACHE STRING "Market catalog (JSON list of apps)")

message(STATUS "astraOS ${ASTRA_VERSION} \"${ASTRA_CODENAME}\" (${ASTRA_CHANNEL}) build ${ASTRA_BUILD_NUMBER} ${ASTRA_GIT_HASH}")
