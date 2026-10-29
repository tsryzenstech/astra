# astraOS input method plugin (QT_IM_MODULE=astra), used by SysBoard
qt_add_plugin(astrainputcontext
    CLASS_NAME AstraInputContextPlugin
    PLUGIN_TYPE platforminputcontexts
    astrainputcontext.cpp astrainputcontext.h
)
target_link_libraries(astrainputcontext PRIVATE Qt6::Core Qt6::Gui Qt6::GuiPrivate)
install(TARGETS astrainputcontext LIBRARY DESTINATION ${ASTRA_LIB_DIR}/qt6/plugins/platforminputcontexts)
