# Astra.Controls - the astraOS design system for SysBoard and apps
include(AstraQml)

set_source_files_properties(Theme.qml Catalog.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

file(GLOB ASTRA_ICONS RELATIVE ${CMAKE_CURRENT_SOURCE_DIR} CONFIGURE_DEPENDS icons/*.svg)

qt_add_qml_module(astracontrols
    URI Astra.Controls
    VERSION 1.0
    PLUGIN_TARGET astracontrols
    OUTPUT_DIRECTORY ${ASTRA_QML_OUTPUT}/Astra/Controls
    IMPORTS Astra.Animation Astra.Core
    QML_FILES
        AppIcon.qml
        BatteryGlyph.qml
        Button.qml
        Card.qml
        Catalog.qml
        CellularGlyph.qml
        EmptyState.qml
        Icon.qml
        IconButton.qml
        ListGroup.qml
        ListItem.qml
        Page.qml
        PageStack.qml
        PinEntry.qml
        PlaceholderApp.qml
        ProgressBar.qml
        SegmentedControl.qml
        Sheet.qml
        ShareSheet.qml
        Slider.qml
        Spinner.qml
        Switch.qml
        TabBar.qml
        TextField.qml
        Theme.qml
        WeatherGlyph.qml
        WidgetTile.qml
        WifiGlyph.qml
    RESOURCES
        ${ASTRA_ICONS}
)
target_link_libraries(astracontrols PRIVATE Qt6::Quick)
astra_install_qml_module(astracontrols Astra/Controls)
