// SPDX-License-Identifier: Apache-2.0
import QtQuick

// Coloured glyph for an astrad weather condition
// (sunny, clear, partly-cloudy, cloudy, foggy, rainy, snowy, stormy).
Icon {
    property string condition: "sunny"
    name: "weather-" + (condition || "sunny")
}
