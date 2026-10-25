# Helpers shared by the framework QML modules.

# Installs a QML module built with qt_add_qml_module() whose plugin and
# backing target are the same MODULE library.
#   astra_install_qml_module(<target> <relative module path, e.g. Astra/Controls>)
function(astra_install_qml_module target module_path)
    set(dest ${ASTRA_QML_DIR}/${module_path})
    # Plugins live 4-5 levels below system/, e.g. system/framework/qml/Astra/Core
    string(REGEX MATCHALL "/" slashes "${dest}")
    list(LENGTH slashes depth)
    string(REPEAT "/.." ${depth} up)
    set_target_properties(${target} PROPERTIES INSTALL_RPATH "$ORIGIN${up}/${ASTRA_LIB_DIR}")
    install(TARGETS ${target} LIBRARY DESTINATION ${dest})
    install(DIRECTORY ${ASTRA_QML_OUTPUT}/${module_path}/
        DESTINATION ${dest}
        FILES_MATCHING PATTERN "qmldir" PATTERN "*.qmltypes")
endfunction()
