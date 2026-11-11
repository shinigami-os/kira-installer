import QtQuick
import qs.components
import qs.services

Page {
    title: "*done*."
    sub: "kira is installed. remove the usb stick, then reboot."
    hint: "r reboot   p power off"
    ready: false

    Choice {
        focus: true
        current: ""
        options: [
            { key: "r", label: "Reboot", sub: "into kira" },
            { key: "p", label: "Power off", sub: "switch the machine off" }
        ]
        onPicked: key => key === "r" ? Installer.reboot() : Installer.powerOff()
    }
}
