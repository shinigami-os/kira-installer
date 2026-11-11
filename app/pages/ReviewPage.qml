import QtQuick
import qs.components
import qs.services

Page {
    id: page
    title: Installer.mode === "whole" ? "this will erase */dev/" + Installer.disk + "*." : "this will *add* a partition."
    sub: Installer.mode === "whole" ? "all of it. every partition on the disk. read the rest first." : "a partition is added in the free space. the others stay as they are."
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
        ["keyboard", Installer.keymap],
        ["network", Installer.online ? "online" : "offline"],
        ["disk", "/dev/" + Installer.disk + "  " + Installer.diskModel],
        ["partitioning", Installer.mode === "whole" ? "erase the whole disk" : "free space, " + Installer.humanMib(Installer.freeMib)],
        ["swap", Installer.swapMib > 0 ? Installer.swapMib + " MiB" : "none"],
        ["hostname", Installer.hostname],
        ["user", Installer.username],
        ["root", Installer.rootSame ? "same password" : "its own password"],
        ["timezone", Installer.timezone],
        ["system", Installer.tier === "server" ? "server" : (Installer.tier === "desktop-sleex" ? "desktop (sleex)" : "desktop (the line)")]
    ]

    Column {
        width: parent.width
        spacing: Theme.u(24)

        Column {
            width: parent.width
            Repeater {
                model: page.rows
                Item {
                    required property var modelData
                    width: parent.width
                    height: Theme.u(24)
                    Text {
                        text: modelData[0]
                        color: Theme.muted
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.u(11)
                    }
                    Text {
                        x: Theme.u(120)
                        width: parent.width - x
                        text: modelData[1]
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.u(12)
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
