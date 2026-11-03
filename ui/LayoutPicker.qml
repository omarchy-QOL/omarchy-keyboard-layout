pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

Column {
    id: root

    required property var layouts
    required property int selectedIndex
    required property color foreground
    required property string fontFamily
    property int cursorPosition: 0
    property bool cursorActive: false
    readonly property int itemCount: layouts.length + 3
    spacing: Style.space(6)

    signal layoutChosen(int index)
    signal settingsRequested
    signal viewerRequested
    signal emojiRequested

    function resetCursor() {
        root.cursorPosition = Math.max(0, Math.min(root.selectedIndex, root.itemCount - 1));
        root.cursorActive = false;
    }

    function moveCursor(delta) {
        if (!root.cursorActive)
            root.cursorActive = true;
        else
            root.cursorPosition = (root.cursorPosition + delta + root.itemCount) % root.itemCount;
    }

    function activateCursor() {
        if (!root.cursorActive)
            return;
        if (root.cursorPosition < root.layouts.length)
            root.layoutChosen(root.cursorPosition);
        else if (root.cursorPosition === root.layouts.length)
            root.emojiRequested();
        else if (root.cursorPosition === root.layouts.length + 1)
            root.viewerRequested();
        else
            root.settingsRequested();
    }

    function hoverItem(index, hovered) {
        if (!hovered)
            return;
        root.cursorActive = true;
        root.cursorPosition = index;
    }

    onSelectedIndexChanged: if (!root.cursorActive)
                                root.resetCursor()
    onItemCountChanged: if (root.cursorPosition >= root.itemCount)
                            root.resetCursor()

    Repeater {
        model: root.layouts

        Button {
            required property var modelData
            required property int index
            width: root.width
            text: modelData
            clip: true
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.bodySmall
            leftAlign: true
            bordered: true
            selected: root.selectedIndex === index
            hasCursor: root.cursorActive && root.cursorPosition === index
            onClicked: root.layoutChosen(index)
            onHovered: function (hovered) {
                root.hoverItem(index, hovered);
            }
        }
    }

    PanelSeparator {
        foreground: root.foreground
    }

    Row {
        width: root.width
        spacing: Style.space(6)

        Repeater {
            model: ["  Emoji", "  View"]

            Button {
                required property string modelData
                required property int index
                width: (root.width - Style.space(6)) / 2
                text: modelData
                foreground: root.foreground
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                leftAlign: true
                bordered: true
                hasCursor: root.cursorActive && root.cursorPosition === root.layouts.length + index
                onClicked: index === 0 ? root.emojiRequested() : root.viewerRequested()
                onHovered: function (hovered) {
                    root.hoverItem(root.layouts.length + index, hovered);
                }
            }
        }
    }

    Button {
        id: settingsButton
        width: root.width
        text: "Settings"
        foreground: root.foreground
        fontFamily: root.fontFamily
        fontSize: Style.font.bodySmall
        leftAlign: true
        bordered: true
        hasCursor: root.cursorActive && root.cursorPosition === root.layouts.length + 2
        onClicked: root.settingsRequested()
        onHovered: function (hovered) {
            root.hoverItem(root.layouts.length + 2, hovered);
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
