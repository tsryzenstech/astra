# astra_add_app(<dir> [PRIVILEGED])
#
# Packs apps/<dir> (app.json + QML + assets) into <package>.apkg with
# tools/apkgtool and installs it as a system app:
#   system/app/<Name>/<package>.apkg        (default)
#   system/priv-app/<Name>/<package>.apkg   (PRIVILEGED: may hold system permissions)
function(astra_add_app dir)
    cmake_parse_arguments(APP "PRIVILEGED" "" "" ${ARGN})
    set(src ${CMAKE_CURRENT_SOURCE_DIR}/${dir})
    file(READ ${src}/app.json manifest)
    string(JSON package GET ${manifest} package)
    string(JSON label GET ${manifest} name)
    string(REPLACE " " "" label "${label}")

    file(GLOB_RECURSE inputs CONFIGURE_DEPENDS ${src}/*)
    set(out ${CMAKE_CURRENT_BINARY_DIR}/${package}.apkg)
    add_custom_command(
        OUTPUT ${out}
        COMMAND ${Python3_EXECUTABLE} ${ASTRA_APKGTOOL} pack ${src} -o ${out}
        DEPENDS ${inputs} ${ASTRA_APKGTOOL}
        COMMENT "Packing ${package}.apkg"
        VERBATIM)
    add_custom_target(apkg_${dir} ALL DEPENDS ${out})

    if(APP_PRIVILEGED)
        set(dest system/priv-app/${label})
    else()
        set(dest system/app/${label})
    endif()
    install(FILES ${out} DESTINATION ${dest})
endfunction()
