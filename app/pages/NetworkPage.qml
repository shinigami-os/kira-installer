import QtQuick
import qs.components
import qs.services

Page {
    id: page
    title: Installer.online ? "You are *online*." : "Get *online*."
    sub: Installer.online ? "The packages will come from the network." : "The packages come from the network. Skip it if you know better."
    hint: pw.visible ? "enter connect   esc back to the list" : "↑↓ move   enter connect   r rescan   → go on   ← back"
    typing: pw.visible

    property int sel: 0
    readonly property var chosen: Installer.wifi[sel]
    property bool asking: false

    Component.onCompleted: {
        Installer.checkOnline();
        Installer.scanWifi();
    }

    function connect() {
        if (!chosen)
            return;
        if (chosen.secured && !chosen.active) {
            asking = true;
            pwField.text = "";
            pwField.forceActive();
        } else {
            Installer.connectWifi(chosen.ssid, "");
        }
    }

    Keys.onPressed: event => {
        if (asking) {
            if (event.key === Qt.Key_Escape) {
                asking = false;
                page.forceActiveFocus();
                event.accepted = true;
            }
            return;
        }
        if (event.key === Qt.Key_Down) {
            sel = Math.min(Installer.wifi.length - 1, sel + 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            sel = Math.max(0, sel - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (chosen) {
                connect();
                event.accepted = true;
            }
        } else if (event.text === "r") {
            Installer.scanWifi();
            event.accepted = true;
        }
    }

    Column {
        width: parent.width
        spacing: Theme.u(12)

        Text {
            visible: Installer.wifi.length === 0
            text: Installer.wifiBusy ? "Looking for networks…" : "No Wi-Fi network found. A cable works without asking."
            color: Theme.read
            font.family: Theme.fontUi
            font.pixelSize: Theme.u(15)
        }

        ListView {
            id: list
            width: parent.width
            height: Math.min(contentHeight, parent.parent.height - Theme.u(120))
            clip: true
            model: Installer.wifi
            boundsBehavior: Flickable.StopAtBounds
            currentIndex: page.sel
            onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
            delegate: ListRow {
                required property var modelData
                required property int index
                label: modelData.ssid
                sub: (modelData.active ? "connected  ·  " : "") + (modelData.secured ? "locked  ·  " : "") + modelData.signal + " %"
                subColor: modelData.active ? Theme.ok : Theme.muted
                selected: index === page.sel
                onClicked: {
                    page.sel = index;
                    page.connect();
                }
            }
        }

        Item {
            id: pw
            visible: page.asking
            width: parent.width
            height: Theme.u(52)
            Field {
                id: pwField
                secret: true
                placeholder: "password for " + (page.chosen ? page.chosen.ssid : "")
                onAccepted: {
                    Installer.connectWifi(page.chosen.ssid, text);
                    page.asking = false;
                    page.forceActiveFocus();
                }
            }
        }

        Text {
            text: Installer.wifiBusy ? "…" : Installer.wifiMessage
            visible: text !== ""
            color: Installer.wifiBusy ? Theme.muted : Theme.error
            font.family: Theme.fontMono
            font.pixelSize: Theme.u(13)
        }
    }
}
