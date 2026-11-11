import QtQuick
import qs.services

// The steps are the ruler (style guide §8.2): one tick per step along a 1 px line, the current one the accent marker
// (it slides, it never jumps), past ones in text, future ones in border.
Item {
    id: ruler

    property int count: 1
    property int current: 0
    readonly property real step: width / count

    height: Theme.u(24)

    Rectangle {
        y: parent.height - 1
        width: parent.width
        height: 1
        color: Theme.borderStrong
    }

    Repeater {
        model: ruler.count
        Rectangle {
            required property int index
            x: Math.round(ruler.step * (index + 0.5)) - 1
            y: ruler.height - 1 - height
            width: 1
            height: Theme.u(8)
            color: index < ruler.current ? Theme.text : Theme.border
            Behavior on color {
                ColorAnimation { duration: Anim.base }
            }
        }
    }

    Rectangle {
        id: marker
        x: Math.round(ruler.step * (ruler.current + 0.5)) - width / 2
        y: ruler.height - 2
        width: Theme.u(14)
        height: 3
        color: Theme.accent
        Behavior on x {
            NumberAnimation { duration: Anim.panel; easing.type: Anim.easing }
        }
    }
}
