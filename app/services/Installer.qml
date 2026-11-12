pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// All the installer's state, and the only place that talks to the machine (through backend/kira-install-backend).
// Pages read and write the properties; nothing is written to a disk before start() is called from the review.
Singleton {
    id: root

    readonly property string backend: Quickshell.shellPath("backend/kira-install-backend")
    // KI_DRY=1: every probe is real, the install itself only walks its stages.
    readonly property bool dry: Quickshell.env("KI_DRY") === "1"

    // ---- the steps: one tick each on the ruler ----
    readonly property var steps: ["welcome", "keymap", "network", "disk", "mode", "swap", "hostname", "username", "password", "root", "timezone", "tier", "review", "install", "done"]
    // what each step is called on the spine
    readonly property var names: ({
        welcome: "Welcome", keymap: "Keyboard", network: "Network", disk: "Disk", mode: "How much of it", swap: "Swap",
        hostname: "Computer name", username: "You", password: "Password", root: "Root", timezone: "Time zone",
        tier: "System", review: "Review", install: "Install", done: "Done"
    })
    property int index: 0
    readonly property string current: steps[index]
    // From the install on there is no way back: the disk has been written to.
    readonly property bool locked: index >= steps.indexOf("install")
    property bool leaving: false

    // Next stops at the review: past it, only holding the button (start) moves on.
    function next() {
        if (index < steps.indexOf("review"))
            index++;
    }
    function back() {
        if (!locked && index > 0)
            index--;
    }
    function goTo(id) {
        index = steps.indexOf(id);
    }

    // ---- the machine ----
    property bool checked: false
    property bool uefi: true
    property bool isRoot: true

    // ---- the answers ----
    property string keymap: "us"
    property var keymaps: ["us"]
    property bool online: false
    property string disk: ""           // short name: nvme0n1
    property string diskModel: ""
    property real diskBytes: 0
    property var disks: []
    property var layout: []            // partitions of the chosen disk
    property real freeStart: 0         // MiB, largest free region of the chosen disk
    property real freeEnd: 0
    property string mode: ""           // "whole" | "free"
    property int swapMib: 0
    property string hostname: "kira"
    property string username: ""
    property string userPass: ""
    property bool rootSame: true
    property string rootPass: ""
    property string timezone: "UTC"
    property string tier: "desktop-the-line"   // "desktop-the-line" | "desktop-sleex" | "server"

    readonly property real minMib: 15360          // same floor as always: a minimal Kira root
    readonly property real diskMib: diskBytes / 1048576
    readonly property real freeMib: freeEnd - freeStart
    readonly property bool wholeOk: diskMib >= minMib
    readonly property bool freeOk: freeMib >= minMib

    // Curated: the live image has no tzdata to list. Anything else can be typed as Region/City.
    readonly property var timezones: ["UTC", "America/New_York", "America/Chicago", "America/Denver", "America/Los_Angeles", "America/Anchorage", "America/Sao_Paulo", "America/Mexico_City", "America/Toronto", "Europe/London", "Europe/Paris", "Europe/Berlin", "Europe/Madrid", "Europe/Rome", "Europe/Amsterdam", "Europe/Moscow", "Europe/Istanbul", "Africa/Cairo", "Africa/Johannesburg", "Africa/Lagos", "Asia/Dubai", "Asia/Kolkata", "Asia/Shanghai", "Asia/Tokyo", "Asia/Seoul", "Asia/Singapore", "Asia/Bangkok", "Asia/Jakarta", "Australia/Sydney", "Australia/Perth", "Pacific/Auckland"]

    // ---- helpers ----
    function pairs(line) {
        const o = {};
        const re = /(\w+)="([^"]*)"/g;
        let m;
        while ((m = re.exec(line)))
            o[m[1]] = m[2];
        return o;
    }
    function human(bytes) {
        const g = bytes / 1073741824;
        if (g >= 1000)
            return (g / 1024).toFixed(1) + " TiB";
        if (g >= 10)
            return Math.round(g) + " GiB";
        return g.toFixed(1) + " GiB";
    }
    function humanMib(mib) {
        return human(mib * 1048576);
    }

    // ---- probes ----
    function probeAll() {
        checkProc.running = true;
        keymapProc.running = true;
        disksProc.running = true;
        pingProc.running = true;
    }

    function selectDisk(d) {
        disk = d.name;
        diskModel = d.model;
        diskBytes = d.bytes;
        mode = "";
        freeStart = freeEnd = 0;
        layout = [];
        layoutProc.command = [backend, "layout", d.name];
        layoutProc.running = true;
        freeProc.command = [backend, "free", d.name];
        freeProc.running = true;
    }

    function applyKeymap(name) {
        keymap = name;
        // Only the console understands a bmap; failing here (not on a console, in a test) is fine.
        keymapApply.command = ["sh", "-c", "loadkmap < /usr/share/kira-keymaps/\"$1\".bmap", "sh", name];
        keymapApply.running = true;
    }

    function checkOnline() {
        pingProc.running = true;
    }

    Process {
        id: checkProc
        command: [root.backend, "check"]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const l of text.split("\n")) {
                    const kv = l.split("=");
                    if (kv[0] === "uefi")
                        root.uefi = kv[1] === "1";
                    else if (kv[0] === "root")
                        root.isRoot = kv[1] === "1";
                }
                root.checked = true;
            }
        }
    }

    Process {
        id: keymapProc
        command: [root.backend, "keymaps"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.split("\n").filter(s => s !== "");
                if (l.length > 0)
                    root.keymaps = l;
            }
        }
    }

    Process {
        id: keymapApply
    }

    Process {
        id: disksProc
        command: [root.backend, "disks"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const p = root.pairs(line);
                    if (!p.NAME)
                        continue;
                    out.push({
                        name: p.NAME,
                        model: (p.MODEL || "").trim(),
                        bytes: parseFloat(p.SIZE),
                        removable: p.RM === "1",
                        live: p.LIVE === "1"
                    });
                }
                root.disks = out;
            }
        }
    }

    Process {
        id: layoutProc
        stdout: StdioCollector {
            onStreamFinished: {
                const out = [];
                for (const line of text.split("\n")) {
                    const p = root.pairs(line);
                    if (p.NAME)
                        out.push({
                            name: p.NAME,
                            size: p.SIZE,
                            fs: p.FSTYPE,
                            label: p.LABEL
                        });
                }
                root.layout = out;
            }
        }
    }

    Process {
        id: freeProc
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split(/\s+/);
                if (f.length === 2) {
                    root.freeStart = parseFloat(f[0]);
                    root.freeEnd = parseFloat(f[1]);
                }
            }
        }
    }

    Process {
        id: pingProc
        command: ["ping", "-c", "1", "-W", "3", "1.1.1.1"]
        onExited: code => root.online = code === 0
    }

    // ---- wifi ----
    property var wifi: []
    property bool wifiBusy: false
    property string wifiMessage: ""

    function scanWifi() {
        wifiBusy = true;
        wifiProc.running = true;
    }

    function connectWifi(ssid, password) {
        wifiBusy = true;
        wifiMessage = "";
        wifiConnect.environment = {
            KI_SSID: ssid,
            KI_WIFI_PW: password
        };
        wifiConnect.running = true;
    }

    Process {
        id: wifiProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list", "--rescan", "yes"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = {};
                const out = [];
                for (const line of text.split("\n")) {
                    // nmcli -t escapes ':' inside fields as '\:'
                    const f = line.replace(/\\:/g, "\u0001").split(":").map(s => s.replace(/\u0001/g, ":"));
                    if (f.length < 4 || f[1] === "" || seen[f[1]])
                        continue;
                    seen[f[1]] = true;
                    out.push({
                        ssid: f[1],
                        signal: parseInt(f[2]) || 0,
                        secured: f[3] !== "",
                        active: f[0] === "*"
                    });
                }
                out.sort((a, b) => b.signal - a.signal);
                root.wifi = out;
                root.wifiBusy = false;
            }
        }
        onExited: root.wifiBusy = false
    }

    Process {
        id: wifiConnect
        command: ["sh", "-c", "if [ -n \"$KI_WIFI_PW\" ]; then nmcli device wifi connect \"$KI_SSID\" password \"$KI_WIFI_PW\"; else nmcli device wifi connect \"$KI_SSID\"; fi"]
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "")
                root.wifiMessage = text.trim().split("\n")[0]
        }
        onExited: code => {
            root.wifiBusy = false;
            if (code === 0) {
                root.wifiMessage = "";
                root.checkOnline();
            } else if (root.wifiMessage === "") {
                root.wifiMessage = "not this one";
            }
        }
    }

    // ---- the install ----
    property bool installing: false
    property bool finished: false
    property string failure: ""
    property real percent: 0
    property string doing: ""
    property string lastLog: ""
    property var logTail: []

    function start() {
        failure = "";
        finished = false;
        percent = 0;
        doing = "starting";
        logTail = [];
        installProc.environment = {
            KI_DISK: disk,
            KI_MODE: mode,
            KI_SWAP_MIB: String(swapMib),
            KI_FREE_START: String(freeStart),
            KI_FREE_END: String(freeEnd),
            KI_HOSTNAME: hostname,
            KI_USERNAME: username,
            KI_USER_PASS: userPass,
            KI_ROOT_PASS: rootSame ? userPass : rootPass,
            KI_TZ: timezone,
            KI_TIER: tier,
            KI_KEYMAP: keymap,
            KI_DRY: dry ? "1" : "0"
        };
        installing = true;
        installProc.running = true;
        goTo("install");
    }

    function reboot() {
        if (dry) {
            Qt.quit();
            return;
        }
        rebootProc.running = true;
    }

    // the live medium has no shell to fall back to: the way out is to switch the machine off
    function powerOff() {
        if (dry) {
            Qt.quit();
            return;
        }
        powerOffProc.running = true;
    }

    Process {
        id: rebootProc
        command: ["reboot"]
    }

    Process {
        id: powerOffProc
        command: ["poweroff"]
    }

    Process {
        id: installProc
        command: [root.backend, "install"]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("@progress ")) {
                    const rest = line.substring(10);
                    const sp = rest.indexOf(" ");
                    root.percent = parseFloat(rest.substring(0, sp));
                    root.doing = rest.substring(sp + 1);
                } else if (line.startsWith("@error ")) {
                    root.failure = line.substring(7);
                } else if (line === "@done") {
                    root.finished = true;
                } else if (line.trim() !== "") {
                    root.lastLog = line;
                    const t = root.logTail.slice(-5);
                    t.push(line);
                    root.logTail = t;
                }
            }
        }
        onExited: code => {
            root.installing = false;
            if (root.finished) {
                root.goTo("done");
            } else if (root.failure === "") {
                root.failure = "the installer stopped (exit " + code + ")";
            }
        }
    }
}
