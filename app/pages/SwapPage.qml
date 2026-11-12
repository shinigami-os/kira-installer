import QtQuick
import TheLine.Ui
import qs.components
import qs.services

Page {
    id: page
    title: "Some *swap*?"
    sub: "Disk space the system can borrow as memory. Optional."
    hint: "a letter picks   → go on   ← back"

    readonly property var sizes: ({ n: 0, "2": 2048, "4": 4096, "8": 8192, "6": 16384 })
    // swap has to leave a root of at least 15 GiB in the space it is carved from
    readonly property real room: (Installer.mode === "free" ? Installer.freeMib : Installer.diskMib - 513) - Installer.minMib

    function opt(key, label) {
        return {
            key: key,
            label: label,
            sub: sizes[key] + " MiB",
            disabled: sizes[key] > room
        };
    }

    Choice {
        focus: true
        current: Object.keys(page.sizes).find(k => page.sizes[k] === Installer.swapMib) ?? "n"
        options: [page.opt("n", "None"), page.opt("2", "2 GiB"), page.opt("4", "4 GiB"), page.opt("8", "8 GiB"), page.opt("6", "16 GiB")]
        onPicked: key => Installer.swapMib = page.sizes[key]
    }
}
