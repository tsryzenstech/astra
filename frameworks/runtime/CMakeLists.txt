qt_add_executable(astra-app main.cpp)
target_link_libraries(astra-app PRIVATE astra Qt6::Gui Qt6::Qml Qt6::Quick)
set_target_properties(astra-app PROPERTIES INSTALL_RPATH "$ORIGIN/../lib")
install(TARGETS astra-app RUNTIME DESTINATION ${ASTRA_BIN_DIR})
