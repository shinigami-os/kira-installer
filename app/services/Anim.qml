pragma Singleton

import QtQuick
import Quickshell

// The whole motion system (style guide §6): one curve, a few durations, all through d().
// KIRA_REDUCE_MOTION=1 makes every duration 1 ms.
Singleton {
    readonly property bool reduce: Quickshell.env("KIRA_REDUCE_MOTION") === "1"

    // Quartic ease-out. Used for everything that moves or resizes.
    readonly property int easing: Easing.OutQuart

    function d(ms) {
        return reduce ? 1 : ms;
    }

    // The same curve as a function, for animations driven by hand (staggers).
    function out(p) {
        const q = 1 - Math.max(0, Math.min(1, p));
        return 1 - q * q * q * q;
    }

    readonly property int press: d(90)
    readonly property int hover: d(120)
    readonly property int base: d(180)
    readonly property int panel: d(260)
    readonly property int exitFade: d(90)
    readonly property int line: d(420)      // the line drawing itself across a dialog

    readonly property int itemStart: d(110)
    readonly property int stagger: d(24)
}
