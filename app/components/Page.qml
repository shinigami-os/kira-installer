import QtQuick
import qs.services

// A screen: centred narration (a big sentence, a muted line under it), the choice below, hints at the bottom.
// One decision per screen. The three parts arrive one after another, each fading in with a 4 px slide.
FocusScope {
    id: page

    property string title
    property string sub
    property string hint: "→ go on   ← back   esc leave"
    property bool typing: false      // a text field has the keys: ← is then alt+← (global back)
    property bool ready: true        // may the user go on?
    property string notice: ""       // a coral line under the choice, why not
    default property alias body: bodyHost.data
    readonly property real colW: Theme.u(640)

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

    Sentence {
        id: titleText
        x: (page.width - page.colW) / 2
        y: Theme.u(96) - (1 - opacity) * Theme.u(4)
        width: page.colW
        markup: page.title
        opacity: page.prog(0)
    }

    Text {
        id: subText
        x: titleText.x
        y: titleText.y + titleText.height + Theme.u(12) + (1 - opacity) * Theme.u(4)
        width: page.colW
        text: page.sub
        visible: text !== ""
        wrapMode: Text.WordWrap
        color: Theme.muted
        font.family: Theme.fontUi
        font.pixelSize: Theme.u(18)
        opacity: page.prog(Anim.itemStart)
    }

    Item {
        id: bodyHost
        x: titleText.x
        y: (subText.visible ? subText.y + subText.height : titleText.y + titleText.height) + Theme.u(36) + (1 - opacity) * Theme.u(4)
        width: page.colW
        height: page.height - y - Theme.u(120)
        opacity: page.prog(Anim.itemStart + Anim.stagger * 2)
    }

    Text {
        x: titleText.x
        y: page.height - Theme.u(150)
        width: page.colW
        text: page.notice
        visible: text !== ""
        color: Theme.error
        font.family: Theme.fontMono
        font.pixelSize: Theme.u(12)
        wrapMode: Text.WordWrap
    }
}
