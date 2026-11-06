find_package(PkgConfig REQUIRED)
pkg_check_modules(DISPTEST_DEPS REQUIRED IMPORTED_TARGET libdrm gbm egl glesv2)

add_executable(disptest disptest.c)
target_link_libraries(disptest PRIVATE PkgConfig::DISPTEST_DEPS)
target_compile_options(disptest PRIVATE -Wall -Wextra)

install(TARGETS disptest RUNTIME DESTINATION system/bin)
install(PROGRAMS astra-diag DESTINATION system/bin)
