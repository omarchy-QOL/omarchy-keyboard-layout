pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui
import "../lib/PulseColor.js" as PulseColor

Column {
    id: root

    required property color foreground
    required property color urgent
    required property string fontFamily
    required property string pulseColor
    required property bool animationEnabled
    required property bool showSingleLayout
    required property bool perWindowLayoutsActive
    required property bool trackerSupportKnown
    required property bool trackerSupported
    required property string shortcutLabel
    readonly property bool keyboardInputActive: colorDropdown.popupOpen || (customColorEditorVisible && customColorField.activeFocus)
    readonly property int compactToggleHeight: Math.round(Style.font.caption * 1.2)
    property bool customColorEditorVisible: false

    signal pulseColorSelected(string value)
    signal animationRequested(bool enabled)
    signal singleLayoutRequested(bool enabled)
    signal perWindowLayoutsRequested(bool enabled)
    signal shortcutEditRequested()
    signal backRequested()
    signal closeRequested()
    signal focusRequested()

    spacing: Style.space(8)

    function beginEditing() {
        customColorField.text = root.pulseColor;
        root.customColorEditorVisible = PulseColor.presetForColor(root.pulseColor) === "custom";
    }

    function endEditing() {
        root.customColorEditorVisible = false;
    }

    function selectPresetColor(value) {
        root.customColorEditorVisible = false;
        root.pulseColorSelected(value);
        customColorField.text = root.pulseColor;
        root.focusRequested();
    }

    function openCustomColorEditor() {
        root.customColorEditorVisible = true;
        customColorField.text = root.pulseColor;
        Qt.callLater(function () {
            customColorField.selectAll();
            customColorField.forceActiveFocus();
        });
    }

    function applyPulseColor(value) {
        if (!PulseColor.isPulseColor(value))
            return;
        root.pulseColorSelected(value);
        customColorField.text = root.pulseColor;
        root.closeRequested();
    }

    Item {
        width: parent.width
        implicitHeight: Math.max(pulseColorHeader.implicitHeight, animationToggleRow.implicitHeight)

        PanelSectionHeader {
            id: pulseColorHeader
            text: "Pulse color"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            anchors.left: pulseColorHeader.parent.left
            anchors.verticalCenter: pulseColorHeader.parent.verticalCenter
        }

        Row {
            id: animationToggleRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: Math.round(pulseColorHeader.topPadding / 2)
            spacing: Style.space(5)

            Text {
                id: animationToggleLabel
                text: "Animation"
                color: root.animationEnabled ? root.foreground : Qt.darker(root.foreground, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.verticalCenter: animationToggleLabel.parent.verticalCenter
            }

            ToggleSwitch {
                id: animationToggle
                anchors.verticalCenter: animationToggleLabel.verticalCenter
                trackHeight: root.compactToggleHeight
                cursorPad: Style.space(3)
                checked: root.animationEnabled
                foreground: root.foreground
                onToggled: root.animationRequested(!animationToggle.checked)

                PanelToolTip {
                    visible: animationToggle.containsMouse
                    text: root.animationEnabled ? "Disable the layout-change animation" : "Enable the layout-change animation"
                    fontFamily: root.fontFamily
                }
            }
        }
    }

    ColorDropdown {
        id: colorDropdown
        width: parent.width
        enabled: root.animationEnabled
        opacity: root.animationEnabled ? 1 : 0.35
        value: root.customColorEditorVisible ? "custom" : PulseColor.presetForColor(root.pulseColor)
        customColor: PulseColor.isPulseColor(customColorField.text) ? PulseColor.normalizedPulseColor(customColorField.text) : root.pulseColor
        presets: PulseColor.colorPresets
        foreground: root.foreground
        fontFamily: root.fontFamily
        onChanged: function (value) {
            if (value === "custom")
                root.openCustomColorEditor();
            else
                root.selectPresetColor(value);
        }
    }

    Row {
        id: customColorRow
        visible: root.customColorEditorVisible
        width: parent.width
        spacing: Style.space(6)
        enabled: root.animationEnabled
        opacity: root.animationEnabled ? 1 : 0.35

        TextField {
            id: customColorField
            width: customColorRow.width - applyColorButton.width - customColorRow.spacing
            placeholderText: "#RRGGBB"
            foreground: root.foreground
            font.family: root.fontFamily
            validator: RegularExpressionValidator {
                regularExpression: /^#[0-9a-fA-F]{6}$/
            }
            onAccepted: root.applyPulseColor(customColorField.text)
            Keys.onEscapePressed: root.backRequested()
        }

        Button {
            id: applyColorButton
            text: "Apply"
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            bordered: true
            focusable: true
            enabled: customColorField.acceptableInput
            onClicked: root.applyPulseColor(customColorField.text)
        }
    }

    Text {
        visible: root.animationEnabled && root.customColorEditorVisible && customColorField.text !== "" && !customColorField.acceptableInput
        width: parent.width
        text: "Use #RRGGBB, for example #2aa198."
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
    }

    Text {
        visible: !root.animationEnabled
        width: parent.width
        text: "Please enable animations first."
        color: root.urgent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
    }

    PanelSeparator {
        foreground: root.foreground
    }

    PanelSectionHeader {
        text: "Keyboard layouts & shortcut"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
    }

    Item {
        width: parent.width
        implicitHeight: Math.max(shortcutText.implicitHeight, shortcutControl.implicitHeight)

        Text {
            id: shortcutText
            anchors.left: parent.left
            anchors.right: shortcutControl.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            text: root.shortcutLabel
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
        }

        Item {
            id: shortcutControl
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: singleLayoutToggle.implicitWidth
            implicitHeight: editShortcutButton.implicitHeight

            PanelActionButton {
                id: editShortcutButton
                anchors.centerIn: parent
                tooltipText: "Edit layouts and keybinding shortcut"
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                size: singleLayoutToggle.trackWidth
                bordered: true
                focusable: true
                onClicked: root.shortcutEditRequested()

                Text {
                    id: shortcutGear
                    readonly property rect glyphBounds: shortcutGearMetrics.tightBoundingRect
                    x: (editShortcutButton.width - glyphBounds.width) / 2 - glyphBounds.x
                    y: (editShortcutButton.height - glyphBounds.height) / 2 - baselineOffset - glyphBounds.y
                    text: "󰒓"
                    textFormat: Text.PlainText
                    color: editShortcutButton.foreground
                    font.family: editShortcutButton.fontFamily
                    font.pixelSize: editShortcutButton.fontSize

                    TextMetrics {
                        id: shortcutGearMetrics
                        font: shortcutGear.font
                        text: shortcutGear.text
                    }
                }
            }
        }
    }

    Item {
        width: parent.width
        implicitHeight: Math.max(singleLayoutLabel.implicitHeight, singleLayoutToggle.implicitHeight)

        Text {
            id: singleLayoutLabel
            anchors.left: singleLayoutLabel.parent.left
            anchors.right: singleLayoutToggle.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: singleLayoutLabel.parent.verticalCenter
            text: "Show with one layout"
            elide: Text.ElideRight
            color: root.showSingleLayout ? root.foreground : Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
        }

        ToggleSwitch {
            id: singleLayoutToggle
            anchors.right: singleLayoutToggle.parent.right
            anchors.verticalCenter: singleLayoutLabel.verticalCenter
            trackHeight: root.compactToggleHeight
            cursorPad: Style.space(3)
            checked: root.showSingleLayout
            foreground: root.foreground
            onToggled: root.singleLayoutRequested(!singleLayoutToggle.checked)

            PanelToolTip {
                visible: singleLayoutToggle.containsMouse
                text: root.showSingleLayout ? "Hide when only one layout is configured" : "Keep visible when only one layout is configured"
                fontFamily: root.fontFamily
            }
        }
    }

    Item {
        width: parent.width
        implicitHeight: Math.max(perWindowLabel.implicitHeight, perWindowToggle.implicitHeight)

        Text {
            id: perWindowLabel
            anchors.left: perWindowLabel.parent.left
            anchors.right: perWindowToggle.left
            anchors.rightMargin: Style.space(6)
            anchors.verticalCenter: perWindowLabel.parent.verticalCenter
            text: "Activate per-window layouts"
            elide: Text.ElideRight
            color: root.perWindowLayoutsActive ? root.foreground : Qt.darker(root.foreground, 2.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
        }

        ToggleSwitch {
            id: perWindowToggle
            anchors.right: perWindowToggle.parent.right
            anchors.verticalCenter: perWindowLabel.verticalCenter
            trackHeight: root.compactToggleHeight
            cursorPad: Style.space(3)
            enabled: root.trackerSupportKnown && root.trackerSupported
            checked: root.perWindowLayoutsActive
            foreground: root.foreground
            onToggled: root.perWindowLayoutsRequested(!perWindowToggle.checked)

            PanelToolTip {
                visible: perWindowToggle.containsMouse
                text: root.trackerSupported ? (root.perWindowLayoutsActive ? "Use one layout across all windows" : "Remember the layout used in each window") : "Per-window layouts require x86-64"
                fontFamily: root.fontFamily
            }
        }
    }

    PanelSeparator {
        foreground: root.foreground
    }

    Button {
        id: backButton
        width: implicitWidth + backChevron.implicitWidth + Style.space(4)
        text: "Back"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        leftAlign: true
        bordered: true
        focusable: true
        onClicked: root.backRequested()

        Text {
            id: backChevron
            anchors.right: parent.right
            anchors.rightMargin: backButton.horizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: backButton.foreground
            font.family: backButton.fontFamily
            font.pixelSize: backButton.fontSize
        }
    }
}
