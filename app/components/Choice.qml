import QtQuick
import qs.services

// A choice between a few options, as the settings app's rows: one row each, its name and what it means, its letter
// as a key cap at the right. The chosen one is lit, with the accent tick. A letter picks it; ↑ ↓ move.
FocusScope {
    id: choice

    // [{ key: "a", label: "...", sub: "...", disabled: false }]
    property var options: []
    property string current: ""
    signal picked(string key)

    width: parent ? parent.width : 0
    implicitHeight: list.height

    function pick(i) {
        if (i < 0 || i >= options.length || options[i].disabled)
            return;
        current = options[i].key;
        picked(current);
    }
    function step(d) {
        let i = options.findIndex(o => o.key === current);
        for (let n = 0; n < options.length; n++) {
            i = (i + d + options.length) % options.length;
            if (!options[i].disabled) {
                pick(i);
                return;
            }
        }
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down) {
            step(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            step(-1);
            event.accepted = true;
        } else if (event.text !== "" && !event.modifiers) {
            const i = options.findIndex(o => o.key === event.text.toLowerCase());
            if (i >= 0) {
                pick(i);
                event.accepted = true;
            }
        }
    }

    Column {
        id: list
        width: parent.width

        Repeater {
            model: choice.options

            Rectangle {
                id: opt
                required property var modelData
                required property int index
                readonly property bool on: modelData.key === choice.current

                width: list.width
                height: Theme.u(58)
                color: opt.on || hover.hovered && !opt.modelData.disabled ? Theme.row : "transparent"
                opacity: modelData.disabled ? 0.45 : 1
                Behavior on color {
                    ColorAnimation { duration: Anim.hover }
                }

                Rectangle {
                    width: 2
                    height: parent.height
                    color: Theme.accent
                    opacity: opt.on ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Anim.base; easing.type: Anim.easing }
                    }
                }

                Column {
                    x: Theme.u(18)
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.u(80)
                    spacing: Theme.u(3)
                    Text {
                        width: parent.width
                        text: opt.modelData.label
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.u(16)
                        font.weight: opt.on ? Font.Medium : Font.Normal
                    }
                    Text {
                        width: parent.width
                        text: opt.modelData.sub ?? ""
                        visible: text !== ""
                        elide: Text.ElideRight
                        color: opt.on ? Theme.read : Theme.muted
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.u(13)
                    }
                }

                KeyCap {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.u(18)
                    anchors.verticalCenter: parent.verticalCenter
                    label: opt.modelData.key
                    lit: opt.on
                }

                HoverHandler {
                    id: hover
                    cursorShape: opt.modelData.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: choice.pick(opt.index)
                }
            }
        }
    }
}
