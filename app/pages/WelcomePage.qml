import QtQuick
import TheLine.Ui
import qs.components
import qs.services

Page {
    title: "Welcome to *Kira*."
    sub: "A Linux distribution you actually understand."
    // a dry run writes nothing, so it may also run without root, to look at it
    ready: Installer.uefi && (Installer.isRoot || Installer.dry)
    notice: !Installer.isRoot && !Installer.dry ? "not running as root: this cannot work." : (!Installer.uefi ? "this computer did not start in UEFI mode. Kira installs on UEFI only." : "")
    hint: "→ go on   esc leave"

    Row {
        width: parent.width
        spacing: Theme.u(40)

        Image {
            width: Theme.u(120)
            height: Theme.u(178)
            fillMode: Image.PreserveAspectFit
            source: "../assets/kira-logo.png"
            smooth: true
            mipmap: true
        }

        Column {
            width: parent.width - Theme.u(160)
            spacing: Theme.u(18)

            Text {
                width: parent.width
                text: "A few questions, then it installs. Nothing is written to a disk until you say so, and you will be told exactly what."
                wrapMode: Text.WordWrap
                lineHeight: 1.3
                color: Theme.read
                font.family: Theme.fontUi
                font.pixelSize: Theme.u(17)
            }

            Column {
                width: parent.width
                Repeater {
                    model: [
                        ["the keyboard", "← → and Enter move between the steps"],
                        ["a list", "↑ ↓ move in it, a letter picks"],
                        ["leaving", "Esc asks first: nothing has been written"],
                        ["the system", "The Line, Sleex or a server, near the end"]
                    ]
                    Item {
                        required property var modelData
                        width: parent.width
                        height: Theme.u(32)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[0]
                            color: Theme.faint
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.u(13)
                        }
                        Text {
                            x: Theme.u(130)
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]
                            color: Theme.read
                            font.family: Theme.fontUi
                            font.pixelSize: Theme.u(15)
                        }
                    }
                }
            }
        }
    }
}
