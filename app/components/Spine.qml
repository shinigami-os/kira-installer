import QtQuick
import qs.services

// The steps, as the settings app's spine: a number left of a vertical line, a short tick across it, the name.
// Past steps are lit a little (and can be clicked back to, until the install), the current one has the accent marker
// on the line and a line running from its name to the panel's edge (`reach`, in this item's coordinates).
Item {
    id: spine

    property real reach: width
    readonly property real lineX: Theme.u(52)
    readonly property real rowH: Theme.u(36)

    Rectangle {
        x: spine.lineX
        width: 1
        height: parent.height
        color: Theme.borderStrong
    }

    Column {
        y: Theme.u(24)
        width: parent.width

        Repeater {
            model: Installer.steps

            Item {
                id: step
                required property string modelData
                required property int index
                readonly property bool now: index === Installer.index
                readonly property bool past: index < Installer.index
                readonly property bool reachable: step.past && !Installer.locked

                width: spine.width
                height: spine.rowH

                Text {
                    x: Theme.u(18)
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(step.index + 1).padStart(2, "0")
                    color: step.now ? Theme.accentSoft : Theme.faint
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.u(11)
                }
                Rectangle {
                    x: spine.lineX - Theme.u(3)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Theme.u(7)
                    height: 1
                    color: Theme.borderStrong
                }
                Rectangle {
                    x: spine.lineX - 1
                    y: Theme.u(7)
                    width: 3
                    height: parent.height - Theme.u(14)
                    color: Theme.accent
                    opacity: step.now ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Anim.base; easing.type: Anim.easing }
                    }
                }
                Text {
                    id: label
                    x: spine.lineX + Theme.u(18)
                    anchors.verticalCenter: parent.verticalCenter
                    text: Installer.names[step.modelData] ?? step.modelData
                    color: step.now ? Theme.text : (step.past ? (hover.hovered && step.reachable ? Theme.text : Theme.muted) : Theme.faint)
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.u(step.now ? 16 : 15)
                    Behavior on color {
                        ColorAnimation { duration: Anim.hover }
                    }
                }
                // from the current step's name into its panel
                Rectangle {
                    x: label.x + label.implicitWidth + Theme.u(14)
                    anchors.verticalCenter: parent.verticalCenter
                    width: step.now ? Math.max(0, spine.reach - x) : 0
                    height: 1
                    color: Theme.borderStrong
                    Behavior on width {
                        NumberAnimation { duration: Anim.panel; easing.type: Anim.easing }
                    }
                }

                HoverHandler {
                    id: hover
                    cursorShape: step.reachable ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
                TapHandler {
                    onTapped: if (step.reachable)
                        Installer.goTo(step.modelData)
                }
            }
        }
    }
}
