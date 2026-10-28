# SysBoard - compositor and system shell
qt_add_executable(sysboard main.cpp)

file(GLOB SYSBOARD_QML RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS qml/*.qml)
file(GLOB SYSBOARD_ICONS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS qml/icons/system/*.svg)
# Files live in qml/ in the source tree but at the module root at runtime,
# so they see each other (and the SystemClock singleton) through the qmldir.
foreach(file IN LISTS SYSBOARD_QML SYSBOARD_ICONS)
    string(REGEX REPLACE "^qml/" "" alias "${file}")
    set_source_files_properties(${file} PROPERTIES QT_RESOURCE_ALIAS ${alias})
endforeach()
set_source_files_properties(qml/SystemClock.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(sysboard
    URI SysBoard
    VERSION 1.0
    SOURCES
        host.cpp host.h
    QML_FILES
        ${SYSBOARD_QML}
    RESOURCES
        ${SYSBOARD_ICONS}
)

target_link_libraries(sysboard PRIVATE
    astra
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::WaylandCompositor
)
set_target_properties(sysboard PROPERTIES INSTALL_RPATH "$ORIGIN/../lib")

install(TARGETS sysboard RUNTIME DESTINATION ${ASTRA_BIN_DIR})
install(FILES sysboard.rc DESTINATION ${ASTRA_ETC_DIR}/init)

file(GLOB SYSBOARD_I18N CONFIGURE_DEPENDS i18n/*.json)
install(FILES ${SYSBOARD_I18N} DESTINATION ${ASTRA_ETC_DIR}/i18n/sysboard)
