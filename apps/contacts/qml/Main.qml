// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Contacts: the address book shared with Phone, Messages and MeetUp.
// Sorted by name with a letter index, favourites, vCard import and sharing.
Rectangle {
    id: app
    color: Theme.background

    property bool granted: false
    readonly property var all: (Contacts.state.contacts || []).slice().sort((a, b) => (a.name || a.phone || "").localeCompare(b.name || b.phone || ""))

    function initials(c) {
        const parts = (c.name || "").trim().split(/\s+/).filter(p => p)
        return parts.length ? (parts[0][0] + (parts.length > 1 ? parts[parts.length - 1][0] : "")).toUpperCase() : "#"
    }
    function letter(c) {
        const l = (c.name || "#").trim().charAt(0).toUpperCase()
        return /[A-Z]/.test(l.normalize("NFD").charAt(0)) ? l.normalize("NFD").charAt(0) : "#"
    }
    function vcard(c) {
        return ["BEGIN:VCARD", "VERSION:3.0", "FN:" + (c.name || ""), c.phone ? "TEL;TYPE=CELL:" + c.phone : "",
                c.email ? "EMAIL:" + c.email : "", c.company ? "ORG:" + c.company : "", c.note ? "NOTE:" + c.note.replace(/\n/g, "\\n") : "",
                "END:VCARD"].filter(l => l).join("\r\n")
    }
    function importVcards(text) {
        let added = 0
        for (const block of text.split(/BEGIN:VCARD/i).slice(1)) {
            const get = (key) => {
                const m = new RegExp("^" + key + "[^:]*:(.*)$", "mi").exec(block)
                return m ? m[1].trim().replace(/\\n/g, "\n") : ""
            }
            const c = { name: get("FN") || get("N").split(";").reverse().join(" ").trim(), phone: get("TEL"), email: get("EMAIL"),
                        company: get("ORG").replace(/;+$/, ""), note: get("NOTE") }
            if (c.name || c.phone) {
                Contacts.call("add", c, null)
                added++
            }
        }
        return added
    }
    function handleArgs(args) {
        if (args && args.files && args.files.length) {
            let n = 0
            for (const f of args.files)
                n += importVcards(Files.readText(f, 4 * 1024 * 1024))
            toast.show(qsTr("%n contacts imported", "", n))
        }
    }

    Component.onCompleted: Permissions.request("astra.permission.CONTACTS", function(ok) {
        app.granted = !!ok
        if (ok)
            app.handleArgs(Application.args)
    })
    Connections {
        target: Application
        function onIntent(args) { if (app.granted) app.handleArgs(args) }
    }

    PageStack {
        id: stack
        anchors.fill: parent
        Component.onCompleted: open(listPage)
    }

    // ---- list -------------------------------------------------------------
    Component {
        id: listPage
        Page {
            id: lp
            title: qsTr("Contacts")
            readonly property var list: app.all.filter(c => !search.text || JSON.stringify(c).toLowerCase().indexOf(search.text.toLowerCase()) >= 0)
            readonly property var letters: {
                const out = []
                for (const c of list) { const l = app.letter(c); if (out.indexOf(l) < 0) out.push(l) }
                return out
            }
            actions: IconButton { iconName: "plus"; size: 38; color: Theme.accent; onClicked: stack.open(editPage, { contact: null }) }

            EmptyState {
                visible: !app.granted
                iconName: "contact"
                title: qsTr("Contacts")
                message: qsTr("Allow Contacts in Settings › Apps › Contacts to see the people you know.")
            }
            TextField { visible: app.granted; id: search; width: parent.width; placeholder: qsTr("Search") }

            Card {
                visible: app.granted && !search.text
                width: parent.width
                pressable: true
                onClicked: Packages.launch("com.astra.settings", { page: "account" })
                Row {
                    spacing: 14
                    Rectangle {
                        width: 56; height: 56; radius: 28
                        gradient: Gradient { GradientStop { position: 0; color: "#FF9A3C" } GradientStop { position: 1; color: "#FF3D00" } }
                        Text { anchors.centerIn: parent; text: (Settings.values["account.name"] || "?").charAt(0).toUpperCase(); font.family: Theme.fontFamily; font.pixelSize: 24; font.weight: Font.Bold; color: "white" }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text { text: Settings.values["account.name"] || qsTr("Your Name"); font.family: Theme.fontFamily; font.pixelSize: Theme.headlineSize; font.weight: Font.DemiBold; color: Theme.text }
                        Text { text: qsTr("My Card"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
                    }
                }
            }

            Repeater {
                model: lp.letters
                delegate: Column {
                    id: section
                    required property string modelData
                    width: parent.width
                    spacing: 6
                    Text { text: section.modelData; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; font.weight: Font.Bold; color: Theme.textSecondary }
                    ListGroup {
                        width: parent.width
                        readonly property var people: lp.list.filter(c => app.letter(c) === section.modelData)
                        Repeater {
                            model: parent.people
                            delegate: ListItem {
                                required property var modelData
                                required property int index
                                text: (modelData.favorite ? "★ " : "") + (modelData.name || modelData.phone)
                                subtitle: modelData.company || ""
                                separator: index < parent.people.length - 1
                                onClicked: stack.open(detailPage, { contactId: modelData.id })
                            }
                        }
                    }
                }
            }
            Text {
                visible: app.granted && lp.list.length > 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: qsTr("%n contacts", "", lp.list.length)
                font.family: Theme.fontFamily
                font.pixelSize: Theme.footnoteSize
                color: Theme.textTertiary
            }
        }
    }

    // ---- detail -----------------------------------------------------------
    Component {
        id: detailPage
        Page {
            id: dp
            property int contactId
            readonly property var c: app.all.find(x => x.id === contactId) || ({})
            title: ""
            actions: Text {
                text: qsTr("Edit")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.accent
                MouseArea { anchors.fill: parent; anchors.margins: -10; onClicked: stack.open(editPage, { contact: dp.c }) }
            }
            Column {
                width: parent.width
                spacing: 10
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 110; height: 110; radius: 55
                    gradient: Gradient { GradientStop { position: 0; color: "#8E8E99" } GradientStop { position: 1; color: "#5A5A66" } }
                    Text { anchors.centerIn: parent; text: app.initials(dp.c); font.family: Theme.fontFamily; font.pixelSize: 42; font.weight: Font.DemiBold; color: "white" }
                }
                Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: dp.c.name || dp.c.phone || ""; font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text; wrapMode: Text.WordWrap }
                Text { visible: !!dp.c.company; width: parent.width; horizontalAlignment: Text.AlignHCenter; text: dp.c.company || ""; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; color: Theme.textSecondary }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                Action { icon: "message"; label: qsTr("message"); active: !!dp.c.phone; onClicked: Packages.launch("com.astra.messages", { number: dp.c.phone }) }
                Action { icon: "phone"; label: qsTr("call"); active: !!dp.c.phone; onClicked: Packages.launch("com.astra.phone", { dial: dp.c.phone }) }
                Action { icon: "video"; label: qsTr("video"); active: !!dp.c.phone; onClicked: Packages.launch("com.astra.meetup", { call: dp.c.phone }) }
                Action { icon: "mail"; label: qsTr("mail"); active: !!dp.c.email; onClicked: Packages.launch("com.astra.email", { to: dp.c.email }) }
            }
            ListGroup {
                ListItem { visible: !!dp.c.phone; text: dp.c.phone || ""; subtitle: qsTr("mobile"); iconName: "phone"; onClicked: Packages.launch("com.astra.phone", { dial: dp.c.phone }) }
                ListItem { visible: !!dp.c.email; text: dp.c.email || ""; subtitle: qsTr("email"); iconName: "mail"; onClicked: Packages.launch("com.astra.email", { to: dp.c.email }) }
                ListItem { visible: !!dp.c.note; text: dp.c.note || ""; subtitle: qsTr("notes"); iconName: "note"; separator: false }
            }
            ListGroup {
                ListItem {
                    text: dp.c.favorite ? qsTr("Remove from Favorites") : qsTr("Add to Favorites")
                    iconName: "star"
                    onClicked: Contacts.call("update", { id: dp.c.id, favorite: !dp.c.favorite }, null)
                }
                ListItem {
                    text: qsTr("Share Contact")
                    iconName: "share"
                    separator: false
                    onClicked: {
                        const path = Files.appData + "/" + (dp.c.name || "contact").replace(/[^\w ]+/g, "") + ".vcf"
                        Files.writeText(path, app.vcard(dp.c))
                        share.open([path], "text/vcard", "share", "")
                    }
                }
            }
        }
    }

    component Action: Rectangle {
        id: action
        property string icon
        property string label
        property bool active: true
        signal clicked()
        width: 74; height: 62
        radius: 14
        color: Theme.surface
        opacity: active ? 1 : 0.4
        Column {
            anchors.centerIn: parent
            spacing: 4
            Icon { anchors.horizontalCenter: parent.horizontalCenter; name: action.icon; size: 22; color: Theme.accent }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: action.label; font.family: Theme.fontFamily; font.pixelSize: 11; color: Theme.accent }
        }
        MouseArea { anchors.fill: parent; enabled: action.active; onClicked: action.clicked() }
    }

    // ---- edit / new ---------------------------------------------------------
    Component {
        id: editPage
        Page {
            id: ed
            property var contact: null
            title: contact ? qsTr("Edit Contact") : qsTr("New Contact")
            actions: Text {
                text: qsTr("Done")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.DemiBold
                color: (name.text + phone.text).trim() ? Theme.accent : Theme.textTertiary
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: {
                        if (!(name.text + phone.text).trim())
                            return
                        const c = { name: name.text, company: company.text, phone: phone.text, email: email.text, note: note.text }
                        if (ed.contact)
                            Contacts.call("update", Object.assign({ id: ed.contact.id }, c), null)
                        else
                            Contacts.call("add", c, null)
                        stack.pop()
                    }
                }
            }
            Column {
                width: parent.width
                spacing: 10
                TextField { id: name; width: parent.width; placeholder: qsTr("Name"); text: ed.contact ? ed.contact.name || "" : "" }
                TextField { id: company; width: parent.width; placeholder: qsTr("Company"); text: ed.contact ? ed.contact.company || "" : "" }
                TextField { id: phone; width: parent.width; placeholder: qsTr("Phone"); inputMethodHints: Qt.ImhDialableCharactersOnly; text: ed.contact ? ed.contact.phone || "" : "" }
                TextField { id: email; width: parent.width; placeholder: qsTr("Email"); inputMethodHints: Qt.ImhEmailCharactersOnly; text: ed.contact ? ed.contact.email || "" : "" }
                TextField { id: note; width: parent.width; placeholder: qsTr("Notes"); text: ed.contact ? ed.contact.note || "" : "" }
            }
            Button {
                visible: ed.contact !== null
                width: parent.width
                text: qsTr("Delete Contact")
                destructive: true
                primary: false
                onClicked: Dialogs.show({ title: qsTr("Delete Contact"), message: qsTr("“%1” is removed from all your apps.").arg(ed.contact.name || ed.contact.phone),
                                          buttons: [{ id: "cancel", label: qsTr("Cancel") }, { id: "delete", label: qsTr("Delete"), style: "destructive" }] },
                                        function(a) {
                                            if (a !== "delete") return
                                            Contacts.call("delete", { id: ed.contact.id }, null)
                                            stack.pop(null)
                                        })
            }
        }
    }

    ShareSheet { id: share }

    Rectangle {
        id: toast
        function show(t) { toastText.text = t; opacity = 1; toastTimer.restart() }
        z: 90
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 160 } }
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height - 120
        width: toastText.implicitWidth + 32; height: 40; radius: 20
        color: "#3A3A42"
        Text { id: toastText; anchors.centerIn: parent; color: "white"; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize }
        Timer { id: toastTimer; interval: 2200; onTriggered: toast.opacity = 0 }
    }
}
