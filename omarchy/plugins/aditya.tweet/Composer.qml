import "Drafts.js" as Drafts
import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
    id: root

    property var shell: null
    property var manifest: null
    property bool opened: false
    property string phase: "compose"
    property string draftId: ""
    property string draftText: ""
    property bool menuOpen: false
    property string dropMode: "post"
    property var drafts: []
    property int sendTick: 0
    property string draftsPath: Quickshell.env("HOME") + "/.local/state/omarchy/tweet-drafts.json"
    property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/aditya.tweet"
    property string pendingPath: Quickshell.env("HOME") + "/.local/state/omarchy/tweet-pending.txt"
    property string consentPath: Quickshell.env("HOME") + "/.local/state/omarchy/tweet-consent.json"
    property string consent: ""
    property string browserName: "your default browser"
    property bool browserSignedIn: false
    property string postError: ""
    property string statusNote: ""
    property var media: []
    property bool picking: false
    property bool gifOpen: false
    property string gifQuery: ""
    property string gifStatus: ""
    property string gifPickUrl: ""
    property string gifPickId: ""
    property bool gifBusy: false
    readonly property int gifChipW: Style.space(48)
    readonly property bool sessionAllowed: consent === "allow"
    readonly property bool needsOnboard: consent !== "allow" && consent !== "deny"
    property color background: Color.menu.background
    property color foreground: Color.menu.text
    property color accent: Color.accent
    property color muted: Color.muted
    property string fontFamily: Style.font.menuFamily
    readonly property string pluginId: (manifest && manifest.id) || "aditya.tweet"
    // Video sheet: large radius, hairline ring, square-ish card.
    readonly property int cardRadius: Math.max(Style.space(24), Style.cornerRadius)
    readonly property int cardPad: Style.space(22)
    readonly property int chipRadius: Style.space(10)
    readonly property int mediaRadius: Style.space(14)
    readonly property int chipH: Style.space(36)
    readonly property int iconBtn: Style.space(28)
    readonly property int cardWidth: Math.min(Style.space(380), Math.max(Style.space(320), panel.width - Style.gapsOut * 2))
    readonly property int cardHeight: Math.min(Style.space(380), Math.max(Style.space(320), panel.height - Style.gapsOut * 2))
    readonly property var borderSpec: Border.flat(Qt.rgba(1, 1, 1, 0.08), 1)
    readonly property int charCount: draftText.length
    readonly property int charLimit: 280
    readonly property bool overLimit: charCount > charLimit
    readonly property bool hasText: draftText.replace(/^\s+|\s+$/g, "").length > 0
    readonly property bool canDrop: (hasText || media.length > 0) && !overLimit
    readonly property bool sending: phase === "sending"
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.12)
    readonly property color chipFill: Qt.rgba(1, 1, 1, 0.03)
    readonly property color chipFillHot: Qt.rgba(1, 1, 1, 0.08)
    readonly property color dropIdle: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.28)
    readonly property color dropArmed: root.accent

    function luma(c) {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }

    function inkOn(fill) {
        return luma(fill) > 0.55 ? Qt.rgba(0, 0, 0, 0.88) : Qt.rgba(1, 1, 1, 0.94);
    }

    function open(payloadJson) {
        var payload = ({
        });
        try {
            payload = JSON.parse(payloadJson || "{}");
        } catch (e) {
            payload = ({
            });
        }
        root.menuOpen = false;
        root.gifOpen = false;
        root.sendTick = 0;
        root.postError = "";
        probeProc.running = true;
        if (payload.text) {
            root.draftId = Drafts.nextId();
            root.applyText(String(payload.text));
        } else if (!root.draftText) {
            root.newDraft(true);
        }
        if (payload.media) {
            var list = Array.isArray(payload.media) ? payload.media : [payload.media];
            root.media = [];
            root.addPaths(list);
        }
        root.phase = root.needsOnboard ? "onboard" : "compose";
        root.opened = true;
        if (root.phase === "compose")
            Qt.callLater(function() {
            if (payload.gif) {
                if (payload.q)
                    root.gifQuery = String(payload.q);

                root.openGifs();
            } else {
                editor.forceActiveFocus();
            }

        });

    }

    function close() {
        root.opened = false;
        root.menuOpen = false;
        root.gifOpen = false;
    }

    function dismiss() {
        if (!root.sending)
            stashCurrent();

        close();
        if (root.shell && typeof root.shell.hide === "function")
            root.shell.hide(root.pluginId);

    }

    function toggle() {
        if (root.opened)
            root.dismiss();
        else
            root.open("{}");
    }

    function applyText(next) {
        root.draftText = String(next || "");
        if (editor.text !== root.draftText)
            editor.text = root.draftText;

    }

    function newDraft(skipStash) {
        if (!skipStash)
            stashCurrent();

        root.draftId = Drafts.nextId();
        root.statusNote = "";
        root.media = [];
        root.applyText("");
        root.menuOpen = false;
        root.gifOpen = false;
        Qt.callLater(function() {
            if (root.opened)
                editor.forceActiveFocus();

        });
    }

    function loadDraft(id) {
        stashCurrent();
        var d = Drafts.find(root.drafts, id);
        if (!d)
            return ;

        root.draftId = d.id;
        root.statusNote = "";
        root.media = Array.isArray(d.media) ? d.media : [];
        root.applyText(d.text);
        Qt.callLater(function() {
            editor.forceActiveFocus();
        });
    }

    function stashCurrent() {
        if (!root.draftId)
            return ;

        root.drafts = Drafts.upsert(root.drafts, root.draftId, root.draftText, root.media);
        saveDrafts();
    }

    function saveDrafts() {
        draftsFile.setText(JSON.stringify(root.drafts, null, 2) + "\n");
    }

    function parseConsent(raw) {
        try {
            var data = JSON.parse(raw || "{}");
            if (data && (data.session === "allow" || data.session === "deny"))
                return data.session;

        } catch (e) {
        }
        return "";
    }

    function setConsent(value) {
        root.consent = value;
        consentFile.setText(JSON.stringify({
            "session": value,
            "at": Date.now()
        }, null, 2) + "\n");
        root.phase = "compose";
        Qt.callLater(function() {
            editor.forceActiveFocus();
        });
    }

    function mediaKind(path) {
        var p = String(path || "").toLowerCase();
        if (/\.(mp4|mov|webm|mkv|m4v)$/.test(p))
            return "video";

        if (/\.gif$/.test(p))
            return "gif";

        if (/\.(png|jpe?g|webp|heic|bmp)$/.test(p))
            return "image";

        return "";
    }

    function fileUrl(path) {
        return "file://" + encodeURI(String(path));
    }

    function addPaths(paths) {
        var next = root.media.slice();
        var hasVideo = next.some(function(m) {
            return m.kind === "video" || m.kind === "gif";
        });
        for (var i = 0; i < paths.length; i++) {
            var path = String(paths[i] || "").replace(/^file:\/\//, "");
            try {
                path = decodeURIComponent(path);
            } catch (e) {
            }
            var kind = root.mediaKind(path);
            if (!kind)
                continue;

            var dup = false;
            for (var j = 0; j < next.length; j++) if (next[j].path === path) {
                dup = true;
            }
            if (dup)
                continue;

            if (kind === "video" || kind === "gif") {
                if (next.length > 0) {
                    root.postError = "A video or GIF has to be the only attachment.";
                    continue;
                }
                next.push({
                    "path": path,
                    "kind": kind
                });
                hasVideo = true;
                continue;
            }
            if (hasVideo) {
                root.postError = "A video or GIF has to be the only attachment.";
                continue;
            }
            if (next.length >= 4) {
                root.postError = "Up to 4 images.";
                break;
            }
            next.push({
                "path": path,
                "kind": kind
            });
        }
        root.media = next;
    }

    function removeMedia(index) {
        var next = [];
        for (var i = 0; i < root.media.length; i++) if (i !== index) {
            next.push(root.media[i]);
        }
        root.media = next;
    }

    function pickMedia() {
        root.postError = "";
        root.gifOpen = false;
        root.picking = true;
        pickProc.running = true;
    }

    function openGifs() {
        root.menuOpen = false;
        root.postError = "";
        root.gifStatus = "";
        root.gifOpen = true;
        root.searchGifs();
        Qt.callLater(function() {
            if (gifSearch.text !== root.gifQuery)
                gifSearch.text = root.gifQuery;

            gifSearch.forceActiveFocus();
        });
    }

    function closeGifs() {
        root.gifOpen = false;
        root.gifBusy = false;
        root.gifStatus = "";
        Qt.callLater(function() {
            if (root.opened)
                editor.forceActiveFocus();

        });
    }

    function searchGifs() {
        root.gifBusy = true;
        root.gifStatus = "";
        if (gifSearchProc.running)
            gifSearchProc.running = false;

        gifSearchProc.running = true;
    }

    function loadGifItems(items) {
        gifModel.clear();
        for (var i = 0; i < items.length; i++) {
            var it = items[i];
            gifModel.append({
                "gid": String(it.id || ""),
                "title": String(it.title || ""),
                "preview": String(it.preview || ""),
                "url": String(it.url || "")
            });
        }
    }

    function pickGif(gid, url) {
        if (!url || root.gifBusy)
            return ;

        root.gifPickId = gid;
        root.gifPickUrl = url;
        root.gifBusy = true;
        root.gifStatus = "Adding GIF…";
        if (gifFetchProc.running)
            gifFetchProc.running = false;

        gifFetchProc.running = true;
    }

    function tileX(i, n, w, g) {
        if (n === 1)
            return 0;

        if (n === 2)
            return i * (w + g) / 2;

        if (n === 3)
            return i === 0 ? 0 : (w + g) / 2;

        return (i % 2) * (w + g) / 2;
    }

    function tileY(i, n, h, g) {
        if (n <= 2)
            return 0;

        if (n === 3)
            return i <= 1 ? 0 : (h + g) / 2;

        return Math.floor(i / 2) * (h + g) / 2;
    }

    function tileW(i, n, w, g) {
        if (n === 1)
            return w;

        return (w - g) / 2;
    }

    function tileH(i, n, h, g) {
        if (n === 1 || n === 2)
            return h;

        if (n === 3)
            return i === 0 ? h : (h - g) / 2;

        return (h - g) / 2;
    }

    function dropIt() {
        if (!root.canDrop || root.sending)
            return ;

        var text = root.draftText;
        root.menuOpen = false;
        root.gifOpen = false;
        root.postError = "";
        if (root.dropMode === "post" && !root.sessionAllowed) {
            root.phase = "onboard";
            return ;
        }
        if (root.dropMode === "draft") {
            if (!root.draftId)
                root.draftId = Drafts.nextId();

            root.drafts = Drafts.upsert(root.drafts, root.draftId, text, root.media);
            saveDrafts();
            root.statusNote = "Saved as draft";
            statusClear.restart();
            return ;
        }
        root.phase = "sending";
        root.sendTick = 0;
        sendAnim.restart();
        var paths = [];
        for (var i = 0; i < root.media.length; i++) paths.push(root.media[i].path)
        pendingFile.setText(JSON.stringify({
            "text": text,
            "media": paths
        }));
        Qt.callLater(function() {
            postProc.running = true;
        });
    }

    function finishSend(ok, message) {
        sendAnim.stop();
        root.sendTick = 0;
        root.phase = "compose";
        if (ok) {
            root.drafts = Drafts.remove(root.drafts, root.draftId);
            saveDrafts();
            root.draftText = "";
            root.draftId = Drafts.nextId();
            root.media = [];
            if (editor.text !== "")
                editor.text = "";

            root.postError = "";
        } else {
            root.postError = message || "Could not post.";
        }
        Qt.callLater(function() {
            editor.forceActiveFocus();
        });
    }

    Component.onCompleted: probeProc.running = true

    FileView {
        id: draftsFile

        path: root.draftsPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: root.drafts = Drafts.parse(text())
        onLoadFailed: root.drafts = []
        onFileChanged: reload()
    }

    FileView {
        id: pendingFile

        path: root.pendingPath
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: consentFile

        path: root.consentPath
        watchChanges: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            root.consent = root.parseConsent(text());
            if (!root.opened)
                return ;

            if (root.needsOnboard)
                root.phase = "onboard";
            else if (root.phase === "onboard")
                root.phase = "compose";
        }
        onLoadFailed: {
            root.consent = "";
            if (root.opened)
                root.phase = "onboard";

        }
        onFileChanged: reload()
    }

    Process {
        id: probeProc

        command: [root.pluginDir + "/.venv/bin/python", root.pluginDir + "/post.py", "--probe"]

        stdout: StdioCollector {
            id: probeOut

            waitForEnd: true
            onStreamFinished: {
                try {
                    var data = JSON.parse(text);
                    if (data.browser)
                        root.browserName = data.browser;

                    root.browserSignedIn = !!data.signedIn;
                } catch (e) {
                }
            }
        }

    }

    Process {
        id: pickProc

        command: [root.pluginDir + "/pick.sh"]
        onExited: function(exitCode) {
            root.picking = false;
            if (exitCode !== 0)
                return ;

            var raw = String(pickOut.text || "");
            var lines = raw.split(/\n/);
            var paths = [];
            for (var i = 0; i < lines.length; i++) {
                var line = lines[i].replace(/^\s+|\s+$/g, "");
                if (line)
                    paths.push(line);

            }
            if (paths.length)
                root.addPaths(paths);

            Qt.callLater(function() {
                if (root.opened)
                    editor.forceActiveFocus();

            });
        }

        stdout: StdioCollector {
            id: pickOut

            waitForEnd: true
        }

    }

    ListModel {
        id: gifModel
    }

    Timer {
        id: gifDebounce

        interval: 280
        onTriggered: root.searchGifs()
    }

    Process {
        id: gifSearchProc

        command: [root.pluginDir + "/.venv/bin/python", root.pluginDir + "/gif.py", "search", root.gifQuery]
        onExited: function(exitCode) {
            root.gifBusy = false;
            var raw = String(gifSearchOut.text || "");
            try {
                var data = JSON.parse(raw);
                if (!data || !data.ok) {
                    root.gifStatus = (data && data.error) ? data.error : "Could not search GIFs.";
                    return ;
                }
                root.loadGifItems(data.items || []);
                if (gifModel.count === 0)
                    root.gifStatus = root.gifQuery.length ? "No GIFs for that." : "No GIFs right now.";

            } catch (e) {
                root.gifStatus = "Could not search GIFs.";
            }
        }

        stdout: StdioCollector {
            id: gifSearchOut

            waitForEnd: true
        }

    }

    Process {
        id: gifFetchProc

        command: [root.pluginDir + "/.venv/bin/python", root.pluginDir + "/gif.py", "fetch", root.gifPickUrl, root.gifPickId]
        onExited: function(exitCode) {
            root.gifBusy = false;
            var raw = String(gifFetchOut.text || "");
            try {
                var data = JSON.parse(raw);
                if (!data || !data.ok || !data.path) {
                    root.gifStatus = (data && data.error) ? data.error : "Could not add that GIF.";
                    return ;
                }
                root.media = [];
                root.addPaths([data.path]);
                root.closeGifs();
                root.statusNote = "GIF attached";
                statusClear.restart();
            } catch (e) {
                root.gifStatus = "Could not add that GIF.";
            }
        }

        stdout: StdioCollector {
            id: gifFetchOut

            waitForEnd: true
        }

    }

    Process {
        id: postProc

        command: [root.pluginDir + "/.venv/bin/python", root.pluginDir + "/post.py", root.pendingPath]
        onExited: function(exitCode) {
            var err = String(postErr.text || "").replace(/^\s+|\s+$/g, "");
            if (exitCode === 0)
                root.finishSend(true, "");
            else
                root.finishSend(false, err);
        }

        stdout: StdioCollector {
            id: postOut

            waitForEnd: true
        }

        stderr: StdioCollector {
            id: postErr

            waitForEnd: true
        }

    }

    Timer {
        id: sendAnim

        interval: 55
        repeat: true
        onTriggered: root.sendTick += 1
    }

    Timer {
        id: statusClear

        interval: 2200
        onTriggered: root.statusNote = ""
    }

    PanelWindow {
        id: panel

        visible: (root.opened || cardHost.opacity > 0.01) && !root.picking
        color: "transparent"
        WlrLayershell.namespace: "aditya-tweet"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: (root.opened && !root.picking) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.22)
            opacity: root.opened ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }

            }

        }

        MouseArea {
            anchors.fill: parent
            enabled: root.opened && !root.sending
            onClicked: root.dismiss()
        }

        Item {
            id: cardHost

            width: root.cardWidth
            height: root.cardHeight
            // Snap to device pixels so 1.25 scale does not land on a half-pixel.
            x: {
                var dpr = panel.screen ? panel.screen.devicePixelRatio : 1;
                var raw = (panel.width - width) / 2;
                return Math.round(raw * dpr) / dpr;
            }
            y: {
                var dpr = panel.screen ? panel.screen.devicePixelRatio : 1;
                var raw = (panel.height - height) / 2 + (root.opened ? 0 : Style.space(12));
                return Math.round(raw * dpr) / dpr;
            }
            opacity: root.opened ? 1 : 0

            Rectangle {
                anchors.fill: card
                anchors.topMargin: Style.space(10)
                radius: root.cardRadius
                color: Qt.rgba(0, 0, 0, 0.38)
                z: -1
            }

            BorderSurface {
                id: card

                anchors.fill: parent
                radius: root.cardRadius
                color: root.background
                borderSpec: Border.none()
                padding: root.cardPad
                clip: true

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.1)
                    enabled: false
                    z: -1
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: root.menuOpen = false
                }

                Item {
                    id: onboardLayer

                    anchors.fill: parent
                    anchors.topMargin: card.contentTopInset
                    anchors.rightMargin: card.contentRightInset
                    anchors.bottomMargin: card.contentBottomInset
                    anchors.leftMargin: card.contentLeftInset
                    opacity: root.phase === "onboard" ? 1 : 0
                    visible: opacity > 0.01
                    z: 3

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -Style.space(18)
                        spacing: Style.space(12)

                        Text {
                            width: parent.width
                            text: "Use your " + root.browserName + " session?"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.heading
                            font.weight: Font.DemiBold
                            wrapMode: Text.Wrap
                            renderType: Text.NativeRendering
                        }

                        Text {
                            width: parent.width
                            text: "Posting reads the X account already signed in on " + root.browserName + ". Compose never sees your password."
                            color: Util.alpha(root.foreground, 0.72)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            wrapMode: Text.Wrap
                            renderType: Text.NativeRendering
                        }

                        Text {
                            width: parent.width
                            visible: !root.browserSignedIn
                            text: "Sign into X in " + root.browserName + " first, then allow."
                            color: root.muted
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.Wrap
                            renderType: Text.NativeRendering
                        }

                    }

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: root.chipH
                        spacing: Style.space(8)

                        Chip {
                            width: (parent.width - Style.space(8)) / 2
                            label: "Deny"
                            onTapped: root.setConsent("deny")
                        }

                        Chip {
                            width: (parent.width - Style.space(8)) / 2
                            label: "Allow"
                            primary: true
                            armed: true
                            onTapped: root.setConsent("allow")
                        }

                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                // --- compose chrome ------------------------------------------------
                Item {
                    id: composeLayer

                    anchors.fill: parent
                    anchors.topMargin: card.contentTopInset
                    anchors.rightMargin: card.contentRightInset
                    anchors.bottomMargin: card.contentBottomInset
                    anchors.leftMargin: card.contentLeftInset
                    opacity: root.phase === "compose" ? 1 : 0
                    visible: opacity > 0.01

                    // Header
                    Row {
                        id: header

                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: root.iconBtn
                        spacing: Style.space(8)

                        Item {
                            id: xMark

                            width: Style.space(18)
                            height: Style.space(18)
                            anchors.verticalCenter: parent.verticalCenter

                            Shape {
                                anchors.fill: parent
                                preferredRendererType: Shape.CurveRenderer

                                ShapePath {
                                    fillColor: root.foreground
                                    strokeWidth: 0

                                    PathSvg {
                                        path: "M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-4.714-6.231-5.401 6.231H2.744l7.727-8.833L1.254 2.25H8.08l4.253 5.622L18.244 2.25zm-1.161 17.52h1.833L7.084 4.126H5.117z"
                                    }

                                }

                                transform: Scale {
                                    xScale: Style.space(18) / 24
                                    yScale: Style.space(18) / 24
                                }

                            }

                        }

                        Item {
                            width: Math.max(0, header.width - xMark.width - root.iconBtn - header.spacing * 2)
                            height: 1
                        }

                        IconHit {
                            onTapped: root.dismiss()
                        }

                    }

                    // Editor
                    DropArea {
                        id: editorWrap

                        anchors.top: header.bottom
                        anchors.topMargin: Style.space(16)
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: footer.top
                        anchors.bottomMargin: Style.space(14)
                        keys: ["text/uri-list"]
                        onDropped: function(drop) {
                            if (!drop.hasUrls)
                                return ;

                            var urls = [];
                            for (var i = 0; i < drop.urls.length; i++) urls.push(String(drop.urls[i]))
                            root.addPaths(urls);
                            drop.acceptProposedAction();
                        }

                        TextArea {
                            id: editor

                            anchors.fill: parent
                            anchors.bottomMargin: (root.media.length > 0 ? Style.space(148) : 0) + (root.dropMode === "draft" && root.drafts.length > 0 ? Style.space(92) : 0)
                            wrapMode: TextEdit.Wrap
                            placeholderText: "Write your message or drop files"
                            placeholderTextColor: Util.alpha(root.foreground, 0.38)
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.heading
                            font.weight: Font.Normal
                            renderType: Text.NativeRendering
                            background: null
                            padding: 0
                            topPadding: 0
                            leftPadding: 0
                            rightPadding: 0
                            selectByMouse: true
                            onTextChanged: {
                                if (text !== root.draftText)
                                    root.draftText = text;

                            }
                            Keys.priority: Keys.BeforeItem
                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Escape) {
                                    if (root.gifOpen)
                                        root.closeGifs();
                                    else
                                        root.dismiss();

                                    event.accepted = true;
                                } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                                    root.dropIt();
                                    event.accepted = true;
                                }
                            }
                        }

                        Item {
                            id: mosaic

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: draftList.top
                            anchors.bottomMargin: Style.space(8)
                            height: root.media.length > 0 ? Style.space(132) : 0
                            visible: height > 0

                            Repeater {
                                model: root.media

                                Item {
                                    required property int index
                                    required property var modelData

                                    x: root.tileX(index, root.media.length, mosaic.width, Style.space(6))
                                    y: root.tileY(index, root.media.length, mosaic.height, Style.space(6))
                                    width: root.tileW(index, root.media.length, mosaic.width, Style.space(6))
                                    height: root.tileH(index, root.media.length, mosaic.height, Style.space(6))

                                    MediaFrame {
                                        id: tile

                                        anchors.fill: parent

                                        Image {
                                            anchors.fill: parent
                                            source: modelData.kind === "video" ? "" : root.fileUrl(modelData.path)
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            visible: modelData.kind !== "video"
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: modelData.kind === "video"
                                            color: Qt.rgba(0, 0, 0, 0.28)
                                        }

                                        Rectangle {
                                            visible: modelData.kind === "video"
                                            width: Math.max(Style.space(22), Math.min(Style.space(28), tile.height * 0.38))
                                            height: width
                                            radius: width / 2
                                            anchors.centerIn: parent
                                            color: Qt.rgba(0, 0, 0, 0.48)
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.16)

                                            Shape {
                                                id: playMark

                                                width: parent.width * 0.42
                                                height: parent.height * 0.42
                                                anchors.centerIn: parent
                                                // Play triangles read left-heavy; shift toward the point.
                                                anchors.horizontalCenterOffset: parent.width * 0.04
                                                preferredRendererType: Shape.CurveRenderer

                                                ShapePath {
                                                    fillColor: Qt.rgba(1, 1, 1, 0.94)
                                                    strokeWidth: 0
                                                    strokeColor: "transparent"
                                                    startX: 1.2
                                                    startY: 0.4

                                                    PathLine {
                                                        x: playMark.width - 0.2
                                                        y: playMark.height / 2
                                                    }

                                                    PathLine {
                                                        x: 1.2
                                                        y: playMark.height - 0.4
                                                    }

                                                    PathLine {
                                                        x: 1.2
                                                        y: 0.4
                                                    }

                                                }

                                            }

                                        }

                                        Rectangle {
                                            visible: modelData.kind === "gif"
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            anchors.margins: Style.space(6)
                                            height: Style.space(18)
                                            width: Style.space(34)
                                            radius: height / 2
                                            color: Qt.rgba(0, 0, 0, 0.55)
                                            border.width: 1
                                            border.color: Qt.rgba(1, 1, 1, 0.12)

                                            Text {
                                                anchors.centerIn: parent
                                                text: "GIF"
                                                color: Qt.rgba(1, 1, 1, 0.94)
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.caption
                                                font.weight: Font.DemiBold
                                                font.letterSpacing: 0.4
                                                renderType: Text.NativeRendering
                                            }

                                        }

                                        Rectangle {
                                            id: removeHit

                                            anchors.top: parent.top
                                            anchors.right: parent.right
                                            anchors.margins: Style.space(5)
                                            width: Style.space(22)
                                            height: Style.space(22)
                                            radius: width / 2
                                            color: removeArea.containsMouse ? Qt.rgba(0, 0, 0, 0.72) : Qt.rgba(0, 0, 0, 0.5)
                                            scale: removeArea.pressed ? 0.96 : 1
                                            Accessible.role: Accessible.Button
                                            Accessible.name: "Remove attachment"

                                            Shape {
                                                anchors.centerIn: parent
                                                width: Style.space(9)
                                                height: Style.space(9)
                                                preferredRendererType: Shape.CurveRenderer

                                                ShapePath {
                                                    strokeWidth: 1.5
                                                    strokeColor: Qt.rgba(1, 1, 1, 0.92)
                                                    fillColor: "transparent"
                                                    capStyle: ShapePath.RoundCap
                                                    startX: 1.2
                                                    startY: 1.2

                                                    PathLine {
                                                        x: 7.8
                                                        y: 7.8
                                                    }

                                                }

                                                ShapePath {
                                                    strokeWidth: 1.5
                                                    strokeColor: Qt.rgba(1, 1, 1, 0.92)
                                                    fillColor: "transparent"
                                                    capStyle: ShapePath.RoundCap
                                                    startX: 7.8
                                                    startY: 1.2

                                                    PathLine {
                                                        x: 1.2
                                                        y: 7.8
                                                    }

                                                }

                                            }

                                            MouseArea {
                                                id: removeArea

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.removeMedia(index)
                                            }

                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 120
                                                    easing.type: Easing.OutCubic
                                                }

                                            }

                                            Behavior on scale {
                                                NumberAnimation {
                                                    duration: 120
                                                    easing.type: Easing.OutCubic
                                                }

                                            }

                                        }

                                    }

                                }

                            }

                        }

                        ListView {
                            id: draftList

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: root.dropMode === "draft" && root.drafts.length > 0 ? Style.space(80) : 0
                            visible: height > 0
                            clip: true
                            spacing: Style.space(2)
                            model: root.drafts
                            boundsBehavior: Flickable.StopAtBounds
                            orientation: ListView.Vertical

                            delegate: Rectangle {
                                required property var modelData

                                width: draftList.width
                                height: Style.space(24)
                                radius: Math.max(4, root.chipRadius - 6)
                                color: modelData.id === root.draftId ? Color.menu.selectedBackground : (rowMouse.containsMouse ? root.chipFillHot : "transparent")

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: Style.space(8)
                                    anchors.rightMargin: Style.space(8)
                                    text: Drafts.preview(modelData.text, 48)
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                    renderType: Text.NativeRendering
                                }

                                MouseArea {
                                    id: rowMouse

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.loadDraft(modelData.id)
                                }

                            }

                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: draftList.height
                            visible: root.postError.length > 0 || root.statusNote.length > 0
                            text: root.postError.length > 0 ? root.postError : root.statusNote
                            color: root.postError.length > 0 ? Color.urgent : root.muted
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.Wrap
                            renderType: Text.NativeRendering
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            visible: root.charCount >= 200 && root.postError.length === 0 && !root.gifOpen
                            text: root.charCount
                            color: root.overLimit ? Color.urgent : root.muted
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                            font.weight: Font.Medium
                            opacity: 0.9
                        }

                        Item {
                            id: gifLayer

                            anchors.fill: parent
                            visible: opacity > 0.01
                            opacity: root.gifOpen ? 1 : 0
                            z: 6

                            Rectangle {
                                anchors.fill: parent
                                color: root.background
                            }

                            TextField {
                                id: gifSearch

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: root.chipH
                                placeholderText: "Search GIFs"
                                placeholderTextColor: Util.alpha(root.foreground, 0.38)
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.subtitle
                                selectByMouse: true
                                leftPadding: Style.space(12)
                                rightPadding: Style.space(12)
                                onTextChanged: {
                                    root.gifQuery = text;
                                    gifDebounce.restart();
                                }
                                Keys.onPressed: function(event) {
                                    if (event.key === Qt.Key_Escape) {
                                        root.closeGifs();
                                        event.accepted = true;
                                    }
                                }

                                background: Rectangle {
                                    radius: root.chipRadius
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    border.width: 1
                                    border.color: root.hairline
                                }

                            }

                            Text {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: gifSearch.bottom
                                anchors.topMargin: Style.space(10)
                                visible: root.gifStatus.length > 0
                                text: root.gifStatus
                                color: root.muted
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                wrapMode: Text.Wrap
                                renderType: Text.NativeRendering
                            }

                            Flickable {
                                id: gifScroll

                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: gifSearch.bottom
                                anchors.topMargin: Style.space(10)
                                anchors.bottom: parent.bottom
                                clip: true
                                contentWidth: width
                                contentHeight: gifGrid.height
                                boundsBehavior: Flickable.StopAtBounds
                                visible: gifModel.count > 0

                                Grid {
                                    id: gifGrid

                                    width: gifScroll.width
                                    columns: 2
                                    spacing: Style.space(6)
                                    height: {
                                        var rows = Math.ceil(gifModel.count / 2);
                                        var cellH = Math.max(Style.space(88), ((width - spacing) / 2) * 0.72);
                                        return rows > 0 ? rows * cellH + Math.max(0, rows - 1) * spacing : 0;
                                    }

                                    Repeater {
                                        model: gifModel

                                        Item {
                                            required property string gid
                                            required property string title
                                            required property string preview
                                            required property string url

                                            width: (gifGrid.width - gifGrid.spacing) / 2
                                            height: Math.max(Style.space(88), width * 0.72)
                                            scale: gifCell.containsMouse && gifCell.pressed ? 0.96 : 1

                                            MediaFrame {
                                                anchors.fill: parent

                                                AnimatedImage {
                                                    anchors.fill: parent
                                                    source: preview
                                                    fillMode: Image.PreserveAspectCrop
                                                    asynchronous: true
                                                    playing: gifCell.containsMouse
                                                }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    visible: gifCell.containsMouse
                                                    color: Qt.rgba(0, 0, 0, 0.12)
                                                }

                                            }

                                            MouseArea {
                                                id: gifCell

                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.pickGif(gid, url)
                                            }

                                            Behavior on scale {
                                                NumberAnimation {
                                                    duration: 120
                                                    easing.type: Easing.OutCubic
                                                }

                                            }

                                        }

                                    }

                                }

                            }

                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 160
                                    easing.type: Easing.OutCubic
                                }

                            }

                        }

                    }

                    BorderSurface {
                        id: modePop

                        anchors.left: footer.left
                        anchors.right: footer.right
                        anchors.bottom: footer.top
                        anchors.bottomMargin: Style.space(8)
                        anchors.leftMargin: root.chipH + root.gifChipW + Style.space(8) * 2
                        height: Style.space(88)
                        radius: root.chipRadius
                        color: root.background
                        borderSpec: root.borderSpec
                        opacity: root.menuOpen ? 1 : 0
                        visible: opacity > 0.01
                        z: 4

                        Column {
                            anchors.fill: parent
                            anchors.margins: Style.space(6)
                            spacing: Style.space(2)

                            Rectangle {
                                width: parent.width
                                height: Style.space(36)
                                radius: Math.max(6, root.chipRadius - 6)
                                color: root.dropMode === "draft" || draftRow.containsMouse ? Color.menu.selectedBackground : "transparent"

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: Style.space(12)
                                    text: "Draft"
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.subtitle
                                    verticalAlignment: Text.AlignVCenter
                                }

                                MouseArea {
                                    id: draftRow

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.dropMode = "draft";
                                        root.menuOpen = false;
                                        Qt.callLater(function() {
                                            editor.forceActiveFocus();
                                        });
                                    }
                                }

                            }

                            Rectangle {
                                width: parent.width
                                height: Style.space(36)
                                radius: Math.max(6, root.chipRadius - 6)
                                color: root.dropMode === "post" || postRow.containsMouse ? Color.menu.selectedBackground : "transparent"

                                Text {
                                    anchors.fill: parent
                                    anchors.leftMargin: Style.space(12)
                                    text: "Post"
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.subtitle
                                    verticalAlignment: Text.AlignVCenter
                                }

                                MouseArea {
                                    id: postRow

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.dropMode = "post";
                                        root.menuOpen = false;
                                        Qt.callLater(function() {
                                            editor.forceActiveFocus();
                                        });
                                    }
                                }

                            }

                        }

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }

                        }

                    }

                    Row {
                        id: footer

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: root.chipH
                        spacing: Style.space(8)

                        Chip {
                            width: root.chipH
                            label: "Attach"
                            icon: "image"
                            onTapped: root.pickMedia()
                        }

                        Chip {
                            width: root.gifChipW
                            label: "GIF"
                            onTapped: root.gifOpen ? root.closeGifs() : root.openGifs()
                        }

                        Chip {
                            width: footer.width - root.chipH - root.gifChipW - dropChip.width - Style.space(8) * 3
                            label: root.dropMode === "draft" ? "Draft" : "Post"
                            chevron: true
                            chevronOpen: root.menuOpen
                            onTapped: root.menuOpen = !root.menuOpen
                        }

                        Chip {
                            id: dropChip

                            width: root.dropMode === "draft" ? Style.space(72) : root.chipH
                            label: root.dropMode === "draft" ? "Save" : "Post"
                            icon: root.dropMode === "draft" ? "" : "arrow"
                            primary: true
                            armed: root.canDrop
                            onTapped: root.dropIt()
                        }

                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }

                    }

                }

                // --- send grid -----------------------------------------------------
                Item {
                    id: sendLayer

                    anchors.fill: parent
                    opacity: root.sending ? 1 : 0
                    visible: opacity > 0.01

                    Grid {
                        anchors.centerIn: parent
                        columns: 5
                        rows: 5
                        spacing: Style.space(3)

                        Repeater {
                            model: 25

                            Rectangle {
                                width: Style.space(5)
                                height: Style.space(5)
                                radius: 1
                                color: root.foreground
                                opacity: {
                                    var col = index % 5;
                                    var row = Math.floor(index / 5);
                                    var t = root.sendTick;
                                    var order = row * 5 + col;
                                    if (t <= 8)
                                        return order < t * 3 ? 0.92 : 0.12;

                                    var remaining = 25 - (t - 8) * 4;
                                    return order < remaining ? 0.92 : 0.08;
                                }

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 80
                                        easing.type: Easing.OutCubic
                                    }

                                }

                            }

                        }

                    }

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 160
                            easing.type: Easing.OutCubic
                        }

                    }

                }

            }

            Behavior on opacity {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }

            }

            Behavior on y {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutCubic
                }

            }

        }

    }

    component MediaFrame: Rectangle {
        radius: root.mediaRadius
        color: Qt.rgba(1, 1, 1, 0.04)
        clip: true
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.1)
        layer.enabled: width > 2 && height > 2
        layer.smooth: true
        layer.textureSize: {
            var dpr = panel.screen ? panel.screen.devicePixelRatio : 1;
            Qt.size(Math.max(1, Math.round(width * dpr)), Math.max(1, Math.round(height * dpr)));
        }
    }

    component IconHit: Rectangle {
        id: hit

        signal tapped()

        width: root.iconBtn
        height: root.iconBtn
        radius: width / 2
        color: area.containsMouse ? root.chipFillHot : Qt.rgba(1, 1, 1, 0.055)
        scale: area.pressed ? 0.96 : 1

        Shape {
            anchors.centerIn: parent
            width: Style.space(10)
            height: Style.space(10)
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 1.5
                strokeColor: root.muted
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: 1.5
                startY: 1.5

                PathLine {
                    x: 8.5
                    y: 8.5
                }

            }

            ShapePath {
                strokeWidth: 1.5
                strokeColor: root.muted
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                startX: 8.5
                startY: 1.5

                PathLine {
                    x: 1.5
                    y: 8.5
                }

            }

        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: hit.tapped()
        }

        Behavior on color {
            ColorAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }

        }

    }

    component Chip: Rectangle {
        id: chip

        property string label: ""
        property string icon: ""
        property bool primary: false
        property bool armed: true
        property bool chevron: false
        property bool chevronOpen: false
        readonly property color mark: chip.primary ? (chip.armed ? root.inkOn(root.dropArmed) : Util.alpha(root.inkOn(root.dropIdle), 0.55)) : root.foreground

        signal tapped()

        height: root.chipH
        radius: chip.primary ? height / 2 : root.chipRadius
        color: {
            if (chip.primary)
                return chip.armed ? root.dropArmed : root.dropIdle;

            return area.containsMouse ? root.chipFillHot : "transparent";
        }
        border.width: chip.primary ? 0 : 1
        border.color: root.hairline
        scale: area.pressed && chip.armed ? 0.96 : 1
        opacity: 1
        Accessible.role: Accessible.Button
        Accessible.name: chip.label

        Row {
            anchors.centerIn: parent
            spacing: Style.space(6)

            Item {
                visible: chip.icon === "image"
                width: visible ? Style.space(14) : 0
                height: Style.space(14)
                anchors.verticalCenter: parent.verticalCenter

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: 1.5
                        strokeColor: chip.mark
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        startX: 2
                        startY: 4.2

                        PathLine {
                            x: 2
                            y: 11
                        }

                        PathLine {
                            x: 12
                            y: 11
                        }

                        PathLine {
                            x: 12
                            y: 4.2
                        }

                        PathLine {
                            x: 2
                            y: 4.2
                        }

                    }

                    ShapePath {
                        strokeWidth: 1.5
                        strokeColor: chip.mark
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        startX: 2
                        startY: 11

                        PathLine {
                            x: 5.2
                            y: 7.1
                        }

                        PathLine {
                            x: 7.4
                            y: 9.1
                        }

                        PathLine {
                            x: 10
                            y: 6.2
                        }

                        PathLine {
                            x: 12
                            y: 8.6
                        }

                    }

                    ShapePath {
                        strokeWidth: 1.5
                        strokeColor: chip.mark
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: 5.5
                        startY: 5.5

                        PathAngleArc {
                            centerX: 4.6
                            centerY: 5.5
                            radiusX: 0.9
                            radiusY: 0.9
                            startAngle: 0
                            sweepAngle: 360
                        }

                    }

                }

            }

            Item {
                visible: chip.icon === "arrow"
                width: visible ? Style.space(12) : 0
                height: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                // Optical nudge: arrowheads read left-heavy when geometrically centered.
                anchors.verticalCenterOffset: 0.5

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: 2
                        strokeColor: chip.mark
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        startX: 1.6
                        startY: 6

                        PathLine {
                            x: 10.2
                            y: 6
                        }

                    }

                    ShapePath {
                        strokeWidth: 2
                        strokeColor: chip.mark
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        startX: 6.4
                        startY: 2.2

                        PathLine {
                            x: 10.4
                            y: 6
                        }

                        PathLine {
                            x: 6.4
                            y: 9.8
                        }

                    }

                }

            }

            Text {
                visible: chip.icon === ""
                text: chip.label
                color: chip.mark
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.weight: chip.primary ? Font.DemiBold : Font.Normal
                anchors.verticalCenter: parent.verticalCenter
            }

            Item {
                visible: chip.chevron
                width: Style.space(8)
                height: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                rotation: chip.chevronOpen ? 180 : 0

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeWidth: 1.4
                        strokeColor: root.muted
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        startX: 1
                        startY: 2.2

                        PathLine {
                            x: 4
                            y: 5.6
                        }

                        PathLine {
                            x: 7
                            y: 2.2
                        }

                    }

                }

                Behavior on rotation {
                    NumberAnimation {
                        duration: 160
                        easing.type: Easing.OutCubic
                    }

                }

            }

        }

        MouseArea {
            id: area

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: chip.armed || !chip.primary ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (!chip.primary || chip.armed) {
                    chip.tapped();
                }
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: 140
                easing.type: Easing.OutCubic
            }

        }

        Behavior on scale {
            NumberAnimation {
                duration: 120
                easing.type: Easing.OutCubic
            }

        }

    }

}
