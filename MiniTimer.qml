import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// The always-on-top timer: a small readout that floats above every window,
// fullscreen ones included, on the overlay layer. It never takes keyboard
// focus. Drag it anywhere; it remembers where. Click it to open the toaster,
// middle-click (or the x) to put it away.
//
// Panel.qml owns all state and passes itself in as `owner`.
PanelWindow {
  id: win

  required property var owner
  property bool shown: false

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  readonly property string fontFamily: owner.bar ? owner.bar.fontFamily : Style.font.family
  readonly property bool barVertical: owner.bar ? owner.bar.vertical : false
  readonly property int barSize: owner.bar ? owner.bar.barSize : 0

  // Position is the card's top-left corner in logical pixels, measured from
  // the area the bar leaves free. -1 in the settings means "default spot":
  // the top-right corner.
  readonly property real edge: 16
  readonly property real maxX: screen ? Math.max(0, screen.width - card.width - (barVertical ? barSize : 0)) : 0
  readonly property real maxY: screen ? Math.max(0, screen.height - card.height - (barVertical ? 0 : barSize)) : 0
  readonly property real savedX: owner.cfg.miniX >= 0 ? owner.cfg.miniX : maxX - edge
  readonly property real savedY: owner.cfg.miniY >= 0 ? owner.cfg.miniY : edge
  property bool dragging: false
  property real dragX: 0
  property real dragY: 0
  readonly property real posX: clamp(dragging ? dragX : savedX, 0, maxX)
  readonly property real posY: clamp(dragging ? dragY : savedY, 0, maxY)

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

  visible: shown
  color: "transparent"
  anchors { top: true; left: true }
  margins { top: Math.round(win.posY); left: Math.round(win.posX) }
  implicitWidth: card.width
  implicitHeight: card.height
  // Stay clear of the bar, but don't push windows around.
  exclusionMode: ExclusionMode.Normal
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  WlrLayershell.namespace: "omarchy-pomodoro-timer"

  // Grow in where it appears instead of popping.
  property bool revealed: false
  onVisibleChanged: {
    revealed = false
    if (visible) Qt.callLater(function() { win.revealed = win.visible })
  }

  readonly property string caption: {
    if (owner.focusing) return owner.locked ? strings.t("mini.focusLocked").arg(owner.workspaceName) : strings.t("mini.focus")
    if (owner.phase === "long") return strings.t("mini.longBreak")
    if (owner.onBreak) return strings.t("mini.break")
    return strings.t("mini.ready")
  }

  Rectangle {
    id: card
    width: 212
    height: 64
    radius: 16
    opacity: win.revealed ? 1 : 0
    scale: win.revealed ? 1 : 0.97
    Behavior on opacity { NumberAnimation { duration: Style.duration(180); easing.type: Easing.OutCubic } }
    Behavior on scale {
      NumberAnimation { duration: Style.duration(180); easing.type: Easing.Bezier; easing.bezierCurve: Style.easeOut }
    }
    gradient: Gradient {
      GradientStop { position: 0; color: win.owner.enamelTop }
      GradientStop { position: 1; color: win.owner.enamelBottom }
    }
    border.width: 1
    border.color: Qt.rgba(0, 0, 0, 0.5)

    // Drag to move, click to open the toaster, middle-click to hide. Sits
    // under the buttons so they still get their own clicks.
    MouseArea {
      id: dragArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.MiddleButton
      cursorShape: win.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      property real pressX: 0
      property real pressY: 0

      onPressed: function(mouse) {
        pressX = mouse.x
        pressY = mouse.y
        win.dragX = win.posX
        win.dragY = win.posY
      }
      onPositionChanged: function(mouse) {
        if (!(pressedButtons & Qt.LeftButton)) return
        // The surface moves under the pointer, so each event's offset from
        // the press point is the distance since the last one.
        var dx = mouse.x - pressX
        var dy = mouse.y - pressY
        if (!win.dragging && Math.abs(dx) + Math.abs(dy) < 4) return
        win.dragging = true
        win.dragX = win.clamp(win.dragX + dx, 0, win.maxX)
        win.dragY = win.clamp(win.dragY + dy, 0, win.maxY)
      }
      onReleased: function(mouse) {
        if (win.dragging) {
          win.owner.setValues({ miniX: Math.round(win.dragX), miniY: Math.round(win.dragY) })
          win.dragging = false
        } else if (mouse.button === Qt.MiddleButton) {
          win.owner.setMini(false)
        } else {
          win.owner.toggle()
        }
      }
      onCanceled: win.dragging = false
    }

    // readout window
    Rectangle {
      id: readout
      x: 6
      y: 6
      width: parent.width - 12 - strip.width - 4
      height: parent.height - 12
      radius: 11
      gradient: Gradient {
        GradientStop { position: 0; color: "#060607" }
        GradientStop { position: 1; color: "#1a1b1e" }
      }
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.14)

      Row {
        anchors.verticalCenter: parent.verticalCenter
        x: 10
        spacing: 10

        Canvas {
          id: pie
          width: 30
          height: 30
          anchors.verticalCenter: parent.verticalCenter
          property real pieLeft: win.owner.running ? 1 - win.owner.progress : 0
          property color hi: win.owner.phaseColor
          onPieLeftChanged: requestPaint()
          onHiChanged: requestPaint()
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var c = width / 2, r = width / 2 - 2
            ctx.lineWidth = 2
            ctx.strokeStyle = "rgba(255,181,71,0.55)"
            ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.stroke()
            if (pieLeft > 0) {
              ctx.fillStyle = hi
              ctx.beginPath()
              ctx.moveTo(c, c)
              ctx.arc(c, c, r - 3, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * pieLeft)
              ctx.closePath()
              ctx.fill()
            }
          }
        }

        Column {
          anchors.verticalCenter: parent.verticalCenter
          spacing: 0
          Text {
            textFormat: Text.PlainText
            text: win.owner.running ? win.owner.clock(win.owner.remaining)
                                    : win.owner.clock((win.owner.cfg.focus || 25) * 60)
            color: win.owner.running ? win.owner.amber : Qt.rgba(1, 0.71, 0.28, 0.4)
            font.family: win.fontFamily
            font.pixelSize: 24
            font.bold: true
            font.letterSpacing: 2
            font.features: { "tnum": 1 }
          }
          Text {
            textFormat: Text.PlainText
            text: win.caption.toUpperCase()
            color: win.owner.focusing ? Qt.rgba(1, 0.35, 0.29, 0.85) : Qt.rgba(1, 0.71, 0.28, 0.6)
            font.family: win.fontFamily
            font.pixelSize: 8
            font.letterSpacing: 1.4
          }
        }
      }
    }

    // hide / start-or-open, down the right edge
    Column {
      id: strip
      width: 22
      anchors.right: parent.right
      anchors.rightMargin: 5
      anchors.verticalCenter: parent.verticalCenter
      spacing: 4

      MiniButton {
        glyph: "󰅖"
        onClicked: win.owner.setMini(false)
      }
      MiniButton {
        glyph: win.owner.running ? "󰁌" : "󰐊"
        enabled: !win.owner.busy
        onClicked: win.owner.running ? win.owner.open() : win.owner.startFocus()
      }
    }
  }

  component MiniButton: Rectangle {
    id: btn
    property string glyph: ""
    signal clicked()
    width: 22
    height: 22
    radius: 11
    color: btnArea.pressed ? Qt.rgba(0, 0, 0, 0.35) : btnArea.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : "transparent"
    opacity: !enabled ? 0.3 : (dragArea.containsMouse || btnArea.containsMouse) ? 1 : 0.55
    Behavior on opacity { NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic } }
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: btn.glyph
      color: win.owner.engraved
      font.family: win.fontFamily
      font.pixelSize: 13
    }
    MouseArea {
      id: btnArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }
}
