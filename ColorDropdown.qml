pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Ui

Item {
    id: root

    property string value: "custom"
    property string customColor: "#2aa198"
    property var presets: []
    property color foreground: Color.popups.text
    property color background: Color.popups.background
    property color popupBorder: Color.popups.border
    property color accent: Color.accent
    property string fontFamily: Style.font.family
    readonly property bool popupOpen: popup.opened
    readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder,
                                                                     Color.popups.border, Style.normalBorderWidth)

    signal changed(string value)

    function currentLabel() {
        if (value === "custom")
            return "Custom";
        for (var index = 0; index < presets.length; index++) {
            if (String(presets[index].value) === value)
                return String(presets[index].label);
        }
        return "Custom";
    }

    function currentColor() {
        return value === "custom" ? customColor : value;
    }

    function select(nextValue) {
        root.changed(nextValue);
        popup.close();
    }

    implicitWidth: Style.spacing.dropdownWidth
    implicitHeight: trigger.implicitHeight

    Button {
        id: trigger
        width: parent.width
        text: root.currentLabel()
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.body
        leftAlign: true
        rightPadding: horizontalPadding + Style.space(38)
        bordered: true
        focusable: true
        onClicked: popup.opened ? popup.close() : popup.open()

        Rectangle {
            width: Style.space(12)
            height: width
            radius: width / 2
            anchors.right: chevron.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            color: root.currentColor()
            border.width: 1
            border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
        }

        Text {
            id: chevron
            anchors.right: parent.right
            anchors.rightMargin: trigger.horizontalPadding
            anchors.verticalCenter: parent.verticalCenter
            text: "󰅀"
            color: Qt.darker(root.foreground, 1.2)
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
        }
    }

    Controls.Popup {
        id: popup
        x: 0
        y: trigger.height + Style.spacing.xxs
        width: trigger.width
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
        focus: true
        closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
        onOpened: customButton.forceActiveFocus()

        background: BorderSurface {
            color: root.background
            borderSpec: root.popupBorderSpec
            radius: Style.cornerRadius
        }

        contentItem: Column {
            spacing: Style.spacing.labelGap

            Button {
                id: customButton
                width: parent.width
                text: "Custom"
                foreground: root.foreground
                accent: root.accent
                fontFamily: root.fontFamily
                fontSize: Style.font.body
                leftAlign: true
                rightPadding: horizontalPadding + Style.space(20)
                selected: root.value === "custom"
                focusable: true
                onClicked: root.select("custom")

                ColorSwatch {
                    colorValue: root.customColor
                    foreground: root.foreground
                    horizontalPadding: parent.horizontalPadding
                }
            }

            PanelSeparator {
                foreground: root.foreground
            }

            Repeater {
                model: root.presets

                Button {
                    required property var modelData
                    width: parent.width
                    text: String(modelData.label)
                    foreground: root.foreground
                    accent: root.accent
                    fontFamily: root.fontFamily
                    fontSize: Style.font.body
                    leftAlign: true
                    rightPadding: horizontalPadding + Style.space(20)
                    selected: root.value === String(modelData.value)
                    focusable: true
                    onClicked: root.select(String(modelData.value))

                    ColorSwatch {
                        colorValue: String(parent.modelData.value)
                        foreground: root.foreground
                        horizontalPadding: parent.horizontalPadding
                    }
                }
            }
        }
    }

    component ColorSwatch: Rectangle {
        required property color colorValue
        required property color foreground
        required property real horizontalPadding
        width: Style.space(12)
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.rightMargin: horizontalPadding
        anchors.verticalCenter: parent.verticalCenter
        color: colorValue
        border.width: 1
        border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.35)
    }
}
