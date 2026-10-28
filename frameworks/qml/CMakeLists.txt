add_subdirectory(core)
add_subdirectory(controls)

# Framework strings (Astra.Controls, Astra.Core), see docs/LOCALIZATION.md
file(GLOB ASTRA_FRAMEWORK_I18N CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/../i18n/*.json)
install(FILES ${ASTRA_FRAMEWORK_I18N} DESTINATION system/framework/i18n)
