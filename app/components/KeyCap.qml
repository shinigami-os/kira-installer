import QtQuick
import qs.services

// A key as a small bordered box, mono. The one that matters gets an accent border.
Rectangle {
    property string label
    property bool lit: false

    width: Math.max(Theme.u(24), cap.implicitWidth + Theme.u(12))
    height: Theme.u(24)
    color: "transparent"
    border.width: 1
    border.color: lit ? Theme.accent : Theme.borderStrong

    Text {
        id: cap
        anchors.centerIn: parent
        text: parent.label
        color: parent.lit ? Theme.text : Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: Theme.u(13)
    }
}
