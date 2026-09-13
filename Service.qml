pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string pluginPath: Quickshell.env("HOME")
                                         + "/.config/omarchy/plugins/io.github.ilyazar.keyboard-layout"
    readonly property string trackerPath: pluginPath + "/native/keyboard-layoutd"

    property bool trackingEnabled: false
    property bool supportKnown: false
    property bool supported: false

    signal restoreRequested(int layout)

    function setTrackingEnabled(enabled) {
        root.trackingEnabled = enabled;
        root.syncTracker();
    }

    function syncTracker() {
        if (root.trackingEnabled && root.supported) {
            if (!layoutTracker.running)
                layoutTracker.running = true;
            return;
        }

        trackerRestartTimer.stop();
        if (layoutTracker.running)
            layoutTracker.running = false;
    }

    function updateSupport(raw) {
        root.supportKnown = true;
        root.supported = String(raw || "").trim() === "x86_64";
        root.syncTracker();
    }

    function parseRestore(line) {
        var match = String(line || "").trim().match(/^restore:([0-9]+)$/);
        if (match)
            root.restoreRequested(Number(match[1]));
    }

    Component.onCompleted: architectureProcess.running = true

    Process {
        id: architectureProcess
        command: ["uname", "-m"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root?.updateSupport(text)
        }
    }

    Process {
        id: layoutTracker
        command: ["setpriv", "--pdeathsig", "TERM", root.trackerPath]
        stdout: SplitParser {
            onRead: function (line) {
                root?.parseRestore(line);
            }
        }
        onRunningChanged: {
            if (!running && root.trackingEnabled && root.supported)
                trackerRestartTimer.restart();
        }
    }

    Timer {
        id: trackerRestartTimer
        interval: 1000
        onTriggered: root.syncTracker()
    }
}
