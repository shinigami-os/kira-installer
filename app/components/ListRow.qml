import QtQuick
import qs.services

// A list line: 34 px, a name in Raleway, a reading in mono at the right. Selected or hovered: surface2 and a 2 px accent tick.
Rectangle {
    id: row

    property string label
    property string sub
    property bool selected: false
    property bool disabled: false
    property color subColor: Theme.muted
    signal clicked

    width: parent ? parent.width : 0
    height: Theme.u(34)
    color: selected || hover.hovered && !disabled ? Theme.surface2 : "transparent"
    opacity: disabled ? 0.5 : 1

    Behavior on color {
        ColorAnimation { duration: Anim.hover }
    }

    Rectangle {
        width: 2
        height: parent.height
        color: Theme.accent
        opacity: row.selected ? 1 : 0
        Behavior on opacity {
            NumberAnimation { duration: Anim.base; easing.type: Anim.easing }
        }
    }

    Text {
        x: Theme.u(14)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Theme.u(28) - subText.width - Theme.u(12)
        text: row.label
        elide: Text.ElideRight
        color: Theme.text
        font.family: Theme.fontUi
        font.pixelSize: Theme.u(13)
        font.weight: Font.Medium
    }
    Text {
        id: subText
        anchors.right: parent.right
        anchors.rightMargin: Theme.u(14)
        anchors.verticalCenter: parent.verticalCenter
        text: row.sub
        color: row.subColor
        font.family: Theme.fontMono
        font.pixelSize: Theme.u(11)
    }

    HoverHandler {
        id: hover
    }
    TapHandler {
        onTapped: if (!row.disabled)
            row.clicked()
    }
}
