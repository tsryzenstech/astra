// SPDX-License-Identifier: Apache-2.0
pragma Singleton
import QtQuick

// Translatable strings that come from system services in English
// (permission labels, dialog buttons). Catalog.tr(text) translates them;
// the QT_TR_NOOP list below registers them with tools/i18n.
QtObject {
    function tr(text) { return text ? qsTr(text) : "" }

    readonly property var strings: [
        // Permissions (services/astrad/permissions.h)
        QT_TR_NOOP("Full network access"), QT_TR_NOOP("Vibration"), QT_TR_NOOP("Alarms and timers"),
        QT_TR_NOOP("Notifications"), QT_TR_NOOP("Camera"), QT_TR_NOOP("Microphone"), QT_TR_NOOP("Location"),
        QT_TR_NOOP("Contacts"), QT_TR_NOOP("Calendar"), QT_TR_NOOP("Photos, videos and music"),
        QT_TR_NOOP("Phone calls"), QT_TR_NOOP("SMS messages"), QT_TR_NOOP("Nearby devices"),
        QT_TR_NOOP("Change system settings"), QT_TR_NOOP("Manage the screen lock"),
        QT_TR_NOOP("Install and remove apps"), QT_TR_NOOP("Manage all notifications"),
        QT_TR_NOOP("Manage networks"), QT_TR_NOOP("Change the system theme"),
        QT_TR_NOOP("Control media playback"), QT_TR_NOOP("Control hardware"), QT_TR_NOOP("Reboot the device"),
        QT_TR_NOOP("Developer options"),
        // Common dialog buttons
        QT_TR_NOOP("Allow"), QT_TR_NOOP("Don't allow"), QT_TR_NOOP("Deny"), QT_TR_NOOP("Cancel"),
        QT_TR_NOOP("OK"), QT_TR_NOOP("Delete"), QT_TR_NOOP("Uninstall"), QT_TR_NOOP("Continue")
    ]
}
