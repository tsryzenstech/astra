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
#   SHARE <mobile dir>   the desktop build keeps the mobile app's files it does not replace (its pages, strings and
#                        widgets): apps-desktop/<dir> is laid over a copy of apps/<mobile dir> and that is what is packed
#   NARROW WIDTH w HEIGHT h [MINWIDTH n] [MINHEIGHT n]
#                        no apps-desktop/<dir> of its own: the mobile app's files as they are, with a desktop manifest
#                        ("target": "desktop", a window of that size that resizes). For the apps whose layout follows the size
#                        of their window (no phone chrome: Theme.statusBarHeight is 0 for a desktop app).
function(astra_add_desktop_app dir)
    cmake_parse_arguments(APP "PRIVILEGED;NARROW" "SHARE;WIDTH;HEIGHT;MINWIDTH;MINHEIGHT" "" ${ARGN})
    if(NOT ASTRA_FORM STREQUAL "desktop")
        return()
    endif()
    set(src ${PROJECT_SOURCE_DIR}/apps-desktop/${dir})
    set(revpaths "")
    if(APP_NARROW)
        set(stage ${CMAKE_CURRENT_BINARY_DIR}/stage/${dir})
        file(REMOVE_RECURSE ${stage})
        file(COPY ${PROJECT_SOURCE_DIR}/apps/${dir}/ DESTINATION ${stage})
        file(READ ${PROJECT_SOURCE_DIR}/apps/${dir}/app.json manifest)
        if(NOT APP_MINWIDTH)
            set(APP_MINWIDTH 320)
        endif()
        if(NOT APP_MINHEIGHT)
            set(APP_MINHEIGHT 420)
        endif()
        string(JSON manifest SET "${manifest}" target "\"desktop\"")
        string(JSON manifest SET "${manifest}" desktop
               "{\"width\": ${APP_WIDTH}, \"height\": ${APP_HEIGHT}, \"minWidth\": ${APP_MINWIDTH}, \"minHeight\": ${APP_MINHEIGHT}}")
        file(WRITE ${stage}/app.json "${manifest}")
        file(GLOB_RECURSE shared CONFIGURE_DEPENDS ${PROJECT_SOURCE_DIR}/apps/${dir}/*)
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${shared})
        set(revpaths apps/${dir})
        set(src ${stage})
    elseif(APP_SHARE)
        set(stage ${CMAKE_CURRENT_BINARY_DIR}/stage/${dir})
        file(REMOVE_RECURSE ${stage})
        file(COPY ${PROJECT_SOURCE_DIR}/apps/${APP_SHARE}/ DESTINATION ${stage})
        file(COPY ${src}/ DESTINATION ${stage})
        # The strings of both (the desktop's win): the staged copy of the desktop's i18n replaced the mobile's.
        execute_process(COMMAND ${Python3_EXECUTABLE} ${PROJECT_SOURCE_DIR}/tools/i18n/merge_i18n.py
                        ${PROJECT_SOURCE_DIR}/apps/${APP_SHARE}/i18n ${src}/i18n ${stage}/i18n)
        file(GLOB_RECURSE desktopstrings CONFIGURE_DEPENDS ${src}/i18n/*)
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${desktopstrings})
        file(GLOB_RECURSE shared CONFIGURE_DEPENDS ${PROJECT_SOURCE_DIR}/apps/${APP_SHARE}/*)
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${shared})
        set(revpaths apps/${APP_SHARE} apps-desktop/${dir})
        set(src ${stage})
    endif()
    _astra_pack_app(${dir} ${src} "${APP_PRIVILEGED}" ".desktop" desktop-desktop "${revpaths}")
endfunction()

function(_astra_pack_app dir src privileged suffix kind)
    set(revpaths "${ARGV5}")
    set(APP_PRIVILEGED ${privileged})
    file(READ ${src}/app.json manifest)
    string(JSON package GET ${manifest} package)
    string(JSON label GET ${manifest} name)
    string(REPLACE " " "" label "${label}")

    # The app's revision: the commits that touched its folder. Market gets the
    # same version of the same commit (tools/market/publish.py), so a phone is
    # offered an update of a system app only when it really changed.
    set(revdir ${src})
    set(revargs .)
    if(revpaths)
        set(revdir ${PROJECT_SOURCE_DIR})
        set(revargs ${revpaths})
    endif()
    execute_process(
        COMMAND git rev-list --count HEAD -- ${revargs}
        WORKING_DIRECTORY ${revdir}
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
        if(NOT EXISTS ${PROJECT_SOURCE_DIR}/apps-desktop/${dir}/app.json AND NOT "${dir}" IN_LIST ASTRA_NARROW_DESKTOP_APPS)
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
