import QtQuick
import TheLine.Ui
import qs.services

// A dialog grown from a line: the screen dims, a line draws itself across the middle from both edges, the box opens
// on it. Closing runs it backwards, content first.
FocusScope {
    id: dlg

    property bool open: false
    property string question: "leave the installer?"
    property string yes: "leave"
    signal confirmed
    signal dismissed

    property real line: 0
    property real box: 0
    visible: line > 0

    // An invisible item cannot take the focus, and the dialog only becomes visible once the line starts to draw:
    // asking for it in onOpenChanged alone left the keys with the page.
    onVisibleChanged: if (visible && open)
        forceActiveFocus()

    onOpenChanged: {
        opening.stop();
        closing.stop();
        if (open) {
            opening.start();
            forceActiveFocus();
        } else {
            closing.start();
        }
    }

    SequentialAnimation {
        id: opening
        NumberAnimation { target: dlg; property: "line"; to: 1; duration: Anim.line; easing.type: Anim.easing }
        NumberAnimation { target: dlg; property: "box"; to: 1; duration: Anim.panel; easing.type: Anim.easing }
    }
    SequentialAnimation {
        id: closing
        NumberAnimation { target: dlg; property: "box"; to: 0; duration: Anim.exitFade }
        NumberAnimation { target: dlg; property: "line"; to: 0; duration: Anim.exitFade }
    }

    Keys.onPressed: event => {
        if (event.text === "y") {
            dlg.confirmed();
            event.accepted = true;
        } else if (event.text === "n" || event.key === Qt.Key_Escape) {
            dlg.dismissed();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.8 * dlg.line
    }

    // the line, from both edges to the middle
    Rectangle {
        x: 0
        y: Math.round(dlg.height / 2)
        width: dlg.width / 2 * dlg.line
        height: 1
        color: Theme.borderStrong
    }
    Rectangle {
        x: dlg.width - width
        y: Math.round(dlg.height / 2)
        width: dlg.width / 2 * dlg.line
        height: 1
        color: Theme.borderStrong
    }

    Rectangle {
        width: Theme.u(500)
        height: Theme.u(140) * dlg.box
        x: (dlg.width - width) / 2
        y: Math.round(dlg.height / 2) - height / 2
        color: Theme.panel
        border.width: 1
        border.color: Theme.border
        clip: true

        Column {
            x: Theme.u(24)
            y: Theme.u(22)
            spacing: Theme.u(6)
            opacity: dlg.box
            Text {
                text: dlg.question
                color: Theme.text
                font.family: Theme.fontUi
                font.pixelSize: Theme.u(24)
                font.weight: Font.Medium
            }
            Text {
                text: "nothing has been written."
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: Theme.u(13)
            }
            Item { width: 1; height: Theme.u(8) }
            Row {
                spacing: Theme.u(8)
                KeyCap { label: "y"; lit: true }
                Text { text: dlg.yes; color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: Theme.u(13); anchors.verticalCenter: parent.verticalCenter }
                Item { width: Theme.u(16); height: 1 }
                KeyCap { label: "n" }
                Text { text: "stay"; color: Theme.muted; font.family: Theme.fontMono; font.pixelSize: Theme.u(13); anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }
}
