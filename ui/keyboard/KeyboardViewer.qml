pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../../lib/keyboard/KeyboardGeometry.js" as Geometry
import "../../lib/keyboard/KeyboardInteraction.js" as Interaction

Item {
    id: root

    required property var keyboard
    required property string helperPath
    required property string fontFamily
    property string keyboardShape: "auto"
    property int configurationRevision: 0
    property bool nativeSupported: true
    property bool initialized: false
    property bool opened: false
    property var targetScreen: null
    property real chosenWidth: 0
    property var savedPositions: ({})
    property var interactionState: Interaction.initialState(false)
    property string repeatingKey: ""
    property var repeatingActions: []
    readonly property bool physicalCapsLock: root.keyboard ? root.keyboard.capsLock === true : false
    readonly property var keymap: keymapReader.description
    readonly property string activeLayoutCode: root.keyboard
        ? String(root.keyboard.layout || "").split(",")[Number(root.keyboard.active_layout_index || 0)] || "" : ""
    readonly property string shapeName: Geometry.shapeFor(root.keyboardShape, root.activeLayoutCode,
                                                          root.keyboard ? root.keyboard.model : "")
    readonly property real screenWidth: root.targetScreen ? root.targetScreen.width : panel.width
    readonly property real screenHeight: root.targetScreen ? root.targetScreen.height : panel.height
    readonly property real screenMargin: Style.space(24)
    readonly property real maximumWidth: Math.max(200, root.screenWidth - root.screenMargin * 2)
    readonly property real minimumWidth: Math.min(Style.space(480), root.maximumWidth)
    readonly property real viewerWidth: Math.max(root.minimumWidth, Math.min(root.maximumWidth, root.chosenWidth
                                                                             || Style.space(760)))
    signal shapeSelected(string shape)
    signal refreshRequested
    Component.onCompleted: root.initialized = true

    function focusedScreen() {
        const monitorName = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        return Quickshell.screens.find(function (screen) {
            return screen.name === monitorName;
        }) || Quickshell.screens[0] || null;
    }

    function open(screen) {
        root.targetScreen = screen || root.focusedScreen();
        root.interactionState = Interaction.initialState(root.physicalCapsLock);
        root.opened = true;
        Qt.callLater(root.placeCard);
    }

    function close() {
        root.stopRepeat();
        accentMenu.choices = [];
        root.opened = false;
    }

    function toggle(screen) {
        if (root.opened)
            root.close();
        else
            root.open(screen);
    }

    function clampX(position) {
        return Math.max(0, Math.min(position, root.screenWidth - card.width));
    }
    function clampY(position) {
        return Math.max(0, Math.min(position, root.screenHeight - card.height));
    }

    function placeCard() {
        const position = root.savedPositions[root.targetScreen ? root.targetScreen.name : ""];
        card.x = root.clampX(position ? position.x : (root.screenWidth - card.width) / 2);
        card.y = root.clampY(position ? position.y : (root.screenHeight - card.height) / 2);
    }

    function rememberPosition() {
        const positions = Object.assign({}, root.savedPositions);
        positions[root.targetScreen ? root.targetScreen.name : ""] = {
            x: card.x,
            y: card.y
        };
        root.savedPositions = positions;
    }

    function performKey(keyId) {
        if (!keymapReader.ready)
            return [];
        const action = Interaction.pressKey(root.keymap, root.interactionState, keyId, Date.now());
        root.interactionState = action.state;
        typing.enqueue(action.commands);
        return action.commands;
    }

    function pressKey(keyId) {
        accentMenu.choices = [];
        if (!Interaction.repeats(root.keymap, keyId))
            return;
        root.repeatingActions = root.performKey(keyId);
        root.repeatingKey = keyId;
        repeatTimer.interval = 400;
        repeatTimer.restart();
    }

    function releaseKey(keyId) {
        if (root.repeatingKey === keyId)
            root.stopRepeat();
    }

    function stopRepeat() {
        repeatTimer.stop();
        root.repeatingKey = "";
        root.repeatingActions = [];
    }

    function clickKey(keyId) {
        accentMenu.choices = [];
        if (!Interaction.repeats(root.keymap, keyId))
            root.performKey(keyId);
    }

    function holdKey(keyId, keyItem, event) {
        if (!keymapReader.ready || Interaction.repeats(root.keymap, keyId)) {
            event.accepted = false;
            return;
        }
        const choices = Interaction.accentChoices(root.keymap, keyId, root.interactionState);
        if (!choices.length) {
            event.accepted = false;
            return;
        }
        accentMenu.choices = choices;
        const point = keyItem.mapToItem(card, 0, 0);
        accentMenu.x = Math.max(card.contentLeftInset, Math.min(point.x + keyItem.width / 2 - accentMenu.width / 2, card.width
                                                                - card.contentRightInset - accentMenu.width));
        const above = point.y - accentMenu.height - Style.space(4);
        accentMenu.y = above >= card.contentTopInset ? above : point.y + keyItem.height + Style.space(4);
    }

    function selectAccent(text) {
        if (!keymapReader.ready)
            return;
        const result = Interaction.chooseAccent(root.interactionState, text);
        root.interactionState = result.state;
        typing.enqueue(result.commands);
        accentMenu.choices = [];
    }

    function selectModifier(name) {
        if (name === "capsLock")
            root.interactionState = Object.assign({}, root.interactionState, {
                                                      capsLock: !root.interactionState.capsLock
                                                  });
        else
            root.interactionState = Interaction.toggleModifier(root.interactionState, name, Date.now());
        accentMenu.choices = [];
    }

    onPhysicalCapsLockChanged: root.interactionState = Object.assign({}, root.interactionState, {
                                                                         capsLock: root.physicalCapsLock
                                                                     })
    onShapeNameChanged: {
        if (!root.initialized)
            return;
        root.stopRepeat();
        accentMenu.choices = [];
    }

    KeymapReader {
        id: keymapReader
        helperPath: root.helperPath
        keyboard: root.keyboard
        active: root.opened
        supported: root.nativeSupported
        configurationRevision: root.configurationRevision
        onSignatureChanged: {
            if (!root.initialized)
                return;
            root.interactionState = Interaction.initialState(root.physicalCapsLock);
            root.stopRepeat();
            accentMenu.choices = [];
        }
    }

    KeyboardTyping {
        id: typing
        active: root.opened && keymapReader.ready
        contextSignature: keymapReader.signature
    }

    Connections {
        target: Hyprland
        function onActiveToplevelChanged() {
            root.stopRepeat();
            typing.clearPending();
        }
    }

    Timer {
        id: repeatTimer
        repeat: true
        onTriggered: {
            interval = 50;
            if (root.repeatingActions.length && !typing.action && !typing.queue.length)
                typing.enqueue(root.repeatingActions);
        }
    }

    // the running shell supplies the platform window factory
    // qmllint disable uncreatable-type
    PanelWindow {
        // qmllint enable uncreatable-type
        id: panel
        visible: root.opened
        screen: root.targetScreen || null
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "omarchy-keyboard-viewer"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {
            item: card
        }

        Item {
            id: resizeProxy
            width: 1
            height: 1
        }

        BorderSurface {
            id: card
            width: root.viewerWidth
            height: content.implicitHeight + contentTopInset + contentBottomInset
            padding: Style.spacing.panelPadding
            radius: Style.cornerRadius
            color: Commons.Color.popups.background
            borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.normalBorderWidth)
            onWidthChanged: if (root.opened)
                                x = root.clampX(x)
            onHeightChanged: if (root.opened)
                                 y = root.clampY(y)

            MouseArea {
                anchors.fill: parent
                onClicked: accentMenu.choices = []
            }

            Column {
                id: content
                x: card.contentLeftInset
                y: card.contentTopInset
                width: card.width - card.contentLeftInset - card.contentRightInset
                spacing: Style.spacing.panelGap

                ViewerToolbar {
                    id: toolbar
                    width: parent.width
                    title: root.keymap ? root.keymap.layoutName : "Keyboard"
                    shape: root.keyboardShape
                    interactionState: root.interactionState
                    fontFamily: root.fontFamily
                    supportedModifiers: root.keymap ? root.keymap.modifiers : {}
                    ready: keymapReader.ready
                    onCloseRequested: root.close()
                    onShapeSelected: function (shape) {
                        root.shapeSelected(shape);
                    }
                    onModifierSelected: function (name) {
                        root.selectModifier(name);
                    }
                }

                KeyboardCanvas {
                    width: parent.width
                    height: implicitHeight
                    keymap: root.keymap
                    interactionState: root.interactionState
                    shapeName: root.shapeName
                    fontFamily: root.fontFamily
                    onKeyPressed: function (keyId) {
                        root.pressKey(keyId);
                    }
                    onKeyReleased: function (keyId) {
                        root.releaseKey(keyId);
                    }
                    onKeyClicked: function (keyId) {
                        root.clickKey(keyId);
                    }
                    onKeyHeld: function (keyId, keyItem, event) {
                        root.holdKey(keyId, keyItem, event);
                    }
                }

                Row {
                    width: parent.width
                    spacing: Style.space(6)

                    Text {
                        width: parent.width - (retryButton.visible ? retryButton.width + parent.spacing : 0)
                        text: keymapReader.errorText || typing.errorText || (!root.keyboard
                                                                             ? "No keyboard layout is available." :
                                                                               !keymapReader.ready
                                                                               ? "Loading keyboard layout…" :
                                                                                 "Click keys to type; double-click a modifier to lock it")
                        textFormat: Text.PlainText
                        color: keymapReader.errorText || typing.errorText ? Commons.Color.urgent : Qt.darker(
                                                                                Commons.Color.popups.text, 1.4)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }

                    Button {
                        id: retryButton
                        visible: keymapReader.errorText !== "" || !root.keyboard
                        text: "Retry"
                        foreground: Commons.Color.popups.text
                        fontFamily: root.fontFamily
                        fontSize: Style.font.bodySmall
                        bordered: true
                        onClicked: {
                            root.refreshRequested();
                            keymapReader.retry();
                        }
                    }
                }
            }

            MouseArea {
                id: dragArea
                x: 0
                y: 0
                width: card.width
                height: card.contentTopInset
                drag.target: card
                drag.threshold: 2
                drag.minimumX: 0
                drag.maximumX: Math.max(0, root.screenWidth - card.width)
                drag.minimumY: 0
                drag.maximumY: Math.max(0, root.screenHeight - card.height)
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                onReleased: root.rememberPosition()
            }

            MouseArea {
                id: resizeArea
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                width: Style.space(18)
                height: width
                hoverEnabled: true
                cursorShape: Qt.SizeFDiagCursor
                drag.target: resizeProxy
                drag.threshold: 0
                property real startWidth: 0
                onPressed: {
                    root.stopRepeat();
                    accentMenu.choices = [];
                    resizeProxy.x = 0;
                    startWidth = card.width;
                }
                onReleased: root.rememberPosition()

                Connections {
                    target: resizeProxy
                    function onXChanged() {
                        if (resizeArea.pressed)
                            root.chosenWidth = Math.max(root.minimumWidth, Math.min(root.screenWidth - card.x,
                                                                                    resizeArea.startWidth
                                                                                    + resizeProxy.x));
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: "◢"
                    color: Commons.Color.popups.text
                    opacity: resizeArea.containsMouse ? 0.8 : 0.35
                    font.pixelSize: Style.font.body
                }
            }

            AccentMenu {
                id: accentMenu
                z: 10
                fontFamily: root.fontFamily
                onChosen: function (text) {
                    root.selectAccent(text);
                }
            }
        }
    }
}
