import QtQuick
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "aditya.grayscale"

  property bool grayscale: false

  implicitWidth: indicator.implicitWidth
  implicitHeight: indicator.implicitHeight

  function refresh() {
    if (statusProc.running) return
    statusProc.running = true
  }

  function toggle() {
    if (toggleProc.running) return
    toggleProc.running = true
  }

  Component.onCompleted: refresh()
  onBarChanged: refresh()

  IpcHandler {
    target: "grayscale"

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
    command: ["omarchy-toggle-grayscale", "--enabled"]
    onExited: function(exitCode) {
      root.grayscale = exitCode === 0
    }
  }

  Process {
    id: toggleProc
    command: ["omarchy-toggle-grayscale"]
    onExited: function() {
      root.refresh()
    }
  }

  BarIndicator {
    id: indicator
    anchors.centerIn: parent
    bar: root.bar
    moduleName: root.moduleName
    active: root.grayscale
    activeText: "󰏘"
    inactiveText: "󰏘"
    activeTooltipText: "Color"
    inactiveTooltipText: "Grayscale"
    onPressed: function() { root.toggle() }
  }
}
