pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Item {
    id: root

    property string value: ""
    property string text: value
    property color foreground: Commons.Color.popups.text
    property color background: Commons.Color.popups.background
    property color popupBorder: Commons.Color.popups.border
    property color accent: Commons.Color.accent
    property string fontFamily: Style.font.family
    property real triggerPadding: Style.space(20)
    property Component triggerDecoration: null
    property bool hasCursor: false
    property alias contentItem: popup.contentItem
    readonly property bool popupOpen: popup.opened
    readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder, Commons.Color.popups.border, Style.normalBorderWidth)

    signal changed(string value)
    signal popupOpened()
    signal triggerDownPressed()

    function open() { popup.open(); }
    function close() { popup.close(); }

    implicitWidth: Style.spacing.dropdownWidth
    implicitHeight: trigger.implicitHeight

    TextMetrics {
        id: triggerMetrics
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        text: root.text
        elide: Qt.ElideRight
        elideWidth: Math.max(0, trigger.width - trigger.leftPadding - trigger.rightPadding)
    }

    Button {
        id: trigger
        width: parent.width
        text: triggerMetrics.elidedText
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.body
        leftAlign: true
        rightPadding: horizontalPadding + root.triggerPadding
        bordered: true
        hasCursor: root.hasCursor
        focusable: true
        onClicked: popup.opened ? popup.close() : popup.open()
        Keys.onDownPressed: root.triggerDownPressed()

        Loader {
            anchors.right: chevron.left
            anchors.rightMargin: Style.space(8)
            anchors.verticalCenter: parent.verticalCenter
            width: (item as Item)?.implicitWidth ?? 0
            height: (item as Item)?.implicitHeight ?? 0
            sourceComponent: root.triggerDecoration
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
        // Keep trigger presses out of automatic outside-click dismissal.
        closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutsideParent
        onOpened: root.popupOpened()

        background: BorderSurface {
            color: root.background
            borderSpec: root.popupBorderSpec
            radius: Style.cornerRadius
        }
    }
}
