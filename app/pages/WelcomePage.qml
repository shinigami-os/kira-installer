import QtQuick
import qs.components
import qs.services

Page {
    title: "welcome to *Kira*."
    sub: "a linux distribution you actually understand."
    ready: Installer.uefi && Installer.isRoot
    notice: !Installer.isRoot ? "not running as root. this cannot work." : (!Installer.uefi ? "this machine did not boot in uefi mode. kira installs on uefi only." : "")
    hint: "→ go on   esc leave"

    Column {
        width: parent.width
        spacing: Theme.u(18)

        Text {
            width: parent.width
            text: "a few questions, then it installs. nothing is written to a disk until you say so, and you will be told exactly what."
            wrapMode: Text.WordWrap
            color: Theme.muted
            font.family: Theme.fontUi
            font.pixelSize: Theme.u(15)
        }
        Text {
            text: (Installer.uefi ? "uefi" : "bios") + (Installer.dry ? "  ·  dry run" : "")
            color: Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: Theme.u(11)
        }
    }
}
