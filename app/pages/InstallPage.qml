import QtQuick
import TheLine.Ui
import qs.components
import qs.services

Page {
    id: page
    title: Installer.failure !== "" ? "That did not *work*." : "Installing *Kira*."
    sub: Installer.failure !== "" ? Installer.failure : "This takes a while. The kettle is a good idea."
    hint: Installer.failure !== "" ? "r try again   q quit" : "no way back from here"
    ready: false

    focus: true
    Keys.onPressed: event => {
        if (Installer.failure === "")
            return;
        if (event.text === "r") {
            Installer.start();
            event.accepted = true;
        } else if (event.text === "q") {
            Qt.quit();
            event.accepted = true;
        }
    }

    Column {
        width: parent.width
        spacing: Theme.u(20)

        // a line filling from the left, with a tick for every tenth
        Item {
            width: parent.width
            height: Theme.u(30)
            Rectangle {
                y: parent.height - 1
                width: parent.width
                height: 1
                color: Theme.borderStrong
            }
            Rectangle {
                y: parent.height - 2
                width: parent.width * Installer.percent / 100
                height: 3
                color: Installer.failure !== "" ? Theme.error : Theme.accent
                Behavior on width {
                    NumberAnimation { duration: Anim.panel; easing.type: Anim.easing }
                }
            }
            Repeater {
                model: 10
                Rectangle {
                    required property int index
                    x: Math.round(parent.width * (index + 1) / 10) - 1
                    y: parent.height - 1 - height
                    width: 1
                    height: Theme.u(10)
                    color: Installer.percent >= (index + 1) * 10 ? (Installer.failure !== "" ? Theme.error : Theme.accent) : Theme.border
                }
            }
        }

        Text {
            text: Installer.doing + "  ·  " + Math.round(Installer.percent) + " %"
            color: Theme.text
            font.family: Theme.fontMono
            font.pixelSize: Theme.u(15)
        }

        Text {
            width: parent.width
            text: Installer.logTail.join("\n")
            elide: Text.ElideRight
            maximumLineCount: 6
            color: Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: Theme.u(12)
        }
    }
}
