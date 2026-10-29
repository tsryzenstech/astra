// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtWebEngine
import Astra.Core

// The call itself: a Jitsi Meet room in a web view with Jitsi's own toolbar
// hidden. MeetUp draws its controls on top and drives the room with Jitsi's
// page API (APP.conference).
WebEngineView {
    id: view

    property bool micOn: true
    property bool camOn: true
    property string displayName
    property string room
    property string server: "https://meet.jit.si"
    property bool joined: false
    signal joinedNow()

    backgroundColor: "black"
    settings.playbackRequiresUserGesture: false
    settings.showScrollBars: false

    function hashConfig() {
        const options = {
            "config.prejoinConfig.enabled": false,
            "config.prejoinPageEnabled": false,
            "config.disableDeepLinking": true,
            "config.toolbarButtons": [],
            "config.startWithAudioMuted": !micOn,
            "config.startWithVideoMuted": !camOn,
            "config.disableInviteFunctions": true,
            "config.hideConferenceSubject": true,
            "config.notifications": [],
            "interfaceConfig.SHOW_JITSI_WATERMARK": false,
            "interfaceConfig.SHOW_BRAND_WATERMARK": false,
            "interfaceConfig.MOBILE_APP_PROMO": false,
            "userInfo.displayName": displayName
        }
        return Object.keys(options).map(k => k + "=" + encodeURIComponent(JSON.stringify(options[k]))).join("&")
    }
    url: server.replace(/\/+$/, "") + "/" + encodeURIComponent(room) + "#" + hashConfig()

    function setMic(on) {
        micOn = on
        runJavaScript("window.APP && APP.conference && APP.conference.isLocalAudioMuted() !== " + !on + " && APP.conference.toggleAudioMuted(false)")
    }
    function setCam(on) {
        camOn = on
        runJavaScript("window.APP && APP.conference && APP.conference.isLocalVideoMuted() !== " + !on + " && APP.conference.toggleVideoMuted(false)")
    }
    // Jitsi starts muted when its join screen is skipped: once in the room,
    // the microphone and camera follow MeetUp's switches.
    Timer {
        interval: 1000
        repeat: true
        running: !view.loading
        onTriggered: view.runJavaScript("(function() {"
            + "var w = document.querySelector('.watermark'); if (w) w.style.display = 'none';"
            + "return !!(window.APP && APP.conference && APP.conference.isJoined()); })()", (inRoom) => {
            if (inRoom && !view.joined) {
                view.joined = true
                view.setMic(view.micOn)
                view.setCam(view.camOn)
                view.joinedNow()
            } else if (!inRoom) {
                view.joined = false
            }
        })
    }
    function leave() {
        runJavaScript("window.APP && APP.conference && APP.conference.hangup(false)")
    }

    onPermissionRequested: (permission) => {
        const t = permission.permissionType
        if (t === WebEnginePermission.PermissionType.MediaAudioCapture) {
            Permissions.request("astra.permission.MICROPHONE", (ok) => ok ? permission.grant() : permission.deny())
        } else if (t === WebEnginePermission.PermissionType.MediaVideoCapture
                   || t === WebEnginePermission.PermissionType.MediaAudioVideoCapture) {
            Permissions.request("astra.permission.CAMERA", (ok) => {
                if (!ok) return permission.deny()
                if (t === WebEnginePermission.PermissionType.MediaAudioVideoCapture)
                    Permissions.request("astra.permission.MICROPHONE", () => permission.grant())
                else
                    permission.grant()
            })
        } else {
            permission.deny()
        }
    }
    // Sign-in pages of the meeting server (some servers want the host to
    // sign in) open in the same view; anything else opens in Planet.
    onNewWindowRequested: (request) => {
        const target = request.requestedUrl.toString()
        if (target.startsWith(server))
            view.url = request.requestedUrl
        else
            Packages.launch("com.astra.planet", { url: target })
    }
}
