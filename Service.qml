pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root

    readonly property string pluginPath: Quickshell.env("HOME")
                                         + "/.config/omarchy/plugins/io.github.ilyazar.keyboard-layout"
    readonly property string helperPath: pluginPath + "/native/keyboard-layoutd"

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
        let supported = false;
        try {
            const capabilities = JSON.parse(raw);
            supported = capabilities.schemaVersion === 1 && capabilities.keymap === true && capabilities.tracking
                    === true;
        } catch (error) {
            supported = false;
        }
        supportDeadline.stop();
        root.supportKnown = true;
        root.supported = supported;
        root.syncTracker();
    }

    function parseRestore(line) {
        var match = String(line || "").trim().match(/^restore:([0-9]+)$/);
        if (match)
            root.restoreRequested(Number(match[1]));
    }

    Component.onCompleted: {
        supportDeadline.start();
        supportProcess.running = true;
    }

    Process {
        id: supportProcess
        command: [root.helperPath, "--probe"]
        clearEnvironment: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.updateSupport(text)
        }
        onExited: function (exitCode) {
            if (exitCode !== 0)
                root.updateSupport("");
        }
    }

    Timer {
        id: supportDeadline
        interval: 3000
        onTriggered: {
            supportProcess.signal(9);
            root.updateSupport("");
        }
    }

    Process {
        id: layoutTracker
        command: ["setpriv", "--pdeathsig", "TERM", root.helperPath]
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
