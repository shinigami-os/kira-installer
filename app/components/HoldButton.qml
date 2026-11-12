import QtQuick
import qs.services

// Hold to confirm. For anything destructive: the word and the border are coral (never a red fill),
// a line fills along the bottom while it is held. Pages call press()/release() for the keyboard.
Item {
    id: btn

    property string label
    property int holdMs: 1500
    property real held: 0     // 0..1
    signal confirmed

    width: Theme.u(460)
    height: Theme.u(56)

    function press() {
        if (!clock.running) {
            clock.startedAt = Date.now();
            clock.running = true;
        }
    }
    function release() {
        clock.running = false;
        drain.restart();
    }

    Timer {
        id: clock
        property double startedAt: 0
        interval: 16
        repeat: true
        onTriggered: {
            btn.held = Math.min(1, (Date.now() - startedAt) / btn.holdMs);
            if (btn.held >= 1) {
                running = false;
                btn.confirmed();
            }
        }
    }
    NumberAnimation {
        id: drain
        target: btn
        property: "held"
        to: 0
        duration: Anim.d(240)
        easing.type: Anim.easing
    }

    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: 1
        border.color: Theme.error
    }
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width * btn.held
        height: 3
        color: Theme.error
    }
    Text {
        anchors.centerIn: parent
        text: btn.label
        color: Theme.error
        font.family: Theme.fontUi
        font.pixelSize: Theme.u(16)
        font.weight: Font.Medium
    }

    // held with the pointer: pressed starts the clock, letting go before the end drains it
    TapHandler {
        gesturePolicy: TapHandler.WithinBounds
        onPressedChanged: pressed ? btn.press() : btn.release()
    }
}
