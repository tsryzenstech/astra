# Astra.Desktop - the controls only astraOS Desktop has (apps with "target": "desktop" import it; a mobile
# app does not: `astra check` E013). Everything else is Astra.Controls.
include(AstraQml)

qt_add_qml_module(astradesktop
    URI Astra.Desktop
    VERSION 1.0
    PLUGIN_TARGET astradesktop
    OUTPUT_DIRECTORY ${ASTRA_QML_OUTPUT}/Astra/Desktop
    IMPORTS Astra.Animation Astra.Core Astra.Controls
    QML_FILES
        ContextMenu.qml
        SidebarItem.qml
        ToolButton.qml
)
target_link_libraries(astradesktop PRIVATE Qt6::Quick)
astra_install_qml_module(astradesktop Astra/Desktop)
