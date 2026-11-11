//@ pragma UseQApplication
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic

import QtQuick
import Quickshell
import qs.components
import qs.services

// The Kira Linux installer, a Quickshell app styled after The Line (THE_LINE_STYLE_GUIDE.md).
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
        color: Theme.bg
        title: "Kira Linux installer"
        implicitWidth: Quickshell.screens[0]?.width ?? 1280
        implicitHeight: Quickshell.screens[0]?.height ?? 800

        Item {
            id: stage
            anchors.fill: parent
            focus: true

            Binding {
                target: Theme
                property: "scale"
                value: Math.max(0.75, stage.height / 768)
            }

            Component.onCompleted: Installer.probeAll()

            readonly property var page: loader.item

            function pageFile(id) {
                return "pages/" + id.charAt(0).toUpperCase() + id.slice(1) + "Page.qml";
            }

            Keys.onPressed: event => {
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

            Loader {
                id: loader
                anchors.fill: parent
                source: stage.pageFile(Installer.current)
                onLoaded: item.forceActiveFocus()
            }

            Ruler {
                x: Theme.u(80)
                y: parent.height - Theme.u(76)
                width: parent.width - Theme.u(160)
                count: Installer.steps.length
                current: Installer.index
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height - Theme.u(44)
                text: stage.page ? stage.page.hint : ""
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: Theme.u(11)
            }

            LeaveDialog {
                id: leave
                anchors.fill: parent
                open: Installer.leaving
                question: Installer.dry ? "leave the installer?" : "power off the computer?"
                yes: Installer.dry ? "leave" : "power off"
                onConfirmed: Installer.powerOff()
                onDismissed: {
                    Installer.leaving = false;
                    if (stage.page)
                        stage.page.forceActiveFocus();
                }
            }
        }
    }
}
