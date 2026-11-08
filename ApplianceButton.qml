import QtQuick
import qs.Commons

// A chunky push button with an indicator lamp above it, like the
// Bagel / Defrost / Cancel buttons on a toaster.
Item {
  id: btn

  property string label: ""
  property bool lit: false
  property color lampColor: "#d8433b"
  property bool showLamp: true
  property string fontFamily: Style.font.family
  property bool armed: false          // highlighted, e.g. waiting for a confirming press

  signal clicked()

  implicitWidth: 78
  implicitHeight: 54
  opacity: enabled ? 1.0 : 0.4

  // lamp
  Item {
    id: lamp
    anchors.horizontalCenter: parent.horizontalCenter
    y: 0
    width: 9; height: 9
    visible: btn.showLamp
    Rectangle {
      anchors.centerIn: parent
      width: 20; height: 20; radius: 10
      color: btn.lampColor
      opacity: btn.lit ? 0.35 : 0
      Behavior on opacity { NumberAnimation { duration: Style.duration(200) } }
    }
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: btn.lit ? Qt.lighter(btn.lampColor, 1.25) : "#2a1f1d"
      border.width: 1
      border.color: Qt.rgba(0, 0, 0, 0.5)
      Behavior on color { ColorAnimation { duration: Style.duration(200) } }
      Rectangle {
        x: 2; y: 1.5; width: 3; height: 2.5; radius: 1.5
        color: Qt.rgba(1, 1, 1, btn.lit ? 0.8 : 0.25)
      }
    }
  }

  Item {
    id: cap
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 32

    Rectangle {  // the hole the button sits in
      anchors.fill: parent
      anchors.topMargin: 3
      radius: 9
      color: Qt.rgba(0, 0, 0, 0.45)
    }
    Rectangle {
      id: face
      width: parent.width
      height: parent.height - 3
      y: mouse.pressed ? 3 : 0
      radius: 9
      Behavior on y { NumberAnimation { duration: Style.duration(60) } }
      gradient: Gradient {
        GradientStop { position: 0; color: mouse.pressed ? "#c9cdd2" : "#f7f8fa" }
        GradientStop { position: 1; color: mouse.pressed ? "#9da3ab" : "#b8bdc4" }
      }
      border.width: btn.armed ? 2 : 1
      border.color: btn.armed ? btn.lampColor : Qt.rgba(0, 0, 0, 0.35)

      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: btn.label
        color: btn.armed ? btn.lampColor : "#33363b"
        style: Text.Raised
        styleColor: Qt.rgba(1, 1, 1, 0.7)
        font.family: btn.fontFamily
        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 1.2
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.clicked()
    }
  }
}
