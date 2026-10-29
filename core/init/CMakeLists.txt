add_executable(astra-init
    main.c
    fstab.c
    lp.c
    rc.c
    rescue.c
    service.c
    util.c
)
set_target_properties(astra-init PROPERTIES OUTPUT_NAME init)
target_compile_options(astra-init PRIVATE -Wall -Wextra -Wno-unused-parameter)

# The same binary is used as the ramdisk's /init (first stage) and as
# /system/bin/init (second stage). It must not depend on shared libraries
# because it runs before /system is mounted.
if(ASTRA_STATIC_INIT)
    target_link_options(astra-init PRIVATE -static)
endif()

install(TARGETS astra-init RUNTIME DESTINATION system/bin)
