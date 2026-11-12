import QtQuick
import qs.components
import qs.services

Page {
    id: page
    title: "What is this computer *called*?"
    sub: "Letters, numbers and hyphens. It can change later, in a plain file."
    typing: true
    hint: "enter go on   alt+← back   esc leave"
    readonly property bool valid: /^[a-zA-Z0-9-]+$/.test(field.text)
    ready: valid
    notice: field.text !== "" && !valid ? "letters, numbers and hyphens only." : ""

    Field {
        id: field
        focus: true
        text: Installer.hostname
        placeholder: "kira"
        invalid: field.text !== "" && !page.valid
        onTextChanged: Installer.hostname = text
        onAccepted: if (page.ready)
            Installer.next()
    }
}
