import QtQuick
import qs.components
import qs.services

Page {
    id: page
    title: "Where *are* you?"
    sub: "Type to filter, or write a Region/City of your own."
    typing: true
    hint: "↑↓ move   enter go on   alt+← back   esc leave"
    ready: current !== ""

    readonly property string q: field.text.trim().toLowerCase()
    readonly property var shown: Installer.timezones.filter(t => q === "" || t.toLowerCase().indexOf(q) >= 0)
    property int sel: 0
    readonly property bool custom: shown.length === 0 && /^[A-Za-z_]+\/[A-Za-z_+\-0-9\/]+$/.test(field.text.trim())
    readonly property string current: custom ? field.text.trim() : (shown[sel] ?? "")

    onShownChanged: sel = 0
    onCurrentChanged: if (current !== "")
        Installer.timezone = current

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Down) {
            sel = Math.min(shown.length - 1, sel + 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            sel = Math.max(0, sel - 1);
            event.accepted = true;
        }
    }

    Column {
        anchors.fill: parent
        spacing: Theme.u(12)

        Field {
            id: field
            focus: true
            placeholder: Installer.timezone
            onAccepted: if (page.ready)
                Installer.next()
        }

        Text {
            visible: page.shown.length === 0
            text: page.custom ? "Not in the list: " + field.text.trim() + " will be used as typed." : "Nothing matches."
            color: Theme.read
            font.family: Theme.fontUi
            font.pixelSize: Theme.u(15)
        }

        ListView {
            width: parent.width
            height: parent.height - Theme.u(64)
            clip: true
            model: page.shown
            currentIndex: page.sel
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            boundsBehavior: Flickable.StopAtBounds
            delegate: ListRow {
                required property string modelData
                required property int index
                label: modelData.split("/").pop().replace(/_/g, " ")
                sub: modelData.indexOf("/") >= 0 ? modelData.split("/")[0] : ""
                selected: index === page.sel
                onClicked: page.sel = index
            }
        }
    }
}
