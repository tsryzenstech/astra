// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls

// Settings > NFC: the switch, the last tag held to the phone with everything it
// says, and writing an address or a text to a tag (astrad's nfc service).
Page {
    id: page
    title: qsTr("NFC")

    property var st: ({})
    property bool loaded: false
    property string error: ""
    readonly property var tag: st.tag || ({})
    readonly property var records: tag.records || []
    readonly property var write: st.write || ({})
    readonly property bool hasTag: tag.uid !== undefined || tag.type !== undefined

    function refresh() {
        System.call("nfc.state", {}, function(r, err) {
            page.loaded = true
            if (!err && r)
                page.st = r
        })
    }
    function call(method, params) {
        page.error = ""
        System.call("nfc." + method, params || {}, function(r, err) {
            if (err)
                page.error = err
            else if (r)
                page.st = r
        })
    }
    Timer {
        interval: 800
        repeat: true
        running: page.visible && Qt.application.state === Qt.ApplicationActive
        triggeredOnStart: true
        onTriggered: page.refresh()
    }

    function label(record) {
        if (record.kind === "uri") {
            const v = String(record.value || "")
            return v.startsWith("tel:") ? qsTr("Phone number") : v.startsWith("mailto:") ? qsTr("Email address")
                 : v.startsWith("geo:") ? qsTr("Place") : qsTr("Address")
        }
        if (record.kind === "text") return qsTr("Text")
        if (record.kind === "app") return qsTr("App")
        return record.type || qsTr("Data")
    }
    function shown(record) {
        if (record.value)
            return String(record.value).replace(/^(tel|mailto|sms|smsto):/, "")
        return record.size !== undefined ? qsTr("%1 bytes").arg(record.size) : ""
    }
    function canOpen(record) {
        return record.kind === "uri" && /^(https?|tel|mailto|sms|smsto|geo):/i.test(String(record.value || ""))
    }
    function open(record) {
        const v = String(record.value || "")
        const rest = v.replace(/^[a-z]+:/i, "")
        if (/^https?:/i.test(v)) Packages.launch("com.astra.planet", { url: v })
        else if (/^tel:/i.test(v)) Packages.launch("com.astra.phone", { dial: rest })
        else if (/^mailto:/i.test(v)) Packages.launch("com.astra.email", { to: rest })
        else if (/^sms(to)?:/i.test(v)) Packages.launch("com.astra.messages", { number: rest })
        else if (/^geo:/i.test(v)) Packages.launch("com.astra.maps", { query: rest.split(";")[0] })
    }

    EmptyState {
        visible: page.loaded && page.st.available === false
        iconName: "nfc"
        title: qsTr("NFC is not available")
        message: qsTr("This phone's NFC controller did not answer.")
    }

    ListGroup {
        visible: page.st.available === true
        footer: qsTr("Hold a tag or a card to the back of the phone, near the cameras. What it says arrives as a notification: an address opens in Planet, a number in Phone.")
        SwitchRow {
            text: qsTr("NFC")
            iconName: "nfc"
            iconTile: 30
            tileColor: Theme.accent
            key: "controls.nfc"
            busy: Settings.values["controls.nfc"] === true && page.st.on === false
            separator: false
        }
    }

    // ---- writing -------------------------------------------------------------------
    Card {
        visible: page.write.waiting === true
        accented: true
        Column {
            width: parent.width
            spacing: 10
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: qsTr("Hold the tag to the back of the phone")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.titleSize
                font.weight: Font.Bold
                color: Theme.accentText
            }
            Text {
                width: parent.width
                wrapMode: Text.Wrap
                text: qsTr("Keep it still until this card goes away. What the tag held before is replaced.")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.accentText
            }
            ProgressBar { width: parent.width; height: 6; indeterminate: true; color: Theme.accentText; trackColor: Theme.glass }
        }
    }
    Button {
        visible: page.write.waiting === true
        width: parent.width
        text: qsTr("Cancel")
        primary: false
        onClicked: page.call("cancelWrite")
    }
    Text {
        visible: page.write.waiting === false || page.error !== ""
        width: parent.width
        wrapMode: Text.Wrap
        text: page.error !== "" ? page.error : page.write.ok ? qsTr("The tag was written.") : (page.write.error || "")
        color: page.error !== "" || !page.write.ok ? Theme.danger : Theme.success
        font.family: Theme.fontFamily
        font.pixelSize: Theme.footnoteSize
    }

    ListGroup {
        visible: page.st.on === true && page.write.waiting !== true
        title: qsTr("Write a tag")
        footer: qsTr("For NTAG and MIFARE Ultralight tags, which most stickers and key fobs are.")
        ListItem {
            text: qsTr("An address")
            subtitle: qsTr("A web page, a phone number (tel:), an email (mailto:)")
            iconName: "link"
            chevron: true
            onClicked: page.stack.open(Qt.resolvedUrl("TextEditPage.qml"), {
                title: qsTr("Address"), text: "https://", placeholder: "https://", maximumLength: 480,
                onSave: (t) => page.call("write", { uri: t }) })
        }
        ListItem {
            text: qsTr("A text")
            iconName: "note"
            chevron: true
            separator: false
            onClicked: page.stack.open(Qt.resolvedUrl("TextEditPage.qml"), {
                title: qsTr("Text"), text: "", placeholder: qsTr("What the tag says"), maximumLength: 480,
                onSave: (t) => page.call("write", { text: t }) })
        }
    }

    // ---- the last tag ---------------------------------------------------------------
    ListGroup {
        visible: page.hasTag
        title: qsTr("Last tag")
        ListItem {
            text: qsTr("Kind")
            value: page.tag.type || ""
        }
        ListItem {
            visible: (page.tag.uid || "") !== ""
            height: visible ? implicitHeight : 0
            text: qsTr("Identifier")
            value: page.tag.uid || ""
        }
        ListItem {
            visible: page.tag.capacity > 0
            height: visible ? implicitHeight : 0
            text: qsTr("Size")
            value: qsTr("%1 bytes").arg(page.tag.capacity || 0) + (page.tag.writable === false ? " · " + qsTr("read-only") : "")
        }
        Repeater {
            model: page.records
            delegate: ListItem {
                required property var modelData
                text: page.label(modelData)
                subtitle: page.shown(modelData)
                chevron: page.canOpen(modelData)
                onClicked: if (page.canOpen(modelData)) page.open(modelData)
            }
        }
        ListItem {
            visible: page.records.length === 0
            height: visible ? implicitHeight : 0
            text: page.tag.error || qsTr("This tag is empty")
            textColor: Theme.textSecondary
        }
        ListItem {
            text: qsTr("Forget this tag")
            destructive: true
            separator: false
            onClicked: page.call("forget")
        }
    }
}
