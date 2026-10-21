import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Compact RAM + CPU + iGPU + dGPU temps, in that order.
// All values share one color: bar foreground, escalating to bar urgent when
// memory or any temperature crosses its threshold.
// Left click opens btop; middle click refreshes immediately.
BarWidget {
  id: root
  moduleName: "aditya.ram"

  readonly property real warnPercent: 90
  readonly property real warnTemp: 85
  readonly property string pluginDir: {
    var s = Qt.resolvedUrl(".").toString()
    if (s.indexOf("file://") === 0) s = s.substring(7)
    return s
  }

  property real percent: -1
  property real usedKb: 0
  property real totalKb: 0
  property real cpuTemp: -1
  property real igpuTemp: -1
  property real dgpuTemp: -1

  readonly property bool ready: percent >= 0 && totalKb > 0
  readonly property bool high: ready && (percent >= warnPercent || cpuTemp >= warnTemp || igpuTemp >= warnTemp || dgpuTemp >= warnTemp)
  readonly property color valueColor: root.high
    ? (root.bar ? root.bar.urgent : Color.urgent)
    : (root.bar ? root.bar.barForeground : Color.foreground)
  readonly property string usedLabel: ready ? formatGb(usedKb) : "—"
  readonly property string cpuLabel: cpuTemp >= 0 ? Math.round(cpuTemp) + "°C" : "—"
  readonly property string igpuLabel: igpuTemp >= 0 ? Math.round(igpuTemp) + "°C" : "—"
  readonly property string dgpuLabel: dgpuTemp >= 0 ? Math.round(dgpuTemp) + "°C" : "—"

  function formatGb(kb) {
    var gb = kb / 1024 / 1024
    if (gb >= 10) return gb.toFixed(0) + "GB"
    return gb.toFixed(1) + "GB"
  }

  function refresh() {
    if (!proc.running) proc.running = true
  }

  function applyStats(raw, exitCode) {
    if (exitCode !== 0) return
    var parts = String(raw || "").trim().split("\t")
    if (parts.length < 6) return
    var nextPercent = Number(parts[0])
    var nextUsed = Number(parts[1])
    var nextTotal = Number(parts[2])
    var nextCpu = Number(parts[3])
    var nextIgpu = Number(parts[4])
    var nextDgpu = Number(parts[5])
    if (!isFinite(nextPercent) || !isFinite(nextUsed) || !isFinite(nextTotal) || nextTotal <= 0)
      return
    percent = nextPercent
    usedKb = nextUsed
    totalKb = nextTotal
    if (isFinite(nextCpu)) cpuTemp = nextCpu
    if (isFinite(nextIgpu)) igpuTemp = nextIgpu
    if (isFinite(nextDgpu)) dgpuTemp = nextDgpu
  }

  visible: ready
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: proc
    command: ["bash", root.pluginDir + "stats.sh"]
    stdout: StdioCollector {
      id: stdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.applyStats(stdout.text, exitCode)
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
    fontSize: Style.font.body
    horizontalMargin: 6
    verticalPadding: 4
    tooltipText: ""
    active: root.high
    fixedWidth: root.vertical ? -1 : content.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: root.vertical ? content.implicitHeight + scaledVerticalPadding * 2 : -1

    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        root.refresh()
        return
      }
      if (root.bar) root.bar.run("omarchy launch or focus tui btop")
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: 6

      Text {
        text: root.usedLabel
        color: root.valueColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      Text {
        text: root.cpuLabel
        color: root.valueColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      Text {
        text: root.igpuLabel
        color: root.valueColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }

      Text {
        text: root.dgpuLabel
        color: root.valueColor
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
      }
    }
  }
}
