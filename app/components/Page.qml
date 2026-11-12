import QtQuick
import TheLine.Ui
import qs.services

// A step, inside its panel: the question as the panel's title with the step's number after it ("Disk 04" in the
// settings app), a line under it saying why, then the choice. One decision per step. The parts arrive one after
// another, each fading in with a 4 px slide.
FocusScope {
    id: page

    property string title
    property string sub
    property bool destructive: false   // the title's lit word is what gets erased: coral, not violet
    property string hint: "→ go on   ← back   esc leave"
    property bool typing: false      // a text field has the keys: ← is then alt+← (global back)
    property bool ready: true        // may the user go on?
    property string notice: ""       // a coral line at the bottom, why not
    default property alias body: bodyHost.data

    // 0 → total ms; each part reads its own progress out of it.
    property real el: 0
    NumberAnimation on el {
        from: 0
        to: Anim.itemStart + Anim.stagger * 3 + Anim.base
        duration: Anim.d(Anim.itemStart + Anim.stagger * 3 + Anim.base)
    }
    function prog(delay) {
        return Anim.out((el - delay) / Anim.base);
    }

    Row {
        id: head
        y: (1 - opacity) * Theme.u(4)
        width: page.width
        spacing: Theme.u(14)
        opacity: page.prog(0)

        Sentence {
            id: titleText
            width: Math.min(implicitWidth, page.width - Theme.u(60))
            markup: page.title
            mark: page.destructive ? Theme.error : Theme.accentSoft
        }
        Text {
            anchors.baseline: titleText.baseline
            text: String(Installer.index + 1).padStart(2, "0")
            color: Theme.accentSoft
            font.family: Theme.fontMono
            font.pixelSize: Theme.u(13)
        }
    }

    Text {
        id: subText
        y: head.height + Theme.u(10) + (1 - opacity) * Theme.u(4)
        width: Math.min(page.width, Theme.u(720))
        text: page.sub
        visible: text !== ""
        wrapMode: Text.WordWrap
        color: Theme.read
        font.family: Theme.fontUi
        font.pixelSize: Theme.u(17)
        lineHeight: 1.3
        opacity: page.prog(Anim.itemStart)
    }

    Item {
        id: bodyHost
        y: (subText.visible ? subText.y + subText.height : head.height) + Theme.u(32) + (1 - opacity) * Theme.u(4)
        width: page.width
        height: page.height - y - Theme.u(36)
        opacity: page.prog(Anim.itemStart + Anim.stagger * 2)
    }

    Text {
        y: page.height - height
        width: page.width
        text: page.notice
        visible: text !== ""
        color: Theme.error
        font.family: Theme.fontMono
        font.pixelSize: Theme.u(13)
        wrapMode: Text.WordWrap
    }
}
