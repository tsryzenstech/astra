// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtWebEngine
import Astra.Core

// YouTube's own embedded player (the IFrame Player API): the way YouTube
// lets other apps play its videos. Tune loads this file with a Loader, so
// Tune keeps working (local music, radio) on a build without Qt WebEngine.
//
// The player is a web page made here; YouTube's script runs inside it and
// reports back through console messages ("tune:{...}"). YouTube's terms
// want the player visible while it plays: Now Playing shows it in place of
// the cover.
Item {
    id: root

    property string videoId: ""
    property real volume: 0.8
    readonly property bool pageReady: d.pageReady
    property bool playing: false
    property bool buffering: false
    property real duration: 0       // ms
    property real position: 0       // ms
    property real positionTime: 0   // Date.now() of the last position
    signal ended()
    signal failed(int code)         // YouTube's code: 101/150 = not playable outside YouTube

    function load(id) {
        videoId = id
        playing = false
        buffering = true
        position = 0
        duration = 0
        positionTime = Date.now()
        d.call("load(" + JSON.stringify(id) + "," + Math.round(volume * 100) + ")")
    }
    function play() { d.call("player && player.playVideo()") }
    function pause() { d.call("player && player.pauseVideo()") }
    function stop() {
        videoId = ""
        playing = false
        buffering = false
        d.call("player && player.stopVideo()")
    }
    function seek(ms) {
        position = ms
        positionTime = Date.now()
        d.call("player && player.seekTo(" + (ms / 1000) + ", true)")
    }
    onVolumeChanged: d.call("player && player.setVolume(" + Math.round(volume * 100) + ")")

    QtObject {
        id: d
        property bool pageReady: false
        property var pending: []
        function call(js) {
            if (pageReady)
                view.runJavaScript(js)
            else
                pending.push(js)
        }
        function handle(m) {
            switch (m.e) {
            case "page":
                pageReady = true
                for (const js of pending)
                    view.runJavaScript(js)
                pending = []
                break
            case "state":
                // -1 unstarted, 0 ended, 1 playing, 2 paused, 3 buffering, 5 cued
                root.playing = m.s === 1
                root.buffering = m.s === 3 || m.s === -1
                if (m.d > 0) root.duration = m.d * 1000
                if (m.s === 0) root.ended()
                break
            case "time":
                root.position = m.t * 1000
                root.positionTime = Date.now()
                if (m.d > 0) root.duration = m.d * 1000
                break
            case "error":
                root.playing = false
                root.buffering = false
                root.failed(m.c)
                break
            }
        }
    }

    readonly property string page: '<!doctype html><html><head><meta charset="utf-8">'
        + '<meta name="viewport" content="width=device-width,initial-scale=1">'
        + '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}#p{position:absolute;left:0;top:0;width:100%;height:100%}</style>'
        + '</head><body><div id="p"></div><script>'
        + 'function send(o){console.log("tune:"+JSON.stringify(o))}'
        + 'var player=null,api=false,queued=null,vol=80;'
        + 'function create(id){player=new YT.Player("p",{width:"100%",height:"100%",videoId:id,'
        + 'playerVars:{autoplay:1,playsinline:1,controls:0,rel:0,iv_load_policy:3,fs:0,disablekb:1,origin:location.origin},'
        + 'events:{onReady:function(e){e.target.setVolume(vol);e.target.playVideo()},'
        + 'onStateChange:function(e){send({e:"state",s:e.data,d:player.getDuration()})},'
        + 'onError:function(e){send({e:"error",c:e.data})}}})}'
        + 'function load(id,v){vol=v;if(!api){queued=id;return}if(!player)create(id);else{player.setVolume(v);player.loadVideoById(id)}}'
        + 'function onYouTubeIframeAPIReady(){api=true;if(queued){create(queued);queued=null}}'
        + 'setInterval(function(){if(player&&player.getCurrentTime&&player.getPlayerState()===1)'
        + 'send({e:"time",t:player.getCurrentTime(),d:player.getDuration()})},1000);'
        + 'send({e:"page"});'
        + '</script><script src="https://www.youtube.com/iframe_api"></script></body></html>'

    WebEngineView {
        id: view
        anchors.fill: parent
        backgroundColor: "black"
        settings.playbackRequiresUserGesture: false
        settings.showScrollBars: false
        settings.javascriptCanOpenWindows: false
        profile: WebEngineProfile {
            storageName: "tune-youtube"
            persistentCookiesPolicy: WebEngineProfile.AllowPersistentCookies
            Component.onCompleted: httpUserAgent = httpUserAgent.replace(/QtWebEngine\/[\d.]+ /, "")
        }
        onJavaScriptConsoleMessage: (level, message) => {
            if (message.startsWith("tune:")) {
                try { d.handle(JSON.parse(message.slice(5))) } catch (e) { }
            }
        }
        // Links in the player (the YouTube logo, the title) open in Planet,
        // never inside Tune.
        onNewWindowRequested: (request) => Packages.launch("com.astra.planet", { action: "open", url: request.requestedUrl.toString() })
        onNavigationRequested: (request) => {
            if (request.isMainFrame && request.url.toString().indexOf("youtube.com") >= 0) {
                request.reject()
                Packages.launch("com.astra.planet", { action: "open", url: request.url.toString() })
            }
        }
        // The page's origin: YouTube refuses embeds that send no referrer.
        Component.onCompleted: loadHtml(root.page, "https://tune.astraos.invalid/")
    }
}
