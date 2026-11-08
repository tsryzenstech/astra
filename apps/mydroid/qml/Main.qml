// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// MyDroid: the client of astraOS's Android subsystem.
//
// The subsystem is part of the system (Waydroid's container and astrad's
// android service, services/astrad/androidservice.h); MyDroid downloads
// Android for it (LineageOS, as Waydroid publishes it), shows how it is doing,
// installs APKs and lists the Android apps. With MyDroid installed and Android
// downloaded, Android starts by itself with the phone; its apps are on the home
// screen with a green badge, open in their own window and show their
// notifications.
Rectangle {
    id: app
    color: Theme.background

    property var st: ({})
    property string message: ""
    property string variant: "vanilla"
    property bool installing: false
    property string pendingApk: ""
    readonly property var apps: st.apps || []
    readonly property bool available: st.available !== false
    readonly property bool installed: st.installed === true
    readonly property bool running: st.running === true
    readonly property bool busy: st.busy === true

    function refresh() {
        System.call("android.status", {}, function(r, err) {
            if (!err && r)
                app.st = r
        })
    }
    function call(method, params) {
        app.message = ""
        System.call("android." + method, params || {}, function(r, err) {
            if (err)
                app.message = err
            app.refresh()
        })
    }
    function install(path) {
        app.message = qsTr("Installing %1…").arg(path.split("/").pop())
        app.installing = true
        System.call("android.install", { path: path }, function(r, err) {
            app.installing = false
            app.message = err ? err : qsTr("Installed: it is on your home screen")
            app.refresh()
        })
    }
    Timer { interval: 1500; repeat: true; running: Qt.application.state === Qt.ApplicationActive; triggeredOnStart: true; onTriggered: app.refresh() }

    // An APK opened from Files ("Open with"): installed once Android runs.
    function route(args) {
        if (args && args.action === "open" && args.files && args.files.length)
            app.pendingApk = args.files[0]
    }
    function tryPending() {
        if (pendingApk && running && !installing) {
            const path = pendingApk
            pendingApk = ""
            install(path)
        }
    }
    onPendingApkChanged: tryPending()
    onStChanged: tryPending()
    Component.onCompleted: route(Application.args)
    Connections {
        target: Application
        function onIntent(args) { app.route(args) }
    }

    readonly property string headline: {
        if (!available) return qsTr("Not available")
        if (st.step === "download") return qsTr("Downloading")
        if (st.step === "starting") return qsTr("Starting")
        if (st.step === "stopping") return qsTr("Restarting")
        if (running) return qsTr("Running")
        if (installed) return qsTr("Starting soon")
        return qsTr("Not installed")
    }
    readonly property string detail: {
        if (!available) return qsTr("This version of astraOS has no Android subsystem.")
        if (st.step === "download")
            return st.progress >= 0 ? qsTr("Android is being downloaded: %1%").arg(Math.round(st.progress * 100))
                                    : qsTr("Android is being downloaded and prepared.")
        if (st.step === "starting") return qsTr("Android is starting. The first time takes a minute.")
        if (running) return qsTr("Android starts with your phone. Its apps are on your home screen.")
        if (installed) return qsTr("Android starts with your phone.")
        return qsTr("Download Android once: then its apps run on astraOS, next to yours.")
    }

    PageStack {
        id: stack
        anchors.fill: parent
        Component.onCompleted: open(mainPage)
    }

    Component {
        id: mainPage
        Page {
            title: qsTr("MyDroid")

            // ---- the subsystem ------------------------------------------------------
            Card {
                accented: true
                Row {
                    width: parent.width
                    spacing: 16
                    Rectangle {
                        width: 64
                        height: 64
                        radius: 20
                        color: Theme.glass
                        Icon { anchors.centerIn: parent; name: "devices"; size: 34; color: Theme.accentText }
                        Rectangle {
                            visible: app.running
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: -2
                            width: 18
                            height: 18
                            radius: 9
                            color: Theme.success
                            border.width: 3
                            border.color: Theme.accentText
                        }
                    }
                    Column {
                        width: parent.width - 80
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            text: qsTr("Android") + " · " + app.headline
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.titleSize
                            font.weight: Font.Bold
                            color: Theme.accentText
                        }
                        Text {
                            width: parent.width
                            wrapMode: Text.Wrap
                            text: app.detail
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.bodySize
                            color: Theme.accentText
                        }
                    }
                }
                Item { width: 1; height: 12; visible: app.busy }
                ProgressBar {
                    visible: app.busy
                    width: parent.width
                    height: 8
                    indeterminate: !(app.st.progress >= 0)
                    value: app.st.progress >= 0 ? app.st.progress : 0
                    color: Theme.accentText
                    trackColor: Theme.glass
                }
            }

            Text {
                visible: app.message !== "" || (app.st.error || "") !== ""
                width: parent.width
                wrapMode: Text.Wrap
                text: app.message || app.st.error || ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.captionSize
                color: Theme.textSecondary
            }

            // ---- first time: download Android -----------------------------------------
            ListGroup {
                visible: app.available && !app.installed && !app.busy
                title: qsTr("Choose your Android")
                footer: qsTr("About 1 GB is downloaded once and kept on the phone. Android runs in its own space: it does not see your files, your accounts or astraOS's apps.")
                ListItem {
                    iconName: "shield"
                    text: qsTr("Android")
                    subtitle: qsTr("Without Google: private, light")
                    selected: app.variant === "vanilla"
                    onClicked: app.variant = "vanilla"
                }
                ListItem {
                    iconName: "globe"
                    text: qsTr("Android with Google")
                    subtitle: qsTr("Play Store and Google's services")
                    selected: app.variant === "gapps"
                    separator: false
                    onClicked: app.variant = "gapps"
                }
            }
            Button {
                visible: app.available && !app.installed && !app.busy
                width: parent.width
                text: qsTr("Download Android")
                onClicked: app.call("setup", { variant: app.variant })
            }

            // ---- installed: what to do ---------------------------------------------------
            Row {
                visible: app.installed
                width: parent.width
                spacing: 10
                Repeater {
                    model: [
                        { id: "apk", icon: "download", label: qsTr("Install APK") },
                        { id: "settings", icon: "settings", label: qsTr("Android settings") },
                        { id: "restart", icon: "refresh", label: qsTr("Restart") }
                    ]
                    delegate: Card {
                        required property var modelData
                        width: (parent.width - 20) / 3
                        height: 86
                        padding: 10
                        pressable: app.running || modelData.id === "restart"
                        opacity: pressable ? 1 : 0.45
                        Column {
                            width: parent.width
                            spacing: 6
                            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: modelData.icon; size: 24; color: Theme.accent }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.captionSize
                                font.weight: Font.Medium
                                color: Theme.text
                            }
                        }
                        onClicked: {
                            if (modelData.id === "apk")
                                Permissions.request("astra.permission.MEDIA", function(granted) { if (granted) picker.load() })
                            else if (modelData.id === "settings")
                                app.call("launch", { package: "com.android.settings" })
                            else
                                app.call("restart")
                        }
                    }
                }
            }

            // ---- the Android apps ----------------------------------------------------------
            ListGroup {
                visible: app.installed
                title: qsTr("Android apps")
                footer: qsTr("Every app installed in Android is on your home screen with a green badge, which shows its notifications: the APKs installed here, and the apps an app store such as Aurora Store installs (allow it in Android's settings when it asks).")
                Text {
                    visible: app.apps.length === 0
                    x: 16
                    width: parent.width - 32
                    topPadding: 14
                    bottomPadding: 14
                    wrapMode: Text.Wrap
                    text: app.installing ? qsTr("Installing…") : qsTr("None yet: install an APK.")
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.bodySize
                    color: Theme.textSecondary
                }
                Grid {
                    id: grid
                    visible: app.apps.length > 0
                    x: 8
                    width: parent.width - 16
                    columns: 4
                    topPadding: 12
                    bottomPadding: 8
                    Repeater {
                        model: app.apps
                        delegate: Item {
                            required property var modelData
                            width: grid.width / 4
                            height: 96
                            AppIcon {
                                id: icon
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: 56
                                source: (Packages.get(modelData.shortcut) || {}).iconUrl || ""
                            }
                            Text {
                                anchors.top: icon.bottom
                                anchors.topMargin: 6
                                width: parent.width - 6
                                anchors.horizontalCenter: parent.horizontalCenter
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: modelData.name || modelData.package
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.captionSize
                                color: Theme.text
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: Packages.launch(modelData.shortcut)
                                onPressAndHold: Dialogs.show({ title: modelData.name || modelData.package,
                                                               message: modelData.package,
                                                               buttons: [{ id: "open", label: qsTr("Open") },
                                                                         { id: "remove", label: qsTr("Uninstall"), style: "destructive" },
                                                                         { id: "cancel", label: qsTr("Cancel") }] },
                                                             function(answer) {
                                    if (answer === "open")
                                        Packages.launch(modelData.shortcut)
                                    else if (answer === "remove")
                                        app.call("remove", { package: modelData.package })
                                })
                            }
                        }
                    }
                }
            }

            ListGroup {
                visible: app.installed
                title: qsTr("Subsystem")
                ListItem {
                    text: qsTr("Edition")
                    value: app.st.variant === "gapps" ? qsTr("Android with Google") : qsTr("Android")
                }
                ListItem {
                    text: qsTr("Starts with the phone")
                    value: qsTr("Yes")
                }
                ListItem {
                    text: qsTr("Remove Android")
                    destructive: true
                    separator: false
                    enabled: !app.busy
                    onClicked: Dialogs.show({ title: qsTr("Remove Android?"),
                                              message: qsTr("Android, its apps and their data are removed from this phone. You can download it again."),
                                              buttons: [{ id: "cancel", label: qsTr("Cancel") },
                                                        { id: "reset", label: qsTr("Remove"), style: "destructive" }] },
                                            function(answer) {
                        if (answer === "reset")
                            app.call("reset")
                    })
                }
            }
        }
    }

    // APKs on the phone's storage.
    Sheet {
        id: picker
        title: qsTr("Install an APK")
        property var files: []
        function load() {
            files = Files.search(Files.home, ".apk", 200).filter(f => !f.dir && String(f.name).toLowerCase().endsWith(".apk"))
            open()
        }
        Column {
            width: parent.width
            EmptyState {
                visible: picker.files.length === 0
                iconName: "file"
                title: qsTr("No APK files")
                message: qsTr("Download an APK with Planet or copy one to the phone, then come back.")
            }
            Repeater {
                model: picker.files
                delegate: ListItem {
                    required property var modelData
                    width: parent.width
                    iconName: "file"
                    text: modelData.name
                    subtitle: (modelData.size / 1e6).toFixed(1) + " MB"
                    onClicked: {
                        picker.close()
                        app.install(modelData.path)
                    }
                }
            }
        }
    }
}
