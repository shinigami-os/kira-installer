import QtQuick
import qs.services

// Raleway text where one or two *words* between stars are lit in the accent (style guide §9).
Text {
    property string markup

    readonly property string escaped: markup.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    text: escaped.replace(/\*([^*]+)\*/g, "<font color=\"" + Theme.accent + "\">$1</font>")
    textFormat: Text.RichText
    wrapMode: Text.WordWrap
    color: Theme.text
    font.family: Theme.fontUi
    font.pixelSize: Theme.u(34)
    font.weight: Font.Light
}
