// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtWebEngine
import Astra.Core
import Astra.Controls

// Bring the contacts of a Google account in (read only; nothing is written back to Google).
// Google asks for the account in its own page, shown here; the answer comes back as an access token,
// and the People API lists the contacts. It needs an OAuth client ID of a Web application (Google
// Cloud Console > APIs & Services > Credentials, with the People API on and http://localhost/ as an
// authorised redirect URI), which is pasted once and kept in the settings.
Rectangle {
    id: root
    color: Theme.background

    signal closed()
    signal done(int added, int total)

    readonly property string clientKey: "app.com.astra.contacts.google_client"
    readonly property string clientId: (Settings.values[clientKey] || "").trim()
    property string state: clientId ? "signin" : "setup"      // setup | signin | fetching | error
    property string message: ""
    property int fetched: 0

    readonly property string redirect: "http://localhost/"
    readonly property string authUrl: "https://accounts.google.com/o/oauth2/v2/auth?client_id=" + encodeURIComponent(clientId)
        + "&redirect_uri=" + encodeURIComponent(redirect) + "&response_type=token"
        + "&scope=" + encodeURIComponent("https://www.googleapis.com/auth/contacts.readonly")
        + "&include_granted_scopes=true&prompt=select_account"

    function fail(text) { state = "error"; message = text }

    // The list, a page of up to 1000 at a time.
    function fetchAll(token) {
        state = "fetching"
        fetched = 0
        const all = []
        const page = function(pageToken) {
            const xhr = new XMLHttpRequest()
            const url = "https://people.googleapis.com/v1/people/me/connections?personFields=names,phoneNumbers,emailAddresses,organizations"
                + "&pageSize=1000" + (pageToken ? "&pageToken=" + encodeURIComponent(pageToken) : "")
            xhr.open("GET", url)
            xhr.setRequestHeader("Authorization", "Bearer " + token)
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return
                if (xhr.status !== 200)
                    return root.fail(xhr.status === 403 ? qsTr("Turn on the People API for this client in Google Cloud, then try again.")
                                                         : qsTr("Google did not answer (%1).").arg(xhr.status))
                let r = {}
                try { r = JSON.parse(xhr.responseText) } catch (e) { return root.fail(qsTr("Google's answer could not be read.")) }
                for (const p of (r.connections || [])) {
                    const first = (list, key) => list && list.length ? (list[0][key] || "") : ""
                    const c = { name: first(p.names, "displayName"), phone: first(p.phoneNumbers, "value"),
                                email: first(p.emailAddresses, "value"), company: first(p.organizations, "name") }
                    if (c.name || c.phone)
                        all.push(c)
                }
                root.fetched = all.length
                if (r.nextPageToken)
                    page(r.nextPageToken)
                else
                    Contacts.call("import", { contacts: all }, (added, e) => {
                        if (e)
                            return root.fail(e)
                        root.done(Number(added) || 0, all.length)
                    })
            }
            xhr.send()
        }
        page("")
    }

    // The page's address changes to the redirect once the account has answered.
    function answered(url) {
        const text = url.toString()
        if (text.indexOf(redirect) !== 0)
            return false
        const params = {}
        for (const part of text.substring(text.indexOf("#") + 1).split("&")) {
            const i = part.indexOf("=")
            if (i > 0)
                params[part.substring(0, i)] = decodeURIComponent(part.substring(i + 1))
        }
        if (params.access_token)
            fetchAll(params.access_token)
        else
            fail(params.error === "access_denied" ? qsTr("You did not allow it.") : qsTr("Google did not sign you in."))
        return true
    }

    // ---- top bar ---------------------------------------------------------------------------
    Item {
        id: bar
        width: parent.width
        height: Theme.statusBarHeight + 52
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: Theme.statusBarHeight + 14
            text: qsTr("Google Contacts")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.headlineSize
            font.weight: Font.DemiBold
            color: Theme.text
        }
        Text {
            x: 18
            y: Theme.statusBarHeight + 14
            text: qsTr("Close")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.accent
            MouseArea { anchors.fill: parent; anchors.margins: -12; onClicked: root.closed() }
        }
    }

    // ---- the client ID ------------------------------------------------------------------------
    Column {
        visible: root.state === "setup"
        anchors.top: bar.bottom
        anchors.topMargin: 16
        x: 20
        width: parent.width - 40
        spacing: 14
        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: qsTr("To bring in your Google contacts, astraOS needs a client ID of your own Google Cloud project: create an OAuth client of the type Web application, turn on the People API, add http://localhost/ as an authorised redirect URI and paste the client ID here. It is kept on this phone only.")
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.textSecondary
        }
        TextField { id: idField; width: parent.width; placeholder: qsTr("Client ID"); inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText }
        Button {
            text: qsTr("Continue")
            enabled: idField.text.trim().length > 20
            onClicked: { Settings.setValue(root.clientKey, idField.text.trim()); root.state = "signin" }
        }
    }

    // ---- Google's own page -------------------------------------------------------------------
    Loader {
        id: webLoader
        anchors.top: bar.bottom
        anchors.bottom: parent.bottom
        width: parent.width
        active: root.state === "signin"
        sourceComponent: WebEngineView {
            backgroundColor: "white"
            profile: WebEngineProfile {
                storageName: "googlecontacts"
                offTheRecord: false
                persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
                httpUserAgent: "Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
            }
            url: root.authUrl
            onNavigationRequested: (request) => { if (root.answered(request.url)) request.action = WebEngineNavigationRequest.IgnoreRequest }
        }
    }

    // ---- working / the answer -----------------------------------------------------------------------
    Column {
        visible: root.state === "fetching" || root.state === "error"
        anchors.centerIn: parent
        width: parent.width - 60
        spacing: 16
        Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: root.state === "fetching" ? qsTr("Getting your contacts… %1").arg(root.fetched) : root.message
            font.family: Theme.fontFamily
            font.pixelSize: Theme.bodySize
            color: Theme.text
        }
        Row {
            visible: root.state === "error"
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            Button { text: qsTr("Try Again"); onClicked: root.state = "signin" }
            Button { text: qsTr("Change Client ID"); primary: false; onClicked: { Settings.setValue(root.clientKey, ""); root.state = "setup" } }
        }
    }
}
