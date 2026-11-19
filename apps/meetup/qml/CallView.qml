// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtWebEngine
import Astra.Core

// The call itself: Google Meet in a web view. Meet draws its own screens (the camera preview, the
// controls, the grid); MeetUp adds a bar above it to leave and to invite. The view signs in to
// Google like any browser (the cookies are kept between calls), and answers as Chrome does, which
// Google wants before it lets an account sign in.
WebEngineView {
    id: view

    // What to open: "new" for a new meeting, or the code of one (abc-defg-hij).
    property string room: "new"
    // The code of the meeting once Google has made it (a new one only has it after the redirect).
    property string code: ""
    signal codeKnown(string code)

    backgroundColor: "black"
    settings.playbackRequiresUserGesture: false
    settings.showScrollBars: false
    settings.javascriptCanOpenWindows: true

    profile: WebEngineProfile {
        storageName: "meetup"
        offTheRecord: false
        persistentCookiesPolicy: WebEngineProfile.ForcePersistentCookies
        httpUserAgent: "Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
    }

    url: "https://meet.google.com/" + (room === "new" ? "new" : encodeURIComponent(room))

    function leave() { url = "about:blank" }

    // The meeting's code, from the address it ends up at.
    onUrlChanged: {
        const m = url.toString().match(/^https:\/\/meet\.google\.com\/([a-z]{3}-[a-z]{4}-[a-z]{3})/)
        if (m && m[1] !== code) {
            code = m[1]
            codeKnown(code)
        }
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
    // Google's own pages (sign-in, the account) stay in this view; anything else is a link for Planet.
    onNewWindowRequested: (request) => {
        const target = request.requestedUrl.toString()
        if (/^https:\/\/([a-z0-9-]+\.)?(google|gstatic|youtube)\.com\//.test(target))
            view.url = request.requestedUrl
        else
            Packages.launch("com.astra.planet", { url: target })
    }
}
