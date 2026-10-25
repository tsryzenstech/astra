# Root filesystem configuration and prebuilt resources shared by every device.

configure_file(build.prop.in ${CMAKE_CURRENT_BINARY_DIR}/build.prop @ONLY)
configure_file(etc/os-release.in ${CMAKE_CURRENT_BINARY_DIR}/os-release @ONLY)

install(FILES ${CMAKE_CURRENT_BINARY_DIR}/build.prop DESTINATION system)
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/os-release DESTINATION ${ASTRA_ETC_DIR})
install(FILES etc/passwd etc/group DESTINATION ${ASTRA_ETC_DIR})
install(DIRECTORY etc/init etc/fonts etc/udev DESTINATION ${ASTRA_ETC_DIR})

set(PREBUILT ${PROJECT_SOURCE_DIR}/prebuilt)
install(DIRECTORY ${PREBUILT}/fonts/ DESTINATION system/fonts)
install(DIRECTORY ${PREBUILT}/media/ DESTINATION system/media)

if(ASTRA_BUILD_CORE)
    install(FILES ${PROJECT_SOURCE_DIR}/core/bootanimation/bootanim.rc DESTINATION ${ASTRA_ETC_DIR}/init)
endif()
