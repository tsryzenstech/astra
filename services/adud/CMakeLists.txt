find_library(ADUD_UTIL util)

qt_add_executable(adud adud.cpp adud.h)
target_link_libraries(adud PRIVATE astra Qt6::Core Qt6::Network)
if(ADUD_UTIL)
    target_link_libraries(adud PRIVATE ${ADUD_UTIL}) # forkpty on glibc (musl has it in libc)
endif()
set_target_properties(adud PROPERTIES INSTALL_RPATH "$ORIGIN/../lib")

install(TARGETS adud RUNTIME DESTINATION ${ASTRA_BIN_DIR})
install(FILES adud.rc DESTINATION ${ASTRA_ETC_DIR}/init)
install(PROGRAMS usb-gadget.sh DESTINATION ${ASTRA_ETC_DIR}/adu)
