# Root filesystem configuration and prebuilt resources shared by every device.

configure_file(build.prop.in ${CMAKE_CURRENT_BINARY_DIR}/build.prop @ONLY)
configure_file(etc/os-release.in ${CMAKE_CURRENT_BINARY_DIR}/os-release @ONLY)

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/build.prop DESTINATION system)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/os-release DESTINATION ${ASTRA_ETC_DIR})
install(FILES etc/passwd etc/group DESTINATION ${ASTRA_ETC_DIR})
install(DIRECTORY etc/init etc/fonts etc/udev DESTINATION ${ASTRA_ETC_DIR})
install(PROGRAMS etc/connectivity/launch.sh DESTINATION ${ASTRA_ETC_DIR}/connectivity)
install(PROGRAMS etc/android/container.sh etc/android/apkinfo.py DESTINATION ${ASTRA_ETC_DIR}/android)
install(DIRECTORY etc/iwd etc/wireplumber DESTINATION ${ASTRA_ETC_DIR})
install(FILES etc/resolvconf.conf DESTINATION ${ASTRA_ETC_DIR})

set(PREBUILT ${PROJECT_SOURCE_DIR}/prebuilt)
install(DIRECTORY ${PREBUILT}/fonts/ DESTINATION system/fonts)
install(DIRECTORY ${PREBUILT}/media/ DESTINATION system/media)
# astraOS Desktop: a smaller logo (docs/DESKTOP.md); installed after the phone's, so it replaces desc.txt.
if(ASTRA_FORM STREQUAL "desktop")
    install(FILES ${PROJECT_SOURCE_DIR}/distro/overlay/system/media/bootanimation/desc.txt DESTINATION system/media/bootanimation)
endif()

if(ASTRA_BUILD_CORE)
    install(FILES ${PROJECT_SOURCE_DIR}/core/bootanimation/bootanim.rc DESTINATION ${ASTRA_ETC_DIR}/init)
endif()
