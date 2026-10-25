# AnimationEngine - the motion system of astraOS (QML module Astra.Animation)
include(AstraQml)

qt_add_qml_module(astraanimation
    URI Astra.Animation
    VERSION 1.0
    PLUGIN_TARGET astraanimation
    OUTPUT_DIRECTORY ${ASTRA_QML_OUTPUT}/Astra/Animation
    SOURCES
        motion.cpp motion.h
        spring.cpp spring.h
        springvalue.cpp springvalue.h
        velocitytracker.cpp velocitytracker.h
    QML_FILES
        SpringNumberAnimation.qml
)
target_link_libraries(astraanimation PRIVATE Qt6::Core Qt6::Qml Qt6::Quick)
astra_install_qml_module(astraanimation Astra/Animation)

# The solver is also used directly by tests.
add_library(astraanimation_solver STATIC spring.cpp)
target_include_directories(astraanimation_solver PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
