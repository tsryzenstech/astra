find_package(Qt6 REQUIRED COMPONENTS DBus)
find_package(PkgConfig)
if(PkgConfig_FOUND)
    pkg_check_modules(ASTRAD_LIBDRM IMPORTED_TARGET libdrm)
endif()

qt_add_executable(astrad
    activitymanager.cpp activitymanager.h
    alarmservice.cpp alarmservice.h
    contactsservice.cpp contactsservice.h
    developerservice.cpp developerservice.h
    dialogservice.cpp dialogservice.h
    displayservice.cpp displayservice.h
    hardwareservice.cpp hardwareservice.h
    initcontrol.h
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
    updateservice.cpp updateservice.h
    weatherservice.cpp weatherservice.h
    network/backends.h
    network/bluez.cpp network/bluez.h
    network/dbusutil.h
    network/iwd.cpp network/iwd.h
    network/modemmanager.cpp network/modemmanager.h
    network/networkservice.cpp network/networkservice.h
    network/simulated.cpp
)
target_link_libraries(astrad PRIVATE astra Qt6::Core Qt6::Network Qt6::DBus)
if(ASTRAD_LIBDRM_FOUND)
    target_link_libraries(astrad PRIVATE PkgConfig::ASTRAD_LIBDRM)
    target_compile_definitions(astrad PRIVATE ASTRA_HAVE_LIBDRM=1)
else()
    target_compile_definitions(astrad PRIVATE ASTRA_HAVE_LIBDRM=0)
endif()
set_target_properties(astrad PROPERTIES INSTALL_RPATH "$ORIGIN/../lib")

install(TARGETS astrad RUNTIME DESTINATION ${ASTRA_BIN_DIR})
install(FILES astrad.rc DESTINATION ${ASTRA_ETC_DIR}/init)
install(FILES defaults.json DESTINATION ${ASTRA_ETC_DIR}/settings)
