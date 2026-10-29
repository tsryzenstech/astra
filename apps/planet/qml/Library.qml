// SPDX-License-Identifier: Apache-2.0
import QtQuick
import QtWebEngine
import Astra.Core
import Astra.Controls

// Bookmarks, Reading List, History and Downloads, plus Planet's settings.
Sheet {
    id: root
    required property var browser
    property int section: 0
    property bool settings: false
    maxHeight: parent ? parent.height * 0.92 : 700
    onOpenedChanged: if (opened) settings = false

    function ago(t) {
        const d = new Date(t)
        const today = new Date()
        if (d.toDateString() === today.toDateString())
            return Qt.locale().toString(d, Qt.locale().timeFormat(Locale.ShortFormat))
        return Qt.locale().toString(d, Qt.locale().dateFormat(Locale.ShortFormat))
    }

    Column {
        width: parent.width
        spacing: 16

        Item {
            width: parent.width
            height: 36
            SegmentedControl {
                visible: !root.settings
                width: parent.width - 52
                model: [qsTr("Bookmarks"), qsTr("Reading"), qsTr("History"), qsTr("Downloads")]
                currentIndex: root.section
                onActivated: (i) => root.section = i
            }
            Text {
                visible: root.settings
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Planet Settings")
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headlineSize
                font.weight: Font.Bold
                color: Theme.text
            }
            IconButton {
                anchors.right: parent.right
                size: 36
                iconName: root.settings ? "close" : "settings"
                onClicked: root.settings = !root.settings
            }
        }

        // ---- Bookmarks
        ListGroup {
            visible: !root.settings && root.section === 0
            width: parent.width
            Repeater {
                model: root.browser.bookmarks
                delegate: ListItem {
                    required property var modelData
                    required property int index
                    text: modelData.title || root.browser.host(modelData.url)
                    subtitle: root.browser.host(modelData.url)
                    iconName: "bookmark"
                    onClicked: { root.close(); root.browser.open(modelData.url) }
                    IconButton {
                        size: 34
                        iconName: "trash"
                        color: "transparent"
                        iconColor: Theme.danger
                        onClicked: {
                            root.browser.bookmarks = root.browser.bookmarks.filter(b => b.url !== modelData.url)
                            root.browser.save()
                        }
                    }
                }
            }
            ListItem {
                visible: root.browser.bookmarks.length === 0
                text: qsTr("No bookmarks yet")
                subtitle: qsTr("Open a page and choose Add Bookmark in the aA menu.")
                enabled: false
                separator: false
            }
        }

        // ---- Reading List
        ListGroup {
            visible: !root.settings && root.section === 1
            width: parent.width
            Repeater {
                model: root.browser.readingList
                delegate: ListItem {
                    required property var modelData
                    text: modelData.title || root.browser.host(modelData.url)
                    subtitle: (modelData.read ? qsTr("Read") + " • " : "") + root.browser.host(modelData.url)
                    iconName: modelData.read ? "check-circle" : "book"
                    onClicked: {
                        root.browser.readingList = root.browser.readingList.map(r => r.url === modelData.url ? Object.assign({}, r, { read: true }) : r)
                        root.browser.save()
                        root.close()
                        root.browser.open(modelData.url)
                    }
                    IconButton {
                        size: 34
                        iconName: "trash"
                        color: "transparent"
                        iconColor: Theme.danger
                        onClicked: {
                            root.browser.readingList = root.browser.readingList.filter(r => r.url !== modelData.url)
                            root.browser.save()
                        }
                    }
                }
            }
            ListItem {
                visible: root.browser.readingList.length === 0
                text: qsTr("Your Reading List is empty")
                subtitle: qsTr("Save pages to read later from the aA menu or by holding a link.")
                enabled: false
                separator: false
            }
        }

        // ---- History
        Column {
            visible: !root.settings && root.section === 2
            width: parent.width
            spacing: 12
            TextField {
                id: historySearch
                width: parent.width
                placeholder: qsTr("Search History")
            }
            ListGroup {
                width: parent.width
                Repeater {
                    model: root.browser.history.filter(h => !historySearch.text || (h.title + " " + h.url).toLowerCase().indexOf(historySearch.text.toLowerCase()) >= 0).slice(0, 150)
                    delegate: ListItem {
                        required property var modelData
                        text: modelData.title || root.browser.host(modelData.url)
                        subtitle: root.browser.host(modelData.url)
                        value: root.ago(modelData.time)
                        iconName: "history"
                        onClicked: { root.close(); root.browser.open(modelData.url) }
                    }
                }
                ListItem {
                    visible: root.browser.history.length === 0
                    text: qsTr("No history")
                    enabled: false
                    separator: false
                }
            }
            Button {
                visible: root.browser.history.length > 0
                width: parent.width
                text: qsTr("Clear History")
                destructive: true
                primary: false
                onClicked: {
                    root.browser.history = []
                    root.browser.save()
                }
            }
        }

        // ---- Downloads
        ListGroup {
            visible: !root.settings && root.section === 3
            width: parent.width
            Repeater {
                model: root.browser.downloads
                delegate: ListItem {
                    required property var modelData
                    readonly property var d: modelData.item
                    readonly property bool finished: d && d.isFinished
                    text: modelData.name
                    subtitle: !d ? "" : d.state === WebEngineDownloadRequest.DownloadCompleted ? qsTr("Done • %1").arg(Math.round(d.totalBytes / 1024) + " KB")
                            : d.state === WebEngineDownloadRequest.DownloadInProgress ? qsTr("%1 of %2").arg(Math.round(d.receivedBytes / 1024) + " KB").arg(d.totalBytes > 0 ? Math.round(d.totalBytes / 1024) + " KB" : "?")
                            : qsTr("Failed")
                    iconName: "download"
                    busy: d && !d.isFinished
                    onClicked: if (finished) Packages.launch("com.astra.files", { action: "open", files: [modelData.path] })
                    IconButton {
                        visible: d && !d.isFinished
                        size: 34
                        iconName: "close"
                        color: "transparent"
                        iconColor: Theme.danger
                        onClicked: d.cancel()
                    }
                }
            }
            ListItem {
                visible: root.browser.downloads.length === 0
                text: qsTr("No downloads")
                subtitle: qsTr("Files you download are saved in Files › Download.")
                enabled: false
                separator: false
            }
        }

        // ---- Settings
        ListGroup {
            visible: root.settings
            width: parent.width
            title: qsTr("Search")
            Repeater {
                model: ["google", "duckduckgo", "bing", "ecosia", "startpage"]
                delegate: ListItem {
                    required property string modelData
                    text: root.browser.engines[modelData].name
                    selected: root.browser.engine === modelData
                    onClicked: { root.browser.engine = modelData; root.browser.save() }
                }
            }
        }
        ListGroup {
            visible: root.settings
            width: parent.width
            title: qsTr("Privacy and Security")
            ListItem {
                text: qsTr("Block Pop-ups")
                showSwitch: true
                checked: root.browser.blockPopups
                onToggled: (on) => { root.browser.blockPopups = on; root.browser.save() }
            }
            ListItem {
                text: qsTr("JavaScript")
                showSwitch: true
                checked: root.browser.javascript
                onToggled: (on) => { root.browser.javascript = on; root.browser.save() }
            }
            ListItem {
                text: qsTr("Clear History and Website Data")
                destructive: true
                separator: false
                onClicked: Dialogs.show({ title: qsTr("Clear History and Website Data?"),
                                          message: qsTr("This removes your history, cookies and cached files."),
                                          buttons: [{ id: "cancel", label: qsTr("Cancel") }, { id: "clear", label: qsTr("Clear"), style: "destructive" }] },
                                        function(a) {
                                            if (a !== "clear")
                                                return
                                            root.browser.history = []
                                            root.browser.profile.clearHttpCache()
                                            root.browser.profile.clearAllVisitedLinks()
                                            for (const t of root.browser.tabs)
                                                if (t.started) t.view.runJavaScript("try{localStorage.clear();sessionStorage.clear()}catch(e){}")
                                            root.browser.clearCookies()
                                            root.browser.save()
                                        })
            }
        }
    }
}
