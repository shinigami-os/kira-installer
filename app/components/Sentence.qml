import QtQuick
import qs.services

// The step's question: Raleway, one or two *words* between stars lit in the accent.
Text {
    property string markup
    property color mark: Theme.accentSoft    // coral where the lit word is what gets destroyed

    readonly property string escaped: markup.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    text: escaped.replace(/\*([^*]+)\*/g, "<font color=\"" + mark + "\">$1</font>")
    textFormat: Text.RichText
    wrapMode: Text.WordWrap
    color: Theme.text
    font.family: Theme.fontUi
    font.pixelSize: Theme.u(32)
    font.weight: Font.Normal
}
