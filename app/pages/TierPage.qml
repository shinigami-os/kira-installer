import QtQuick
import qs.components
import qs.services

Page {
    title: "what kind of *system*?"
    sub: "you can add the others later with flux."
    hint: "l the line   s sleex   v server   → go on   ← back"

    Choice {
        focus: true
        current: Installer.tier === "server" ? "v" : (Installer.tier === "desktop-sleex" ? "s" : "l")
        options: [
            { key: "l", label: "The Line", sub: "kira's own desktop" },
            { key: "s", label: "Sleex", sub: "the AxOS desktop" },
            { key: "v", label: "Server", sub: "a shell and nothing else" }
        ]
        onPicked: key => Installer.tier = key === "v" ? "server" : (key === "s" ? "desktop-sleex" : "desktop-the-line")
    }
}
