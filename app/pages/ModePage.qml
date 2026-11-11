import QtQuick
import qs.components
import qs.services

Page {
    id: page
    title: "how much of it?"
    sub: "/dev/" + Installer.disk
    hint: "w whole   f free space   → go on   ← back"
    ready: Installer.mode !== ""
    notice: !Installer.wholeOk && !Installer.freeOk ? "this disk is too small: kira needs at least 15 GiB." : ""

    Choice {
        id: choice
        focus: true
        current: Installer.mode === "whole" ? "w" : (Installer.mode === "free" ? "f" : "")
        options: [
            {
                key: "w",
                label: "Erase the whole disk",
                sub: Installer.wholeOk ? Installer.human(Installer.diskBytes) + ", all of it" : "too small",
                disabled: !Installer.wholeOk
            },
            {
                key: "f",
                label: "Use the free space",
                sub: Installer.freeOk ? Installer.humanMib(Installer.freeMib) + ", the rest stays" : "needs 15 GiB free",
                disabled: !Installer.freeOk
            }
        ]
        onPicked: key => Installer.mode = key === "w" ? "whole" : "free"
    }

    Text {
        y: Theme.u(100)
        width: parent.width
        text: Installer.mode === "whole" ? "a fresh gpt table: a 512 MiB boot partition, then the system. every partition on this disk goes." : (Installer.mode === "free" ? "a new partition in the largest free region (" + Installer.freeStart + " – " + Installer.freeEnd + " MiB). the boot partition already there is reused. nothing else is touched." : "")
        wrapMode: Text.WordWrap
        color: Theme.muted
        font.family: Theme.fontMono
        font.pixelSize: Theme.u(12)
    }
}
