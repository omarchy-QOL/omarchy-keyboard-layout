pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BorderSurface {
    id: root

    required property string fontFamily
    property var choices: []
    readonly property real choiceSize: Style.space(32)
    readonly property real choiceGap: Style.space(3)
    signal chosen(string text)

    visible: choices.length > 0
    width: choices.length * choiceSize + Math.max(0, choices.length - 1) * choiceGap + contentLeftInset
           + contentRightInset
    height: choiceSize + contentTopInset + contentBottomInset
    padding: Style.space(4)
    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
    radius: Style.cornerRadius

    MouseArea {
        anchors.fill: parent
    }

    Row {
        id: choiceRow
        x: root.contentLeftInset
        y: root.contentTopInset
        spacing: root.choiceGap

        Repeater {
            model: root.choices

            Button {
                required property string modelData
                width: root.choiceSize
                height: width
                text: modelData
                foreground: Commons.Color.popups.text
                fontFamily: root.fontFamily
                fontSize: Style.font.title
                onClicked: root.chosen(modelData)
            }
        }
    }
}
