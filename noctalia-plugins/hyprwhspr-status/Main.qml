import QtQuick
import Quickshell
import Quickshell.Io

// Shared singleton-style state for the hyprwhspr-rs status indicator.
// Watches the JSON status file the daemon writes for its waybar module and
// re-parses on every change so BarWidget.qml can bind reactively.
Item {
  id: root

  property var pluginApi: null

  // Daemon writes here regardless of waybar being installed. Falls back to
  // $HOME/.cache if XDG_CACHE_HOME is unset (matches XDG base-dir spec).
  readonly property string cacheHome: Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
  readonly property string statusPath: cacheHome + "/hyprwhspr-rs/status.json"

  // Reactive state — read by BarWidget.qml via pluginApi.mainInstance.
  property string iconText: "󰍭"
  property string tooltip: "hyprwhspr-rs not running"
  property string cls: "missing"

  property FileView statusFile: FileView {
    path: root.statusPath
    watchChanges: true
    printErrors: false

    onFileChanged: reload()
    onLoaded: root.parseStatus(text())
    onLoadFailed: {
      root.iconText = "󰍭"
      root.tooltip = "hyprwhspr-rs not running"
      root.cls = "missing"
    }
  }

  function parseStatus(s) {
    try {
      const o = JSON.parse(s)
      root.iconText = o.text || "󰍭"
      root.tooltip = o.tooltip || ""
      root.cls = o["class"] || "inactive"
    } catch (e) {
      root.cls = "error"
    }
  }
}
