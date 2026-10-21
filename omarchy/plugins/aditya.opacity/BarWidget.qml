import QtQuick
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "aditya.opacity"

  property bool opaque: false

  readonly property string pluginDir: {
    var s = Qt.resolvedUrl(".").toString()
    if (s.indexOf("file://") === 0)
      s = s.substring(7)
    return s
  }

  implicitWidth: indicator.implicitWidth
  implicitHeight: indicator.implicitHeight

  function refresh() {
    if (statusProc.running)
      return
    statusProc.running = true
  }

  function toggle() {
    if (toggleProc.running)
      return
    toggleProc.running = true
  }

  Component.onCompleted: refresh()
  onBarChanged: refresh()

  IpcHandler {
    target: "opaque"

    function refresh(): void {
      root.broadcast("refresh")
    }

    function toggle(): string {
      root.toggle()
      return "toggled"
    }
  }

  Process {
    id: statusProc
    command: [root.pluginDir + "toggle.sh", "--enabled"]
    onExited: function(exitCode) {
      root.opaque = exitCode === 0
    }
  }

  Process {
    id: toggleProc
    command: [root.pluginDir + "toggle.sh"]
    onExited: function() {
      root.refresh()
    }
  }

  // BarIndicator hides itself while inactive, which would make the off state unclickable.
  BarIconButton {
    id: indicator
    anchors.centerIn: parent
    bar: root.bar
    text: "󰗌"
    tooltipText: root.opaque ? "Transparent" : "Opaque"
    active: root.opaque
    useActiveColor: root.opaque
    dimmed: !root.opaque
    concealed: false
    interactive: true
    onPressed: function() { root.toggle() }
  }
}
