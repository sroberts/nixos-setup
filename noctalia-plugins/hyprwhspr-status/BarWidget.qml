import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  // Injected by Noctalia's BarWidgetLoader.
  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""
  property int sectionWidgetIndex: -1
  property int sectionWidgetsCount: 0

  readonly property string screenName: screen ? screen.name : ""
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)

  readonly property var mainInstance: pluginApi?.mainInstance
  readonly property string cls: mainInstance?.cls || "missing"
  readonly property string iconText: mainInstance?.iconText || "󰍭"
  readonly property string tooltipText: mainInstance?.tooltip || ""

  readonly property var stateColorKey: ({
    "inactive":   "onSurfaceVariant",
    "active":     "error",
    "processing": "primary",
    "error":      "error",
    "missing":    "onSurfaceVariant"
  })

  implicitWidth: capsuleHeight
  implicitHeight: capsuleHeight

  Rectangle {
    id: visualCapsule
    x: Style.pixelAlignCenter(parent.width, width)
    y: Style.pixelAlignCenter(parent.height, height)
    width: root.implicitWidth
    height: root.implicitHeight
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
    radius: Style.radiusM
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth
    opacity: root.cls === "missing" ? 0.4 : 1.0

    NText {
      id: glyph
      anchors.centerIn: parent
      text: root.iconText
      color: mouseArea.containsMouse
             ? Color.mOnHover
             : Color.resolveColorKey(root.stateColorKey[root.cls] || "onSurfaceVariant")
      pointSize: root.barFontSize

      // Pulse only during transcription so it's visually distinct from a
      // steady red "recording" state. Driven via target/property so onStopped
      // can snap opacity back to 1.0 when the animation halts mid-fade.
      SequentialAnimation {
        id: pulseAnim
        target: glyph
        property: "opacity"
        running: root.cls === "processing"
        loops: Animation.Infinite
        alwaysRunToEnd: false
        NumberAnimation { from: 1.0; to: 0.35; duration: 600 }
        NumberAnimation { from: 0.35; to: 1.0; duration: 600 }
        onStopped: glyph.opacity = 1.0
      }
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor

    onEntered: TooltipService.show(root,
                                   root.tooltipText,
                                   BarService.getTooltipDirection(root.screenName))
    onExited: TooltipService.hide()
    onClicked: Quickshell.execDetached(["hyprwhspr-rs", "record", "toggle"])
  }
}
