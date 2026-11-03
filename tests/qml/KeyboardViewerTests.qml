import QtQuick
import Quickshell
import Quickshell.Io
import QtTest
import "../../ui/keyboard" as Keyboard
import "../../ui" as PluginUi

TestCase {
    id: tests
    name: "KeyboardViewer"
    visible: true
    width: 900
    height: 700
    when: started
    property bool started: false
    property var readyGroups: []
    property int selectedLayout: -1
    property int viewersOpened: 0
    property int emojisOpened: 0
    property int settingsOpened: 0
    property var clickedKeys: []
    property var pressedKeys: []
    property var heldKeys: []
    Timer {
        interval: 100
        running: true
        onTriggered: tests.started = true
    }
    onCompletedChanged: if (completed)
                            console.log("KEYBOARD_QML_RESULT", JSON.stringify({
                                                                                  passed: qtest_results.passCount,
                                                                                  failed: qtest_results.failCount
                                                                              }))

    Keyboard.KeymapReader {
        id: reader
        helperPath: Quickshell.env("TEST_HELPER")
        keyboard: ({
                       layout: "us,de",
                       variant: ",",
                       options: "",
                       active_layout_index: 0
                   })
        onReadyChanged: if (ready)
                            tests.readyGroups.push(description.group)
    }

    Keyboard.KeyboardTyping {
        id: typing
    }

    PluginUi.LayoutPicker {
        id: picker
        width: 180
        layouts: ["US", "DE"]
        selectedIndex: 0
        foreground: "white"
        fontFamily: "monospace"
        onLayoutChosen: function (index) {
            tests.selectedLayout = index;
        }
        onViewerRequested: tests.viewersOpened++
        onEmojiRequested: tests.emojisOpened++
        onSettingsRequested: tests.settingsOpened++
    }

    Keyboard.KeyboardCanvas {
        id: canvas
        y: 250
        width: 760
        keymap: reader.description
        interactionState: ({
                               shift: 0,
                               altGr: 0,
                               control: 0,
                               alt: 0,
                               superKey: 0,
                               capsLock: false,
                               pendingDeadKey: "",
                               pendingDeadKeyId: ""
                           })
        shapeName: "iso"
        fontFamily: "monospace"
        onKeyClicked: function (keyId) {
            tests.clickedKeys.push(keyId);
        }
        onKeyPressed: function (keyId) {
            tests.pressedKeys.push(keyId);
        }
        onKeyHeld: function (keyId, keyItem, event) {
            tests.heldKeys.push(keyId);
            event.accepted = true;
        }
    }

    FileView {
        id: actionLog
        path: Quickshell.env("TEST_ACTION_LOG")
        printErrors: false
    }

    function cleanup() {
        if (qtest_results.failed)
            console.error("QML_TEST_FAILED", qtest_results.functionName);
    }

    function equal(actual, expected) {
        if (actual !== expected)
            console.error("QML_ASSERT", qtest_results.functionName, actual, "expected", expected);
        compare(actual, expected);
    }

    function test_01_pickerNavigation() {
        picker.resetCursor();
        picker.moveCursor(1);
        picker.moveCursor(1);
        picker.activateCursor();
        equal(selectedLayout, 1);
        picker.moveCursor(1);
        picker.activateCursor();
        equal(emojisOpened, 1);
        picker.moveCursor(1);
        picker.activateCursor();
        equal(viewersOpened, 1);
        picker.moveCursor(1);
        picker.activateCursor();
        equal(settingsOpened, 1);
    }

    function test_02_currentGroupAndLateResults() {
        reader.keyboard = {
            layout: "us,de",
            variant: ",",
            options: "test:slow",
            active_layout_index: 1
        };
        reader.active = true;
        tryVerify(function () {
            return reader.job !== null;
        });
        reader.keyboard = {
            layout: "us,de",
            variant: ",",
            options: "",
            active_layout_index: 0
        };
        readyGroups = [];
        verify(!reader.ready);
        tryVerify(function () {
            return reader.ready;
        });
        equal(reader.description.group, 0);
        equal(reader.description.keys.AD06.states[0].text, "y");
        verify(readyGroups.every(function (group) {
            return group === 0;
        }));
        reader.keyboard = {
            layout: "us,de",
            variant: ",",
            options: "",
            active_layout_index: 1
        };
        tryVerify(function () {
            return reader.ready;
        });
        equal(reader.description.keys.AD06.states[0].text, "z");
        reader.active = false;
    }

    function test_03_timeoutAndRecovery() {
        reader.configurationRevision++;
        reader.timeout = 50;
        reader.keyboard = {
            layout: "us",
            options: "test:slow",
            active_layout_index: 0
        };
        reader.active = true;
        tryVerify(function () {
            return reader.errorText !== "";
        });
        verify(!reader.ready);
        reader.timeout = 3000;
        reader.keyboard = {
            layout: "us",
            options: "",
            active_layout_index: 0
        };
        tryVerify(function () {
            return reader.ready;
        });
        equal(reader.description.keys.AD01.states[0].text, "q");
        reader.active = false;
    }

    function test_04_geometrySurvivesResize() {
        const fullHeight = canvas.implicitHeight;
        canvas.width = 480;
        verify(canvas.implicitHeight < fullHeight);
        canvas.shapeName = "ansi";
        canvas.shapeName = "jis";
        canvas.width = 760;
        verify(canvas.implicitHeight > 0);
    }

    function findKey(item, keyId) {
        if (item.keyGeometry && item.keyGeometry.keyId === keyId)
            return item;
        for (const child of item.children) {
            const found = findKey(child, keyId);
            if (found)
                return found;
        }
        return null;
    }

    function test_045_pointerAndHoldSignals() {
        const key = findKey(canvas, "AD03");
        verify(key !== null && key.available);
        mouseClick(key);
        equal(clickedKeys[0], "AD03");
        mousePress(key);
        wait(500);
        mouseRelease(key);
        equal(heldKeys[0], "AD03");
        equal(clickedKeys.length, 1);
    }

    function test_046_doubleClickSignals() {
        const space = findKey(canvas, "SPCE");
        const shift = findKey(canvas, "LFSH");
        pressedKeys = [];
        clickedKeys = [];
        mouseDoubleClickSequence(space);
        equal(pressedKeys.filter(function (keyId) {
            return keyId === "SPCE";
        }).length, 2);
        mouseDoubleClickSequence(shift);
        equal(clickedKeys.filter(function (keyId) {
            return keyId === "LFSH";
        }).length, 2);
    }

    Component {
        id: legendFixture
        Keyboard.KeyboardKey {
            fontFamily: "monospace"
        }
    }

    function test_047_legendsStayInsideTheirKey() {
        const labels = [["Shift", "ISO_Prev_Group"], ["Tab", "ISO_Left_Tab"],
                        ["ش", "َّ"], ["၁", "ဍ"], ["﷽", ""], ["ب", "﷽"], ["Very long custom action", "Long alternate action"]];
        for (const pitch of [28, 47, 74]) {
            for (const pair of labels) {
                const key = legendFixture.createObject(tests, {
                    keyGeometry: {x: 0, y: 0, width: pitch - 3, height: pitch - 3,
                                  notchWidth: 0, notchY: 0, hitRectangles: []},
                    keyPitch: pitch, label: pair[0], alternateLabel: pair[1]
                });
                verify(key !== null);
                wait(20);
                const primary = findChild(key, "primaryLegend");
                const secondary = findChild(key, "secondaryLegend");
                if (secondary.visible)
                    verify(primary.y >= secondary.y + secondary.height);
                for (const text of [primary, secondary]) {
                    if (!text.visible) continue;
                    verify(text.x >= 0 && text.y >= 0);
                    verify(text.x + text.width <= text.parent.width);
                    verify(text.y + text.height <= text.parent.height);
                    verify(text.contentWidth <= text.width + 0.5, "width " + pair + " pitch " + pitch + " " + text.objectName + " " + text.contentWidth + " > " + text.width);
                    verify(text.contentHeight <= text.height + 0.5, "height " + pair + " pitch " + pitch + " " + text.objectName + " " + text.contentHeight + " > " + text.height);
                }
                key.destroy();
            }
        }
    }

    function test_05_privateTypingAndFailure() {
        typing.active = true;
        typing.enqueue([
                           {
                               command: ["wtype", "-"],
                               input: "é😀"
                           },
                           {
                               command: ["wtype", "-M", "ctrl", "-k", "a", "-m", "ctrl"]
                           }
                       ]);
        tryVerify(function () {
            return typing.action === null && typing.queue.length === 0;
        });
        actionLog.reload();
        tryVerify(function () {
            return actionLog.text().length > 0;
        });
        const lines = actionLog.text().trim().split("\n").map(function (line) {
            return JSON.parse(line);
        });
        equal(lines.length, 2);
        equal(lines[0].input, "é😀");
        equal(lines[0].command.join(" "), "-");
        equal(lines[1].command.join(" "), "-M ctrl -k a -m ctrl");
        typing.enqueue([
                           {
                               command: ["wtype", "-k", "TestFailure"]
                           }
                       ]);
        tryVerify(function () {
            return typing.errorText !== "";
        });
        typing.active = false;
    }
}
