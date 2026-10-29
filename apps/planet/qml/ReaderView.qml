// SPDX-License-Identifier: Apache-2.0
import QtQuick
import Astra.Core
import Astra.Controls
import Astra.Animation

// Reader: the article of the page as clean text, without ads or menus.
Rectangle {
    id: root
    property var blocks: []          // [{ t: "h"|"p"|"q"|"li"|"img", v }]
    property string title
    property string site
    property real fontSize: Theme.bodySize + 2
    property int themeIndex: Theme.light ? 0 : 2
    signal unavailable()
    readonly property var themes: [
        { bg: "#FFFFFF", fg: "#1B1B1F" }, { bg: "#F6EEDC", fg: "#3B2F20" }, { bg: "#1C1C1F", fg: "#E8E8EA" }, { bg: "#000000", fg: "#D8D8DA" }
    ]
    color: themes[themeIndex].bg
    visible: reveal.value > 0.01
    opacity: reveal.value
    Spring { id: reveal; to: 0; response: 0.34; dampingFraction: 1 }

    // Picks the element with most paragraph text (a simple Readability).
    readonly property string extractor: "(function() {
        const pick = () => {
            let best = document.querySelector('article') || null, score = 0;
            for (const el of document.querySelectorAll('article, main, [role=main], div, section')) {
                let s = 0;
                for (const p of el.querySelectorAll(':scope > p, :scope > div > p')) s += p.innerText.length;
                if (s > score) { score = s; best = el; }
            }
            return best || document.body;
        };
        const root = pick(), out = [];
        const walk = (el) => {
            for (const n of el.children) {
                const tag = n.tagName.toLowerCase();
                if (/^(nav|aside|footer|header|form|script|style|button|figure figcaption)$/.test(tag)) continue;
                if (getComputedStyle(n).display === 'none') continue;
                if (/^h[1-4]$/.test(tag)) out.push({ t: 'h', v: n.innerText.trim() });
                else if (tag === 'p') { const v = n.innerText.trim(); if (v.length > 1) out.push({ t: 'p', v }); }
                else if (tag === 'blockquote') out.push({ t: 'q', v: n.innerText.trim() });
                else if (tag === 'li') out.push({ t: 'li', v: n.innerText.trim() });
                else if (tag === 'img' && n.naturalWidth > 200) out.push({ t: 'img', v: n.currentSrc || n.src });
                else if (tag === 'pre') out.push({ t: 'q', v: n.innerText });
                else walk(n);
            }
        };
        walk(root);
        return { title: document.title, site: location.hostname.replace(/^www\\./, ''), blocks: out.filter(b => b.v).slice(0, 600) };
    })()"

    function show(view) {
        view.runJavaScript(extractor, function(r) {
            if (!r || !r.blocks || r.blocks.length < 2) {
                root.unavailable()
                return
            }
            root.title = r.title
            root.site = r.site
            root.blocks = r.blocks
            flick.contentY = 0
            reveal.animateTo(1, 0)
        })
    }
    function close() { reveal.animateTo(0, 0) }

    MouseArea { anchors.fill: parent }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: column.height + 120
        Column {
            id: column
            x: 24
            y: 64
            width: parent.width - 48
            spacing: 16
            Text { text: root.site; font.family: Theme.fontFamily; font.pixelSize: Theme.footnoteSize; color: Qt.alpha(root.themes[root.themeIndex].fg, 0.6) }
            Text {
                width: parent.width
                text: root.title
                wrapMode: Text.WordWrap
                font.family: Theme.fontFamily
                font.pixelSize: root.fontSize + 10
                font.weight: Font.Bold
                color: root.themes[root.themeIndex].fg
            }
            Repeater {
                model: root.blocks
                delegate: Loader {
                    required property var modelData
                    width: column.width
                    sourceComponent: modelData.t === "img" ? img : txt
                    Component {
                        id: txt
                        Text {
                            width: column.width
                            leftPadding: modelData.t === "li" ? 18 : modelData.t === "q" ? 14 : 0
                            text: (modelData.t === "li" ? "•  " : "") + modelData.v
                            wrapMode: Text.WordWrap
                            lineHeight: 1.35
                            font.family: Theme.fontFamily
                            font.pixelSize: modelData.t === "h" ? root.fontSize + 4 : root.fontSize
                            font.weight: modelData.t === "h" ? Font.Bold : Font.Normal
                            font.italic: modelData.t === "q"
                            color: root.themes[root.themeIndex].fg
                        }
                    }
                    Component {
                        id: img
                        Image {
                            width: column.width
                            fillMode: Image.PreserveAspectFit
                            source: modelData.v
                            asynchronous: true
                        }
                    }
                }
            }
        }
    }

    // Reader controls
    Row {
        anchors.top: parent.top
        anchors.topMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 14
        spacing: 8
        IconButton { iconName: "minus"; size: 38; onClicked: root.fontSize = Math.max(13, root.fontSize - 2) }
        IconButton { iconName: "plus"; size: 38; onClicked: root.fontSize = Math.min(34, root.fontSize + 2) }
        IconButton { iconName: "palette"; size: 38; onClicked: root.themeIndex = (root.themeIndex + 1) % root.themes.length }
        IconButton { iconName: "close"; size: 38; color: Theme.accent; onClicked: root.close() }
    }
}
