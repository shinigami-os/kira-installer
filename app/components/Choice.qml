import QtQuick
import qs.services

// An inline choice: a row of bordered options, a letter under each. The letter picks it; ↑ ↓ move.
FocusScope {
    id: choice

    // [{ key: "a", label: "...", sub: "...", disabled: false }]
    property var options: []
    property string current: ""
    signal picked(string key)

    implicitHeight: Theme.u(72)
    width: parent ? parent.width : 0

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

    Row {
        spacing: Theme.u(10)
        Repeater {
            model: choice.options
            delegate: Item {
                id: opt
                required property var modelData
                required property int index
                readonly property bool on: modelData.key === choice.current
                width: Math.floor((choice.width - Theme.u(10) * (choice.options.length - 1)) / choice.options.length)
                height: choice.height
                opacity: modelData.disabled ? 0.45 : 1

                Rectangle {
                    width: parent.width
                    height: Theme.u(48)
                    color: opt.on ? Theme.accentTint : "transparent"
                    border.width: 1
                    border.color: opt.on ? Theme.accent : (hover.hovered && !opt.modelData.disabled ? Theme.borderStrong : Theme.border)
                    Behavior on color {
                        ColorAnimation { duration: Anim.base }
                    }
                    Behavior on border.color {
                        ColorAnimation { duration: Anim.hover }
                    }

                    Text {
                        x: Theme.u(12)
                        y: opt.modelData.sub ? parent.height / 2 - height - 1 : (parent.height - height) / 2
                        width: parent.width - Theme.u(24)
                        text: opt.modelData.label
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.u(13)
                        font.weight: Font.Medium
                    }
                    Text {
                        x: Theme.u(12)
                        y: parent.height / 2 + 1
                        width: parent.width - Theme.u(24)
                        text: opt.modelData.sub ?? ""
                        elide: Text.ElideRight
                        color: opt.on ? Theme.text : Theme.muted
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.u(11)
                    }
                }

                KeyCap {
                    x: Theme.u(2)
                    y: Theme.u(54)
                    label: opt.modelData.key
                    lit: opt.on
                }

                HoverHandler {
                    id: hover
                }
                TapHandler {
                    onTapped: choice.pick(opt.index)
                }
            }
        }
    }
}
