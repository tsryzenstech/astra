qt_add_executable(astrad
    activitymanager.cpp activitymanager.h
    hardwareservice.cpp hardwareservice.h
    jsonstore.h
    locksettingsservice.cpp locksettingsservice.h
    main.cpp
    mediasessionservice.cpp mediasessionservice.h
    notificationservice.cpp notificationservice.h
    packagemanager.cpp packagemanager.h
    permissions.h
    server.cpp server.h
    settingsservice.cpp settingsservice.h
    systemservice.cpp systemservice.h
    weatherservice.cpp weatherservice.h
)
target_link_libraries(astrad PRIVATE astra Qt6::Core Qt6::Network)
set_target_properties(astrad PROPERTIES INSTALL_RPATH "$ORIGIN/../lib")

install(TARGETS astrad RUNTIME DESTINATION ${ASTRA_BIN_DIR})
install(FILES astrad.rc DESTINATION ${ASTRA_ETC_DIR}/init)
install(FILES defaults.json DESTINATION ${ASTRA_ETC_DIR}/settings)
