pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../lib/keyboard/KeymapData.js" as KeymapData

Item {
    id: root

    required property string helperPath
    required property var keyboard
    property bool active: false
    property int configurationRevision: 0
    property bool supported: true
    property int timeout: 3000
    property string keymapFile: ""
    property bool fileOptionReady: false
    property string fileOptionError: ""
    property int fileRequestRevision: -1
    property int fileRevision: 0
    property var cache: ({})
    property var job: null
    property string failedSignature: ""

    readonly property var request: KeymapData.requestFor(root.keyboard, root.keymapFile)
    readonly property string signature: KeymapData.signature(root.request, root.configurationRevision + ":"
                                                             + root.fileRevision)

    readonly property var description: root.fileOptionReady && root.signature ? root.cache[root.signature] || null :
                                                                                null

    readonly property bool ready: root.description !== null
    readonly property bool loading: root.active && root.supported && !root.ready && (root.job !== null
                                                                                     || fileOptionProcess.running)
    readonly property string errorText: !root.supported ? "The native keyboard helper is unavailable." :
                                                          root.fileOptionError || (root.signature !== ""
                                                                                   && root.failedSignature
                                                                                   === root.signature
                                                                                   ? "Could not read the current keyboard layout." :
                                                                                     "")

    function readFileOption() {
        if (!root.active || !root.supported || fileOptionProcess.running)
            return;
        root.fileOptionReady = false;
        root.fileOptionError = "";
        root.fileRequestRevision = root.configurationRevision;
        fileDeadline.restart();
        fileOptionProcess.running = true;
    }

    function invalidate() {
        root.cache = {};
        root.failedSignature = "";
        root.fileOptionReady = false;
        if (root.active)
            root.readFileOption();
    }

    function retry() {
        root.failedSignature = "";
        root.readFileOption();
    }

    function load() {
        if (!root.active || !root.supported || !root.helperPath || !root.fileOptionReady || !root.request || root.ready
                || root.job || root.failedSignature === root.signature)
            return;
        root.job = jobFactory.createObject(root, {
                                               helperPath: root.helperPath,
                                               request: root.request,
                                               signature: root.signature,
                                               timeout: root.timeout
                                           });
        if (!root.job)
            root.failedSignature = root.signature;
    }

    function acceptResult(finishedJob, description) {
        if (root.job !== finishedJob)
            return;
        if (description)
            root.cache = KeymapData.remember(root.cache, finishedJob.signature, description);
        else
            root.failedSignature = finishedJob.signature;
        root.job = null;
        finishedJob.destroy();
        Qt.callLater(root.load);
    }

    Component {
        id: jobFactory
        KeymapJob {
            id: descriptionJob
            onFinished: function (description) {
                root.acceptResult(descriptionJob, description);
            }
        }
    }

    onActiveChanged: if (active) {
                         root.failedSignature = "";
                         root.readFileOption();
                     }
    onHelperPathChanged: {
        root.failedSignature = "";
        Qt.callLater(root.load);
    }
    onSupportedChanged: if (supported && active)
                            root.readFileOption()
    onSignatureChanged: Qt.callLater(root.load)
    onConfigurationRevisionChanged: root.invalidate()

    Process {
        id: fileOptionProcess
        command: ["hyprctl", "-j", "getoption", "input:kb_file"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (root.fileRequestRevision !== root.configurationRevision)
                    return;
                try {
                    const option = JSON.parse(text);
                    if (typeof option.str !== "string")
                        throw new Error("invalid keyboard option");
                    let path = option.set === false || option.str === "[[EMPTY]]" ? "" : option.str;
                    if (path.startsWith("~/"))
                        path = Quickshell.env("HOME") + path.slice(1);
                    root.keymapFile = path;
                    root.fileOptionReady = true;
                    Qt.callLater(root.load);
                } catch (error) {
                    root.fileOptionError = "Could not read the keyboard configuration.";
                }
            }
        }
        onExited: function (exitCode) {
            fileDeadline.stop();
            if (root.fileRequestRevision !== root.configurationRevision)
                Qt.callLater(root.readFileOption);
            else if (exitCode !== 0)
                root.fileOptionError = "Could not read the keyboard configuration.";
        }
    }

    Timer {
        id: fileDeadline
        interval: root.timeout
        onTriggered: {
            fileOptionProcess.signal(9);
            root.fileOptionError = "Reading the keyboard configuration timed out.";
        }
    }

    FileView {
        path: root.keymapFile
        watchChanges: true
        preload: false
        printErrors: false
        onFileChanged: {
            root.fileRevision++;
            root.cache = {};
            root.failedSignature = "";
            Qt.callLater(root.load);
        }
    }
}
