import QtQuick
import qs.services

// A field: 1 px border, a › prompt in accent. A secret is never drawn: each character is an accent tick instead.
FocusScope {
    id: field

    property alias text: input.text
    property string placeholder
    property bool secret: false
    property bool invalid: false
    property string prompt: "›"
    property alias validator: input.validator
    signal accepted

    height: Theme.u(44)
    width: parent ? parent.width : 0

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: field.invalid ? Theme.error : (input.activeFocus ? Theme.accent : Theme.border)
        Behavior on border.color {
            ColorAnimation { duration: Anim.hover }
        }
    }

    Text {
        x: Theme.u(14)
        anchors.verticalCenter: parent.verticalCenter
        text: field.prompt
        color: Theme.accent
        font.family: Theme.fontMono
        font.pixelSize: Theme.u(14)
    }

    TextInput {
        id: input
        focus: true
        x: Theme.u(36)
        width: parent.width - Theme.u(52)
        anchors.verticalCenter: parent.verticalCenter
        clip: true
        echoMode: field.secret ? TextInput.Password : TextInput.Normal
        // the real input stays (it owns the keyboard), a secret is simply not painted
        color: field.secret ? "transparent" : Theme.text
        selectionColor: Theme.accent
        selectedTextColor: Theme.accentText
        cursorDelegate: Rectangle {
            width: field.secret ? 0 : 1
            color: Theme.accent
        }
        font.family: Theme.fontMono
        font.pixelSize: Theme.u(14)
        onAccepted: field.accepted()

        Text {
            visible: input.text === "" && field.placeholder !== ""
            text: field.placeholder
            color: Theme.muted
            font: input.font
        }
    }

    Row {
        visible: field.secret
        x: Theme.u(36)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.u(6)
        Repeater {
            model: Math.min(input.text.length, 40)
            Rectangle {
                width: 2
                height: Theme.u(12)
                color: Theme.accent
            }
        }
    }
    function forceActive() {
        input.forceActiveFocus();
    }
}
