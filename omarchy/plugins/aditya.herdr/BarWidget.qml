import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Herdr status light: one dot, colored by the most urgent agent state.
//
//   red    blocked (needs you)
//   yellow working
//   green  idle / done
//   dim    server unreachable
//
// Status colors follow the active Omarchy theme. The shell's Color singleton
// only carries the foundational palette (urgent = theme red), so yellow and
// green are read from the theme's colors.toml directly.
BarWidget {
  id: root
  moduleName: "aditya.herdr"

  readonly property real dotSize: 10

  // Agents per status, e.g. counts.blocked; rebuilt on every poll.
  property var counts: ({})
  property bool online: false
  // red/yellow/green from the active theme's colors.toml.
  property var themeColors: ({})

  // First status with agents wins the dot's color.
  readonly property var priority: ["blocked", "working", "unknown"]
  readonly property var displayOrder: ["blocked", "working", "idle", "unknown"]
  readonly property var stateColors: ({
    blocked: themeColors.red || Color.urgent,
    working: themeColors.yellow || "#ffbd2e",
    unknown: themeColors.yellow || "#ffbd2e",
    idle: themeColors.green || "#27c93f"
  })

  readonly property string activeState: {
    for (var i = 0; i < priority.length; i++)
      if ((counts[priority[i]] || 0) > 0) return priority[i]
    return "idle"
  }
  readonly property color lightColor: online ? stateColors[activeState] : Color.muted
  readonly property real lightOpacity: online ? 1 : 0.35
  readonly property string tooltipText: {
    if (!online) return "Herdr offline"
    var parts = []
    for (var i = 0; i < displayOrder.length; i++) {
      var n = counts[displayOrder[i]] || 0
      if (n > 0) parts.push(n + " " + displayOrder[i])
    }
    return parts.length ? "Herdr: " + parts.join(" · ") : "Herdr idle"
  }

  function applyThemeColors(raw) {
    var colors = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var m = lines[i].match(/^\s*(red|yellow|green)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (m) colors[m[1]] = m[2]
    }
    themeColors = colors
  }

  function refresh() {
    if (!listProc.running) listProc.running = true
  }

  function applyList(raw, exitCode) {
    if (exitCode !== 0) {
      online = false
      return
    }
    try {
      var agents = JSON.parse(String(raw || "").trim()).result.agents || []
      var tally = {}
      for (var i = 0; i < agents.length; i++) {
        var status = String(agents[i].agent_status || "unknown")
        if (status === "done") status = "idle"
        tally[status] = (tally[status] || 0) + 1
      }
      counts = tally
      online = true
    } catch (e) {
      online = false
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: listProc
    command: ["herdr", "agent", "list"]
    stdout: StdioCollector {
      id: listStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.applyList(listStdout.text, exitCode)
    }
  }

  FileView {
    id: themeColorsFile
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.applyThemeColors(text())
    onLoadFailed: root.applyThemeColors("")
  }

  // A theme switch swaps the `current` symlink, so watch its parent
  // directory; a watch on the file itself would trail a stale inode.
  FileView {
    path: Color.stateHome + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: themeColorsFile.reload()
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

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (root.bar) root.bar.run("bash ~/.config/omarchy/plugins/aditya.herdr/focus-herdr")
    }

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
