pragma Singleton

import QtQuick
import Quickshell

// Every colour and font the installer uses, straight from THE_LINE_STYLE_GUIDE.md §3. Kira violet is fixed:
// a product with an identity of its own (the installer) does not offer the accent choice.
Singleton {
    readonly property color bg: "#000000"
    readonly property color surface: "#1B1A18"
    readonly property color surface2: "#24221F"
    readonly property color border: "#3A3631"
    readonly property color borderStrong: "#5A544C"
    readonly property color text: "#ECE8E1"
    readonly property color muted: "#9C968C"
    readonly property color accent: "#9A5CFF"
    readonly property color accentText: "#0F0D12"
    readonly property color ok: "#6CC495"
    readonly property color error: "#EF7A5E"
    readonly property color accentTint: Qt.tint(surface, Qt.rgba(accent.r, accent.g, accent.b, 0.14))

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
