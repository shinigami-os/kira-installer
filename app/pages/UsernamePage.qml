import QtQuick
import qs.components
import qs.services

Page {
    id: page
    title: "who is *using* it?"
    sub: "your account. you get sudo through the wheel group."
    typing: true
    hint: "enter go on   alt+← back   esc leave"
    readonly property bool valid: /^[a-z_][a-z0-9_-]*$/.test(field.text)
    ready: valid
    notice: field.text !== "" && !valid ? "lowercase letters, numbers, _ and -, starting with a letter or _." : ""

    Field {
        id: field
        focus: true
        text: Installer.username
        placeholder: "kira"
        invalid: field.text !== "" && !page.valid
        onTextChanged: Installer.username = text
        onAccepted: if (page.ready)
            Installer.next()
    }
}
