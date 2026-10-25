find_package(ZLIB REQUIRED)

qt_add_library(astra SHARED
    include/astra/apkg.h
    include/astra/client.h
    include/astra/global.h
    include/astra/paths.h
    include/astra/properties.h
    include/astra/protocol.h
    src/apkg.cpp
    src/client.cpp
    src/paths.cpp
    src/properties.cpp
)
target_include_directories(astra PUBLIC $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>)
target_compile_definitions(astra PRIVATE ASTRA_BUILD_LIBRARY
    ASTRA_VERSION="${PROJECT_VERSION}")
target_link_libraries(astra PUBLIC Qt6::Core Qt6::Network PRIVATE ZLIB::ZLIB)
set_target_properties(astra PROPERTIES
    VERSION ${PROJECT_VERSION}
    SOVERSION ${PROJECT_VERSION_MAJOR}
    INSTALL_RPATH "$ORIGIN")

install(TARGETS astra LIBRARY DESTINATION ${ASTRA_LIB_DIR})
