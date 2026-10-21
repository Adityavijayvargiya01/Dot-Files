import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "verbs.js" as Verbs

// Traffic-light for coding agents. Harness-agnostic: Pi, OpenCode, and OMP write
// the same status files; collect-status also folds in other Herdr agents.
//
//   red    blocked (needs you)
//   yellow working / unknown
//   green  idle / done
//   dim    the other two lamps, or all three when offline
//
// Lamps keep their capsule. A second shell wraps that capsule and the verb.
// Hover lists running agents. A left click while red focuses the blocked one.
BarWidget {
  id: root
  moduleName: "aditya.herdr"

  readonly property real dotSize: 12
  readonly property real dotGap: 4
  readonly property real cluster: dotSize * 3 + dotGap * 2
  readonly property real lampInset: 4
  readonly property real lampW: vertical ? dotSize + lampInset * 2 : cluster + lampInset * 2
  readonly property real lampH: vertical ? cluster + lampInset * 2 : dotSize + lampInset * 2
  readonly property real frameInset: 4
  readonly property real frameW: {
    if (vertical || verbWidth <= 0) return lampW
    return frameInset * 2 + verbWidth + verbGap + lampW
  }
  readonly property real frameH: {
    if (vertical || verbWidth <= 0) return lampH
    return Math.max(lampH, verbText.implicitHeight) + frameInset * 2
  }
  readonly property color shellFill: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.1)
  readonly property color shellBorder: Qt.rgba(Color.foreground.r, Color.foreground.g, Color.foreground.b, 0.24)
  readonly property color plate: bar ? bar.background : Color.background
  readonly property real verbGap: 6
  readonly property var lamps: [
    { key: "blocked", color: "#ff5f56" },
    { key: "working", color: "#ffbd2e" },
    { key: "idle", color: "#27c93f" }
  ]
  readonly property string pluginDir: {
    var s = Qt.resolvedUrl(".").toString()
    if (s.indexOf("file://") === 0) s = s.substring(7)
    return s
  }

  property var counts: ({})
  property bool online: false
  property string verb: ""
  property var agents: []
  property string lastFocusId: ""
  property bool trayHold: false

  readonly property var priority: ["blocked", "working", "unknown"]
  readonly property var displayOrder: ["blocked", "working", "idle", "unknown"]

  readonly property string activeState: {
    for (var i = 0; i < priority.length; i++)
      if ((counts[priority[i]] || 0) > 0) return priority[i]
    return "idle"
  }
  function lampOn(key) {
    if (!online) return false
    if (key === "working") return activeState === "working" || activeState === "unknown"
    return activeState === key
  }

  readonly property bool spinning: lampOn("working")
  readonly property color verbColor: Color.accent
  readonly property real verbWidth: spinning && !vertical ? verbText.implicitWidth : 0
  readonly property real rowWidth: frameW
  readonly property bool trayOpen: (trayHold || agentTray.containsMouse) && agents.length > 0

  function stateColor(state) {
    if (state === "blocked") return "#ff5f56"
    if (state === "idle") return "#27c93f"
    return "#ffbd2e"
  }

  function focusAgent(agent) {
    if (!agent) return
    focusProc.command = [root.pluginDir + "focus-agent", JSON.stringify({
      id: agent.id || "",
      source: agent.source || "",
      pid: agent.pid || 0
    })]
    if (!focusProc.running) focusProc.running = true
  }

  function focusBlocked() {
    var blocked = []
    for (var i = 0; i < agents.length; i++)
      if (agents[i] && agents[i].state === "blocked") blocked.push(agents[i])
    if (!blocked.length) return
    var start = 0
    for (var j = 0; j < blocked.length; j++) {
      if (blocked[j].id === lastFocusId) {
        start = (j + 1) % blocked.length
        break
      }
    }
    lastFocusId = blocked[start].id
    focusAgent(blocked[start])
  }

  function nextVerb() {
    verb = Verbs.pick(verb)
  }

  Component.onCompleted: nextVerb()

  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  function applyList(raw, exitCode) {
    if (exitCode !== 0) {
      online = false
      counts = ({})
      agents = []
      return
    }
    try {
      var data = JSON.parse(String(raw || "").trim())
      counts = data.counts || ({})
      agents = data.agents || []
      online = !!data.online
    } catch (e) {
      online = false
      counts = ({})
      agents = []
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: listProc
    command: [root.pluginDir + "collect-status"]
    stdout: StdioCollector {
      id: listStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.applyList(listStdout.text, exitCode)
    }
  }

  Process {
    id: focusProc
  }

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 8000
    repeat: true
    running: root.spinning
    onTriggered: root.nextVerb()
  }

  Timer {
    id: trayClose
    interval: 220
    repeat: true
    running: root.trayHold
    onTriggered: {
      // trayHold bridges the gap between the button and the popup. Once the
      // pointer leaves both, drop it so the popup cannot stay latched open.
      if (!buttonHover.hovered && !agentTray.containsMouse)
        root.trayHold = false
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    tooltipText: ""
    pressable: (root.counts.blocked || 0) > 0
    horizontalMargin: 4
    verticalPadding: 4
    fixedWidth: root.vertical ? -1 : root.rowWidth + 8
    fixedHeight: root.vertical ? root.frameH + 8 : -1
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.focusBlocked()
    }

    HoverHandler {
      id: buttonHover
      onHoveredChanged: {
        if (hovered)
          root.trayHold = true
      }
    }

    Item {
      id: content
      anchors.centerIn: parent
      width: root.frameW
      height: root.frameH

      Rectangle {
        visible: root.verbWidth > 0
        anchors.fill: parent
        radius: 8
        color: root.plate
        border.width: 1
        border.color: root.shellBorder
      }

      Text {
        id: verbText
        visible: root.verbWidth > 0
        opacity: 1
        x: root.frameInset
        anchors.verticalCenter: parent.verticalCenter
        text: root.verb
        color: root.verbColor
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.QtRendering
      }

      Item {
        opacity: 1
        x: root.vertical ? 0 : (root.verbWidth > 0 ? root.frameInset + root.verbWidth + root.verbGap : 0)
        y: root.vertical ? 0 : (root.frameH - root.lampH) / 2
        width: root.lampW
        height: root.lampH

        Rectangle {
          anchors.fill: parent
          radius: 6
          color: root.plate
        }
        Rectangle {
          anchors.fill: parent
          radius: 6
          color: root.shellFill
          border.width: 1
          border.color: root.shellBorder
        }

        Repeater {
          model: root.lamps
          Rectangle {
            required property int index
            required property var modelData
            width: root.dotSize
            height: root.dotSize
            radius: width / 2
            x: root.vertical ? root.lampInset : root.lampInset + index * (root.dotSize + root.dotGap)
            y: root.vertical
              ? root.lampInset + index * (root.dotSize + root.dotGap)
              : root.lampInset
            color: modelData.color
            opacity: root.lampOn(modelData.key) ? 1 : 0.28

            Behavior on opacity {
              NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
            }
          }
        }
      }
    }
  }

  PopupCard {
    id: agentTray
    anchorItem: button
    bar: root.bar
    triggerMode: "hover"
    margin: 0
    padding: 10
    open: root.trayOpen
    contentWidth: Math.max(148, agentColumn.implicitWidth + 20)
    contentHeight: Math.max(36, agentColumn.implicitHeight + 20)

    Column {
      id: agentColumn
      spacing: 8

      Repeater {
        model: root.agents
        Item {
          required property var modelData
          width: agentRow.implicitWidth
          height: 18

          Row {
            id: agentRow
            spacing: 8
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              width: 10
              height: 10
              radius: 5
              anchors.verticalCenter: parent.verticalCenter
              color: root.stateColor(modelData.state)
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label || modelData.harness || modelData.id || "agent"
              color: root.bar ? root.bar.barForeground : Color.foreground
              font.family: button.fontFamily
              font.pixelSize: Style.font.body
              renderType: Text.QtRendering
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.focusAgent(modelData)
          }
        }
      }
    }
  }
}
