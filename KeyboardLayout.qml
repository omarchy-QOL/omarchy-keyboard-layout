pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "lib/shortcuts" as Shortcuts
import "lib/PulseColor.js" as PulseColor
import "ui" as LocalUi

Panel {
    id: root
    moduleName: "io.github.ilyazar.keyboard-layout"

    readonly property string keyboardConfigPath: Quickshell.env("HOME") + "/.config/hypr/input.lua"
    readonly property var trackerService: bar?.shell?.serviceFor(moduleName)
    readonly property string pulseColor: PulseColor.normalizedPulseColor(setting("pulseColor", PulseColor.tealColor))
    readonly property bool animationEnabled: setting("animation", true) !== false
    readonly property bool showSingleLayout: setting("showSingleLayout", false) === true
    readonly property bool perWindowLayouts: setting("perWindowLayouts", false) === true
    readonly property bool trackerSupportKnown: trackerService ? trackerService.supportKnown : false
    readonly property bool trackerSupported: trackerService ? trackerService.supported : false
    readonly property bool perWindowLayoutsActive: perWindowLayouts && trackerSupported
    readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
    property bool settingsPage: false
    property int keyboardOptionsLine: 1

    property string keyboardName: ""
    property var keyboardNames: []
    property string layoutConfig: ""
    property var layouts: []
    property int activeLayoutIndex: -1
    property int cursorIndex: 0
    property bool cursorActive: false
    property string layoutFull: ""
    property string layoutLabel: ""
    property bool multipleLayouts: true
    property real pulseOpacity: 1
    property real pulseScale: 1
    property int automaticRestoreLayout: -1

    function storeSettings(next) {
        root.settings = next;
        if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function") {
            console.warn("Keyboard Layout Pulse: inline settings are unavailable");
            return false;
        }
        return root.bar.shell.updateEntryInline(root.moduleName, next);
    }

    function persistSettings(values) {
        var next = {};
        for (let existing in root.settings)
            next[existing] = root.settings[existing];
        for (let key in values)
            next[key] = values[key];
        return root.storeSettings(next);
    }

    function setPulseColor(value) {
        if (!PulseColor.isPulseColor(value))
            return;
        var color = PulseColor.normalizedPulseColor(value);
        persistSettings({
            pulseColor: color
        });
    }

    function resetPulse() {
        pulseAnimation.stop();
        root.pulseOpacity = 1;
        root.pulseScale = 1;
    }

    function setAnimationEnabled(enabled) {
        persistSettings({
            animation: enabled
        });
        if (!enabled)
            resetPulse();
    }

    function setShowSingleLayout(enabled) {
        persistSettings({
            showSingleLayout: enabled
        });
        if (!enabled && !root.multipleLayouts)
            root.close();
    }

    function setPerWindowLayouts(enabled) {
        persistSettings({
            perWindowLayouts: enabled
        });
        syncLayoutTracker();
    }

    function syncLayoutTracker() {
        if (root.trackerService && typeof root.trackerService.setTrackingEnabled === "function")
            root.trackerService.setTrackingEnabled(root.perWindowLayouts);
        if (!root.perWindowLayoutsActive) {
            automaticRestoreTimer.stop();
            root.automaticRestoreLayout = -1;
        }
    }

    function expectAutomaticRestore(layout) {
        root.automaticRestoreLayout = Number(layout);
        automaticRestoreTimer.restart();
    }

    function updateKeyboardConfig(raw) {
        var lines = String(raw || "").split("\n");
        var commentedLine = 1;

        for (let index = 0; index < lines.length; index++) {
            if (/^\s*kb_options\s*=/.test(lines[index])) {
                root.keyboardOptionsLine = index + 1;
                return;
            }
            if (/kb_options\s*=/.test(lines[index]))
                commentedLine = index + 1;
        }

        root.keyboardOptionsLine = commentedLine;
    }

    function openSettings() {
        root.settingsPage = true;
        settingsView.beginEditing();
    }

    function closeSettings() {
        root.settingsPage = false;
        settingsView.endEditing();
        keyCatcher.forceActiveFocus();
    }

    function editKeyboardShortcut() {
        root.close();
        Quickshell.execDetached(["omarchy-launch-terminal", "nvim", "-c", String(root.keyboardOptionsLine) + " | normal! zz", root.keyboardConfigPath]);
    }

    function typingKeyboards(keyboards) {
        var physical = keyboards.filter(function (keyboard) {
            var name = String(keyboard.name);
            return name === "keyd-virtual-keyboard" || !name.includes("virtual-keyboard");
        });
        var typing = physical.filter(function (keyboard) {
            var name = String(keyboard.name);
            // Hotkey-only devices do not follow layout group switches.
            return !name.endsWith("-system-control") && !name.endsWith("-consumer-control") && name !== "video-bus" && !name.startsWith("power-button") && !name.endsWith("-extra-buttons") && !name.endsWith("-wmi-hotkeys");
        });
        return typing.length > 0 ? typing : physical;
    }

    function selectKeyboard(keyboards) {
        var typing = root.typingKeyboards(keyboards);
        return typing.find(function (keyboard) {
            return keyboard.name === root.keyboardName;
        }) || typing.find(function (keyboard) {
            return keyboard.main;
        }) || typing[0];
    }

    function updateKeyboards(keyboards) {
        var keyboard = root.selectKeyboard(keyboards);
        if (!keyboard || !keyboard.active_keymap)
            return;
        var nextLayouts = keyboard.layout ? String(keyboard.layout).split(",") : [];
        var variants = String(keyboard.variant || "").split(",");
        var index = Number(keyboard.active_layout_index || 0);
        var config = JSON.stringify([nextLayouts, variants]);
        var sameConfig = root.layoutConfig === config;
        var changed = sameConfig && root.activeLayoutIndex >= 0 && root.activeLayoutIndex !== index;
        var automatic = root.automaticRestoreLayout === index;

        root.keyboardName = String(keyboard.name || "");
        root.keyboardNames = root.typingKeyboards(keyboards).map(function (item) {
            return String(item.name || "");
        }).filter(Boolean);
        root.layoutConfig = config;
        root.layouts = nextLayouts.map(function (layout, i) {
            var variant = String(variants[i] || "").trim();
            return layout.trim().toUpperCase() + (variant ? "(" + variant + ")" : "");
        });
        root.activeLayoutIndex = index;
        root.layoutFull = String(keyboard.active_keymap);
        root.layoutLabel = root.layouts[index] || root.layoutFull;
        root.multipleLayouts = nextLayouts.length > 1;
        if (!sameConfig || automatic) {
            automaticRestoreTimer.stop();
            root.automaticRestoreLayout = -1;
            resetPulse();
        } else if (changed && root.animationEnabled) {
            pulseAnimation.restart();
        }
    }

    function refresh() {
        if (!queryProcess.running)
            queryProcess.running = true;
    }

    function switchLayouts(target) {
        if (!root.bar || root.keyboardNames.length === 0)
            return;
        var commands = root.keyboardNames.map(function (name) {
            return "hyprctl switchxkblayout -- " + Util.shellQuote(name) + " " + Util.shellQuote(target);
        });
        root.bar.run(commands.join("; "));
        refreshTimer.restart();
    }

    function cycle(direction) {
        root.switchLayouts(direction);
    }

    function selectLayout(index) {
        if (index < 0 || index >= root.layouts.length)
            return;
        root.switchLayouts(String(index));
        root.close();
    }

    function moveCursor(delta) {
        var itemCount = root.layouts.length + 1;
        if (!root.cursorActive) {
            root.cursorActive = true;
            return;
        }
        root.cursorIndex = (root.cursorIndex + delta + itemCount) % itemCount;
    }

    function activateCursor() {
        if (!root.cursorActive)
            return;
        if (root.cursorIndex === root.layouts.length)
            root.openSettings();
        else
            root.selectLayout(root.cursorIndex);
    }

    onOpenedChanged: {
        if (!root.opened)
            return;
        root.settingsPage = false;
        root.cursorIndex = root.activeLayoutIndex;
        root.cursorActive = false;
        root.refresh();
        layoutShortcut.refresh();
    }

    onAnimationEnabledChanged: if (!animationEnabled)
        resetPulse()
    onPerWindowLayoutsChanged: syncLayoutTracker()
    onTrackerServiceChanged: syncLayoutTracker()
    Component.onCompleted: refresh()

    Shortcuts.XkbGroupOption {
        id: layoutShortcut
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (!event)
                return;
            var name = String(event.name || "");
            if (name.indexOf("activelayout") !== -1) {
                let device = String(event.data || "").split(",")[0];
                if (device && !device.startsWith("hl-virtual-keyboard"))
                    root.keyboardName = device;
            } else if (name !== "configreloaded")
                return;
            root.refresh();
        }
    }

    Connections {
        target: root.trackerService
        ignoreUnknownSignals: true
        function onRestoreRequested(layout) {
            root.expectAutomaticRestore(layout);
        }
    }

    Process {
        id: queryProcess
        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    root.updateKeyboards(JSON.parse(text || "{}").keyboards || []);
                } catch (error) {
                    root.layoutLabel = "";
                }
            }
        }
    }

    FileView {
        path: root.keyboardConfigPath
        watchChanges: true
        printErrors: false
        onLoaded: root.updateKeyboardConfig(text())
        onFileChanged: reload()
    }

    Timer {
        id: refreshTimer
        interval: 600
        onTriggered: root.refresh()
    }

    Timer {
        id: automaticRestoreTimer
        interval: 1500
        onTriggered: root.automaticRestoreLayout = -1
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }

    SequentialAnimation {
        id: pulseAnimation
        loops: 3
        onStopped: {
            root.pulseOpacity = 1;
            root.pulseScale = 1;
        }
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "pulseOpacity"
                from: 0.65
                to: 1
                duration: 650
                easing.type: Easing.InOutSine
            }
            SequentialAnimation {
                NumberAnimation {
                    target: root
                    property: "pulseScale"
                    from: 1
                    to: 1.16
                    duration: 325
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    target: root
                    property: "pulseScale"
                    from: 1.16
                    to: 1
                    duration: 325
                    easing.type: Easing.InOutSine
                }
            }
        }
    }

    visible: layoutLabel !== "" && (multipleLayouts || showSingleLayout)
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    WidgetButton {
        id: button
        anchors.fill: button.parent
        bar: root.bar
        text: ""
        hasVisualContent: root.layoutLabel !== ""
        labelVisible: false
        fixedWidth: Math.max(12, labelProbe.implicitWidth + Style.space(12))
        horizontalMargin: 6
        tooltipText: root.layoutFull
        onPressed: function (mouseButton) {
            if (mouseButton === Qt.LeftButton)
                root.toggle();
        }
        onWheelMoved: function (delta) {
            root.cycle(delta > 0 ? "next" : "prev");
        }
    }

    Text {
        id: labelProbe
        visible: false
        text: root.layoutLabel
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
    }

    Text {
        id: pulseLabel
        anchors.centerIn: button
        text: root.layoutLabel
        color: root.animationEnabled && pulseAnimation.running ? root.pulseColor : button.foreground
        opacity: root.pulseOpacity
        scale: root.pulseScale
        transformOrigin: Item.Center
        font.family: button.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: root.animationEnabled && pulseAnimation.running
        renderType: Text.NativeRendering
        layer.enabled: root.animationEnabled && pulseAnimation.running
        layer.smooth: true

        Behavior on color {
            ColorAnimation {
                duration: 160
            }
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(root.settingsPage ? Style.space(260) : (panelColumn.implicitHeight > 0 ? panel.contentHeight : Style.space(180)))
        contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: keyCatcher.parent
            blocked: root.settingsPage && settingsView.keyboardInputActive
            onMoveRequested: function (dx, dy) {
                if (!root.settingsPage)
                    root.moveCursor(dy !== 0 ? dy : dx);
            }
            onActivateRequested: root.activateCursor()
            onCloseRequested: {
                if (root.settingsPage)
                    root.closeSettings();
                else
                    root.close();
            }
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }

            Column {
                id: panelColumn
                width: parent.width
                spacing: Style.space(6)

                Column {
                    id: layoutColumn
                    visible: !root.settingsPage
                    width: parent.width
                    spacing: Style.space(6)

                    Repeater {
                        model: root.layouts

                        Button {
                            required property var modelData
                            required property int index
                            width: layoutColumn.width
                            text: modelData
                            foreground: root.bar.foreground
                            fontFamily: root.bar.fontFamily
                            fontSize: Style.font.bodySmall
                            leftAlign: true
                            bordered: true
                            selected: root.activeLayoutIndex === index
                            hasCursor: root.cursorActive && root.cursorIndex === index
                            onClicked: root.selectLayout(index)
                            onHovered: function (hovered) {
                                if (!hovered)
                                    return;
                                root.cursorActive = true;
                                root.cursorIndex = index;
                            }
                        }
                    }

                    PanelSeparator {
                        foreground: root.bar.foreground
                    }

                    Button {
                        id: settingsButton
                        width: layoutColumn.width
                        text: "Settings"
                        foreground: root.bar.foreground
                        fontFamily: root.bar.fontFamily
                        fontSize: Style.font.bodySmall
                        leftAlign: true
                        bordered: true
                        hasCursor: root.cursorActive && root.cursorIndex === root.layouts.length
                        onClicked: root.openSettings()
                        onHovered: function (hovered) {
                            if (!hovered)
                                return;
                            root.cursorActive = true;
                            root.cursorIndex = root.layouts.length;
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: settingsButton.horizontalPadding
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            color: settingsButton.foreground
                            font.family: settingsButton.fontFamily
                            font.pixelSize: settingsButton.fontSize
                        }
                    }
                }

                LocalUi.KeyboardSettings {
                    id: settingsView
                    visible: root.settingsPage
                    width: parent.width
                    foreground: root.bar.foreground
                    urgent: root.urgent
                    fontFamily: root.bar.fontFamily
                    pulseColor: root.pulseColor
                    animationEnabled: root.animationEnabled
                    showSingleLayout: root.showSingleLayout
                    perWindowLayoutsActive: root.perWindowLayoutsActive
                    trackerSupportKnown: root.trackerSupportKnown
                    trackerSupported: root.trackerSupported
                    shortcutLabel: layoutShortcut.label
                    onPulseColorSelected: function (value) {
                        root.setPulseColor(value);
                    }
                    onAnimationRequested: function (enabled) {
                        root.setAnimationEnabled(enabled);
                    }
                    onSingleLayoutRequested: function (enabled) {
                        root.setShowSingleLayout(enabled);
                    }
                    onPerWindowLayoutsRequested: function (enabled) {
                        root.setPerWindowLayouts(enabled);
                    }
                    onShortcutEditRequested: root.editKeyboardShortcut()
                    onBackRequested: root.closeSettings()
                    onCloseRequested: root.close()
                    onFocusRequested: keyCatcher.forceActiveFocus()
                }
            }
        }
    }
}
