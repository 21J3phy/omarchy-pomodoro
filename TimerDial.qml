import QtQuick
import qs.Commons

// A mechanical kitchen-timer dial. The cream face carries the minutes and
// turns under a fixed red pointer, so the number under the pointer is the time
// left. Twist it clockwise (drag or scroll) to wind it while it's idle; it
// unwinds back toward zero as the timer runs.
Item {
  id: dial

  property real minutes: 0            // value under the pointer; may be fractional
  property bool interactive: false
  property string fontFamily: Style.font.family
  property color pointerColor: "#d8433b"
  property int maxMinutes: 60

  signal wound(int minutes)           // the user let go after winding

  property real dragMinutes: -1
  readonly property real shown: Math.max(0, Math.min(maxMinutes, dragMinutes >= 0 ? dragMinutes : minutes))
  readonly property real r: Math.min(width, height) / 2

  implicitWidth: 240
  implicitHeight: 240

  // Drop shadow, chrome bezel and the well the face sits in. Static.
  Canvas {
    id: bezel
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var c = width / 2, R = dial.r
      // soft shadow on the enamel
      var sh = ctx.createRadialGradient(c, c + R * 0.06, R * 0.80, c, c + R * 0.06, R)
      sh.addColorStop(0, "rgba(0,0,0,0.45)")
      sh.addColorStop(1, "rgba(0,0,0,0)")
      ctx.fillStyle = sh
      ctx.beginPath(); ctx.arc(c, c + R * 0.04, R, 0, Math.PI * 2); ctx.fill()
      // brushed chrome ring
      var ring = ctx.createConicalGradient(c, c, Math.PI / 4)
      var stops = ["#f4f6f8", "#8a9099", "#e9ecef", "#5d636c", "#f7f8fa", "#7d838c", "#dfe3e7", "#646a73", "#f4f6f8"]
      for (var i = 0; i < stops.length; i++) ring.addColorStop(i / (stops.length - 1), stops[i])
      ctx.fillStyle = ring
      ctx.beginPath(); ctx.arc(c, c, R * 0.93, 0, Math.PI * 2); ctx.fill()
      // bevel edges
      ctx.lineWidth = 1.2
      ctx.strokeStyle = "rgba(255,255,255,0.55)"
      ctx.beginPath(); ctx.arc(c, c, R * 0.93 - 0.6, Math.PI * 1.05, Math.PI * 1.95); ctx.stroke()
      ctx.strokeStyle = "rgba(0,0,0,0.45)"
      ctx.beginPath(); ctx.arc(c, c, R * 0.93 - 0.6, Math.PI * 0.05, Math.PI * 0.95); ctx.stroke()
      // recessed well
      var well = ctx.createLinearGradient(0, c - R * 0.82, 0, c + R * 0.82)
      well.addColorStop(0, "#2a2c30")
      well.addColorStop(1, "#6d727a")
      ctx.fillStyle = well
      ctx.beginPath(); ctx.arc(c, c, R * 0.82, 0, Math.PI * 2); ctx.fill()
    }
  }

  // The turning face.
  Item {
    id: face
    anchors.fill: parent
    rotation: dial.shown * 360 / dial.maxMinutes
    Behavior on rotation {
      enabled: dial.dragMinutes < 0
      NumberAnimation { duration: Style.duration(260); easing.type: Easing.OutCubic }
    }

    Canvas {
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var c = width / 2, R = dial.r
        var faceR = R * 0.79
        var cream = ctx.createRadialGradient(c - R * 0.25, c - R * 0.3, R * 0.05, c, c, faceR)
        cream.addColorStop(0, "#fffaf0")
        cream.addColorStop(0.7, "#f1e7d2")
        cream.addColorStop(1, "#d9cbb0")
        ctx.fillStyle = cream
        ctx.beginPath(); ctx.arc(c, c, faceR, 0, Math.PI * 2); ctx.fill()

        // The first five minutes are painted red, the "nearly done" zone.
        ctx.strokeStyle = "rgba(216,67,59,0.85)"
        ctx.lineWidth = R * 0.05
        ctx.beginPath()
        ctx.arc(c, c, faceR - R * 0.035, -Math.PI / 2 - Math.PI * 2 * 5 / dial.maxMinutes, -Math.PI / 2)
        ctx.stroke()

        // Minutes run counter-clockwise, so winding clockwise brings them up.
        for (var m = 0; m < dial.maxMinutes; m++) {
          var a = -m * Math.PI * 2 / dial.maxMinutes
          var major = m % 5 === 0
          var r1 = faceR - R * 0.015
          var r0 = faceR - R * (major ? 0.15 : 0.08)
          ctx.strokeStyle = major ? "#2b2622" : "rgba(43,38,34,0.55)"
          ctx.lineWidth = major ? R * 0.022 : R * 0.01
          ctx.lineCap = "round"
          ctx.beginPath()
          ctx.moveTo(c + r0 * Math.sin(a), c - r0 * Math.cos(a))
          ctx.lineTo(c + r1 * Math.sin(a), c - r1 * Math.cos(a))
          ctx.stroke()
          if (major) {
            ctx.save()
            ctx.translate(c + (faceR - R * 0.26) * Math.sin(a), c - (faceR - R * 0.26) * Math.cos(a))
            ctx.rotate(a)
            ctx.fillStyle = m === 0 ? "#c0392b" : "#2b2622"
            ctx.font = "bold " + Math.round(R * 0.12) + "px \"" + dial.fontFamily + "\""
            ctx.textAlign = "center"
            ctx.textBaseline = "middle"
            ctx.fillText(String(m), 0, 0)
            ctx.restore()
          }
        }
      }
    }

    // The knob grip in the middle turns with the face.
    Canvas {
      anchors.fill: parent
      onWidthChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var c = width / 2, R = dial.r
        var kr = R * 0.36
        var sh = ctx.createRadialGradient(c, c + R * 0.05, kr * 0.7, c, c + R * 0.05, kr * 1.25)
        sh.addColorStop(0, "rgba(0,0,0,0.35)")
        sh.addColorStop(1, "rgba(0,0,0,0)")
        ctx.fillStyle = sh
        ctx.beginPath(); ctx.arc(c, c + R * 0.05, kr * 1.25, 0, Math.PI * 2); ctx.fill()
        var knob = ctx.createConicalGradient(c, c, 0.6)
        var stops = ["#fbfcfd", "#9aa0a8", "#eef0f2", "#737982", "#fbfcfd"]
        for (var i = 0; i < stops.length; i++) knob.addColorStop(i / (stops.length - 1), stops[i])
        ctx.fillStyle = knob
        ctx.beginPath(); ctx.arc(c, c, kr, 0, Math.PI * 2); ctx.fill()
        ctx.lineWidth = 1
        ctx.strokeStyle = "rgba(0,0,0,0.35)"
        ctx.stroke()
        // the ridge you'd pinch to twist it
        var gw = R * 0.15, gh = kr * 1.75
        var grip = ctx.createLinearGradient(c - gw / 2, 0, c + gw / 2, 0)
        grip.addColorStop(0, "#5f656e")
        grip.addColorStop(0.35, "#f6f7f9")
        grip.addColorStop(0.65, "#c9cdd3")
        grip.addColorStop(1, "#4d535b")
        ctx.fillStyle = "rgba(0,0,0,0.3)"
        roundRect(ctx, c - gw / 2 + 1.5, c - gh / 2 + 3, gw, gh, gw / 2)
        ctx.fill()
        ctx.fillStyle = grip
        roundRect(ctx, c - gw / 2, c - gh / 2, gw, gh, gw / 2)
        ctx.fill()
        // a little red index on the ridge
        ctx.fillStyle = dial.pointerColor
        ctx.beginPath(); ctx.arc(c, c - gh / 2 + gw * 0.55, gw * 0.18, 0, Math.PI * 2); ctx.fill()
      }

      function roundRect(ctx, x, y, w, h, rad) {
        ctx.beginPath()
        ctx.moveTo(x + rad, y)
        ctx.lineTo(x + w - rad, y)
        ctx.arcTo(x + w, y, x + w, y + rad, rad)
        ctx.lineTo(x + w, y + h - rad)
        ctx.arcTo(x + w, y + h, x + w - rad, y + h, rad)
        ctx.lineTo(x + rad, y + h)
        ctx.arcTo(x, y + h, x, y + h - rad, rad)
        ctx.lineTo(x, y + rad)
        ctx.arcTo(x, y, x + rad, y, rad)
        ctx.closePath()
      }
    }
  }

  // Fixed pointer at twelve o'clock, plus a glass glint over the face.
  Canvas {
    anchors.fill: parent
    onWidthChanged: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var c = width / 2, R = dial.r
      var glint = ctx.createLinearGradient(0, c - R * 0.8, 0, c)
      glint.addColorStop(0, "rgba(255,255,255,0.22)")
      glint.addColorStop(1, "rgba(255,255,255,0)")
      ctx.fillStyle = glint
      ctx.beginPath(); ctx.ellipse(c - R * 0.62, c - R * 0.80, R * 1.24, R * 0.75); ctx.fill()

      var top = c - R * 0.93, tip = c - R * 0.70, w = R * 0.11
      ctx.fillStyle = "rgba(0,0,0,0.35)"
      ctx.beginPath(); ctx.moveTo(c - w + 1, top + 2); ctx.lineTo(c + w + 1, top + 2); ctx.lineTo(c + 1, tip + 2); ctx.closePath(); ctx.fill()
      ctx.fillStyle = dial.pointerColor
      ctx.beginPath(); ctx.moveTo(c - w, top); ctx.lineTo(c + w, top); ctx.lineTo(c, tip); ctx.closePath(); ctx.fill()
      ctx.strokeStyle = "rgba(255,255,255,0.45)"
      ctx.lineWidth = 1
      ctx.beginPath(); ctx.moveTo(c - w + 1, top + 0.5); ctx.lineTo(c + w - 1, top + 0.5); ctx.stroke()
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: dial.interactive
    hoverEnabled: true
    cursorShape: dial.interactive ? (pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor

    property real lastAngle: 0
    property real acc: 0

    function angleAt(x, y) { return Math.atan2(x - width / 2, height / 2 - y) * 180 / Math.PI }

    onPressed: function(e) {
      lastAngle = angleAt(e.x, e.y)
      acc = Math.round(dial.minutes)
      dial.dragMinutes = acc
    }
    onPositionChanged: function(e) {
      if (!pressed) return
      var a = angleAt(e.x, e.y)
      var d = a - lastAngle
      if (d > 180) d -= 360
      if (d < -180) d += 360
      lastAngle = a
      acc = Math.max(1, Math.min(dial.maxMinutes, acc + d * dial.maxMinutes / 360))
      dial.dragMinutes = Math.round(acc)
    }
    onReleased: {
      var v = Math.round(acc)
      dial.wound(v)
      releaseHold.restart()
    }
    onWheel: function(e) {
      var v = Math.max(1, Math.min(dial.maxMinutes, Math.round(dial.dragMinutes >= 0 ? dial.dragMinutes : dial.minutes) + (e.angleDelta.y > 0 ? 1 : -1)))
      dial.dragMinutes = v
      dial.wound(v)
      releaseHold.restart()
    }
  }

  // Hold the wound value until the setting round-trips, so the face doesn't
  // flick back to the old number for a moment.
  Timer { id: releaseHold; interval: 1200; onTriggered: dial.dragMinutes = -1 }
}
