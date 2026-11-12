import QtQuick
import TheLine.Ui
import qs.components
import qs.services

Page {
    id: page
    title: "How much *of it*?"
    sub: "/dev/" + Installer.disk + (Installer.diskModel ? ", " + Installer.diskModel : "") + ", " + Installer.human(Installer.diskBytes)
    hint: "w whole   f free space   → go on   ← back"
    ready: Installer.mode !== ""
    notice: !Installer.wholeOk && !Installer.freeOk ? "this disk is too small: Kira needs at least 15 GiB." : ""

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
        y: choice.height + Theme.u(24)
        leftPadding: Theme.u(18)
        width: parent.width
        text: Installer.mode === "whole" ? "A fresh GPT table: a 512 MiB boot partition, then the system. Every partition on this disk goes." : (Installer.mode === "free" ? "A new partition in the largest free region (" + Installer.freeStart + " – " + Installer.freeEnd + " MiB). The boot partition already there is reused. Nothing else is touched." : "")
        wrapMode: Text.WordWrap
        color: Theme.read
        font.family: Theme.fontUi
        font.pixelSize: Theme.u(15)
    }
}
