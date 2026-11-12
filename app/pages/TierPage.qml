import QtQuick
import TheLine.Ui
import qs.components
import qs.services

Page {
    title: "What kind of *system*?"
    sub: "The others can be added later, with flux."
    hint: "l the line   s sleex   v server   → go on   ← back"

    Choice {
        focus: true
        current: Installer.tier === "server" ? "v" : (Installer.tier === "desktop-sleex" ? "s" : "l")
        options: [
            { key: "l", label: "The Line", sub: "Kira's own desktop: one line across the top of the screen" },
            { key: "s", label: "Sleex", sub: "The AxOS desktop: a bar, a dashboard, a dock" },
            { key: "v", label: "Server", sub: "A shell and nothing else" }
        ]
        onPicked: key => Installer.tier = key === "v" ? "server" : (key === "s" ? "desktop-sleex" : "desktop-the-line")
    }
}
