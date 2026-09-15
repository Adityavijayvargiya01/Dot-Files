import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Traffic-light for coding agents. Harness-agnostic: Pi and OpenCode write
// the same status files, collect-status also folds in other Herdr agents.
//
//   red    blocked (needs you)
//   yellow working
//   green  idle / done
//   dim    no live reporters and Herdr unreachable
//
// Colors are fixed traffic-light red / yellow / green, not the Omarchy theme.
BarWidget {
  id: root
  moduleName: "aditya.herdr"

  readonly property real dotSize: 10
  readonly property string pluginDir: {
    var s = Qt.resolvedUrl(".").toString()
    if (s.indexOf("file://") === 0) s = s.substring(7)
    return s
  }

  // Agents per status, e.g. counts.blocked; rebuilt on every poll.
  property var counts: ({})
  property bool online: false

  // First status with agents wins the dot's color.
  readonly property var priority: ["blocked", "working", "unknown"]
  readonly property var displayOrder: ["blocked", "working", "idle", "unknown"]
  readonly property var stateColors: ({
    blocked: "#ff5f56",
    working: "#ffbd2e",
    unknown: "#ffbd2e",
    idle: "#27c93f"
  })

  readonly property string activeState: {
    for (var i = 0; i < priority.length; i++)
      if ((counts[priority[i]] || 0) > 0) return priority[i]
    return "idle"
  }
  readonly property color lightColor: online ? stateColors[activeState] : Color.muted
  readonly property real lightOpacity: online ? 1 : 0.35
  readonly property string tooltipText: {
    if (!online) return "Agents offline"
    var parts = []
    for (var i = 0; i < displayOrder.length; i++) {
      var n = counts[displayOrder[i]] || 0
      if (n > 0) parts.push(n + " " + displayOrder[i])
    }
    return parts.length ? "Agents: " + parts.join(" · ") : "Agents idle"
  }

  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  function applyList(raw, exitCode) {
    if (exitCode !== 0) {
      online = false
      counts = ({})
      return
    }
    try {
      var data = JSON.parse(String(raw || "").trim())
      counts = data.counts || ({})
      online = !!data.online
    } catch (e) {
      online = false
      counts = ({})
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

  Timer {
    interval: 2000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    labelVisible: false
    hasVisualContent: true
    tooltipText: root.tooltipText
    horizontalMargin: 6
    verticalPadding: 4
    fixedWidth: root.vertical ? -1 : Style.bar.iconSlot
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1

    Rectangle {
      anchors.centerIn: parent
      width: root.dotSize
      height: root.dotSize
      radius: width / 2
      color: root.lightColor
      opacity: root.lightOpacity

      Behavior on color {
        ColorAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
      Behavior on opacity {
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
      }
    }
  }
}
