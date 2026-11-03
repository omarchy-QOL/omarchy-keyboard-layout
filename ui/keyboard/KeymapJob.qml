pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "../../lib/keyboard/KeymapData.js" as KeymapData

Item {
    id: root

    required property string helperPath
    required property var request
    required property string signature
    property int timeout: 3000
    property bool outputComplete: false
    property bool processComplete: false
    property bool completed: false
    property int exitCode: -1
    property string outputText: ""
    signal finished(var description)

    function complete(description) {
        if (root.completed)
            return;
        root.completed = true;
        deadline.stop();
        root.outputText = "";
        root.finished(description);
    }

    function finishIfReady() {
        if (!root.outputComplete || !root.processComplete || root.completed)
            return;
        const description = root.exitCode === 0 ? KeymapData.parseDescription(root.outputText) : null;
        root.complete(description && description.group === root.request.group ? description : null);
    }

    Component.onCompleted: {
        deadline.start();
        process.running = true;
    }

    Process {
        id: process
        command: [root.helperPath, "--describe-keymap"]
        stdinEnabled: true
        onStarted: {
            write(JSON.stringify(root.request) + "\n");
            stdinEnabled = false;
        }
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.outputText = text.length <= KeymapData.outputLimit ? text : "";
                root.outputComplete = true;
                root.finishIfReady();
            }
        }
        onExited: function (exitCode) {
            root.exitCode = exitCode;
            root.processComplete = true;
            root.finishIfReady();
        }
    }

    Timer {
        id: deadline
        interval: root.timeout
        onTriggered: {
            process.signal(9);
            root.complete(null);
        }
    }
}
