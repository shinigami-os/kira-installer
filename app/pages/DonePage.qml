import QtQuick
import qs.components
import qs.services

Page {
    title: "*Done*."
    sub: "Kira is installed. Remove the USB stick, then reboot."
    hint: "r reboot   p power off"
    ready: false

    Choice {
        focus: true
        current: ""
        options: [
            { key: "r", label: "Reboot", sub: "Into Kira" },
            { key: "p", label: "Power off", sub: "Switch the machine off" }
        ]
        onPicked: key => key === "r" ? Installer.reboot() : Installer.powerOff()
    }
}
