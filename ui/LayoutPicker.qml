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
    readonly property int itemCount: 4
    readonly property bool keyboardInputActive: layoutDropdown.popupOpen
    spacing: Style.space(6)

    signal layoutChosen(int index)
    signal settingsRequested
    signal viewerRequested
    signal emojiRequested
    signal focusRequested

    function resetCursor() {
        layoutDropdown.close();
        root.cursorPosition = 0;
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
        if (root.cursorPosition === 0)
            layoutDropdown.open();
        else if (root.cursorPosition === 1)
            root.emojiRequested();
        else if (root.cursorPosition === 2)
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

    LayoutDropdown {
        id: layoutDropdown
        objectName: "layoutSelector"
        width: root.width
        options: root.layouts
        selectedIndex: root.selectedIndex
        value: root.layouts[root.selectedIndex] || ""
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.layouts.length > 0
        hasCursor: root.cursorActive && root.cursorPosition === 0
        onIndexSelected: function (index) { root.layoutChosen(index); }
        onPopupOpenChanged: if (!popupOpen) root.focusRequested()
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
                hasCursor: root.cursorActive && root.cursorPosition === 1 + index
                onClicked: index === 0 ? root.emojiRequested() : root.viewerRequested()
                onHovered: function (hovered) {
                    root.hoverItem(1 + index, hovered);
                }
            }
        }
    }

    PanelSeparator {
        foreground: root.foreground
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
        hasCursor: root.cursorActive && root.cursorPosition === 3
        onClicked: root.settingsRequested()
        onHovered: function (hovered) {
            root.hoverItem(3, hovered);
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
