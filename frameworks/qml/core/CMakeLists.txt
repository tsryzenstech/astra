# Astra.Core - QML bindings for astrad (system services)
include(AstraQml)

qt_add_qml_module(astracore
    URI Astra.Core
    VERSION 1.0
    PLUGIN_TARGET astracore
    OUTPUT_DIRECTORY ${ASTRA_QML_OUTPUT}/Astra/Core
    SOURCES
        common.cpp common.h
        files.cpp files.h
        imagetools.cpp imagetools.h
        mail.cpp mail.h
        media.cpp media.h
        notifications.cpp notifications.h
        packages.cpp packages.h
        services.cpp services.h
        servicestate.cpp servicestate.h
        settings.cpp settings.h
        system.cpp system.h
)
target_link_libraries(astracore PRIVATE astra Qt6::Core Qt6::Gui Qt6::Network Qt6::Qml)
astra_install_qml_module(astracore Astra/Core)
