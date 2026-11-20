// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Desktop

// The astraOS installer (the recovery environment of the live ISO): Welcome, the disk, a last question, the progress,
// done. It asks astrad's installer service (astra.permission.MANAGE_DISKS) to partition the disk the user chose,
// copy the system and install the bootloader; the first start of the installed system shows the usual setup.
Rectangle {
    id: app
    color: Theme.background

    property int step: 0                       // 0 welcome, 1 disk, 2 confirm, 3 installing, 4 done, 5 failed
    property var disks: []
    property string chosen: ""                 // a disk path
    property string mode: "erase"              // "erase": the whole disk, astraOS alone; "dual": next to what is on the disk
    property string rootPartition: ""          // dual: the partition astraOS goes on ("new": one made in the free space)
    property real newSizeGB: 40
    readonly property var esp: disk ? (disk.partitions.find(p => p.esp) || null) : null
    property real percent: 0
    property string text: ""
    property string error: ""
    readonly property var disk: disks.find(d => d.path === chosen) || null

    function refresh() {
        Installer.call("disks", {}, function(result, err) { if (!err && result) app.disks = result })
    }
    Component.onCompleted: refresh()
    function size(bytes) {
        if (bytes >= 1e12) return (bytes / 1e12).toFixed(1) + " TB"
        if (bytes >= 1e9) return (bytes / 1e9).toFixed(1) + " GB"
        return Math.round(bytes / 1e6) + " MB"
    }
    function start() {
        step = 3
        percent = 0
        text = qsTr("Starting...")
        const go = (root) => {
            const params = mode === "erase" ? { disk: chosen }
                : { root: root, esp: esp ? esp.path : undefined, bootdisk: chosen, dual: true }
            Installer.call("install", params, function(result, err) { if (err) { app.error = err; app.step = 5 } })
        }
        if (mode === "dual" && rootPartition === "new") {
            // The partition is made in the free space first, then it is the one astraOS goes on.
            text = qsTr("Making the partition...")
            Installer.call("createPartition", { disk: chosen, size: newSizeGB * 1e9, format: "ext4", label: "astraOS" }, function(result, err) {
                if (err) { app.error = err; app.step = 5; return }
                Installer.call("disks", {}, function(list) {
                    const d = (list || []).find(x => x.path === chosen)
                    go(d && d.partitions.length ? d.partitions[d.partitions.length - 1].path : "")
                })
            })
        } else {
            go(mode === "dual" ? rootPartition : "")
        }
    }
    Connections {
        target: Installer
        function onEvent(name, data) {
            if (name === "progress") { app.percent = data.percent / 100; app.text = data.text }
            else if (name === "finished") app.step = 4
            else if (name === "error") { app.error = data.message; app.step = 5 }
        }
    }

    // ---- 0: welcome ----
    Column {
        visible: app.step === 0
        anchors.centerIn: parent
        spacing: 18
        AppIcon { anchors.horizontalCenter: parent.horizontalCenter; size: 96; source: Packages.get("com.astra.installer").iconUrl || "" }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Install astraOS"); font.family: Theme.fontFamily
               font.pixelSize: Theme.largeTitleSize; font.weight: Font.DemiBold; color: Theme.text }
        Text { anchors.horizontalCenter: parent.horizontalCenter; width: 420; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
               text: qsTr("This puts astraOS Desktop on a disk of this computer. You choose the disk next; nothing is changed before you confirm.")
               font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.textSecondary }
        Button { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Continue"); onClicked: { app.refresh(); app.step = 1 } }
    }

    // ---- 1: the disk ----
    Item {
        visible: app.step === 1
        anchors.fill: parent
        anchors.margins: 32
        Text { id: title1; text: qsTr("Choose a disk"); font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.DemiBold; color: Theme.text }
        Text { id: sub1; anchors.top: title1.bottom; anchors.topMargin: 6; width: parent.width; wrapMode: Text.Wrap
               text: qsTr("astraOS will be installed on it. For more control (partitions, formats) open Disk Utility first.")
               font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.textSecondary }
        ListView {
            anchors.top: sub1.bottom
            anchors.topMargin: 16
            anchors.bottom: modeBox.visible ? modeBox.top : buttons1.top
            anchors.bottomMargin: 16
            width: parent.width
            spacing: 10
            clip: true
            model: app.disks
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property bool usable: !modelData.live
                readonly property bool selected: app.chosen === modelData.path
                width: ListView.view.width
                height: 76
                radius: Theme.radius
                color: selected ? Theme.surfaceRaised : Theme.surface
                border.width: selected ? 2 : 0
                border.color: Theme.accent
                opacity: usable ? 1 : 0.45
                Icon { x: 18; anchors.verticalCenter: parent.verticalCenter; name: "storage"; size: 30; color: Theme.accent }
                Column {
                    x: 66
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: card.modelData.model || card.modelData.name; font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.DemiBold; color: Theme.text }
                    Text { text: app.size(card.modelData.size) + " · " + card.modelData.path + (card.modelData.live ? " · " + qsTr("the installer is on this disk") : card.modelData.removable ? " · " + qsTr("removable") : "")
                           font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textSecondary }
                }
                Text { anchors.right: parent.right; anchors.rightMargin: 18; anchors.verticalCenter: parent.verticalCenter
                       text: qsTr("%n partitions", "", card.modelData.partitions.length); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textTertiary }
                MouseArea { anchors.fill: parent; enabled: card.usable; onClicked: { app.chosen = card.modelData.path; app.mode = "erase" } }
            }
        }
        // Alone, or next to what is on the disk.
        Column {
            id: modeBox
            visible: app.chosen !== ""
            anchors.bottom: buttons1.top
            anchors.bottomMargin: 12
            width: parent.width
            spacing: 8
            Row {
                spacing: 8
                Repeater {
                    model: [ { id: "erase", label: qsTr("Erase the disk (astraOS alone)") }, { id: "dual", label: qsTr("Install next to another system (dual boot)") } ]
                    delegate: Rectangle {
                        required property var modelData
                        height: 36; width: modeText.implicitWidth + 32; radius: 18
                        color: app.mode === modelData.id ? Theme.accent : Theme.surfaceRaised
                        Text { id: modeText; anchors.centerIn: parent; text: modelData.label; font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize
                               color: app.mode === modelData.id ? Theme.accentText : Theme.text }
                        MouseArea { anchors.fill: parent; onClicked: { app.mode = modelData.id; if (modelData.id === "dual" && app.rootPartition === "") app.rootPartition = app.disk && app.disk.free > 25e9 ? "new" : "" } }
                    }
                }
            }
            Text {
                visible: app.mode === "erase"
                width: parent.width; wrapMode: Text.Wrap
                text: qsTr("astraOS starts by itself, without a menu.")
                font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textSecondary
            }
            Column {
                visible: app.mode === "dual"
                width: parent.width
                spacing: 6
                Text { width: parent.width; wrapMode: Text.Wrap
                       text: qsTr("The other systems stay. The boot menu appears at every start, to choose which one starts. Choose where astraOS goes (it is erased):")
                       font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.textSecondary }
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: (app.disk ? app.disk.partitions.filter(p => !p.esp && p.size > 8e9) : []).concat(app.disk && app.disk.free > 25e9 ? [{ path: "new", name: qsTr("New partition (%1 free)").arg(app.size(app.disk.free)), size: 0 }] : [])
                        delegate: Rectangle {
                            required property var modelData
                            height: 34; width: partText.implicitWidth + 28; radius: 17
                            color: app.rootPartition === modelData.path ? Theme.accent : Theme.surfaceRaised
                            Text { id: partText; anchors.centerIn: parent; text: modelData.path === "new" ? modelData.name : modelData.name + " " + app.size(modelData.size) + (modelData.fstype ? " " + modelData.fstype : "")
                                   font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: app.rootPartition === modelData.path ? Theme.accentText : Theme.text }
                            MouseArea { anchors.fill: parent; onClicked: app.rootPartition = modelData.path }
                        }
                    }
                }
                Row {
                    visible: app.rootPartition === "new"
                    spacing: 10
                    Text { anchors.verticalCenter: parent.verticalCenter; text: qsTr("Size: %1 GB").arg(Math.round(app.newSizeGB)); font.family: Theme.fontFamily; font.pixelSize: Theme.captionSize; color: Theme.text }
                    Slider { width: 240; from: 20; to: Math.max(21, Math.floor((app.disk ? app.disk.free : 0) / 1e9)); value: app.newSizeGB; onMoved: app.newSizeGB = value }
                }
            }
        }
        EmptyState { visible: app.disks.length === 0; anchors.centerIn: parent; iconName: "storage"; title: qsTr("No disk found"); message: qsTr("Connect a disk and press Refresh.") }
        Row {
            id: buttons1
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            spacing: 10
            Button { text: qsTr("Back"); primary: false; onClicked: app.step = 0 }
            Button { text: qsTr("Refresh"); primary: false; onClicked: app.refresh() }
            Button { text: qsTr("Continue"); enabled: app.chosen !== "" && (app.mode === "erase" || app.rootPartition !== ""); onClicked: app.step = 2 }
        }
    }

    // ---- 2: confirm ----
    Column {
        visible: app.step === 2
        anchors.centerIn: parent
        spacing: 16
        width: Math.min(460, parent.width - 64)
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "warning"; size: 48; color: Theme.warning }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
               text: app.mode === "erase" ? qsTr("Erase “%1” and install astraOS?").arg(app.disk ? (app.disk.model || app.disk.name) : "")
                                          : qsTr("Install astraOS next to your other systems?")
               font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.DemiBold; color: Theme.text }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
               text: app.mode === "erase" ? qsTr("Everything on this disk (%1) will be erased and cannot be recovered.").arg(app.disk ? app.size(app.disk.size) : "")
                     : app.rootPartition === "new" ? qsTr("A partition of %1 GB is made in the free space. The other systems are not touched; the boot menu appears at every start.").arg(Math.round(app.newSizeGB))
                     : qsTr("The partition %1 is erased and astraOS goes on it. The other systems are not touched; the boot menu appears at every start.").arg(app.rootPartition)
               font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.textSecondary }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            Button { text: qsTr("Back"); primary: false; onClicked: app.step = 1 }
            Button { text: app.mode === "erase" ? qsTr("Erase and Install") : qsTr("Install"); onClicked: app.start() }
        }
    }

    // ---- 3: installing ----
    Column {
        visible: app.step === 3
        anchors.centerIn: parent
        spacing: 18
        width: Math.min(460, parent.width - 64)
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Installing astraOS"); font.family: Theme.fontFamily
               font.pixelSize: Theme.titleSize; font.weight: Font.DemiBold; color: Theme.text }
        ProgressBar { width: parent.width; value: app.percent }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: app.text; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.textSecondary }
        Text { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Do not turn the computer off."); font.family: Theme.fontFamily
               font.pixelSize: Theme.captionSize; color: Theme.textTertiary }
    }

    // ---- 4: done ----
    Column {
        visible: app.step === 4
        anchors.centerIn: parent
        spacing: 16
        width: Math.min(460, parent.width - 64)
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "check-circle"; size: 56; color: Theme.success }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("astraOS is installed"); font.family: Theme.fontFamily
               font.pixelSize: Theme.titleSize; font.weight: Font.DemiBold; color: Theme.text }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap
               text: qsTr("Remove the installation medium and restart. The first start sets the computer up.")
               font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.textSecondary }
        Button { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Restart"); onClicked: System.power("reboot") }
    }

    // ---- 5: failed ----
    Column {
        visible: app.step === 5
        anchors.centerIn: parent
        spacing: 16
        width: Math.min(460, parent.width - 64)
        Icon { anchors.horizontalCenter: parent.horizontalCenter; name: "warning"; size: 48; color: Theme.danger }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: qsTr("The installation failed"); font.family: Theme.fontFamily
               font.pixelSize: Theme.titleSize; font.weight: Font.DemiBold; color: Theme.text }
        Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.Wrap; text: app.error; font.family: Theme.fontFamily
               font.pixelSize: Theme.bodySize; color: Theme.textSecondary }
        Button { anchors.horizontalCenter: parent.horizontalCenter; text: qsTr("Back"); onClicked: { app.refresh(); app.step = 1 } }
    }
}
