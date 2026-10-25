find_package(PkgConfig REQUIRED)
pkg_check_modules(LIBDRM REQUIRED IMPORTED_TARGET libdrm)
pkg_check_modules(LIBPNG REQUIRED IMPORTED_TARGET libpng)

add_executable(astra-bootanim bootanim.c)
target_link_libraries(astra-bootanim PRIVATE PkgConfig::LIBDRM PkgConfig::LIBPNG)
target_compile_options(astra-bootanim PRIVATE -Wall -Wextra)
set_target_properties(astra-bootanim PROPERTIES OUTPUT_NAME bootanim)

install(TARGETS astra-bootanim RUNTIME DESTINATION system/bin)
