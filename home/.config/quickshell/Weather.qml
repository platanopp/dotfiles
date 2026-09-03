pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Current conditions plus a 7-day forecast from Open-Meteo.
//
// The location is resolved from the public IP, which means one request to
// ip-api.com per refresh. Set latitude/longitude below to pin a place and skip
// that lookup entirely.
Singleton {
    id: root

    property string latitude: ""
    property string longitude: ""
    property string cityOverride: ""

    property bool loading: false
    property bool ready: false
    property string error: ""

    property string city: ""
    property real temp: 0
    property int code: 0
    property int humidity: 0
    property real wind: 0
    property bool isDay: true

    // [{ date, code, max, min }], today first.
    property var days: []

    function refresh() {
        if (root.loading) return
        root.loading = true
        weatherProc.command = ["python3", Quickshell.env("HOME") + "/.config/quickshell/scripts/weather.py",
                               root.latitude, root.longitude, root.cityOverride]
        weatherProc.running = true
    }

    // WMO weather codes, grouped the way the icons and wording differ.
    function icon(wmoCode, daytime) {
        if (wmoCode === 0) return daytime === false ? "󰖔" : "󰖙"
        if (wmoCode === 1 || wmoCode === 2) return daytime === false ? "󰼱" : "󰖕"
        if (wmoCode === 3) return "󰖐"
        if (wmoCode === 45 || wmoCode === 48) return "󰖑"
        if (wmoCode >= 51 && wmoCode <= 57) return "󰖗"
        if (wmoCode >= 61 && wmoCode <= 67) return "󰖖"
        if (wmoCode >= 71 && wmoCode <= 77) return "󰖘"
        if (wmoCode >= 80 && wmoCode <= 82) return "󰖖"
        if (wmoCode === 85 || wmoCode === 86) return "󰖘"
        if (wmoCode >= 95) return "󰖓"
        return "󰖐"
    }

    function describe(wmoCode) {
        if (wmoCode === 0) return "Clear"
        if (wmoCode === 1) return "Mostly clear"
        if (wmoCode === 2) return "Partly cloudy"
        if (wmoCode === 3) return "Overcast"
        if (wmoCode === 45 || wmoCode === 48) return "Fog"
        if (wmoCode >= 51 && wmoCode <= 55) return "Drizzle"
        if (wmoCode === 56 || wmoCode === 57) return "Freezing drizzle"
        if (wmoCode >= 61 && wmoCode <= 65) return "Rain"
        if (wmoCode === 66 || wmoCode === 67) return "Freezing rain"
        if (wmoCode >= 71 && wmoCode <= 77) return "Snow"
        if (wmoCode >= 80 && wmoCode <= 82) return "Showers"
        if (wmoCode === 85 || wmoCode === 86) return "Snow showers"
        if (wmoCode === 95) return "Thunderstorm"
        if (wmoCode >= 96) return "Thunderstorm with hail"
        return "—"
    }

    function load(text) {
        try {
            var data = JSON.parse(text)
            if (data.error) {
                root.error = data.error
                root.ready = false
                return
            }
            root.city = data.city
            root.temp = data.temp
            root.code = data.code
            root.humidity = data.humidity
            root.wind = data.wind
            root.isDay = data.isDay === 1
            root.days = data.days
            root.error = ""
            root.ready = true
        } catch (e) {
            root.error = "unreadable response"
            root.ready = false
        }
    }

    Process {
        id: weatherProc
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false
                root.load(text)
            }
        }
    }

    Timer {
        interval: 1800000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
