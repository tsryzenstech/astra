# astraOS Desktop's own apps (target "desktop"): built only for -DASTRA_FORM=desktop. The ones that
# share a package with a mobile app (apps/<name>) are that app's desktop build: Market has one page.
# (astra_add_desktop_app comes from cmake/AstraApp.cmake, included by apps/CMakeLists.txt.)
astra_add_desktop_app(files)
