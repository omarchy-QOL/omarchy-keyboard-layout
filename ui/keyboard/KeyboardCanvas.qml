pragma ComponentBehavior: Bound

import QtQuick
import "../../lib/keyboard/KeyboardGeometry.js" as Geometry
import "../../lib/keyboard/KeyboardInteraction.js" as Interaction

Item {
    id: root

    required property var keymap
    required property var interactionState
    required property string shapeName
    required property string fontFamily
    readonly property real keyGap: Math.max(3, Math.round(width / Geometry.rowWidthUnits * 0.08))
    readonly property real keyPitch: (width + keyGap) / Geometry.rowWidthUnits
    readonly property var placement: Geometry.placeKeys(root.shapeName, root.keyPitch, root.keyGap)
    implicitHeight: placement.height

    signal keyPressed(string keyId)
    signal keyReleased(string keyId)
    signal keyClicked(string keyId)
    signal keyHeld(string keyId, Item keyItem, var event)

    Repeater {
        model: root.placement.keys

        KeyboardKey {
            id: key
            required property var modelData
            readonly property string keyId: modelData.keyId
            readonly property var entry: Interaction.displayEntry(root.keymap, keyId, root.interactionState)
            keyGeometry: modelData
            keyPitch: root.keyPitch
            fontFamily: root.fontFamily
            label: Interaction.labelFor(root.keymap, keyId, root.interactionState)
            alternateLabel: Interaction.alternateLabel(root.keymap, keyId, root.interactionState)
            available: entry !== null
            latched: Interaction.latchFor(root.keymap, keyId, root.interactionState) > 0
            locked: Interaction.latchFor(root.keymap, keyId, root.interactionState) === Interaction.locked
            pendingAccent: root.interactionState.pendingDeadKeyId === keyId
            deadKey: entry ? entry.dead !== "" : false
            onKeyPressed: root.keyPressed(keyId)
            onKeyReleased: root.keyReleased(keyId)
            onKeyClicked: root.keyClicked(keyId)
            onKeyHeld: function (event) {
                root.keyHeld(keyId, key, event);
            }
        }
    }
}
