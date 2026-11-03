pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import ".." as LocalUi

Row {
    id: root

    required property string title
    required property string shape
    required property var interactionState
    required property string fontFamily
    property var supportedModifiers: ({})
    property bool ready: false
    signal closeRequested
    signal shapeSelected(string shape)
    signal modifierSelected(string name)
    spacing: Style.space(6)

    Text {
        width: Math.max(0, root.width - controls.width - root.spacing)
        height: shapeSelector.implicitHeight
        text: root.title
        textFormat: Text.PlainText
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        color: Commons.Color.popups.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
    }

    Row {
        id: controls
        spacing: Style.space(4)

        Repeater {
            model: [
                {
                    label: "Shift",
                    name: "shift"
                },
                {
                    label: "Caps",
                    name: "capsLock"
                },
                {
                    label: "AltGr",
                    name: "altGr"
                }
            ]

            Button {
                required property var modelData
                height: shapeSelector.height
                text: modelData.label
                foreground: Commons.Color.popups.text
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                selected: !!root.interactionState[modelData.name]
                bordered: true
                enabled: root.ready && root.supportedModifiers[modelData.name] === true
                onClicked: root.modifierSelected(modelData.name)
            }
        }

        LocalUi.LayoutDropdown {
            id: shapeSelector
            width: Style.space(82)
            options: ["Auto", "ANSI", "ISO", "ABNT", "JIS"]
            value: root.shape === "auto" ? "Auto" : root.shape.toUpperCase()
            foreground: Commons.Color.popups.text
            fontFamily: root.fontFamily
            onChanged: function (value) {
                root.shapeSelected(value.toLowerCase());
            }
        }

        PanelActionButton {
            size: shapeSelector.height
            iconText: "×"
            tooltipText: "Close keyboard viewer"
            foreground: Commons.Color.popups.text
            fontFamily: root.fontFamily
            fontSize: Style.font.title
            bordered: true
            onClicked: root.closeRequested()
        }
    }
}
