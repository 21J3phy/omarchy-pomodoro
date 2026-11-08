import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Bar button and panel for bin/pomodoro, which ships beside this file and owns
// all state. The script's daemon runs the timer and, during focus, bounces any
// workspace switch back to the workspace the session started on.
//
// The panel is a little toaster: twist the kitchen-timer dial to set the focus
// length, push the lever down to start, and it pops up when the time is done.
Panel {
  id: root
  moduleName: "21j3phy.pomodoro"
  ipcTarget: "21j3phy.pomodoro"

  readonly property string script: String(Qt.resolvedUrl("bin/pomodoro")).replace(/^file:\/\//, "")
  readonly property string barGlyph: "󰔛"

  property string phase: "idle"
  property int startedAt: 0
  property int endsAt: 0
  property int clockSkew: 0
  property int nowSec: Math.floor(Date.now() / 1000)
  property bool locked: false
  property string workspaceName: ""
  property int cycle: 0
  property int completedToday: 0
  property int minutesToday: 0
  property var cfg: ({ focus: 25, short: 5, long: 15, longEvery: 4, lock: true, strict: false, autoBreak: true,
                       mini: false, miniX: -1, miniY: -1, miniScreen: "" })
  property bool busy: false
  property bool pendingStart: false
  property bool showSettings: false
  // Ending focus early ("stop", "skip" or "break") waits here until the
  // confession has been typed out.
  property string pendingExit: ""
  property string phrase: "I am being very unproductive and wasting my time by doing this."
  readonly property bool confirming: pendingExit !== "" && focusing

  readonly property bool running: phase !== "idle"
  readonly property bool focusing: phase === "focus"
  readonly property bool onBreak: running && !focusing
  readonly property int remaining: running ? Math.max(0, endsAt - (nowSec + clockSkew)) : 0
  readonly property int total: Math.max(1, endsAt - startedAt)
  readonly property real progress: running ? Math.min(1, Math.max(0, 1 - remaining / total)) : 0
  readonly property bool strictLock: focusing && cfg.strict === true
  readonly property bool vertical: root.bar ? root.bar.vertical : false

  // The bar, and so this widget, exists once per monitor. Only the copy on
  // the chosen monitor shows the floating timer; if that monitor is gone, the
  // first one takes it.
  readonly property var myScreen: {
    var w = root.QsWindow.window
    return w && w.screen ? w.screen : null
  }
  readonly property string myScreenName: root.myScreen ? String(root.myScreen.name || "") : ""
  readonly property bool miniHere: {
    if (root.cfg.mini !== true || !root.myScreen) return false
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (screens[i].name === root.cfg.miniScreen) return screens[i].name === root.myScreenName
    }
    return screens.length > 0 && screens[0].name === root.myScreenName
  }

  // The appliance has its own physical palette; only the enamel takes the
  // theme's accent hue, so it still belongs to the desktop.
  readonly property color red: "#ff5a4a"
  readonly property color green: "#5fd38d"
  readonly property color amber: "#ffb547"
  readonly property color phaseColor: focusing ? red : green
  readonly property color accentC: Commons.Color.accent
  readonly property real enamelHue: accentC.hslHue < 0 ? 0.55 : accentC.hslHue
  readonly property real enamelSat: Math.min(0.42, accentC.hslSaturation)
  readonly property color enamelTop: Qt.hsla(enamelHue, enamelSat, 0.36, 1)
  readonly property color enamelBottom: Qt.hsla(enamelHue, enamelSat, 0.19, 1)
  readonly property color engraved: Qt.rgba(1, 1, 1, 0.62)

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  function pad(n) { return n < 10 ? "0" + n : String(n) }
  function clock(seconds) {
    var s = Math.max(0, seconds)
    return pad(Math.floor(s / 60)) + ":" + pad(s % 60)
  }

  function applyStatus(text) {
    var data
    try { data = JSON.parse(String(text || "")) } catch (e) { return }
    if (!data || typeof data !== "object") return
    var phases = ["idle", "focus", "short", "long"]
    root.phase = phases.indexOf(data.phase) >= 0 ? data.phase : "idle"
    root.startedAt = parseInt(data.startedAt, 10) || 0
    root.endsAt = parseInt(data.endsAt, 10) || 0
    root.nowSec = Math.floor(Date.now() / 1000)
    root.clockSkew = (parseInt(data.now, 10) || root.nowSec) - root.nowSec
    root.locked = data.locked === true
    var ws = data.workspace && typeof data.workspace === "object" ? data.workspace : null
    root.workspaceName = ws ? String(ws.name).slice(0, 24) : ""
    root.cycle = parseInt(data.cycle, 10) || 0
    var today = data.today && typeof data.today === "object" ? data.today : {}
    root.completedToday = parseInt(today.completed, 10) || 0
    root.minutesToday = parseInt(today.focusMinutes, 10) || 0
    if (data.settings && typeof data.settings === "object") {
      // Settings still waiting to be saved win over what's on disk, so a
      // status poll can't snap the dial or the floating timer back.
      root.cfg = Object.assign({}, data.settings, root.pendingValues)
    }
    if (typeof data.phrase === "string" && data.phrase.length > 0 && data.phrase.length < 300) root.phrase = data.phrase
    if (!root.focusing) root.pendingExit = ""
    root.pendingStart = false
  }

  function refresh() { if (!statusProc.running) statusProc.running = true }

  function runAction(args) {
    if (actionProc.running) return
    root.busy = true
    actionProc.command = [root.script].concat(args)
    actionProc.running = true
  }

  function setValue(key, value) {
    var change = {}
    change[key] = value
    root.setValues(change)
  }
  // Changes land in cfg at once and reach the script together, shortly after.
  function setValues(change) {
    root.cfg = Object.assign({}, root.cfg, change)
    root.pendingValues = Object.assign({}, root.pendingValues, change)
    saveTimer.restart()
  }
  property var pendingValues: ({})

  function flushSettings() {
    var keys = Object.keys(root.pendingValues)
    if (keys.length === 0) return
    // Another command is still running; try again in a moment.
    if (actionProc.running) { saveTimer.restart(); return }
    var args = ["set"]
    for (var i = 0; i < keys.length; i++) args.push(keys[i], String(root.pendingValues[keys[i]]))
    root.pendingValues = ({})
    root.runAction(args)
  }

  // Show or hide the always-on-top timer. Showing it puts it on `screenName`.
  function setMini(on, screenName) {
    if (!on) { root.setValue("mini", false); return }
    var change = { mini: true }
    if (screenName) change.miniScreen = screenName
    root.setValues(change)
  }
  function toggleMini(screenName) { root.setMini(root.cfg.mini !== true, screenName) }
  function focusedScreenName() {
    var m = Hyprland.focusedMonitor
    return m ? String(m.name || "") : root.myScreenName
  }

  function startFocus() {
    if (root.running || root.busy) return
    root.pendingStart = true
    root.runAction(["start"])
  }

  // Leaving a break is free. Leaving focus early means typing out the
  // confession first; the script checks it again, so the CLI is no shortcut.
  function requestExit(action) {
    if (root.strictLock || root.busy) return
    if (!root.focusing) { root.runAction([action]); return }
    root.pendingExit = action
    if (!root.opened) root.open()
  }
  function giveUp() { root.requestExit("stop") }

  function normalize(t) { return String(t).toLowerCase().split(/\s+/).join(" ").replace(/[.!]+$/, "").trim() }
  function phraseMatches(t) { return root.normalize(t) === root.normalize(root.phrase) }
  // True while what's typed so far is still on track.
  function phraseOnTrack(t) {
    var typed = String(t).toLowerCase().replace(/\s+/g, " ").replace(/^ /, "")
    return root.phrase.toLowerCase().indexOf(typed) === 0 || root.phraseMatches(t)
  }

  function confirmExit(typed) {
    if (!root.confirming || !root.phraseMatches(typed)) return
    var action = root.pendingExit
    root.pendingExit = ""
    root.runAction([action, "--phrase", typed])
  }

  function quickAction() {
    if (!root.running) root.startFocus()
    else root.requestExit("stop")
  }

  Timer {
    id: saveTimer
    interval: 400
    onTriggered: root.flushSettings()
  }

  Process {
    id: statusProc
    command: [root.script, "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyStatus(text) }
  }

  Process {
    id: actionProc
    onExited: { root.busy = false; root.refresh() }
  }

  // Local second hand for the countdown.
  Timer {
    interval: 1000
    running: root.running
    repeat: true
    onTriggered: {
      root.nowSec = Math.floor(Date.now() / 1000)
      if (root.remaining <= 0) root.refresh()
    }
  }

  // The script pushes changes over IPC; this is a slow safety net.
  Timer {
    interval: root.opened ? 2000 : 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  ShellIpc {
    target: root.moduleName + ".state"
    function refresh(): void { root.refresh() }
    // Same as pressing STOP: during focus it asks for the confession first.
    function stop(): void { root.refresh(); root.requestExit("stop") }
    // The always-on-top timer, on the focused monitor.
    function mini(): void { root.toggleMini(root.focusedScreenName()) }
    function showMini(): void { root.setMini(true, root.focusedScreenName()) }
    function hideMini(): void { root.setMini(false) }
  }

  MiniTimer {
    owner: root
    screen: root.myScreen
    shown: root.miniHere
  }

  // ------------------------------------------------------------------ bar

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight + (minutesLabel.visible ? minutesLabel.implicitHeight : 0)

  BarIconButton {
    id: button
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    bar: root.bar
    text: root.barGlyph
    opacity: root.running ? 1.0 : 0.55
    iconComponent: root.running ? pieIcon : null
    labelText: root.running && !root.vertical ? Math.ceil(root.remaining / 60) + "m" : ""
    tooltipText: !root.running ? strings.t("tooltip.idle")
      : root.focusing
        ? (root.locked ? strings.t("tooltip.focus").arg(root.clock(root.remaining)).arg(root.workspaceName)
                       : strings.t("tooltip.focusUnlocked").arg(root.clock(root.remaining)))
        : strings.t("tooltip.break").arg(root.clock(root.remaining))
    onPressed: function(b) {
      if (b === Qt.RightButton) root.quickAction()
      else if (b === Qt.MiddleButton) root.toggleMini(root.myScreenName)
      else root.toggle()
    }
  }

  // Minutes left, under the icon, on a vertical bar.
  Text {
    id: minutesLabel
    visible: root.running && root.vertical
    anchors.top: button.bottom
    anchors.topMargin: -Style.space(4)
    anchors.horizontalCenter: parent.horizontalCenter
    textFormat: Text.PlainText
    text: Math.ceil(root.remaining / 60)
    color: root.bar ? root.bar.barForeground : Commons.Color.foreground
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: root.focusing
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      onClicked: function(mouse) {
        if (mouse.button === Qt.RightButton) root.quickAction()
        else if (mouse.button === Qt.MiddleButton) root.toggleMini(root.myScreenName)
        else root.toggle()
      }
    }
  }

  // A tiny kitchen timer: the wedge is the time left.
  Component {
    id: pieIcon
    Canvas {
      width: 32
      height: 32
      property real pieLeft: 1 - root.progress
      property color fg: root.bar ? root.bar.barForeground : Commons.Color.foreground
      property color hi: root.phaseColor
      onPieLeftChanged: requestPaint()
      onFgChanged: requestPaint()
      onHiChanged: requestPaint()
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var c = width / 2, r = width / 2 - 2
        ctx.lineWidth = 2.5
        ctx.strokeStyle = fg
        ctx.beginPath(); ctx.arc(c, c, r, 0, Math.PI * 2); ctx.stroke()
        if (pieLeft > 0) {
          ctx.fillStyle = hi
          ctx.beginPath()
          ctx.moveTo(c, c)
          ctx.arc(c, c, r - 3.5, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * pieLeft)
          ctx.closePath()
          ctx.fill()
        }
        ctx.fillStyle = fg
        ctx.beginPath(); ctx.moveTo(c - 3, 0); ctx.lineTo(c + 3, 0); ctx.lineTo(c, 5); ctx.closePath(); ctx.fill()
      }
    }
  }

  // ---------------------------------------------------------------- panel

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---- the toaster
        Item {
          id: appliance
          width: parent.width
          height: body.height + 14

          // feet
          Repeater {
            model: 2
            Rectangle {
              y: body.height - 6
              x: index === 0 ? body.width * 0.14 : body.width * 0.86 - width
              width: 46; height: 18; radius: 6
              color: "#121315"
            }
          }

          Rectangle {
            id: body
            width: parent.width
            height: bodyColumn.implicitHeight + 34 + bumper.height
            radius: 28
            gradient: Gradient {
              GradientStop { position: 0; color: root.enamelTop }
              GradientStop { position: 1; color: root.enamelBottom }
            }
            border.width: 1
            border.color: Qt.rgba(0, 0, 0, 0.5)

            // sheen across the top
            Rectangle {
              x: 18; y: 2
              width: parent.width - 36; height: 30
              radius: 15
              gradient: Gradient {
                GradientStop { position: 0; color: Qt.rgba(1, 1, 1, 0.20) }
                GradientStop { position: 1; color: Qt.rgba(1, 1, 1, 0) }
              }
            }

            // chrome bumper along the bottom
            Rectangle {
              id: bumper
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 1
              height: 16
              radius: 27
              gradient: Gradient {
                GradientStop { position: 0; color: "#f2f4f6" }
                GradientStop { position: 0.5; color: "#9ea4ac" }
                GradientStop { position: 1; color: "#5a6068" }
              }
            }

            Column {
              id: bodyColumn
              x: 18
              y: 16
              width: parent.width - 36
              spacing: 12

              // brand plate + lock lamp
              Item {
                width: parent.width
                height: 22

                Rectangle {
                  id: plate
                  anchors.verticalCenter: parent.verticalCenter
                  width: brand.implicitWidth + 20
                  height: 22
                  radius: 5
                  gradient: Gradient {
                    GradientStop { position: 0; color: "#eef0f2" }
                    GradientStop { position: 1; color: "#a9aeb5" }
                  }
                  border.width: 1
                  border.color: Qt.rgba(0, 0, 0, 0.35)
                  Text {
                    id: brand
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: strings.t("brand")
                    color: "#3a3d42"
                    style: Text.Raised
                    styleColor: Qt.rgba(1, 1, 1, 0.8)
                    font.family: root.bar.fontFamily
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 3
                  }
                }

                Row {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 7
                  Lamp {
                    anchors.verticalCenter: parent.verticalCenter
                    lit: root.focusing && root.locked
                    color: root.red
                  }
                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: (root.focusing && root.locked ? strings.t("lamp.locked").arg(root.workspaceName)
                      : root.cfg.lock === true ? strings.t("lamp.ready") : strings.t("lamp.off")).toUpperCase()
                    color: root.engraved
                    style: Text.Sunken
                    styleColor: Qt.rgba(0, 0, 0, 0.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: 10
                    font.bold: true
                    font.letterSpacing: 1.5
                  }
                }
              }

              // dial + lever
              Row {
                id: works
                width: parent.width
                spacing: 10
                readonly property real leverW: 54
                readonly property real dialSize: width - leverW - spacing

                TimerDial {
                  id: dial
                  width: works.dialSize
                  height: works.dialSize
                  fontFamily: root.bar.fontFamily
                  minutes: root.running ? root.remaining / 60 : (root.cfg.focus || 25)
                  interactive: !root.running
                  onWound: function(m) { root.setValue("focus", m) }
                }

                ToasterLever {
                  width: works.leverW
                  height: works.dialSize
                  down: root.running || root.pendingStart
                  locked: root.strictLock
                  glow: root.phaseColor
                  fontFamily: root.bar.fontFamily
                  onPushed: root.startFocus()
                  onPulled: root.giveUp()
                }
              }

              // readout window
              Rectangle {
                width: parent.width
                height: 58
                radius: 10
                gradient: Gradient {
                  GradientStop { position: 0; color: "#060607" }
                  GradientStop { position: 1; color: "#1a1b1e" }
                }
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.14)

                Column {
                  anchors.centerIn: parent
                  spacing: 2
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    text: root.running ? root.clock(root.remaining) : root.clock((root.cfg.focus || 25) * 60)
                    color: root.running ? root.amber : Qt.rgba(1, 0.71, 0.28, 0.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: 30
                    font.bold: true
                    font.letterSpacing: 3
                    font.features: { "tnum": 1 }
                  }
                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    text: (root.confirming ? strings.t("hint.confirm")
                      : root.strictLock ? strings.t("hint.strict")
                      : root.focusing ? strings.t("hint.focus")
                      : root.onBreak ? strings.t("hint.break")
                      : strings.t("hint.idle")).toUpperCase()
                    color: root.confirming ? root.red : Qt.rgba(1, 0.71, 0.28, 0.6)
                    font.family: root.bar.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 1.6
                  }
                }
              }

              // push buttons
              Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12

                ApplianceButton {
                  label: strings.t("button.break")
                  lit: root.onBreak
                  lampColor: root.green
                  fontFamily: root.bar.fontFamily
                  armed: root.confirming && root.pendingExit === "break"
                  enabled: !root.busy && !root.onBreak && !root.strictLock
                  onClicked: root.requestExit("break")
                }
                ApplianceButton {
                  label: strings.t("button.skip")
                  lit: false
                  lampColor: root.amber
                  fontFamily: root.bar.fontFamily
                  armed: root.confirming && root.pendingExit === "skip"
                  enabled: !root.busy && root.running && !root.strictLock
                  onClicked: root.requestExit("skip")
                }
                ApplianceButton {
                  label: strings.t("button.stop")
                  lit: root.focusing
                  armed: root.confirming && root.pendingExit === "stop"
                  lampColor: root.red
                  fontFamily: root.bar.fontFamily
                  enabled: !root.busy && root.running && !root.strictLock
                  onClicked: root.giveUp()
                }
              }
            }
          }
        }

        // ---- the confession: type it out to end focus early
        Rectangle {
          id: confession
          visible: root.confirming
          width: parent.width
          height: confessionColumn.implicitHeight + 32
          radius: 14
          color: Qt.rgba(root.red.r, root.red.g, root.red.b, 0.08)
          border.width: 1.5
          border.color: Qt.rgba(root.red.r, root.red.g, root.red.b, 0.6)

          onVisibleChanged: {
            confessionField.text = ""
            if (visible) Qt.callLater(function() { confessionField.forceActiveFocus() })
          }

          readonly property bool matches: root.phraseMatches(confessionField.text)
          readonly property bool onTrack: root.phraseOnTrack(confessionField.text)

          Column {
            id: confessionColumn
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 10

            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: strings.t("confess.title." + (root.pendingExit || "stop"))
              color: root.red
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: strings.t("confess.body").arg(root.clock(root.remaining))
              color: root.bar.foreground
              opacity: 0.75
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: "\u201C" + root.phrase + "\u201D"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.body
              font.italic: true
            }

            TextField {
              id: confessionField
              width: parent.width
              placeholderText: strings.t("confess.placeholder")
              foreground: root.bar.foreground
              accent: confession.onTrack ? Commons.Color.accent : root.red
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              // Type it, don't paste it.
              Keys.onPressed: function(event) {
                if (event.matches(StandardKey.Paste) || (event.key === Qt.Key_Insert && (event.modifiers & Qt.ShiftModifier))) {
                  event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                  root.pendingExit = ""
                  event.accepted = true
                }
              }
              onAccepted: root.confirmExit(text)
              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.MiddleButton | Qt.RightButton
                onClicked: confessionField.forceActiveFocus()
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: confession.matches ? strings.t("confess.ok")
                : confession.onTrack ? strings.t("confess.progress").arg(confessionField.text.length).arg(root.phrase.length)
                : strings.t("confess.typo")
              color: confession.matches ? root.amber : confession.onTrack ? root.bar.foreground : root.red
              opacity: confession.onTrack && !confession.matches ? 0.55 : 1
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              spacing: 8
              Button {
                text: strings.t("confess.keep")
                iconText: "󰐊"
                bordered: true
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.pendingExit = ""
              }
              Button {
                text: strings.t("confess.do." + (root.pendingExit || "stop"))
                iconText: "󰓛"
                bordered: true
                enabled: confession.matches && !root.busy
                opacity: enabled ? 1 : 0.4
                foreground: root.red
                fontFamily: root.bar.fontFamily
                fontSize: Style.font.bodySmall
                onClicked: root.confirmExit(confessionField.text)
              }
            }
          }
        }

        // ---- tally: one pip per session in the cycle, then today's totals
        Item {
          width: parent.width
          height: 18

          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6
            Repeater {
              model: root.cfg.longEvery || 4
              Rectangle {
                readonly property int done: root.cycle % (root.cfg.longEvery || 4)
                readonly property bool filled: index < done
                readonly property bool current: root.focusing && index === done
                width: 12; height: 12; radius: 6
                color: filled ? root.red : "transparent"
                border.width: 1.5
                border.color: filled || current ? root.red : Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.35)
                Rectangle {
                  visible: parent.current
                  anchors.centerIn: parent
                  width: 4; height: 4; radius: 2
                  color: root.red
                }
              }
            }
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: strings.t("today") + "  " + strings.tn("today.value", root.completedToday)
              .arg(Commons.I18n.formatNumber(root.completedToday))
              .arg(Commons.I18n.formatNumber(root.minutesToday))
            color: root.bar.foreground
            opacity: 0.65
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        // ---- settings, folded away, and the floating timer toggle
        Item {
          width: parent.width
          height: Math.max(settingsButton.implicitHeight, miniButton.implicitHeight)

          Button {
            id: settingsButton
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t("settings")
            iconText: root.showSettings ? "󰅃" : "󰅀"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.showSettings = !root.showSettings
          }
          Button {
            id: miniButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: strings.t(root.cfg.mini === true ? "mini.toggle.on" : "mini.toggle.off")
            iconText: root.cfg.mini === true ? "󰐃" : "󰤰"
            tooltipText: strings.t("mini.toggle.tooltip")
            selected: root.cfg.mini === true
            bordered: true
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            onClicked: root.toggleMini(root.myScreenName)
          }
        }

        Column {
          visible: root.showSettings
          width: parent.width
          spacing: Style.space(12)
          enabled: !root.strictLock
          opacity: enabled ? 1.0 : 0.5

          NumberField {
            label: strings.t("short.label")
            from: 1; to: 120; stepSize: 1
            value: root.cfg.short || 5
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onModified: function(v) { root.setValue("short", v) }
          }
          NumberField {
            label: strings.t("long.label")
            from: 1; to: 120; stepSize: 5
            value: root.cfg.long || 15
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onModified: function(v) { root.setValue("long", v) }
          }
          NumberField {
            label: strings.t("longEvery.label")
            from: 1; to: 12; stepSize: 1
            value: root.cfg.longEvery || 4
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onModified: function(v) { root.setValue("longEvery", v) }
          }
          Toggle {
            width: parent.width
            label: strings.t("lock.label")
            description: strings.t("lock.description")
            checked: root.cfg.lock === true
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.setValue("lock", !(root.cfg.lock === true))
          }
          Toggle {
            width: parent.width
            label: strings.t("strict.label")
            description: strings.t("strict.description")
            checked: root.cfg.strict === true
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.setValue("strict", !(root.cfg.strict === true))
          }
          Toggle {
            width: parent.width
            label: strings.t("autoBreak.label")
            description: strings.t("autoBreak.description")
            checked: root.cfg.autoBreak === true
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onClicked: root.setValue("autoBreak", !(root.cfg.autoBreak === true))
          }
        }
      }
    }
  }

  component Lamp: Item {
    property bool lit: false
    property color color: "#ff5a4a"
    width: 9; height: 9
    Rectangle {
      anchors.centerIn: parent
      width: 20; height: 20; radius: 10
      color: parent.color
      opacity: parent.lit ? 0.35 : 0
    }
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: parent.lit ? Qt.lighter(parent.color, 1.2) : "#2a1f1d"
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.5)
    }
  }
}
