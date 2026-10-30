# astraOS input method plugin (QT_IM_MODULE=astra), used by SysBoard

# Qt's platform input context API is private: since Qt 6.10 its target has to
# be asked for (the package exists since 6.9).
if(Qt6_VERSION VERSION_GREATER_EQUAL 6.9)
    find_package(Qt6 REQUIRED COMPONENTS GuiPrivate)
endif()

qt_add_plugin(astrainputcontext
    CLASS_NAME AstraInputContextPlugin
    PLUGIN_TYPE platforminputcontexts
    astrainputcontext.cpp astrainputcontext.h
)
target_link_libraries(astrainputcontext PRIVATE Qt6::Core Qt6::Gui Qt6::GuiPrivate)
install(TARGETS astrainputcontext LIBRARY DESTINATION ${ASTRA_LIB_DIR}/qt6/plugins/platforminputcontexts)
