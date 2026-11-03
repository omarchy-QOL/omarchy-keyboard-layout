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
import "ui/keyboard" as KeyboardUi
import "lib/keyboard/KeyboardDevices.js" as KeyboardDevices

Panel {
    id: root
    moduleName: "io.github.ilyazar.keyboard-layout"

    readonly property string keyboardConfigPath: Quickshell.env("HOME") + "/.config/hypr/input.lua"
    readonly property var trackerService: bar?.shell?.serviceFor(moduleName)
    readonly property string pulseColor: PulseColor.normalizedPulseColor(setting("pulseColor", PulseColor.tealColor))
    readonly property bool animationEnabled: setting("animation", true) !== false
    readonly property bool showSingleLayout: setting("showSingleLayout", false) === true
    readonly property bool keycapStyle: setting("keycapStyle", false) === true
    readonly property bool perWindowLayouts: setting("perWindowLayouts", false) === true
    readonly property bool trackerSupportKnown: trackerService ? trackerService.supportKnown : false
    readonly property bool trackerSupported: trackerService ? trackerService.supported : false
    readonly property bool perWindowLayoutsActive: perWindowLayouts && trackerSupported
    readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
    property bool settingsPage: false
    property int keyboardOptionsLine: 1

    property var keyboardDetails: null
    property int configurationRevision: 0
    property string keyboardName: ""
    property var keyboardNames: []
    property string layoutConfig: ""
    property var layoutKeys: []
    readonly property int maxLayoutLabelLength: 256
    readonly property var layoutLabels: {
        const labels = root.setting("layoutLabels", {});
        return labels && typeof labels === "object" && !Array.isArray(labels) ? labels : {};
    }
    readonly property var layouts: root.layoutKeys.map(function (key) {
        return root.layoutDisplayName(key);
    })
    property int activeLayoutIndex: -1
    property string layoutFull: ""
    readonly property string layoutLabel: root.layouts[root.activeLayoutIndex] || root.layoutFull
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

    function validLayoutLabel(value) {
        // reject broken surrogate pairs while allowing supplementary glyphs
        return typeof value === "string" && value.length <= root.maxLayoutLabelLength && !
                /[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(value) && !
                /[\ud800-\udbff](?![\udc00-\udfff])|(^|[^\ud800-\udbff])[\udc00-\udfff]/.test(value);
    }

    function layoutDisplayName(key) {
        const alias = root.layoutLabels[key];
        return validLayoutLabel(alias) && alias.trim() ? alias.trim() : key;
    }

    function setLayoutDisplayName(key, value) {
        if (!root.layoutKeys.includes(key) || !validLayoutLabel(value))
            return;
        const aliases = Object.assign({}, root.layoutLabels);
        const name = value.trim();
        if (name && name !== key)
            aliases[key] = name;
        else
            delete aliases[key];
        if (JSON.stringify(aliases) !== JSON.stringify(root.layoutLabels))
            persistSettings({
                                layoutLabels: aliases
                            });
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
        Quickshell.execDetached(["omarchy-launch-terminal", "nvim", "-c", String(root.keyboardOptionsLine)
                                 + " | normal! zz", root.keyboardConfigPath]);
    }

    function clearKeyboardState() {
        root.keyboardDetails = null;
        root.layoutConfig = "";
        root.layoutKeys = [];
        root.activeLayoutIndex = -1;
        root.layoutFull = "";
        root.multipleLayouts = false;
        resetPulse();
        root.close();
    }

    function updateKeyboards(keyboards) {
        const keyboard = KeyboardDevices.selectDevice(keyboards, root.keyboardName);
        if (!keyboard || !keyboard.active_keymap) {
            root.clearKeyboardState();
            return;
        }
        var nextLayouts = keyboard.layout ? String(keyboard.layout).split(",") : [];
        var variants = String(keyboard.variant || "").split(",");
        var index = Number(keyboard.active_layout_index || 0);
        var config = JSON.stringify([nextLayouts, variants]);
        var sameConfig = root.layoutConfig === config;
        var changed = sameConfig && root.activeLayoutIndex >= 0 && root.activeLayoutIndex !== index;
        var automatic = root.automaticRestoreLayout === index;

        root.keyboardDetails = keyboard;
        root.keyboardName = String(keyboard.name || "");
        root.keyboardNames = KeyboardDevices.typingDevices(keyboards).map(function (item) {
            return String(item.name || "");
        }).filter(Boolean);
        root.layoutConfig = config;
        if (!sameConfig) {
            root.layoutKeys = nextLayouts.map(function (layout, i) {
                const variant = String(variants[i] || "").trim();
                return layout.trim().toUpperCase() + (variant ? "(" + variant + ")" : "");
            });
        }
        root.activeLayoutIndex = index;
        root.layoutFull = String(keyboard.active_keymap);
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
    }

    function openKeyboardViewer() {
        root.refresh();
        root.close();
        keyboardViewer.open(button.QsWindow.window ? button.QsWindow.window.screen : null);
    }

    onOpenedChanged: {
        if (!root.opened) {
            layoutPicker.resetCursor();
            return;
        }
        root.settingsPage = false;
        layoutPicker.resetCursor();
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
            } else if (name === "configreloaded") {
                root.configurationRevision++;
            } else {
                return;
            }
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
        onRunningChanged: queryDeadline.running = running
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    root.updateKeyboards(JSON.parse(text || "{}").keyboards || []);
                } catch (error) {
                    root.clearKeyboardState();
                }
            }
        }
    }

    Timer {
        id: queryDeadline
        interval: 3000
        onTriggered: queryProcess.signal(9)
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
        fixedWidth: Math.min(Style.space(160), root.keycapStyle
            ? Math.max(keycap.height, labelProbe.implicitWidth + keycap.height * 0.4) + Style.space(12)
            : Math.max(12, labelProbe.implicitWidth + Style.space(12)))
        horizontalMargin: 6
        tooltipText: root.layoutFull
        onPressed: function (mouseButton) {
            if (mouseButton === Qt.LeftButton || mouseButton === Qt.RightButton)
                root.toggle();
        }
        onWheelMoved: function (delta) {
            root.cycle(delta > 0 ? "next" : "prev");
        }
    }

    Text {
        id: labelProbe
        textFormat: Text.PlainText
        visible: false
        text: root.layoutLabel
        font.family: button.fontFamily
        font.pixelSize: root.keycapStyle ? Math.round(keycap.height * (root.layoutLabel.length > 1 ? 0.6 : 0.72))
            : Style.font.caption
        font.bold: root.keycapStyle
    }

    Rectangle {
        id: keycap
        visible: root.keycapStyle
        anchors.centerIn: button
        width: Math.max(0, button.width - Style.space(12))
        height: Style.space(15)
        radius: Math.max(Math.round(height * 0.2), Math.min(Style.cornerRadius, height * 0.3))
        color: root.animationEnabled && pulseAnimation.running ? root.pulseColor : button.foreground
        opacity: root.pulseOpacity
        scale: root.pulseScale
        readonly property real luminance: 0.299 * color.r + 0.587 * color.g + 0.114 * color.b

        Behavior on color {
            ColorAnimation { duration: 160 }
        }
    }

    Text {
        id: pulseLabel
        textFormat: Text.PlainText
        width: Math.max(0, button.width - Style.space(12))
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        maximumLineCount: 1
        anchors.centerIn: button
        text: root.layoutLabel
        color: root.keycapStyle ? (keycap.luminance > 0.55 ? "#20242b" : "#f5f5f5")
            : root.animationEnabled && pulseAnimation.running ? root.pulseColor : button.foreground
        opacity: root.pulseOpacity
        scale: root.pulseScale
        transformOrigin: Item.Center
        font.family: button.fontFamily
        font.pixelSize: labelProbe.font.pixelSize
        font.bold: root.keycapStyle || (root.animationEnabled && pulseAnimation.running)
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
        contentWidth: panel.fittedContentWidth(Style.space(260))
        contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: keyCatcher.parent
            blocked: root.settingsPage ? settingsView.keyboardInputActive : layoutPicker.keyboardInputActive
            onMoveRequested: function (dx, dy) {
                if (!root.settingsPage)
                    layoutPicker.moveCursor(dy !== 0 ? dy : dx);
            }
            onActivateRequested: if (!root.settingsPage)
                                     layoutPicker.activateCursor()
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

                LocalUi.LayoutPicker {
                    id: layoutPicker
                    visible: !root.settingsPage
                    width: parent.width
                    layouts: root.layouts
                    selectedIndex: root.activeLayoutIndex
                    foreground: root.bar.foreground
                    fontFamily: root.bar.fontFamily
                    onLayoutChosen: function (index) {
                        root.selectLayout(index);
                    }
                    onSettingsRequested: root.openSettings()
                    onFocusRequested: keyCatcher.forceActiveFocus()
                    onViewerRequested: root.openKeyboardViewer()
                    onEmojiRequested: {
                        root.close();
                        root.bar.run("omarchy-shell shell toggle omarchy.emojis");
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
                    keycapStyle: root.keycapStyle
                    perWindowLayoutsActive: root.perWindowLayoutsActive
                    trackerSupportKnown: root.trackerSupportKnown
                    trackerSupported: root.trackerSupported
                    shortcutLabel: layoutShortcut.label
                    layoutKeys: root.layoutKeys
                    layoutLabels: root.layoutLabels
                    maxLayoutLabelLength: root.maxLayoutLabelLength
                    onLayoutLabelEdited: function (key, value) {
                        root.setLayoutDisplayName(key, value);
                    }
                    onPulseColorSelected: function (value) {
                        root.setPulseColor(value);
                    }
                    onAnimationRequested: function (enabled) {
                        root.setAnimationEnabled(enabled);
                    }
                    onSingleLayoutRequested: function (enabled) {
                        root.setShowSingleLayout(enabled);
                    }
                    onKeycapStyleRequested: function (enabled) {
                        root.persistSettings({ keycapStyle: enabled });
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

    KeyboardUi.KeyboardViewer {
        id: keyboardViewer
        keyboard: root.keyboardDetails
        helperPath: root.trackerService ? root.trackerService.helperPath : ""
        nativeSupported: root.trackerService ? !root.trackerService.supportKnown || root.trackerService.supported : true
        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
        keyboardShape: root.setting("keyboardShape", "auto")
        configurationRevision: root.configurationRevision
        onShapeSelected: function (shape) {
            root.persistSettings({
                                     keyboardShape: shape
                                 });
        }
        onRefreshRequested: root.refresh()
    }
}
