import QtQuick
import qs.components
import qs.services

Page {
    id: page
    title: "which *keyboard* is this?"
    sub: "it applies right now, and to the installed system."
    hint: "↑↓ move   a letter jumps   → go on   ← back"

    readonly property var names: Installer.keymaps
    property int sel: Math.max(0, names.indexOf(Installer.keymap))

    onSelChanged: {
        list.positionViewAtIndex(sel, ListView.Contain);
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down) {
            sel = Math.min(names.length - 1, sel + 1);
            Installer.applyKeymap(names[sel]);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            sel = Math.max(0, sel - 1);
            Installer.applyKeymap(names[sel]);
            event.accepted = true;
        } else if (event.text.length === 1 && /[a-z0-9]/i.test(event.text) && !event.modifiers) {
            // typing is read on the layout being chosen, so a letter is only a jump to the first name that starts with it
            const i = names.findIndex(n => n.startsWith(event.text.toLowerCase()));
            if (i >= 0) {
                sel = i;
                Installer.applyKeymap(names[sel]);
            }
            event.accepted = true;
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        model: page.names
        boundsBehavior: Flickable.StopAtBounds
        delegate: ListRow {
            required property string modelData
            required property int index
            label: modelData
            sub: modelData === "us" ? "default" : ""
            selected: index === page.sel
            onClicked: {
                page.sel = index;
                Installer.applyKeymap(modelData);
            }
        }
    }
}
