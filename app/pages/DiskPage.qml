import QtQuick
import qs.components
import qs.services

Page {
    id: page
    title: "which *disk*?"
    sub: "kira goes on one disk. the next screen says how much of it."
    hint: "↑↓ move   → go on   ← back"
    ready: Installer.disk !== ""
    notice: Installer.disks.length === 0 ? "no disk found." : ""

    property int sel: Math.max(0, Installer.disks.findIndex(d => d.name === Installer.disk))
    readonly property var chosen: Installer.disks[sel]

    function choose(i) {
        const d = Installer.disks[i];
        if (!d || d.live)
            return;
        sel = i;
        Installer.selectDisk(d);
    }

    Component.onCompleted: if (Installer.disk === "")
        choose(Installer.disks.findIndex(d => !d.live))

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down) {
            choose(Math.min(Installer.disks.length - 1, sel + 1));
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            choose(Math.max(0, sel - 1));
            event.accepted = true;
        }
    }

    Column {
        width: parent.width
        spacing: Theme.u(18)

        Column {
            width: parent.width
            Repeater {
                model: Installer.disks
                ListRow {
                    required property var modelData
                    required property int index
                    label: "/dev/" + modelData.name + (modelData.model ? "   " + modelData.model : "")
                    sub: modelData.live ? "the medium you booted from" : Installer.human(modelData.bytes)
                    subColor: modelData.live ? Theme.error : Theme.muted
                    disabled: modelData.live
                    selected: index === page.sel && !modelData.live
                    onClicked: page.choose(index)
                }
            }
        }

        // what is on it now, so nobody finds out later
        Column {
            width: parent.width
            visible: Installer.layout.length > 0
            spacing: 2
            Text {
                text: "ON IT NOW"
                color: Theme.muted
                font.family: Theme.fontUi
                font.pixelSize: Theme.u(10)
                font.weight: Font.DemiBold
                font.letterSpacing: 0.8
            }
            Repeater {
                model: Installer.layout.slice(0, 8)
                Text {
                    required property var modelData
                    text: modelData.name.padEnd(18) + modelData.size.padEnd(10) + modelData.fs + (modelData.label ? "  " + modelData.label : "")
                    color: Theme.muted
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.u(11)
                }
            }
        }
    }
}
