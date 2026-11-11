import QtQuick
import qs.components
import qs.services

Page {
    id: page
    title: "and for *root*?"
    sub: "the account that can break everything. the same password is fine."
    hint: Installer.rootSame ? "s same   d different   → go on   ← back" : "enter next field   alt+← back   esc leave"
    typing: !Installer.rootSame
    readonly property bool match: first.text === second.text
    ready: Installer.rootSame || (first.text !== "" && match)
    notice: !Installer.rootSame && second.text !== "" && !match ? "not the same twice." : ""

    Column {
        width: parent.width
        spacing: Theme.u(24)

        Choice {
            id: choice
            focus: Installer.rootSame
            current: Installer.rootSame ? "s" : "d"
            options: [
                { key: "s", label: "Same as " + Installer.username, sub: "one password" },
                { key: "d", label: "A different one", sub: "root only" }
            ]
            onPicked: key => {
                Installer.rootSame = key === "s";
                if (!Installer.rootSame)
                    first.forceActive();
                else
                    choice.forceActiveFocus();
            }
        }

        Column {
            visible: !Installer.rootSame
            width: parent.width
            spacing: Theme.u(12)
            Field {
                id: first
                secret: true
                text: Installer.rootPass
                placeholder: "root password"
                onTextChanged: Installer.rootPass = text
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
}
