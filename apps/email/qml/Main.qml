// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Email: an IMAP / SMTP mail client. Mailboxes, the message list (swipe
// right: read / unread, swipe left: delete), reading, compose, reply and
// forward. The account (with its password) stays in the app's private data.
Rectangle {
    id: app
    color: Theme.background

    readonly property string configPath: Files.appData + "/mail.json"
    property var account: ({})
    readonly property bool configured: !!account.imapHost
    property var folders: []
    property string trash: ""
    property string archive: ""

    readonly property var presets: [
        { id: "gmail", name: "Gmail", imapHost: "imap.gmail.com", imapPort: 993, smtpHost: "smtp.gmail.com", smtpPort: 465,
          note: qsTr("Use an app password: Google Account › Security › 2-Step Verification › App passwords.") },
        { id: "icloud", name: "iCloud Mail", imapHost: "imap.mail.me.com", imapPort: 993, smtpHost: "smtp.mail.me.com", smtpPort: 587,
          note: qsTr("Use an app-specific password from account.apple.com.") },
        { id: "yahoo", name: "Yahoo Mail", imapHost: "imap.mail.yahoo.com", imapPort: 993, smtpHost: "smtp.mail.yahoo.com", smtpPort: 465,
          note: qsTr("Use an app password from Yahoo Account Security.") },
        { id: "outlook", name: "Outlook.com", imapHost: "outlook.office365.com", imapPort: 993, smtpHost: "smtp-mail.outlook.com", smtpPort: 587,
          note: qsTr("Your Microsoft account must allow IMAP with a password (app password).") },
        { id: "other", name: qsTr("Other"), imapHost: "", imapPort: 993, smtpHost: "", smtpPort: 465, note: "" }
    ]

    MailClient { id: mail }

    function loadAccount() {
        try { account = JSON.parse(Files.readText(configPath) || "{}") } catch (e) { account = {} }
        if (configured) {
            mail.configure(account)
            refreshFolders()
        }
    }
    function saveAccount(a) {
        account = a
        Files.writeText(configPath, JSON.stringify(a))
        mail.configure(a)
        refreshFolders()
    }
    function refreshFolders() {
        mail.folders(function(list, error) {
            if (!list) return
            const order = ["inbox", "drafts", "sent", "junk", "trash", "archive"]
            app.folders = list.sort((a, b) => {
                const ia = order.indexOf(a.special), ib = order.indexOf(b.special)
                return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib) || a.path.localeCompare(b.path)
            })
            const t = list.find(f => f.special === "trash"), ar = list.find(f => f.special === "archive" || f.special === "all")
            app.trash = t ? t.path : ""
            app.archive = ar ? ar.path : ""
        })
    }
    function folderTitle(f) {
        return ({ inbox: qsTr("Inbox"), sent: qsTr("Sent"), drafts: qsTr("Drafts"), trash: qsTr("Trash"), junk: qsTr("Junk"), archive: qsTr("Archive"), all: qsTr("All Mail"), flagged: qsTr("Flagged") })[f.special] || f.name
    }
    function folderIcon(f) {
        return ({ inbox: "inbox", sent: "send", drafts: "file", trash: "trash", junk: "warning", archive: "archive", all: "archive", flagged: "flag" })[f.special] || "folder"
    }
    function when(t) {
        if (!t) return ""
        const d = new Date(t), now = new Date()
        if (d.toDateString() === now.toDateString()) return Qt.locale().toString(d, Qt.locale().timeFormat(Locale.ShortFormat))
        if (now - d < 6 * 86400000) return Qt.locale().toString(d, "ddd")
        return Qt.locale().toString(d, Qt.locale().dateFormat(Locale.ShortFormat))
    }

    Component.onCompleted: {
        loadAccount()
        if (Application.args.to)
            stack.open(composePage, { to: Application.args.to })
    }
    Connections {
        target: Application
        function onIntent(args) { if (args.to) stack.open(composePage, { to: args.to }) }
    }

    PageStack {
        id: stack
        anchors.fill: parent
        Component.onCompleted: open(app.configured ? mailboxesPage : setupPage)
    }

    // ---- mailboxes ---------------------------------------------------------------
    Component {
        id: mailboxesPage
        Page {
            title: qsTr("Mailboxes")
            actions: Row {
                spacing: 8
                IconButton { iconName: "settings"; size: 38; onClicked: stack.open(setupPage) }
                IconButton { iconName: "edit"; size: 38; color: Theme.accent; onClicked: stack.open(composePage, {}) }
            }
            Text { text: app.account.address || ""; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
            Spinner { visible: app.folders.length === 0 && mail.busy; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                visible: app.folders.length === 0 && !mail.busy && mail.lastError !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: mail.lastError
                color: Theme.danger
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
            }
            ListGroup {
                visible: app.folders.length > 0
                Repeater {
                    model: app.folders
                    delegate: ListItem {
                        required property var modelData
                        required property int index
                        text: app.folderTitle(modelData)
                        iconName: app.folderIcon(modelData)
                        iconColor: Theme.accent
                        chevron: true
                        separator: index < app.folders.length - 1
                        onClicked: stack.open(listPage, { folder: modelData })
                    }
                }
            }
        }
    }

    // ---- message list -----------------------------------------------------------------
    Component {
        id: listPage
        Page {
            id: lp
            property var folder
            property var items: []
            property int count: 40
            property bool loading: false
            title: app.folderTitle(folder)
            function reload() {
                loading = true
                mail.messages(folder.path, count, function(list, error) {
                    lp.loading = false
                    if (list) lp.items = list
                    else errorText.text = error || ""
                })
            }
            Component.onCompleted: reload()
            actions: Row {
                spacing: 8
                Spinner { visible: lp.loading; anchors.verticalCenter: parent.verticalCenter }
                IconButton { iconName: "refresh"; size: 38; onClicked: lp.reload() }
                IconButton { iconName: "edit"; size: 38; color: Theme.accent; onClicked: stack.open(composePage, {}) }
            }
            TextField { id: search; width: parent.width; placeholder: qsTr("Search") }
            Text { id: errorText; visible: text !== ""; width: parent.width; wrapMode: Text.WordWrap; color: Theme.danger; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize }
            EmptyState { visible: !lp.loading && lp.items.length === 0; iconName: "inbox"; title: qsTr("No Mail") }
            Column {
                width: parent.width
                Repeater {
                    model: lp.items.filter(m => !search.text || (m.from + " " + m.subject).toLowerCase().indexOf(search.text.toLowerCase()) >= 0)
                    delegate: Item {
                        id: row
                        required property var modelData
                        width: parent.width
                        height: 86
                        clip: true
                        property real swipe: 0
                        Rectangle {
                            anchors.fill: parent
                            color: row.swipe > 0 ? "#0A84FF" : Theme.danger
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                x: row.swipe > 0 ? 24 : parent.width - 48
                                name: row.swipe > 0 ? "message" : "trash"
                                size: 24
                            }
                        }
                        Rectangle {
                            width: parent.width
                            height: parent.height
                            x: row.swipe
                            color: Theme.background
                            Rectangle { visible: !row.modelData.seen; x: 2; y: 14; width: 10; height: 10; radius: 5; color: "#0A84FF" }
                            Column {
                                x: 18
                                y: 10
                                width: parent.width - 30
                                spacing: 2
                                Item {
                                    width: parent.width
                                    height: fromText.height
                                    Text { id: fromText; width: parent.width - 90; elide: Text.ElideRight; text: row.modelData.from; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
                                    Text { anchors.right: parent.right; text: (row.modelData.flagged ? "⚑ " : "") + app.when(row.modelData.date); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
                                }
                                Text { width: parent.width; elide: Text.ElideRight; text: (row.modelData.attachments ? "📎 " : "") + (row.modelData.subject || qsTr("(No Subject)")); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize + 1; color: Theme.text }
                            }
                            Rectangle { anchors.bottom: parent.bottom; x: 18; width: parent.width - 18; height: 1; color: Theme.separator }
                        }
                        MouseArea {
                            anchors.fill: parent
                            property real startX
                            property bool dragging: false
                            onPressed: (m) => { startX = m.x; dragging = false }
                            onPositionChanged: (m) => {
                                if (!dragging && Math.abs(m.x - startX) > 14) { dragging = true; preventStealing = true }
                                if (dragging) row.swipe = m.x - startX
                            }
                            onReleased: {
                                preventStealing = false
                                const s = row.swipe
                                row.swipe = 0
                                if (!dragging) {
                                    stack.open(readPage, { folder: lp.folder.path, header: row.modelData })
                                    lp.items = lp.items.map(x => x.uid === row.modelData.uid ? Object.assign({}, x, { seen: true }) : x)
                                } else if (s > row.width * 0.3) {
                                    mail.setFlag(lp.folder.path, row.modelData.uid, "\\Seen", !row.modelData.seen, null)
                                    lp.items = lp.items.map(x => x.uid === row.modelData.uid ? Object.assign({}, x, { seen: !x.seen }) : x)
                                } else if (s < -row.width * 0.3) {
                                    const uid = row.modelData.uid
                                    lp.items = lp.items.filter(x => x.uid !== uid)
                                    if (app.trash && app.trash !== lp.folder.path) mail.move(lp.folder.path, uid, app.trash, null)
                                    else mail.remove(lp.folder.path, uid, null)
                                }
                            }
                        }
                    }
                }
            }
            Button {
                visible: lp.items.length >= lp.count
                width: parent.width
                primary: false
                text: qsTr("Load More")
                onClicked: { lp.count += 40; lp.reload() }
            }
        }
    }

    // ---- reading -------------------------------------------------------------------------
    Component {
        id: readPage
        Page {
            id: rp
            property string folder
            property var header
            property var msg: null
            property bool flagged: header ? header.flagged : false
            title: ""
            Component.onCompleted: mail.message(folder, header.uid, function(m, error) { rp.msg = m; if (!m) body.text = error })
            actions: Row {
                spacing: 6
                IconButton { iconName: "flag"; size: 38; iconColor: rp.flagged ? "#FF9F0A" : Theme.text; onClicked: { rp.flagged = !rp.flagged; mail.setFlag(rp.folder, rp.header.uid, "\\Flagged", rp.flagged, null) } }
                IconButton { visible: app.archive !== "" && app.archive !== rp.folder; iconName: "archive"; size: 38; onClicked: { mail.move(rp.folder, rp.header.uid, app.archive, null); stack.pop() } }
                IconButton {
                    iconName: "trash"
                    size: 38
                    onClicked: {
                        if (app.trash && app.trash !== rp.folder) mail.move(rp.folder, rp.header.uid, app.trash, null)
                        else mail.remove(rp.folder, rp.header.uid, null)
                        stack.pop()
                    }
                }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; text: rp.header.subject || qsTr("(No Subject)"); font.family: Theme.fontFamily; font.pixelSize: Theme.titleSize; font.weight: Font.Bold; color: Theme.text }
            Column {
                width: parent.width
                Text { width: parent.width; elide: Text.ElideRight; text: rp.msg ? rp.msg.from : rp.header.from; font.family: Theme.fontFamily; font.pixelSize: Theme.bodySize; font.weight: Font.DemiBold; color: Theme.text }
                Text { width: parent.width; elide: Text.ElideRight; text: rp.msg ? qsTr("To: %1").arg(rp.msg.to) : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
                Text { text: rp.header.date ? Qt.locale().toString(new Date(rp.header.date), Locale.LongFormat) : ""; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
            }
            Rectangle { width: parent.width; height: 1; color: Theme.separator }
            Spinner { visible: rp.msg === null && body.text === ""; anchors.horizontalCenter: parent.horizontalCenter }
            Text {
                id: body
                width: parent.width
                wrapMode: Text.WordWrap
                textFormat: rp.msg && !rp.msg.text && rp.msg.html ? Text.RichText : Text.PlainText
                text: rp.msg ? (rp.msg.text || rp.msg.html.replace(/<(script|style)[\s\S]*?<\/\1>/gi, "")) : ""
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.text
                linkColor: Theme.accent
                onLinkActivated: (l) => Packages.launch("com.astra.planet", { url: l })
            }
            Repeater {
                model: rp.msg ? rp.msg.attachments : []
                delegate: Card { required property string modelData; width: parent.width; padding: 12; Text { text: "📎 " + modelData; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.text } }
            }
            Row {
                spacing: 10
                Button { text: qsTr("Reply"); iconName: "reply"; enabled: rp.msg !== null; onClicked: stack.open(composePage, { replyTo: rp.msg }) }
                Button { text: qsTr("Forward"); iconName: "forward"; primary: false; enabled: rp.msg !== null; onClicked: stack.open(composePage, { forward: rp.msg }) }
            }
        }
    }

    // ---- compose ---------------------------------------------------------------------------
    Component {
        id: composePage
        Page {
            id: cp
            property string to: ""
            property var replyTo: null
            property var forward: null
            property bool sending: false
            title: replyTo ? qsTr("Reply") : forward ? qsTr("Forward") : qsTr("New Message")
            function quoteOf(m) {
                return "\n\n" + qsTr("On %1, %2 wrote:").arg(Qt.locale().toString(new Date(m.date), Locale.ShortFormat)).arg(m.from) + "\n"
                     + (m.text || m.html.replace(/<[^>]+>/g, "")).split("\n").map(l => "> " + l).join("\n")
            }
            actions: Text {
                text: cp.sending ? qsTr("Sending…") : qsTr("Send")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                font.weight: Font.DemiBold
                color: toField.text.trim() && !cp.sending ? Theme.accent : Theme.textTertiary
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    onClicked: {
                        if (!toField.text.trim() || cp.sending) return
                        cp.sending = true
                        mail.send({ to: toField.text, cc: ccField.text, subject: subjectField.text, text: bodyField.text,
                                    inReplyTo: cp.replyTo ? cp.replyTo.messageId : "" }, function(ok, error) {
                            cp.sending = false
                            if (ok) stack.pop()
                            else sendError.text = error || qsTr("The message could not be sent.")
                        })
                    }
                }
            }
            Component.onCompleted: {
                if (replyTo) {
                    toField.text = replyTo.from
                    subjectField.text = /^re:/i.test(replyTo.subject) ? replyTo.subject : "Re: " + replyTo.subject
                    bodyField.text = quoteOf(replyTo)
                } else if (forward) {
                    subjectField.text = "Fwd: " + forward.subject
                    bodyField.text = quoteOf(forward)
                } else {
                    toField.text = to
                }
            }
            Text { id: sendError; visible: text !== ""; width: parent.width; wrapMode: Text.WordWrap; color: Theme.danger; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize }
            TextField { id: toField; width: parent.width; placeholder: qsTr("To"); inputMethodHints: Qt.ImhEmailCharactersOnly }
            TextField { id: ccField; width: parent.width; placeholder: qsTr("Cc"); inputMethodHints: Qt.ImhEmailCharactersOnly }
            TextField { id: subjectField; width: parent.width; placeholder: qsTr("Subject") }
            Text { text: qsTr("From: %1").arg(app.account.address || ""); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
            TextEdit {
                id: bodyField
                width: parent.width
                height: Math.max(300, implicitHeight)
                wrapMode: TextEdit.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.bodySize
                color: Theme.text
                selectByMouse: true
                selectionColor: Theme.accent
                Component.onCompleted: cursorPosition = 0
            }
        }
    }

    // ---- account setup ---------------------------------------------------------------------
    Component {
        id: setupPage
        Page {
            id: sp
            property var preset: app.presets.find(p => p.id === (app.account.preset || "gmail")) || app.presets[0]
            title: qsTr("Mail Account")
            SegmentedControl {
                width: parent.width
                model: app.presets.map(p => p.name.split(" ")[0])
                currentIndex: app.presets.indexOf(sp.preset)
                onActivated: (i) => {
                    sp.preset = app.presets[i]
                    imapHost.text = sp.preset.imapHost; imapPort.text = sp.preset.imapPort
                    smtpHost.text = sp.preset.smtpHost; smtpPort.text = sp.preset.smtpPort
                }
            }
            Text { visible: sp.preset.note !== ""; width: parent.width; wrapMode: Text.WordWrap; text: sp.preset.note; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textSecondary }
            TextField { id: nameField; width: parent.width; placeholder: qsTr("Your name"); text: app.account.name || Settings.values["account.name"] || "" }
            TextField { id: address; width: parent.width; placeholder: qsTr("Email address"); text: app.account.address || ""; inputMethodHints: Qt.ImhEmailCharactersOnly }
            TextField { id: password; width: parent.width; placeholder: qsTr("Password"); text: app.account.password || ""; echoMode: TextInput.Password }
            Text { text: qsTr("Servers"); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; font.weight: Font.Bold; color: Theme.textSecondary }
            Row {
                width: parent.width
                spacing: 8
                TextField { id: imapHost; width: parent.width - 98; placeholder: qsTr("IMAP server"); text: app.account.imapHost || sp.preset.imapHost; inputMethodHints: Qt.ImhUrlCharactersOnly }
                TextField { id: imapPort; width: 90; text: app.account.imapPort || sp.preset.imapPort; inputMethodHints: Qt.ImhDigitsOnly }
            }
            Row {
                width: parent.width
                spacing: 8
                TextField { id: smtpHost; width: parent.width - 98; placeholder: qsTr("SMTP server"); text: app.account.smtpHost || sp.preset.smtpHost; inputMethodHints: Qt.ImhUrlCharactersOnly }
                TextField { id: smtpPort; width: 90; text: app.account.smtpPort || sp.preset.smtpPort; inputMethodHints: Qt.ImhDigitsOnly }
            }
            Text { width: parent.width; wrapMode: Text.WordWrap; text: qsTr("IMAP uses TLS on port 993. SMTP uses TLS on 465 or STARTTLS on 587."); font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Theme.textTertiary }
            Button {
                width: parent.width
                text: qsTr("Save")
                enabled: address.text.indexOf("@") > 0 && password.text !== "" && imapHost.text !== "" && smtpHost.text !== ""
                onClicked: {
                    app.saveAccount({ preset: sp.preset.id, name: nameField.text.trim(), address: address.text.trim(), user: address.text.trim(),
                                      password: password.text, imapHost: imapHost.text.trim(), imapPort: Number(imapPort.text) || 993,
                                      smtpHost: smtpHost.text.trim(), smtpPort: Number(smtpPort.text) || 465 })
                    stack.clear()
                    stack.open(mailboxesPage)
                }
            }
            Button {
                visible: app.configured
                width: parent.width
                primary: false
                destructive: true
                text: qsTr("Remove Account")
                onClicked: {
                    app.saveAccount({})
                    app.folders = []
                    mail.disconnectFromServer()
                }
            }
        }
    }
}
