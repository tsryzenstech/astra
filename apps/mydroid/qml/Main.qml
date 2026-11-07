// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// MyDroid: Android apps on astraOS. A modern Android (LineageOS, as Waydroid
// publishes it) runs in its own space; the APKs installed from here get an
// icon on the home screen with a green badge, open in their own windows and
// show their notifications. astrad does the work (android.*, see
// services/astrad/androidservice.h); this app is its face.
Rectangle {
    id: app
    color: Theme.background

    property var st: ({})
    property string message: ""
    property string variant: "vanilla"
    readonly property var apps: st.apps || []

    function refresh() {
        System.call("android.status", {}, function(r, err) {
            if (!err && r)
                app.st = r
        })
    }
    function call(method, params, done) {
        app.message = ""
        System.call("android." + method, params || {}, function(r, err) {
            if (err)
                app.message = err
            app.refresh()
            if (done)
                done(!err)
        })
    }
    function install(path) {
        app.message = qsTr("Installing %1…").arg(path.split("/").pop())
        installing = true
        System.call("android.install", { path: path }, function(r, err) {
            app.installing = false
            app.message = err ? err : qsTr("Installed: it is on your home screen")
            app.refresh()
        })
    }
    property bool installing: false

    Timer { interval: 1500; repeat: true; running: Qt.application.state === Qt.ApplicationActive; triggeredOnStart: true; onTriggered: app.refresh() }

    // An APK opened from Files ("Open with").
    function route(args) {
        if (args && args.action === "open" && args.files && args.files.length)
            app.pendingApk = args.files[0]
    }
    property string pendingApk: ""
    onPendingApkChanged: tryPending()
    function tryPending() {
        if (pendingApk && st.running && !installing) {
            const path = pendingApk
            pendingApk = ""
            install(path)
        }
    }
    onStChanged: tryPending()
    Component.onCompleted: route(Application.args)
    Connections {
        target: Application
        function onIntent(args) { app.route(args) }
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

            Card {
                accented: true
                Column {
                    width: parent.width
                    spacing: 4
                    Text {
                        text: qsTr("Android")
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.titleSize + 4
                        font.weight: Font.Bold
                        color: Theme.accentText
                    }
                    Text {
                        width: parent.width
                        wrapMode: Text.Wrap
                        text: {
                            if (app.st.available === false)
                                return qsTr("This build of astraOS has no Android environment.")
                            if (app.st.step === "download")
                                return app.st.progress >= 0 ? qsTr("Downloading Android… %1%").arg(Math.round(app.st.progress * 100))
                                                            : qsTr("Downloading Android…")
                            if (app.st.step === "starting")
                                return qsTr("Starting Android…")
                            if (app.st.step === "stopping")
                                return qsTr("Turning Android off…")
                            if (app.st.running)
                                return qsTr("Android is on: your Android apps are on the home screen.")
                            if (app.st.installed)
                                return qsTr("Android is off. Your Android apps turn it on when you open them.")
                            return qsTr("Install Android once to use Android apps.")
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.bodySize
                        font.weight: Font.Medium
                        color: Theme.accentText
                    }
                    Item { width: 1; height: 6 }
                    ProgressBar {
                        visible: app.st.busy === true
                        width: parent.width
                        height: 8
                        indeterminate: !(app.st.progress >= 0)
                        value: app.st.progress >= 0 ? app.st.progress : 0
                        color: Theme.accentText
                        trackColor: Theme.glass
                    }
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

            // ---- first time: which Android -------------------------------------------------
            ListGroup {
                visible: app.st.available !== false && app.st.installed === false && app.st.busy !== true
                title: qsTr("Android to install")
                footer: qsTr("About 1 GB is downloaded and kept on the phone. Android runs in its own space: it does not see your files, your accounts or astraOS's apps.")
                ListItem {
                    text: qsTr("Android")
                    subtitle: qsTr("Without Google's services")
                    selected: app.variant === "vanilla"
                    onClicked: app.variant = "vanilla"
                }
                ListItem {
                    text: qsTr("Android with Google")
                    subtitle: qsTr("Play Store and Google's services (sign in to Google in Android)")
                    selected: app.variant === "gapps"
                    separator: false
                    onClicked: app.variant = "gapps"
                }
            }
            Button {
                visible: app.st.available !== false && app.st.installed === false && app.st.busy !== true
                width: parent.width
                text: qsTr("Install Android")
                onClicked: app.call("setup", { variant: app.variant })
            }

            // ---- installed -------------------------------------------------------------------
            ListGroup {
                visible: app.st.installed === true
                ListItem {
                    text: qsTr("Android")
                    showSwitch: true
                    checked: app.st.running === true || app.st.step === "starting"
                    enabled: app.st.busy !== true
                    separator: false
                    onClicked: app.call(app.st.running ? "stop" : "start")
                }
            }
            Button {
                visible: app.st.installed === true
                width: parent.width
                enabled: app.st.running === true && !app.installing
                text: app.installing ? qsTr("Installing…") : qsTr("Install an APK")
                onClicked: Permissions.request("astra.permission.MEDIA", function(granted) {
                    if (granted)
                        picker.load()
                })
            }

            ListGroup {
                visible: app.st.installed === true
                title: qsTr("Android apps")
                footer: app.apps.length ? qsTr("They are on your home screen with a green badge, which shows their notifications.") : ""
                ListItem {
                    visible: app.apps.length === 0
                    text: qsTr("None yet: install an APK")
                    separator: false
                }
                Repeater {
                    model: app.apps
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: modelData.name || modelData.package
                        subtitle: modelData.package
                        iconSource: (Packages.get(modelData.shortcut) || {}).iconUrl || ""
                        chevron: true
                        separator: index < app.apps.length - 1
                        onClicked: Dialogs.show({ title: modelData.name,
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

            ListGroup {
                visible: app.st.installed === true
                ListItem {
                    text: qsTr("Remove Android")
                    destructive: true
                    separator: false
                    enabled: app.st.busy !== true
                    onClicked: Dialogs.show({ title: qsTr("Remove Android?"),
                                              message: qsTr("Android, its apps and their data are removed from this phone."),
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
