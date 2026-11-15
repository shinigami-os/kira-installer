//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import TheLine.Ui
import Quickshell
import qs.components
import qs.services

// The Kira Linux installer, a Quickshell app laid out like The Line's settings app.
// Launched by launch.sh, inside cage, on the live medium: no session, no login, nothing to start by hand.
// KI_DRY=1 tries the whole thing in a window without writing to any disk. KIRA_REDUCE_MOTION=1 turns the motion off.
//
// Keys: → / enter go on, ← back, ↑↓ move in a list, a letter picks an option, esc asks before powering off
// (there is nothing to leave to on the live medium; with KI_DRY=1 it just closes the window).
// On a screen with a text field the field owns ← and →: alt+← goes back there.
ShellRoot {
    FloatingWindow {
        id: win
        visible: true
        color: Theme.surface
        title: "Kira Linux installer"
        implicitWidth: Quickshell.screens[0]?.width ?? 1280
        implicitHeight: Quickshell.screens[0]?.height ?? 800

        Item {
            id: stage
            anchors.fill: parent
            focus: true

            // the design language (TheLine.Ui) drawn for this screen's size, in Kira violet
            Binding {
                target: Theme
                property: "scale"
                value: Math.max(0.75, stage.height / 768)
            }
            Binding {
                target: Anim
                property: "reduce"
                value: Quickshell.env("KIRA_REDUCE_MOTION") === "1"
            }

            Component.onCompleted: Installer.probeAll()

            readonly property var page: loader.item

            function pageFile(id) {
                return "pages/" + id.charAt(0).toUpperCase() + id.slice(1) + "Page.qml";
            }

            // The leave dialog is asked to take the keyboard, but the page keeps it for itself whenever it can (a text
            // field, a list): while the question is up the page is switched off, so the keys come here.
            function dismissLeave() {
                Installer.leaving = false;
                if (stage.page)
                    stage.page.forceActiveFocus();
            }

            Keys.onPressed: event => {
                if (Installer.leaving) {
                    if (event.text === "y")
                        Installer.powerOff();
                    else if (event.text === "n" || event.key === Qt.Key_Escape)
                        stage.dismissLeave();
                    event.accepted = true;
                    return;
                }
                const p = stage.page;
                const typing = p && p.typing;
                const alt = (event.modifiers & Qt.AltModifier) !== 0;
                if (event.key === Qt.Key_Escape) {
                    if (!Installer.locked)
                        Installer.leaving = true;
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left && (!typing || alt)) {
                    Installer.back();
                    event.accepted = true;
                } else if ((event.key === Qt.Key_Right && (!typing || alt)) || ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !typing)) {
                    if (p && p.ready)
                        Installer.next();
                    event.accepted = true;
                }
            }

            // the header: the logo, the app's name, and what kind of run this is; the line under it
            Item {
                id: header
                width: parent.width
                height: Theme.u(56)

                Image {
                    x: Theme.u(28)
                    anchors.verticalCenter: parent.verticalCenter
                    height: Theme.u(24)
                    fillMode: Image.PreserveAspectFit
                    source: "assets/kira-logo.png"
                    smooth: true
                    mipmap: true
                }
                Text {
                    x: Theme.u(62)
                    anchors.verticalCenter: parent.verticalCenter
                    text: "KIRA INSTALLER"
                    color: Theme.muted
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.u(12)
                    font.weight: Font.DemiBold
                    font.letterSpacing: Theme.u(2)
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.u(28)
                    anchors.verticalCenter: parent.verticalCenter
                    text: (Installer.checked ? (Installer.uefi ? "uefi" : "bios") : "…") + (Installer.dry ? "  ·  dry run, nothing is written" : "")
                    color: Installer.dry ? Theme.accentSoft : Theme.faint
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.u(12)
                }
                Rectangle {
                    y: parent.height - 1
                    width: parent.width
                    height: 1
                    color: Theme.borderStrong
                }
            }

            Spine {
                id: spine
                y: header.height
                width: Theme.u(260)
                height: parent.height - header.height
                reach: panel.x
            }

            // the current step, in its panel
            Rectangle {
                id: panel
                x: spine.width + Theme.u(14)
                y: header.height + Theme.u(24)
                width: Math.min(parent.width - x - Theme.u(28), Theme.u(900))
                height: parent.height - y - Theme.u(64)
                color: Theme.panel
                border.width: 1
                border.color: Theme.border

                Loader {
                    id: loader
                    anchors.fill: parent
                    anchors.margins: Theme.u(40)
                    anchors.bottomMargin: Theme.u(28)
                    source: stage.pageFile(Installer.current)
                    enabled: !Installer.leaving
                    onLoaded: item.forceActiveFocus()
                }
            }

            // what the keys do here
            Text {
                x: panel.x
                y: panel.y + panel.height + Theme.u(18)
                text: stage.page ? stage.page.hint : ""
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: Theme.u(12)
            }

            LeaveDialog {
                id: leave
                anchors.fill: parent
                open: Installer.leaving
                question: Installer.dry ? "leave the installer?" : "power off the computer?"
                yes: Installer.dry ? "leave" : "power off"
                onConfirmed: Installer.powerOff()
                onDismissed: stage.dismissLeave()
            }
        }
    }
}
