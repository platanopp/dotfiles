pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
// Qualified: qs.services has a Bluetooth of its own (the bar's).
import Quickshell.Bluetooth as QsBluetooth
import Quickshell.Hyprland
import Quickshell.Networking
import Quickshell.Services.Pam
import Quickshell.Services.UPower
import qs.config
import qs.services

// the lock session's brain: pam, the attempt ledger, the keyboard's locks and the two faces the
// surface can wear. LockScreen only draws what it reads here
Singleton {
    id: root

    // session
    property bool locked: false
    // the surface is playing its exit and must not accept anything more
    property bool leaving: false
    // glance shows the day; focus shows the field. typing crosses over
    property bool focused: false
    // surfaces: translucent cards over the blurred wallpaper, so the
    // colour of the day shows through
    readonly property color card: Theme.alpha(Theme.background, 0.52)
    readonly property color hairline: Theme.alpha(Theme.outline, 0.45)

    // who is being asked: read lazily, since touching Users spawns its probe
    readonly property var account: null
    readonly property string userName: root.account ? root.account.name : (Quickshell.env("USER") || "")
    readonly property string displayName: root.userName
    readonly property string initials: root.userName.length > 0 ? root.userName.charAt(0).toUpperCase() : "?"
    readonly property string avatar: ""

    // pam: /etc/pam.d/login is the one service every distro ships for a local seat
    property string pamConfig: "login"
    // idle | prompting | checking | failed | error | granted
    property string phase: "idle"
    // pam asks in its own words once it wants anything but the password
    property string prompt: ""
    property bool secret: true
    // pam's own last sentence, which is better copy than anything we invent
    property string pamText: ""
    property int attempts: 0
    // faillock's defaults, replaced by its config when that sets them
    property int denyAfter: 3
    property int unlockAfter: 600

    // seconds left on a faillock lockout, counted down locally
    property int lockoutLeft: 0
    readonly property bool lockedOut: root.lockoutLeft > 0
    readonly property int triesLeft: Math.max(0, root.denyAfter - root.attempts)
    readonly property bool busy: root.phase === "checking"
    readonly property bool granted: root.phase === "granted"
    // nothing may be typed while pam owns the turn or the account is barred
    readonly property bool acceptsInput: !root.busy && !root.granted && !root.leaving && !root.lockedOut

    // keyboard
    property bool capsLock: false
    property string layout: ""
    // "English (US)" is too much for a 20px chip; keep the short half
    readonly property string layoutShort: {
        if (root.layout === "")
            return "";

        var m = /\(([^)]+)\)/.exec(root.layout);
        var t = m ? m[1] : root.layout.split(/[\s,]+/)[0];
        return t.substring(0, 6).toUpperCase();
    }

    // the one line under the field; kind drives its colour: error | good | info | none
    readonly property string statusKind: {
        if (root.granted)
            return "good";

        if (root.lockedOut || root.phase === "failed" || root.phase === "error")
            return "error";

        if (root.phase === "checking" || root.phase === "prompting")
            return "info";

        return "none";
    }
    readonly property string statusText: {
        if (root.granted)
            return "Welcome back";

        if (root.lockedOut)
            return "Too many attempts. Try again in " + root.humanSecs(root.lockoutLeft);

        if (root.phase === "checking")
            return "Checking…";

        if (root.phase === "error")
            return root.pamText !== "" ? root.pamText : "Authentication is unavailable right now";

        if (root.phase === "failed") {
            if (root.pamText !== "")
                return root.pamText;

            if (root.triesLeft === 1)
                return "Incorrect password, one try left";

            if (root.triesLeft > 1)
                return "Incorrect password, " + root.triesLeft + " tries left";

            return "Incorrect password";
        }
        if (root.phase === "prompting" && root.prompt !== "")
            return root.prompt;

        return "";
    }

    function humanSecs(s) {
        if (s >= 90)
            return Math.round(s / 60) + " minutes";

        if (s > 45)
            return "a minute";

        return Math.max(1, s) + " seconds";
    }

    // session control
    function lock() {
        root.beginLock(true);
    }

    // `photograph` is false only for the boot lock: no desktop worth starting
    // from, and it wants to be up early.
    function beginLock(photograph) {
        if (root.locked || root.raising)
            return ;

        root.reset();
        root.leaving = false;
        root.focused = false;
        root.secured = false;
        root.raising = true;
        root.focusSettled = false;
        root.shotStamp = "";
        root.takingStamp = "";
        root.shotSettled = true;
        // Armed first: whatever happens to the pictures, the lock goes up.
        lockAfterFocus.restart();
        raiseCap.restart();
        // A capture still hanging from an earlier lock is neither waited on nor used:
        // its pictures are of another moment.
        if (photograph && root.shotDir !== "" && !shotProc.running) {
            try {
                var names = [];
                for (const m of Hyprland.monitors.values)
                    names.push(m.name);

                root.takingStamp = String(Date.now());
                root.shotSettled = false;
                shotProc.command = ["sh", "-c", root.shotScript, "sh", root.shotDir, root.takingStamp].concat(names);
                shotProc.running = true;
            } catch (e) {
                root.takingStamp = "";
                root.shotSettled = true;
            }
        }
        // Move focus before locking: Hyprland gives the keyboard to the focused
        // monitor's lock surface. `hyprctl eval`, not dispatch: a hyphen in a monitor
        // name is a Lua syntax error in a dispatch.
        if (root.fieldMonitor !== "")
            Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.focus({ monitor = \"" + root.fieldMonitor + "\" }))"]);

    }

    // Between the ask and the lock being up: focus moving, screens being photographed.
    property bool raising: false
    property bool focusSettled: false
    property bool shotSettled: true

    function tryRaise() {
        if (root.raising && root.focusSettled && root.shotSettled)
            root.raise();

    }

    function raise() {
        raiseCap.stop();
        root.raising = false;
        root.arriving = true;
        arrivalWindow.restart();
        root.locked = true;
    }

    // A beat for the dispatch to land; the lock goes up whether or not focus moved.
    Timer {
        id: lockAfterFocus

        interval: 120
        onTriggered: {
            root.focusSettled = true;
            root.tryRaise();
        }
    }

    // Nothing may hold the lock down for long: past this it goes up without the pictures.
    Timer {
        id: raiseCap

        interval: 400
        onTriggered: {
            if (root.raising)
                root.raise();

        }
    }

    // The desktop, as it was: each screen is photographed just before locking (grim, raw PPM to
    // tmpfs, ~36 ms) so the desktop steps back into the blur. A surface that arrives later (the
    // Xiaomi re-plugging) comes up out of black.
    readonly property string shotDir: {
        var r = Quickshell.env("XDG_RUNTIME_DIR");
        return r ? r + "/quickshell" : "";
    }
    // Part of every file name, so a later lock is never handed an earlier one's pictures.
    property string shotStamp: ""
    property string takingStamp: ""
    property bool arriving: false
    // `timeout`: grim waits for the next frame, and a powered-down output never draws one.
    readonly property string shotScript: "d=$1; s=$2; shift 2; mkdir -p \"$d\" || exit 1; " + "rm -f \"$d\"/lockshot-*.ppm; " + "for n; do timeout 1 grim -o \"$n\" -t ppm \"$d/lockshot-$s-$n.ppm\" & done; wait; " + "ls \"$d\"/lockshot-\"$s\"-*.ppm >/dev/null 2>&1"

    function shotFor(name) {
        if (root.shotStamp === "" || !name)
            return "";

        return "file://" + root.shotDir + "/lockshot-" + root.shotStamp + "-" + name + ".ppm";
    }

    Process {
        id: shotProc

        running: false
        onExited: (code) => {
            // Only for the lock that asked, while it still waits; once the cap raised it
            // without them, they stay unused.
            if (!root.raising || root.takingStamp === "")
                return ;

            if (code === 0)
                root.shotStamp = root.takingStamp;

            root.shotSettled = true;
            root.tryRaise();
        }
    }

    // Long enough for every surface the lock raises to have been made.
    Timer {
        id: arrivalWindow

        interval: 1500
        onTriggered: root.arriving = false
    }

    // Deleted once the surfaces showing them are gone: the exit's last frame still draws from them.
    property string staleStamp: ""

    Timer {
        id: shotCleanup

        interval: 1000
        onTriggered: {
            Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"/lockshot-\"$2\"-*.ppm", "sh", root.shotDir, root.staleStamp]);
            if (root.shotStamp === root.staleStamp && !root.locked && !root.raising)
                root.shotStamp = "";

        }
    }

    // Which screen the field belongs on: Hyprland has no primary output and lists the side monitor
    // first, so the screen is named in Settings -> Shell (ShellSettings.lockMonitor).
    readonly property string mainMonitor: ShellSettings.lockMonitor

    // The named screen while plugged in, else whatever holds focus, so
    // unplugging it leaves a usable lock.
    readonly property string fieldMonitor: {
        for (const m of Hyprland.monitors.values) {
            if (m.name === root.mainMonitor)
                return m.name;

        }
        const f = Hyprland.focusedMonitor;
        return f ? f.name : "";
    }

    // if the surface never reports back (it failed to draw, or its screen went away), let go anyway
    Timer {
        id: deadman

        running: root.leaving
        interval: 2000
        onTriggered: {
            if (root.locked)
                root.release();

        }
    }

    // the surface calls this once its exit animation has played out
    function release() {
        root.locked = false;
        root.leaving = false;
        root.focused = false;
        root.secured = false;
        root.arriving = false;
        root.reset();
        if (root.shotStamp !== "") {
            root.staleStamp = root.shotStamp;
            shotCleanup.restart();
        }
    }

    // every unlock asked for from outside: the ipc, logind. asking twice, or
    // asking when nothing is locked, must not strand `leaving` set
    function requestUnlock() {
        if (root.locked && !root.leaving)
            root.leaving = true;

    }

    function reset() {
        if (pam.active)
            pam.abort();

        root.phase = "idle";
        root.prompt = "";
        root.secret = true;
        root.pamText = "";
        root.attempts = 0;
        root.pending = "";
        root.lockoutLeft = 0;
    }

    // typing or clicking anywhere crosses from glance into the field
    function engage() {
        if (!root.focused)
            root.focused = true;

        idleBack.restart();
    }

    // authentication
    property string pending: ""

    function submit(text) {
        if (!root.acceptsInput || text.length === 0)
            return ;

        root.pamText = "";
        root.phase = "checking";
        root.pending = text;
        if (pam.active) {
            // pam is mid-conversation and was waiting on us
            root.pending = "";
            pam.respond(text);
            return ;
        }
        if (!pam.start()) {
            root.pending = "";
            root.phase = "error";
            root.pamText = "Cannot reach PAM (/etc/pam.d/" + root.pamConfig + ")";
        } else {
            authTimeout.restart();
        }
    }

    function fail(text) {
        authTimeout.stop();
        root.attempts += 1;
        root.pamText = text || "";
        root.phase = "failed";
        root.focused = true;
        failed();
        faillockProc.running = true;
    }

    function grant() {
        authTimeout.stop();
        root.phase = "granted";
        root.attempts = 0;
        // let the lock be seen opening; the surface leaves a beat later
        graceOut.restart();
    }

    // Lets the field's "opened" beat (two durMedium steps in LockScreen)
    // finish before the cards lift off.
    Timer {
        id: graceOut

        interval: Theme.durLong + Theme.durShort
        onTriggered: root.leaving = true
    }

    signal failed()

    PamContext {
        id: pam

        config: root.pamConfig
        onPamMessage: {
            if (pam.responseRequired) {
                if (root.pending !== "") {
                    var p = root.pending;
                    root.pending = "";
                    root.phase = "checking";
                    pam.respond(p);
                } else {
                    // a second question: pam wants something we were not holding
                    authTimeout.stop();
                    root.prompt = pam.message.replace(/:\s*$/, "");
                    root.secret = !pam.responseVisible;
                    root.phase = "prompting";
                    root.focused = true;
                }
            } else if (pam.message !== "") {
                // an aside, not a question — usually the faillock warning
                root.pamText = pam.message;
            }
        }
        onCompleted: (result) => {
            root.pending = "";
            if (result === PamResult.Success)
                root.grant();
            else if (result === PamResult.MaxTries)
                root.fail("Too many attempts. The account is locked");
            else if (result === PamResult.Error)
                root.error("PAM could not complete the check");
            else
                root.fail(root.pamText);
        }
        onError: (e) => root.error(PamError.toString(e) === "StartFailed" ? "PAM refused to start a session" : "PAM failed: " + PamError.toString(e))
    }

    function error(text) {
        authTimeout.stop();
        root.pamText = text;
        root.phase = "error";
        root.focused = true;
        failed();
    }

    // pam should never take this long; if it does, say so instead of spinning
    Timer {
        id: authTimeout

        interval: 20000
        onTriggered: {
            pam.abort();
            root.error("The check timed out");
        }
    }

    // focus falls back to the glance face when the keyboard goes quiet
    Timer {
        id: idleBack

        interval: 25000
        onTriggered: {
            if (root.locked && !root.busy && root.phase !== "prompting")
                root.focused = false;

        }
    }

    // faillock
    FileView {
        path: "/etc/security/faillock.conf"
        onLoaded: {
            var deny = /^\s*deny\s*=\s*(\d+)/m.exec(this.text());
            var unlock = /^\s*unlock_time\s*=\s*(\d+)/m.exec(this.text());
            if (deny)
                root.denyAfter = parseInt(deny[1]);

            if (unlock)
                root.unlockAfter = parseInt(unlock[1]);

        }
    }

    // pam only says "account locked"; faillock knows for how much longer
    Process {
        id: faillockProc

        running: false
        command: ["faillock", "--user", root.userName]

        stdout: StdioCollector {
            onStreamFinished: {
                var latest = 0;
                var valid = 0;
                var lines = this.text.split("\n");
                for (var i = 0; i < lines.length; i++) {
                    var m = /^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\s+\S+.*\s(V|I)\s*$/.exec(lines[i].trim());
                    if (!m || m[2] !== "V")
                        continue;

                    valid += 1;
                    var t = Date.parse(m[1].replace(" ", "T"));
                    if (!isNaN(t) && t > latest)
                        latest = t;

                }
                root.attempts = Math.max(root.attempts, valid);
                if (valid >= root.denyAfter && latest > 0) {
                    var left = Math.round((latest + root.unlockAfter * 1000 - Date.now()) / 1000);
                    root.lockoutLeft = Math.max(0, left);
                }
            }
        }
    }

    Timer {
        running: root.lockoutLeft > 0
        interval: 1000
        repeat: true
        onTriggered: {
            root.lockoutLeft -= 1;
            if (root.lockoutLeft <= 0)
                root.phase = "idle";

        }
    }

    // keyboard locks: hyprland has no event for the lock keys, so the field polls while in use
    Timer {
        running: root.locked && root.focused
        interval: 400
        repeat: true
        triggeredOnStart: true
        onTriggered: kbProc.running = true
    }

    Process {
        id: kbProc

        running: false
        command: ["hyprctl", "devices", "-j"]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var kbs = JSON.parse(this.text).keyboards || [];
                    var main = null;
                    for (var i = 0; i < kbs.length; i++) {
                        if (kbs[i].main) {
                            main = kbs[i];
                            break;
                        }
                    }
                    if (!main && kbs.length > 0)
                        main = kbs[0];

                    if (!main)
                        return ;

                    root.capsLock = !!main.capsLock;
                    root.layout = main.active_keymap || "";
                } catch (e) {
                }
            }
        }
    }

    // glance: read straight off the platform services, not the shell's singletons, so the lock
    // pulls no nmcli/rfkill probes into shell startup
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: root.battery ? root.battery.isPresent : false
    readonly property int batteryPercent: root.hasBattery ? Math.round(root.battery.percentage * 100) : 0
    readonly property bool charging: root.hasBattery && (root.battery.state === UPowerDeviceState.Charging || root.battery.state === UPowerDeviceState.FullyCharged)
    readonly property bool batteryLow: root.hasBattery && !root.charging && root.batteryPercent <= 15

    readonly property var wifiDevice: {
        for (const d of Networking.devices.values) {
            if (d.type === DeviceType.Wifi)
                return d;

        }
        return null;
    }
    readonly property var wiredDevice: {
        for (const d of Networking.devices.values) {
            if (d.type === DeviceType.Wired)
                return d;

        }
        return null;
    }
    readonly property bool ethernet: !!(root.wiredDevice && root.wiredDevice.connected)
    readonly property bool wifiUp: root.wifiDevice ? root.wifiDevice.connected : false
    property var activeNetwork: null
    readonly property string netGlyph: root.ethernet ? "ethernet" : (root.wifiUp ? "wifi" : "wifiOff")
    readonly property string netLabel: {
        if (root.ethernet)
            return "Ethernet";

        if (root.wifiUp && root.activeNetwork)
            return root.activeNetwork.name;

        if (root.wifiUp)
            return "Wi-Fi";

        return "Offline";
    }

    function refreshNetwork() {
        if (!root.wifiDevice) {
            root.activeNetwork = null;
            return ;
        }
        var found = null;
        for (const net of root.wifiDevice.networks.values) {
            if (net.connected) {
                found = net;
                break;
            }
        }
        root.activeNetwork = found;
    }

    Timer {
        running: root.locked
        interval: 5000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshNetwork()
    }

    readonly property var btAdapter: QsBluetooth.Bluetooth.defaultAdapter
    readonly property bool btOn: root.btAdapter ? root.btAdapter.enabled : false
    readonly property var btDevices: (root.btAdapter && root.btAdapter.devices) ? root.btAdapter.devices.values.filter((d) => {
        return d.connected;
    }) : []
    readonly property string btLabel: {
        if (!root.btAdapter)
            return "No adapter";

        if (!root.btOn)
            return "Bluetooth off";

        if (root.btDevices.length === 1)
            return root.btDevices[0].name;

        if (root.btDevices.length > 1)
            return root.btDevices.length + " devices";

        return "Bluetooth on";
    }

    // the day: one tick a second keeps the clock and the greeting current
    property int tick: 0

    Timer {
        running: root.locked
        interval: 1000
        repeat: true
        triggeredOnStart: true
        onTriggered: root.tick += 1
    }

    readonly property var now: {
        void root.tick;
        return new Date();
    }
    readonly property string timeText: {
        var d = root.now;
        var h = d.getHours();
        var hh = ShellSettings.clock24h ? h : (h % 12 === 0 ? 12 : h % 12);
        return (ShellSettings.clock24h && hh < 10 ? "0" : "") + hh + ":" + (d.getMinutes() < 10 ? "0" : "") + d.getMinutes();
    }
    readonly property string hourText: root.timeText.split(":")[0]
    readonly property string minuteText: root.timeText.split(":")[1]
    readonly property string meridiem: ShellSettings.clock24h ? "" : (root.now.getHours() < 12 ? "AM" : "PM")
    readonly property string dateText: root.now.toLocaleDateString(Qt.locale(), "dddd, d MMMM")
    readonly property string greeting: {
        var h = root.now.getHours();
        if (h < 5)
            return "Still up?";

        if (h < 12)
            return "Good morning";

        if (h < 18)
            return "Good afternoon";

        if (h < 22)
            return "Good evening";

        return "Good night";
    }

    // wallpaper: the desktop's own picture (Wallpaper.wallpaperStill: with
    // a video up, its poster frame)
    readonly property string wallpaper: Wallpaper.wallpaperStill

    // power: the same five the dock offers, with the same commands behind them
    readonly property var powerActions: [
        {
            "id": "suspend",
            "label": "Suspend",
            "glyph": "suspend",
            "confirm": false
        },
        {
            "id": "hibernate",
            "label": "Hibernate",
            "glyph": "hibernate",
            "confirm": false
        },
        {
            "id": "logout",
            "label": "Log out",
            "glyph": "logout",
            "confirm": true
        },
        {
            "id": "reboot",
            "label": "Restart",
            "glyph": "restart",
            "confirm": true
        },
        {
            "id": "shutdown",
            "label": "Shut down",
            "glyph": "power",
            "confirm": true
        }
    ]

    function runPower(id) {
        var cmds = {
            // uwsm only stops a session it started, so fall back to hyprland
            "logout": ["sh", "-c", "uwsm stop 2>/dev/null || hyprctl dispatch exit"],
            "suspend": ["systemctl", "suspend"],
            "shutdown": ["systemctl", "poweroff"],
            "hibernate": ["systemctl", "hibernate"],
            "reboot": ["systemctl", "reboot"]
        };
        var cmd = cmds[id];
        if (cmd)
            Quickshell.execDetached(cmd);

    }

    // logind: `loginctl lock-session` arrives as Lock on our session object (hypridle relays it
    // only while running). gdbus listens, as quickshell has no dbus binding; signals come on the
    // real escaped path, not `auto`. exit 3: no session
    Process {
        id: logindWatch

        running: true
        command: ["sh", "-c", "id=$(busctl --system get-property org.freedesktop.login1 /org/freedesktop/login1/session/auto org.freedesktop.login1.Session Id 2>/dev/null | sed 's/^s \"//;s/\"$//'); " + "[ -n \"$id\" ] || exit 3; " + "p=$(busctl --system call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager GetSession s \"$id\" 2>/dev/null | sed 's/^o \"//;s/\"$//'); " + "[ -n \"$p\" ] || exit 3; " + "exec gdbus monitor --system --dest org.freedesktop.login1 --object-path \"$p\""]
        onExited: (code) => {
            if (code !== 3)
                logindRetry.restart();

        }

        stdout: SplitParser {
            // honouring Unlock is no weaker than `qs ipc call lock unlock`,
            // which any process of this user can already call
            onRead: (line) => {
                var m = /\.Session\.(Lock|Unlock)\b/.exec(line);
                if (!m)
                    return ;

                if (m[1] === "Lock")
                    root.lock();
                else
                    root.requestUnlock();
            }
        }

    }

    // dbus going away takes the watcher with it; go back for it
    Timer {
        id: logindRetry

        interval: 10000
        onTriggered: logindWatch.running = true
    }

    // LockedHint is what loginctl and others read, so it follows the surface; pushed at startup
    // too, in case a shell died while locked
    function pushLockedHint() {
        Quickshell.execDetached(["busctl", "--system", "call", "org.freedesktop.login1", "/org/freedesktop/login1/session/auto", "org.freedesktop.login1.Session", "SetLockedHint", "b", root.locked ? "true" : "false"]);
    }

    onLockedChanged: root.pushLockedHint()
    Component.onCompleted: {
        root.pushLockedHint();
        // A shell that died while locked leaves its pictures behind.
        if (root.shotDir !== "")
            Quickshell.execDetached(["sh", "-c", "rm -f \"$1\"/lockshot-*.ppm", "sh", root.shotDir]);

    }

    // Confirmed by the compositor: true once the lock surface is in front
    // (WlSessionLock.secure, set by LockScreen). Anything that must not happen over a visible
    // desktop, suspend most of all, waits on this, not `locked`.
    property bool secured: false

    // The lock that stands in for a greeter: the seat arrives logged in, so this asks for the
    // password. Raised from here rather than an exec-once, so it's up on the shell's first frame.
    // Once per boot, not per start (saving a QML file rebuilds the tree): the claim is a file in
    // $XDG_RUNTIME_DIR, kept across restarts.
    Process {
        id: bootLockClaim

        running: true
        // noclobber makes the redirect fail if the file exists, so test and claim are one
        // atomic step. The braces put `2>/dev/null` before the failing `>`, or every reload
        // logs "cannot overwrite existing file".
        command: ["sh", "-c", "f=\"$XDG_RUNTIME_DIR/quickshell/boot-lock\"; mkdir -p \"${f%/*}\" || exit 1; { set -C; : > \"$f\"; } 2>/dev/null"]
        onExited: (code) => {
            // The claim is taken either way, so enabling the setting later doesn't
            // lock the screen there and then.
            if (code === 0 && ShellSettings.lockAtBoot)
                root.beginLock(false);

        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            root.lock();
        }

        function unlock(): void {
            root.requestUnlock();
        }

        function isLocked(): bool {
            return root.locked;
        }

        function status(): string {
            return JSON.stringify({
                "locked": root.locked,
                "secured": root.secured,
                "photographed": root.shotStamp !== "",
                "fieldMonitor": root.fieldMonitor,
                "phase": root.phase,
                "focused": root.focused,
                "attempts": root.attempts,
                "lockoutLeft": root.lockoutLeft
            });
        }
    }
}
