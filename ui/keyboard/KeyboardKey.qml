pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Commons as Commons

Item {
    id: root

    required property var keyGeometry
    required property real keyPitch
    required property string fontFamily
    property string label: ""
    property string alternateLabel: ""
    property bool available: true
    property bool latched: false
    property bool locked: false
    property bool pendingAccent: false
    property bool deadKey: false
    readonly property bool hovered: root.anyArea("containsMouse")
    readonly property bool pressed: root.anyArea("pressed")
    readonly property color foreground: Commons.Color.popups.text

    signal keyPressed
    signal keyReleased
    signal keyClicked
    signal keyHeld(var event)

    function anyArea(propertyName) {
        for (let index = 0; index < hitAreas.count; index++) {
            const area = hitAreas.itemAt(index);
            if (area && area[propertyName])
                return true;
        }
        return false;
    }

    x: keyGeometry.x
    y: keyGeometry.y
    width: keyGeometry.width
    height: keyGeometry.height

    KeyFace {
        anchors.fill: parent
        notchWidth: root.keyGeometry.notchWidth
        notchY: root.keyGeometry.notchY
        fillColor: root.locked ? Util.alpha(Commons.Color.accent, 0.38) : Util.alpha(root.foreground, !root.available
                                                                                     ? 0.04 : root.pressed ? 0.34 :
                                                                                                             root.hovered
                                                                                                             ? 0.2 : 0.1)
        edgeColor: root.latched || root.pendingAccent || root.deadKey ? Commons.Color.accent : Util.alpha(root.foreground,
                                                                                                          root.hovered
                                                                                                          || root.pressed
                                                                                                          ? 0.9 : root.available
                                                                                                            ? 0.32 : 0.14)
        edgeWidth: root.hovered || root.pressed || root.latched || root.pendingAccent ? 1.5 : 1
    }

    Item {
        id: legends
        x: root.keyGeometry.notchWidth
        width: parent.width - x
        height: parent.height
        clip: true
        readonly property real padding: Math.max(1, Math.round(root.keyPitch * 0.05))
        readonly property real preferredPrimaryHeight: Math.ceil(primaryMetrics.height) + 1
        readonly property real minimumSecondaryHeight: Math.ceil(secondaryMinimumMetrics.height) + 1

        TextMetrics {
            id: primaryMetrics
            font: primaryLegend.font
            text: root.label
        }

        TextMetrics {
            id: secondaryMinimumMetrics
            font: Qt.font({family: root.fontFamily, pixelSize: 6})
            text: root.alternateLabel
        }

        TextMetrics {
            id: primaryMinimumMetrics
            font: secondaryMinimumMetrics.font
            text: root.label
        }

        Text {
            id: primaryLegend
            objectName: "primaryLegend"
            x: legends.padding
            y: secondaryLegend.visible ? secondaryLegend.y + secondaryLegend.height + 1 : legends.padding
            width: Math.max(0, parent.width - legends.padding * 2)
            height: Math.max(0, parent.height - y - legends.padding)
            // Qt cannot elide a single ligature wider than the entire key
            text: root.label.length <= 2 && primaryMinimumMetrics.width > width ? "…" : root.label
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            fontSizeMode: Text.Fit
            minimumPixelSize: 6
            clip: true
            font.family: root.fontFamily
            font.pixelSize: Math.max(8, Math.round(root.keyPitch * (root.label.length > 2 ? 0.24 : 0.34)))
            color: Util.alpha(root.foreground, root.available ? 1 : 0.3)
        }

        Text {
            id: secondaryLegend
            objectName: "secondaryLegend"
            // give tall fallback glyphs the full key when two legends cannot fit
            visible: root.alternateLabel !== "" && legends.height >= legends.preferredPrimaryHeight
                + legends.minimumSecondaryHeight + legends.padding * 2 + 1
            x: legends.padding
            y: legends.padding
            width: Math.max(0, parent.width - legends.padding * 2)
            height: Math.min(Math.max(legends.minimumSecondaryHeight, Math.ceil(secondaryMetrics.height) + 1),
                Math.max(0, parent.height - legends.preferredPrimaryHeight - legends.padding * 2 - 1))
            text: root.alternateLabel.length <= 2 && secondaryMinimumMetrics.width > width ? "…" : root.alternateLabel
            textFormat: Text.PlainText
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            fontSizeMode: Text.Fit
            minimumPixelSize: 6
            clip: true
            font.family: root.fontFamily
            font.pixelSize: Math.max(8, Math.round(root.keyPitch * 0.22))
            color: Util.alpha(root.foreground, 0.65)

            TextMetrics {
                id: secondaryMetrics
                font: secondaryLegend.font
                text: secondaryLegend.text
            }
        }
    }

    Repeater {
        id: hitAreas
        model: root.keyGeometry.hitRectangles

        MouseArea {
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: modelData.height
            enabled: root.available
            hoverEnabled: true
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            pressAndHoldInterval: 450
            onPressedChanged: pressed ? root.keyPressed() : root.keyReleased()
            onCanceled: root.keyReleased()
            onClicked: root.keyClicked()
            onDoubleClicked: root.keyClicked()
            onPressAndHold: function (event) {
                root.keyHeld(event);
            }
        }
    }

    Component.onDestruction: if (root.pressed)
                                 root.keyReleased()
}
