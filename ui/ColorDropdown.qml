pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

DropdownBase {
    id: root

    value: "custom"
    property string customColor: "#2aa198"
    property var presets: []

    function currentLabel() {
        if (value === "custom")
            return "Custom";
        for (let index = 0; index < presets.length; index++) {
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
        root.close();
    }

    text: root.currentLabel()
    triggerPadding: Style.space(38)
    onPopupOpened: customButton.forceActiveFocus()

    triggerDecoration: Rectangle {
        implicitWidth: Style.space(12)
        implicitHeight: implicitWidth
        radius: width / 2
        color: root.currentColor()
        border.width: 1
        border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
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
