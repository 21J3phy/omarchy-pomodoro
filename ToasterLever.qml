import QtQuick
import qs.Commons

// The toaster's carriage lever. Push it down (drag or click) to start; it stays
// down while the timer runs and pops up when the timer is done. Pulling it up
// while it's down asks to stop. `locked` pins it down (strict mode).
Item {
  id: lever

  property bool down: false
  property bool locked: false
  property string fontFamily: Style.font.family
  property color glow: "#d8433b"

  signal pushed()
  signal pulled()

  implicitWidth: 64
  implicitHeight: 220

  readonly property real handleH: 34
  readonly property real inset: 10
  readonly property real travel: Math.max(0, height - handleH - inset * 2)
  property real dragY: -1
  readonly property real restY: down ? travel : 0
  readonly property real handleY: dragY >= 0 ? dragY : restY

  // The slot in the side of the toaster.
  Rectangle {
    id: slot
    anchors.horizontalCenter: parent.horizontalCenter
    y: lever.inset + lever.handleH / 2 - width / 2
    width: 12
    height: lever.travel + width
    radius: width / 2
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: "#050506" }
      GradientStop { position: 0.6; color: "#1b1d21" }
      GradientStop { position: 1; color: "#3a3d43" }
    }
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)

    // A warm glow down the slot while it's toasting.
    Rectangle {
      anchors.fill: parent
      anchors.margins: 3
      radius: width / 2
      color: lever.glow
      opacity: lever.down ? 0.55 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(240); easing.type: Easing.OutCubic } }
    }
  }

  // The handle.
  Item {
    id: handle
    x: 0
    width: parent.width
    height: lever.handleH
    y: lever.inset + lever.handleY
    Behavior on y {
      enabled: lever.dragY < 0
      NumberAnimation { duration: Style.duration(lever.down ? 220 : 140); easing.type: Easing.OutCubic }
    }

    Rectangle {  // shadow
      x: 2; y: 4
      width: parent.width; height: parent.height
      radius: 9
      color: Qt.rgba(0, 0, 0, 0.4)
    }
    Rectangle {
      anchors.fill: parent
      radius: 9
      gradient: Gradient {
        GradientStop { position: 0; color: "#fdfdfe" }
        GradientStop { position: 0.45; color: "#c4c9cf" }
        GradientStop { position: 0.55; color: "#9aa0a8" }
        GradientStop { position: 1; color: "#e3e6ea" }
      }
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.35)
    }
    // finger groove
    Rectangle {
      anchors.centerIn: parent
      width: parent.width - 18
      height: 4
      radius: 2
      color: Qt.rgba(0, 0, 0, 0.18)
      visible: !lever.locked
    }
    Text {
      anchors.centerIn: parent
      visible: lever.locked
      textFormat: Text.PlainText
      text: "󰌾"
      color: "#3b3f45"
      font.family: lever.fontFamily
      font.pixelSize: 16
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: !lever.locked
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ForbiddenCursor
    property real grabOffset: 0
    property real pressY: 0
    property bool moved: false

    onPressed: function(e) {
      pressY = e.y
      moved = false
      grabOffset = e.y - (lever.inset + lever.restY)
    }
    onPositionChanged: function(e) {
      if (!pressed) return
      if (Math.abs(e.y - pressY) > 4) moved = true
      if (moved) lever.dragY = Math.max(0, Math.min(lever.travel, e.y - grabOffset - lever.inset))
    }
    onReleased: {
      var y = lever.dragY
      lever.dragY = -1
      if (!moved) {
        lever.down ? lever.pulled() : lever.pushed()
      } else if (!lever.down && y > lever.travel * 0.6) {
        lever.pushed()
      } else if (lever.down && y < lever.travel * 0.4) {
        lever.pulled()
      }
    }
  }
}
