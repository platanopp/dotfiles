pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// CPU and memory from /proc, the CPU package temperature from hwmon, and the GPU from nvidia-smi,
// for the desktop's system widget. Runs only while subscribed (subscribe()/unsubscribe(), as
// Spectrum); /proc is read in place, and the GPU is one long-running nvidia-smi (-lms).
Singleton {
    id: root

    // Every two seconds: often enough to follow a load, seldom enough that
    // reading it is not itself the load.
    readonly property int interval: 2000

    property int subscribers: 0
    readonly property bool active: root.subscribers > 0

    function subscribe() { root.subscribers++ }
    function unsubscribe() { if (root.subscribers > 0) root.subscribers-- }

    // 0..1 where a fraction; -1 until the first reading.
    property real cpu: -1
    property real cpuTemp: -1        // °C
    property real memUsed: -1        // GiB
    property real memTotal: -1       // GiB
    property real gpu: -1
    property real gpuTemp: -1        // °C
    property real vramUsed: -1       // GiB
    property real vramTotal: -1      // GiB

    readonly property bool ready: root.cpu >= 0 && root.memTotal > 0

    // The last /proc/stat totals, for the busy share between two readings.
    property real lastIdle: 0
    property real lastTotal: 0

    Timer {
        interval: root.interval
        running: root.active
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            procStat.reload()
            memInfo.reload()
            if (cpuTempFile.path.length > 0) cpuTempFile.reload()
        }
    }

    FileView {
        id: procStat
        path: "/proc/stat"
        onLoaded: {
            var line = procStat.text().split("\n")[0]
            var f = line.trim().split(/\s+/).slice(1).map(Number)
            // user nice system idle iowait irq softirq steal
            var idle = f[3] + f[4]
            var total = 0
            for (var i = 0; i < 8 && i < f.length; i++) total += f[i]
            if (root.lastTotal > 0 && total > root.lastTotal)
                root.cpu = 1 - (idle - root.lastIdle) / (total - root.lastTotal)
            root.lastIdle = idle
            root.lastTotal = total
        }
    }

    FileView {
        id: memInfo
        path: "/proc/meminfo"
        onLoaded: {
            var t = memInfo.text()
            var total = /MemTotal:\s+(\d+)/.exec(t)
            var avail = /MemAvailable:\s+(\d+)/.exec(t)
            if (!total || !avail) return
            root.memTotal = Number(total[1]) / 1048576
            root.memUsed = (Number(total[1]) - Number(avail[1])) / 1048576
        }
    }

    // The package sensor's hwmon number moves between boots, so it's found by
    // driver name once (coretemp, k10temp).
    FileView {
        id: cpuTempFile
        path: ""
        onLoaded: {
            var v = Number(cpuTempFile.text().trim())
            if (!isNaN(v)) root.cpuTemp = v / 1000
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "for d in /sys/class/hwmon/hwmon*; do "
                  + "n=$(cat \"$d/name\" 2>/dev/null); "
                  + "if [ \"$n\" = coretemp ] || [ \"$n\" = k10temp ]; then echo \"$d/temp1_input\"; break; fi; done"]
        stdout: StdioCollector {
            onStreamFinished: cpuTempFile.path = text.trim()
        }
    }

    Process {
        running: root.active
        command: ["nvidia-smi", "--query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total",
                  "--format=csv,noheader,nounits", "-lms", String(root.interval)]
        stdout: SplitParser {
            onRead: data => {
                var f = data.split(",").map(s => Number(s.trim()))
                if (f.length < 4 || f.some(isNaN)) return
                root.gpu = f[0] / 100
                root.gpuTemp = f[1]
                root.vramUsed = f[2] / 1024
                root.vramTotal = f[3] / 1024
            }
        }
    }

    // Stale numbers are worse than none: a widget shown again after an hour
    // should not start from where the machine was then.
    onActiveChanged: {
        if (root.active) return
        root.cpu = -1
        root.gpu = -1
        root.lastIdle = 0
        root.lastTotal = 0
    }
}
