import QtQuick
import qs.services

// A row, as in the settings app: a name in Raleway, what it is in mono at the right. Selected (or hovered): the row is
// lit and a 2 px accent tick stands at its left edge.
Rectangle {
    id: row

    property string label
    property string detail          // a second, quieter part of the name (a disk's model)
    property string sub
    property bool selected: false
    property bool disabled: false
    property color subColor: Theme.muted
    signal clicked

    width: parent ? parent.width : 0
    height: Theme.u(44)
    color: selected || hover.hovered && !disabled ? Theme.row : "transparent"
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

    Row {
        x: Theme.u(18)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Theme.u(36) - subText.width - Theme.u(16)
        spacing: Theme.u(14)
        clip: true

        Text {
            text: row.label
            color: Theme.text
            font.family: Theme.fontUi
            font.pixelSize: Theme.u(16)
            font.weight: row.selected ? Font.Medium : Font.Normal
        }
        Text {
            anchors.baseline: parent.children[0].baseline
            text: row.detail
            visible: text !== ""
            color: Theme.muted
            font.family: Theme.fontUi
            font.pixelSize: Theme.u(14)
        }
    }
    Text {
        id: subText
        anchors.right: parent.right
        anchors.rightMargin: Theme.u(18)
        anchors.verticalCenter: parent.verticalCenter
        text: row.sub
        color: row.subColor
        font.family: Theme.fontMono
        font.pixelSize: Theme.u(13)
    }

    HoverHandler {
        id: hover
        cursorShape: row.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: if (!row.disabled)
            row.clicked()
    }
}
