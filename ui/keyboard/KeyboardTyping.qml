pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io

Item {
    id: root

    property bool active: false
    property string contextSignature: ""
    property var queue: []
    property var action: null
    property string errorText: ""

    function clearPending() {
        root.queue = [];
    }

    function validAction(action) {
        return action && Array.isArray(action.command) && action.command[0] === "wtype" && action.command.length <= 24
                && action.command.every(function (argument) {
                    return typeof argument === "string" && argument.length <= 512;
                }) && (action.input === undefined || (typeof action.input === "string" && action.input.length <= 4096
                                                      && action.command.length === 2 && action.command[1] === "-"));
    }

    function enqueue(actions) {
        if (!root.active || !Array.isArray(actions) || !actions.every(root.validAction))
            return;
        if (actions.length + root.queue.length > 32) {
            root.errorText = "Typing is busy. Wait and try again.";
            return;
        }
        root.errorText = "";
        root.queue = root.queue.concat(actions);
        root.startNext();
    }

    function startNext() {
        if (!root.active || root.action || inputProcess.running || !root.queue.length)
            return;
        root.action = root.queue[0];
        root.queue = root.queue.slice(1);
        inputProcess.stdinEnabled = typeof root.action.input === "string";
        inputDeadline.restart();
        inputProcess.running = true;
    }

    onActiveChanged: if (!active)
                         root.clearPending()
    onContextSignatureChanged: root.clearPending()

    Process {
        id: inputProcess
        command: root.action ? root.action.command : []
        onStarted: {
            if (typeof root.action.input === "string") {
                write(root.action.input);
                stdinEnabled = false;
            }
        }
        onExited: function (exitCode) {
            inputDeadline.stop();
            root.action = null;
            if (exitCode !== 0) {
                root.errorText = "Could not type this key.";
                root.clearPending();
            }
            Qt.callLater(root.startNext);
        }
    }

    Timer {
        id: inputDeadline
        interval: 2000
        onTriggered: {
            inputProcess.signal(9);
            root.errorText = "Typing this key timed out.";
            root.clearPending();
            if (!inputProcess.running)
                root.action = null;
        }
    }
}
