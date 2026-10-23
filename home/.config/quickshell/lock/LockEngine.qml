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

// the lock session's brain: pam, the attempt ledger, the keyboard's locks and
// the two faces the surface can wear. lucidlock/ only draws what it reads here
Singleton {
    id: root

    // ── session ────────────────────────────────────────────────────────────
    property bool locked: false
    // the surface is playing its exit and must not accept anything more
    property bool leaving: false
    // glance shows the day; focus shows the field. typing crosses over
    property bool focused: false
    // ── surfaces ───────────────────────────────────────────────────────────
    // the lock draws over a blurred wallpaper, so its cards stay translucent
    // and let the colour of the day through instead of sitting on flat black
    readonly property color card: Theme.alpha(Theme.background, 0.52)
    readonly property color hairline: Theme.alpha(Theme.outline, 0.45)

    // ── who is being asked ─────────────────────────────────────────────────
    // read lazily: touching Users spawns its probe, and nothing wants that
    // at shell start — only once a lock is actually up
    readonly property var account: null
    readonly property string userName: root.account ? root.account.name : (Quickshell.env("USER") || "")
    readonly property string displayName: root.userName
    readonly property string initials: root.userName.length > 0 ? root.userName.charAt(0).toUpperCase() : "?"
    readonly property string avatar: ""

    // ── pam ────────────────────────────────────────────────────────────────
    // /etc/pam.d/login is the one service every distro ships for a local seat
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

    // ── keyboard ───────────────────────────────────────────────────────────
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

    // ── the one line under the field ───────────────────────────────────────
    // kind drives its colour: error | good | info | none
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
            return "Too many attempts — try again in " + root.humanSecs(root.lockoutLeft);

        if (root.phase === "checking")
            return "Checking…";

        if (root.phase === "error")
            return root.pamText !== "" ? root.pamText : "Authentication is unavailable right now";

        if (root.phase === "failed") {
            if (root.pamText !== "")
                return root.pamText;

            if (root.triesLeft === 1)
                return "Incorrect password — one try left";

            if (root.triesLeft > 1)
                return "Incorrect password — " + root.triesLeft + " tries left";

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

    // ── session control ────────────────────────────────────────────────────
    function lock() {
        root.beginLock(true);
    }

    // `photograph` is false only for the boot lock: there is no desktop yet
    // worth starting from, and that lock wants to be up as early as it can.
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
        // Armed before anything that could go wrong below: whatever happens
        // to the pictures, the lock goes up.
        lockAfterFocus.restart();
        raiseCap.restart();
        // A capture still hanging from an earlier lock (an output that never
        // delivered a frame) is not waited on, and not used: its pictures
        // would be of some other moment.
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
        // Move the focus before the lock, not after. Hyprland hands the
        // keyboard to the lock surface of whichever monitor has focus, so
        // without this the field can be drawn on one screen and typed into on
        // another -- which is exactly what a cold boot did, focus sitting on
        // the monitor Hyprland enumerates first.
        //
        // `hyprctl eval` and not `hyprctl dispatch`: this Hyprland config is
        // Lua, so a dispatch argument is parsed as Lua and the hyphen in a
        // monitor name is a syntax error. Same idiom as focus_cursor_monitor()
        // in scripts/display_control.py.
        if (root.fieldMonitor !== "")
            Quickshell.execDetached(["hyprctl", "eval", "hl.dispatch(hl.dsp.focus({ monitor = \"" + root.fieldMonitor + "\" }))"]);

    }

    // Between the ask and the lock being up: the focus is moving and the
    // screens are being photographed.
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

    // A beat for that dispatch to land -- short enough not to be felt. The
    // lock goes up whether or not the focus actually moved: a dispatch that
    // failed must not be able to hold the screen open.
    Timer {
        id: lockAfterFocus

        interval: 120
        onTriggered: {
            root.focusSettled = true;
            root.tryRaise();
        }
    }

    // Nothing may hold the lock down for long -- not a capture that is slow,
    // not one that hangs. Past this it goes up without the pictures.
    Timer {
        id: raiseCap

        interval: 400
        onTriggered: {
            if (root.raising)
                root.raise();

        }
    }

    // ── The desktop, as it was ─────────────────────────────────────────────
    //
    // Each screen is photographed just before the lock goes up -- grim, raw
    // PPM into the runtime tmpfs, both screens at once: 36 ms here on
    // 2026-10-23, inside the beat the focus already waits. The surface starts
    // on that picture, so the desktop itself seems to step back into the blur
    // rather than being cut away; on the way out it comes forward again, so
    // the lock's last frame is the desktop the session is about to show.
    //
    // Only the surfaces raised with the lock open on it. One that arrives
    // later -- the Xiaomi re-plugging itself when the screens wake -- must not
    // open on a sharp picture of the session, so it comes up out of black.
    readonly property string shotDir: {
        var r = Quickshell.env("XDG_RUNTIME_DIR");
        return r ? r + "/quickshell" : "";
    }
    // Set while this lock's pictures exist; part of every file name, so a
    // later lock can never be handed an earlier one's.
    property string shotStamp: ""
    property string takingStamp: ""
    property bool arriving: false
    // `timeout`: grim waits for the output's next frame, and an output that
    // is powered down never draws one.
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
            // Only for the lock that asked, and only while it still waits:
            // once the cap has raised it without them, they stay unused.
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

    // The pictures go once the surfaces that showed them have; until then
    // the last frame of the way out is still drawing from them.
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

    // ── Which screen the field belongs on ──────────────────────────────────
    //
    // Hyprland has no notion of a primary output, and the one it enumerates
    // first here is HDMI-A-1 -- the side monitor, the one sitting at 0,0. At a
    // cold boot that is also the one holding focus, so the card came up there.
    //
    // So the screen is named, the same way the workspace rules and hypridle's
    // wlopm lines in the Hyprland config name it. One place to change if the
    // desk ever changes.
    // Chosen in Settings -> Shell; see ShellSettings.
    readonly property string mainMonitor: ShellSettings.lockMonitor

    // What the field lands on in the end: the named screen while it is plugged
    // in, and whatever holds focus when it is not -- unplugging the main
    // monitor should leave a lock that can still be typed into, not a field
    // drawn on an output that is no longer there.
    readonly property string fieldMonitor: {
        for (const m of Hyprland.monitors.values) {
            if (m.name === root.mainMonitor)
                return m.name;

        }
        const f = Hyprland.focusedMonitor;
        return f ? f.name : "";
    }

    // if the surface never reports back — it failed to draw, or the screen it
    // was on went away — let go anyway rather than stranding the session
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

    // ── authentication ─────────────────────────────────────────────────────
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

    // Long enough for the field's own "opened" beat (two durMedium steps in
    // LockScreen) to finish before the cards lift off.
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
                root.fail("Too many attempts — the account is locked");
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

    // ── faillock ───────────────────────────────────────────────────────────
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

    // ── keyboard locks ─────────────────────────────────────────────────────
    // hyprland has no event for the lock keys, so the field polls while it is
    // the thing being used
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

    // ── glance ─────────────────────────────────────────────────────────────
    // read straight off the platform services rather than the shell's settings
    // singletons: the lock must not drag nmcli/rfkill probes into shell startup
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

    // ── the day ────────────────────────────────────────────────────────────
    // one tick a second so the clock and the greeting stay honest
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

    // ── wallpaper ──────────────────────────────────────────────────────────
    // The shell already tracks which wallpaper is up -- wallpaper_crop.py
    // records the original in its state file and Wallpaper publishes it, so the
    // lock shows the same picture the desktop has rather than a second guess.
    // wallpaperStill rather than selectedWallpaper: with a video up, that is
    // the video's poster frame instead of the image sitting underneath it.
    readonly property string wallpaper: Wallpaper.wallpaperStill

    // ── power ──────────────────────────────────────────────────────────────
    // the same five the dock offers, with the same commands behind them
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

    // ── logind ─────────────────────────────────────────────────────────────
    // `loginctl lock-session` is how anything off-shell asks for a lock, and
    // logind answers it by emitting Lock on our own session object. hypridle
    // relays that too, but only while it is running, and Idle can be turned
    // off entirely — then nothing would be listening
    //
    // quickshell has no dbus binding, so gdbus does the listening (glib2 rides
    // in under qt6-base, so it is always here). the path has to come from
    // logind: the `auto` alias only resolves for calls, while signals arrive on
    // the real, escaped one. exit 3 is ours, and means no session to watch
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

    // LockedHint is what loginctl and anything else reading the session go by,
    // so it has to follow the surface. pushed at startup as well: a shell that
    // died while locked would otherwise leave the hint stuck on
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

    // ── Confirmed by the compositor ────────────────────────────────────────
    // `locked` is only this shell's side of the ask. This one is true once the
    // compositor has answered that the lock surface is actually in front of
    // the session -- LockScreen writes it off WlSessionLock.secure. Anything
    // that must not happen over a visible desktop, suspending most of all,
    // waits on this rather than on `locked`.
    property bool secured: false

    // ── The lock that stands in for a greeter ──────────────────────────────
    //
    // The seat is handed over already logged in, so by the time the desktop is
    // up nothing has asked for a password. This is what asks.
    //
    // Raised from in here rather than by an exec-once in the Hyprland config,
    // because an exec-once would have to poll until this shell's ipc existed
    // and the desktop would be on the panels for those frames. From here the
    // surface goes up on the first frame the shell is able to put one there.
    //
    // Once per boot, and deliberately not once per start: quickshell rebuilds
    // this whole tree every time a QML file is saved, so a plain
    // Component.onCompleted would lock the screen on every edit. The claim is
    // a file under $XDG_RUNTIME_DIR, which is a tmpfs -- gone again after a
    // reboot, still there after a `pkill quickshell`. So booting locks, and
    // restarting the shell by hand does not.
    Process {
        id: bootLockClaim

        running: true
        // noclobber makes the redirect itself fail when the file is already
        // there, so the test and the claim are a single step and two shells
        // racing cannot both win it.
        //
        // The braces matter: redirections are applied left to right, so a
        // `2>/dev/null` written after the failing `>` comes too late to catch
        // its complaint, and every reload of this file would put one more
        // "cannot overwrite existing file" in the log.
        command: ["sh", "-c", "f=\"$XDG_RUNTIME_DIR/quickshell/boot-lock\"; mkdir -p \"${f%/*}\" || exit 1; { set -C; : > \"$f\"; } 2>/dev/null"]
        onExited: (code) => {
            // The claim is taken either way, so switching the setting on
            // later in the session does not lock the screen there and then.
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
