# astraOS test suite (ctest)

add_test(NAME apkgtool
    COMMAND ${Python3_EXECUTABLE} -m unittest -v test_apkgtool
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR})
set_tests_properties(apkgtool PROPERTIES ENVIRONMENT "ASTRA_SOURCE_DIR=${PROJECT_SOURCE_DIR}")

if(ASTRA_BUILD_CORE)
    add_test(NAME init_rc_parses COMMAND astra-init --check ${PROJECT_SOURCE_DIR}/core/rootdir/etc/init)
    set_tests_properties(init_rc_parses PROPERTIES FAIL_REGULAR_EXPRESSION "unknown command|invalid|outside of a section")
endif()

if(ASTRA_BUILD_UI)
    find_package(Qt6 REQUIRED COMPONENTS Test)

    qt_add_executable(tst_spring tst_spring.cpp)
    target_link_libraries(tst_spring PRIVATE astraanimation_solver Qt6::Test)
    add_test(NAME spring COMMAND tst_spring)

    # Packages built by tools/apkgtool must be readable by the device-side reader.
    qt_add_executable(tst_apkg tst_apkg.cpp)
    target_link_libraries(tst_apkg PRIVATE astra Qt6::Test)
    add_dependencies(tst_apkg apkg_settings)
    target_compile_definitions(tst_apkg PRIVATE
        SETTINGS_APKG="${CMAKE_BINARY_DIR}/apps/com.astra.settings.apkg")
    add_test(NAME apkg_reader COMMAND tst_apkg)
endif()
