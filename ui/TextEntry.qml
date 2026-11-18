pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The kit's TextField look on a TextArea. A writable TextField reads the whole
// clipboard text, with no size or time limit, on every clipboard change and on
// paste. TextArea only checks the offered formats, and paste goes through a
// capped helper instead of Qt.
TextArea {
    id: root

    property color foreground: Commons.Color.foreground
    readonly property var borderSpec: Border.controlSpec(root.activeFocus ? "focus" : (root.hovered ? "hover-cursor" : "normal"), root.foreground, Commons.Color.accent)

    signal accepted()

    function pasteCapped(primary) {
        if (pasteProcess.running)
            return;
        pasteProcess.command = ["timeout", "--signal=KILL", "2", "sh", "-c", "wl-paste --no-newline --type text \"$@\" 2>/dev/null | head -c 1024", "sh"].concat(primary ? ["--primary"] : []);
        pasteProcess.running = true;
    }

    color: root.foreground
    selectionColor: Style.selectionFillFor(root.foreground, Commons.Color.accent)
    selectedTextColor: root.foreground
    placeholderTextColor: Qt.darker(root.foreground, 1.6)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    leftPadding: Style.spacing.controlPaddingX + Border.left(root.borderSpec)
    rightPadding: Style.spacing.controlPaddingX + Border.right(root.borderSpec)
    topPadding: Style.spacing.inputPaddingY + Border.top(root.borderSpec)
    bottomPadding: Style.spacing.inputPaddingY + Border.bottom(root.borderSpec)
    verticalAlignment: TextEdit.AlignVCenter
    clip: true
    // its Paste entry is Qt's own paste
    ContextMenu.menu: null
    Keys.onPressed: function (event) {
        // single line, and no paste by Qt
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.accepted();
            root.editingFinished();
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            root.nextItemInFocusChain(event.key === Qt.Key_Tab).forceActiveFocus();
        } else if (event.matches(StandardKey.Paste)) {
            root.pasteCapped(false);
        } else {
            return;
        }
        event.accepted = true;
    }

    Process {
        id: pasteProcess
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                // one short printable line, and only while still being edited
                const line = Array.from(text.split(/[\r\n]/)[0].replace(/[\x00-\x1f\x7f]/g, " ")).slice(0, 256).join("");
                if (!line || !root.activeFocus)
                    return;
                const start = root.selectionStart;
                root.remove(start, root.selectionEnd);
                root.insert(start, line);
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.MiddleButton
        onClicked: root.pasteCapped(true)
    }

    background: BorderSurface {
        color: Style.controlFill(root.activeFocus, root.hovered, root.foreground, Commons.Color.accent)
        borderSpec: root.borderSpec
        radius: Style.cornerRadius
    }
}
