pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui

DropdownBase {
    id: root

    property var options: []
    property int selectedIndex: -1
    signal indexSelected(int index)

    onTriggerDownPressed: root.open()
    onPopupOpened: {
        optionList.currentIndex = Math.max(0, root.selectedIndex >= 0 ? root.selectedIndex : root.options.indexOf(root.value));
        optionList.forceActiveFocus();
    }

    function select(index) {
        if (index < 0 || index >= root.options.length)
            return;
        root.changed(String(root.options[index]));
        root.indexSelected(index);
        root.close();
    }

    contentItem: ListView {
        id: optionList
        implicitHeight: Math.min(contentHeight, Style.spacing.popupRowHeight * 8 + Style.spacing.labelGap * 7)
        spacing: Style.spacing.labelGap
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.options
        currentIndex: -1
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Escape)
                root.close();
            else if (event.key === Qt.Key_Down || event.text === "j")
                currentIndex = Math.min(count - 1, currentIndex + 1);
            else if (event.key === Qt.Key_Up || event.text === "k")
                currentIndex = Math.max(0, currentIndex - 1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                root.select(currentIndex);
            else
                return;
            event.accepted = true;
        }

        delegate: Button {
            id: optionButton
            required property string modelData
            required property int index
            width: optionList.width
            height: Style.spacing.popupRowHeight
            text: optionMetrics.elidedText
            foreground: root.foreground
            fontFamily: root.fontFamily
            fontSize: Style.font.body
            leftAlign: true
            focusable: true
            selected: root.selectedIndex >= 0 ? root.selectedIndex === optionButton.index : root.value === optionButton.modelData
            hasCursor: optionList.currentIndex === optionButton.index
            onClicked: root.select(optionButton.index)
            onHovered: function (hovered) {
                if (hovered)
                    optionList.currentIndex = optionButton.index;
            }

            TextMetrics {
                id: optionMetrics
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                text: optionButton.modelData
                elide: Qt.ElideRight
                elideWidth: Math.max(0, optionButton.width - optionButton.leftPadding - optionButton.rightPadding)
            }
        }
    }
}
