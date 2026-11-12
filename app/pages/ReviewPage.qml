import QtQuick
import qs.components
import qs.services

Page {
    id: page
    title: Installer.mode === "whole" ? "This will erase */dev/" + Installer.disk + "*." : "This will *add* a partition."
    sub: Installer.mode === "whole" ? "All of it: every partition on the disk. Read the rest first." : "A partition is added in the free space. The others stay as they are."
    destructive: Installer.mode === "whole"
    hint: "hold enter to install   ← back   esc leave"
    ready: false

    focus: true
    Keys.onPressed: event => {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && !event.isAutoRepeat) {
            hold.press();
            event.accepted = true;
        }
    }
    Keys.onReleased: event => {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && !event.isAutoRepeat) {
            hold.release();
            event.accepted = true;
        }
    }

    readonly property var rows: [
        ["Keyboard", Installer.keymap],
        ["Network", Installer.online ? "online" : "offline"],
        ["Disk", "/dev/" + Installer.disk + "  " + Installer.diskModel],
        ["Partitioning", Installer.mode === "whole" ? "erase the whole disk" : "free space, " + Installer.humanMib(Installer.freeMib)],
        ["Swap", Installer.swapMib > 0 ? Installer.swapMib + " MiB" : "none"],
        ["Computer name", Installer.hostname],
        ["User", Installer.username],
        ["Root", Installer.rootSame ? "same password" : "its own password"],
        ["Time zone", Installer.timezone],
        ["System", Installer.tier === "server" ? "Server" : (Installer.tier === "desktop-sleex" ? "Sleex" : "The Line")]
    ]

    Column {
        width: parent.width
        spacing: Theme.u(32)

        Column {
            width: parent.width
            Repeater {
                model: page.rows
                Item {
                    required property var modelData
                    width: parent.width
                    height: Theme.u(34)
                    Text {
                        x: Theme.u(18)
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData[0]
                        color: Theme.muted
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.u(15)
                    }
                    Text {
                        x: Theme.u(200)
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x
                        text: modelData[1]
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.u(14)
                    }
                    Rectangle {
                        y: parent.height - 1
                        width: parent.width
                        height: 1
                        color: Theme.border
                    }
                }
            }
        }

        HoldButton {
            id: hold
            label: Installer.mode === "whole" ? "Hold to erase /dev/" + Installer.disk + " and install" : "Hold to install"
            onConfirmed: Installer.start()
        }
    }
}
