# astra_add_app(<dir> [PRIVILEGED])
#
# Packs apps/<dir> (app.json + QML + assets) into <package>.apkg with
# tools/apkgtool and installs it as a system app:
#   system/app/<Name>/<package>.apkg        (default)
#   system/priv-app/<Name>/<package>.apkg   (PRIVILEGED: may hold system permissions)
#
# In an image for astraOS Desktop (-DASTRA_FORM=desktop, docs/DESKTOP.md) every app is installed in
#   Applications/<Name>.apkg
# and the PRIVILEGED ones are listed in system/etc/priv-apps.txt (root-owned: astrad's package manager
# reads it). An app with a desktop build in apps-desktop/<dir> (astra_add_desktop_app) is installed from
# that one; its mobile build runs in a phone shaped window otherwise.
include_guard(GLOBAL)
set_property(GLOBAL PROPERTY ASTRA_PRIV_APPS "")

function(astra_add_app dir)
    cmake_parse_arguments(APP "PRIVILEGED" "" "" ${ARGN})
    set(src ${CMAKE_CURRENT_SOURCE_DIR}/${dir})
    _astra_pack_app(${dir} ${src} "${APP_PRIVILEGED}" "" ${ASTRA_FORM}-mobile)
endfunction()

# The desktop build of an app: apps-desktop/<dir>, "target": "desktop", the same package as the mobile
# build when there is one (Market has one page for both and gives each device its own).
function(astra_add_desktop_app dir)
    cmake_parse_arguments(APP "PRIVILEGED" "" "" ${ARGN})
    if(NOT ASTRA_FORM STREQUAL "desktop")
        return()
    endif()
    _astra_pack_app(${dir} ${PROJECT_SOURCE_DIR}/apps-desktop/${dir} "${APP_PRIVILEGED}" ".desktop" desktop-desktop)
endfunction()

function(_astra_pack_app dir src privileged suffix kind)
    set(APP_PRIVILEGED ${privileged})
    file(READ ${src}/app.json manifest)
    string(JSON package GET ${manifest} package)
    string(JSON label GET ${manifest} name)
    string(REPLACE " " "" label "${label}")

    # The app's revision: the commits that touched its folder. Market gets the
    # same version of the same commit (tools/market/publish.py), so a phone is
    # offered an update of a system app only when it really changed.
    execute_process(
        COMMAND git rev-list --count HEAD -- .
        WORKING_DIRECTORY ${src}
        OUTPUT_VARIABLE revision
        OUTPUT_STRIP_TRAILING_WHITESPACE
        RESULT_VARIABLE git_result
        ERROR_QUIET)
    if(NOT git_result EQUAL 0 OR revision STREQUAL "")
        set(revision 0)
    endif()

    file(GLOB_RECURSE inputs CONFIGURE_DEPENDS ${src}/*)
    set(out ${CMAKE_CURRENT_BINARY_DIR}/${package}${suffix}.apkg)
    add_custom_command(
        OUTPUT ${out}
        COMMAND ${Python3_EXECUTABLE} ${ASTRA_APKGTOOL} pack ${src} -o ${out} --build ${revision}
        DEPENDS ${inputs} ${ASTRA_APKGTOOL}
        COMMENT "Packing ${package}.apkg"
        VERBATIM)
    add_custom_target(apkg_${dir}${suffix} ALL DEPENDS ${out})

    if(kind STREQUAL "desktop-desktop")
        install(FILES ${out} DESTINATION Applications RENAME ${label}.apkg)
    elseif(ASTRA_FORM STREQUAL "desktop")
        # The mobile build stays out of the image when the app has a desktop one.
        if(NOT EXISTS ${PROJECT_SOURCE_DIR}/apps-desktop/${dir}/app.json)
            install(FILES ${out} DESTINATION Applications RENAME ${label}.apkg)
        endif()
    elseif(APP_PRIVILEGED)
        install(FILES ${out} DESTINATION system/priv-app/${label})
    else()
        install(FILES ${out} DESTINATION system/app/${label})
    endif()
    if(APP_PRIVILEGED AND ASTRA_FORM STREQUAL "desktop")
        set_property(GLOBAL APPEND PROPERTY ASTRA_PRIV_APPS ${package})
    endif()
endfunction()

# Call once, after the last astra_add_app (apps/CMakeLists.txt).
function(astra_finish_apps)
    if(NOT ASTRA_FORM STREQUAL "desktop")
        return()
    endif()
    get_property(privs GLOBAL PROPERTY ASTRA_PRIV_APPS)
    list(JOIN privs "\n" body)
    file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/priv-apps.txt "# Packages in /Applications that hold system permissions.\n${body}\n")
    install(FILES ${CMAKE_CURRENT_BINARY_DIR}/priv-apps.txt DESTINATION ${ASTRA_ETC_DIR})
endfunction()
