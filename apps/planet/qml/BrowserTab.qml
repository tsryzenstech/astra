// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtWebEngine
import Astra.Core
import Astra.Controls

// One tab: a web view, or the start page while it has no address.
Item {
    id: tab

    required property var browser          // Main
    property bool isPrivate: false
    property string initialUrl: ""
    property bool desktop: false             // Request Desktop Website
    property real textZoom: 1.0
    property url thumbnail
    property bool started: initialUrl !== ""

    readonly property alias view: web
    // Restored tabs load the first time they are shown.
    readonly property string url: started ? (web.url.toString() || initialUrl) : ""
    readonly property string title: !started ? qsTr("Start Page") : (web.title || host(url))
    readonly property url icon: web.icon
    readonly property bool loading: started && web.loading
    readonly property real progress: web.loadProgress / 100
    readonly property bool secure: url.startsWith("https://")
    readonly property real scrollY: web.scrollPosition.y
    signal contextMenu(var request)

    function host(u) {
        const m = /^[a-z]+:\/\/([^\/?#]+)/i.exec(u || "")
        return m ? m[1].replace(/^www\./, "") : u
    }
    onVisibleChanged: if (visible && initialUrl && web.url.toString() === "") web.url = initialUrl
    Component.onCompleted: if (visible && initialUrl) web.url = initialUrl

    function load(u) {
        started = true
        web.url = u
    }
    function snapshot(done) {
        const target = started ? web : start
        target.grabToImage(function(r) { tab.thumbnail = r.url; if (done) done() }, Qt.size(target.width / 2, target.height / 2))
    }

    WebEngineView {
        id: web
        anchors.fill: parent
        // True while the page has an editable field in focus: only then is there a keyboard
        // (the runtime's WebInputFilter answers "no input method" for a view without it).
        property bool astraEditable: false
        onJavaScriptConsoleMessage: (level, message, line, source) => {
            if (message.indexOf("astra:editable:") !== 0)
                return
            const on = message === "astra:editable:1"
            if (on !== astraEditable) {
                astraEditable = on
                Qt.inputMethod.update(Qt.ImEnabled)
                if (!on)
                    Qt.inputMethod.hide()
            }
        }
        // (In Qt 6 userScripts is a collection that is filled through its `collection`, not a list
        // to assign: assigning one is an error that stopped Planet from loading.)
        userScripts.collection: [
            WebEngineScript {
                name: "astra-editable"
                injectionPoint: WebEngineScript.DocumentCreation
                worldId: WebEngineScript.MainWorld
                runsOnSubFrames: true
                sourceCode: "(function(){var last=null;function ed(e){while(e&&e.shadowRoot&&e.shadowRoot.activeElement)e=e.shadowRoot.activeElement;if(!e)return false;if(e.isContentEditable)return true;var t=e.tagName;if(t==='TEXTAREA')return !e.readOnly;if(t==='INPUT'){var k=(e.type||'text').toLowerCase();return ['button','submit','reset','checkbox','radio','file','image','color','range'].indexOf(k)<0&&!e.readOnly;}return false;}function report(){var v=ed(document.activeElement);if(v!==last){last=v;console.log('astra:editable:'+(v?1:0));}}document.addEventListener('focusin',report,true);document.addEventListener('focusout',function(){setTimeout(report,0);},true);window.addEventListener('pageshow',report);})();"
            }
        ]
        visible: tab.started
        profile: tab.isPrivate ? tab.browser.privateProfile : tab.browser.profile
        zoomFactor: tab.textZoom
        settings.javascriptEnabled: tab.browser.javascript
        settings.javascriptCanOpenWindows: !tab.browser.blockPopups
        settings.fullScreenSupportEnabled: true
        settings.pluginsEnabled: false
        settings.focusOnNavigationEnabled: false
        settings.playbackRequiresUserGesture: true
        backgroundColor: Theme.background

        onLoadingChanged: (info) => {
            if (info.status === WebEngineView.LoadSucceededStatus && !tab.isPrivate)
                tab.browser.addHistory(url.toString(), title)
        }
        onTitleChanged: if (!loading && !tab.isPrivate) tab.browser.addHistory(url.toString(), title)
        onNewWindowRequested: (request) => {
            const t = tab.browser.newTab("", tab.isPrivate, true)
            t.started = true
            request.openIn(t.view)
        }
        onFullScreenRequested: (request) => {
            tab.browser.fullScreen = request.toggleOn
            request.accept()
        }
        onContextMenuRequested: (request) => {
            request.accepted = true
            tab.contextMenu(request)
        }
        onPermissionRequested: (permission) => tab.browser.askPermission(permission)
        onFindTextFinished: (result) => tab.browser.findResult(result.numberOfMatches, result.activeMatch)
        onRenderProcessTerminated: (status, code) => {
            if (status !== WebEngineView.NormalTerminationStatus)
                reloadTimer.start()
        }
        Timer { id: reloadTimer; interval: 800; onTriggered: web.reload() }
    }

    // Left edge swipe: back.
    MouseArea {
        anchors.left: parent.left
        width: 18
        height: parent.height
        visible: tab.started && web.canGoBack
        property real startX
        onPressed: (m) => startX = m.x
        onReleased: (m) => { if (m.x - startX > 60) web.goBack() }
    }

    StartPage {
        id: start
        anchors.fill: parent
        visible: !tab.started
        browser: tab.browser
        isPrivate: tab.isPrivate
    }
}
