pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Commons

Item {
    id: root

    property real notchWidth: 0
    property real notchY: 0
    property color fillColor: "transparent"
    property color edgeColor: "transparent"
    property real edgeWidth: 1
    readonly property real cornerRadius: Math.max(3, Math.min(Style.space(6), width * 0.1))
    readonly property real edgeInset: edgeWidth / 2

    Behavior on fillColor {
        ColorAnimation {
            duration: 70
        }
    }
    Behavior on edgeColor {
        ColorAnimation {
            duration: 70
        }
    }

    Rectangle {
        visible: root.notchWidth === 0
        anchors.fill: parent
        radius: root.cornerRadius
        color: root.fillColor
        border.width: root.edgeWidth
        border.color: root.edgeColor
    }

    Shape {
        visible: root.notchWidth > 0
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: root.fillColor
            strokeColor: root.edgeColor
            strokeWidth: root.edgeWidth
            startX: root.cornerRadius
            startY: root.edgeInset
            PathLine {
                x: root.width - root.cornerRadius
                y: root.edgeInset
            }
            PathArc {
                x: root.width - root.edgeInset
                y: root.cornerRadius
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
            }
            PathLine {
                x: root.width - root.edgeInset
                y: root.height - root.cornerRadius
            }
            PathArc {
                x: root.width - root.cornerRadius
                y: root.height - root.edgeInset
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
            }
            PathLine {
                x: root.notchWidth + root.cornerRadius
                y: root.height - root.edgeInset
            }
            PathArc {
                x: root.notchWidth + root.edgeInset
                y: root.height - root.cornerRadius
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
            }
            PathLine {
                x: root.notchWidth + root.edgeInset
                y: root.notchY - root.edgeInset
            }
            PathLine {
                x: root.cornerRadius
                y: root.notchY - root.edgeInset
            }
            PathArc {
                x: root.edgeInset
                y: root.notchY - root.cornerRadius
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
            }
            PathLine {
                x: root.edgeInset
                y: root.cornerRadius
            }
            PathArc {
                x: root.cornerRadius
                y: root.edgeInset
                radiusX: root.cornerRadius
                radiusY: root.cornerRadius
            }
        }
    }
}
