pragma Singleton

import QtQuick
import Quickshell

// Every colour and font the installer uses: The Line's, laid out like its settings app (a window, a panel in it,
// lit rows). Kira violet is fixed: the installer has an identity of its own and offers no accent choice.
Singleton {
    readonly property color bg: "#1B1A18"          // the window
    readonly property color panel: "#262420"       // the current step's panel
    readonly property color row: "#302D29"         // a lit row
    readonly property color inset: "#161513"       // a field, sunk into the panel
    readonly property color border: "#3A3631"
    readonly property color borderStrong: "#5A544C"
    readonly property color text: "#ECE8E1"
    readonly property color read: "#B8B1A6"        // running text on the panel
    readonly property color muted: "#9C968C"
    readonly property color faint: "#77716A"
    readonly property color accent: "#9A5CFF"
    readonly property color accentSoft: "#B892FF"  // the accent for small text on the panel
    readonly property color accentText: "#0F0D12"
    readonly property color ok: "#6CC495"
    readonly property color error: "#EF7A5E"
    readonly property color accentTint: Qt.tint(panel, Qt.rgba(accent.r, accent.g, accent.b, 0.16))

    readonly property string fontUi: "Raleway"
    readonly property string fontMono: Qt.fontFamilies().indexOf("IBM Plex Mono") >= 0 ? "IBM Plex Mono" : "JetBrains Mono"

    // Square corners, always.
    readonly property int radius: 0

    // Sizes are written for a 768 px tall screen and scaled to the real one (set by shell.qml).
    property real scale: 1
    function u(n) {
        return Math.max(1, Math.round(n * scale));
    }
}
