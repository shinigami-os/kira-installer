import QtQuick
import qs.components
import qs.services

Page {
    id: page
    title: "A *password* for " + Installer.username + "."
    sub: "Typed as ticks. Nobody is looking, but still."
    typing: true
    hint: "enter next field   alt+← back   esc leave"
    readonly property bool match: first.text === second.text
    ready: first.text !== "" && match
    notice: second.text !== "" && !match ? "not the same twice." : ""

    Column {
        width: parent.width
        spacing: Theme.u(12)

        Field {
            id: first
            focus: true
            secret: true
            text: Installer.userPass
            placeholder: "password"
            onTextChanged: Installer.userPass = text
            onAccepted: second.forceActive()
        }
        Field {
            id: second
            secret: true
            placeholder: "again"
            invalid: second.text !== "" && !page.match
            onAccepted: if (page.ready)
                Installer.next()
        }
    }
}
