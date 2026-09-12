import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui
import "lib/shortcuts" as Shortcuts

Panel {
  id: root
  moduleName: "io.github.ilyazar.keyboard-layout"

  readonly property string tealColor: "#2aa198"
  readonly property string purpleColor: "#a77bd8"
  readonly property string blueColor: "#3b82f6"
  readonly property string yellowColor: "#ebcb8b"
  readonly property var colorPresets: [
    { label: "Teal", value: tealColor },
    { label: "Purple", value: purpleColor },
    { label: "Blue", value: blueColor },
    { label: "Yellow", value: yellowColor }
  ]
  readonly property string keyboardConfigPath:
    Quickshell.env("HOME") + "/.config/hypr/input.lua"
  readonly property string pluginPath:
    Quickshell.env("HOME") + "/.config/omarchy/plugins/" + moduleName
  readonly property string settingsPath:
    pluginPath + "/.settings.json"
  readonly property string trackerPath:
    pluginPath + "/native/keyboard-layoutd"
  readonly property string pulseColor: normalizedPulseColor(
    savedSetting("pulseColor", tealColor))
  readonly property bool animationEnabled:
    savedSetting("animation", true) !== false
  readonly property bool showSingleLayout:
    savedSetting("showSingleLayout", false) === true
  readonly property bool perWindowLayouts:
    savedSetting("perWindowLayouts", false) === true
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  property bool settingsPage: false
  property bool customColorEditorVisible: false
  property int keyboardOptionsLine: 1

  property string keyboardName: ""
  property var keyboardNames: []
  property var deviceLayouts: []
  property var configuredLayouts: []
  property var layouts: []
  property int activeLayoutIndex: 0
  property int cursorIndex: 0
  property bool cursorActive: false
  property string layoutFull: ""
  property string layoutLabel: ""
  property bool multipleLayouts: true
  property real pulseOpacity: 1
  property real pulseScale: 1
  property int automaticRestoreLayout: -1
  property var savedSettings: ({})

  function savedSetting(name, fallback) {
    var value = root.savedSettings[name]
    return value === undefined || value === null ? fallback : value
  }

  function loadSettings(raw) {
    try {
      var value = JSON.parse(raw || "{}")
      root.savedSettings = value && typeof value === "object"
        && !Array.isArray(value) ? value : ({})
    } catch (error) {
      root.savedSettings = ({})
    }
  }

  function isPulseColor(value) {
    return /^#[0-9a-fA-F]{6}$/.test(String(value || "").trim())
  }

  function normalizedPulseColor(value) {
    var color = String(value || "").trim().toLowerCase()
    return isPulseColor(color) ? color : tealColor
  }

  function presetForColor(value) {
    var color = normalizedPulseColor(value)
    return color === tealColor || color === purpleColor || color === blueColor
      || color === yellowColor
      ? color
      : "custom"
  }

  function persistSettings(values) {
    var next = {}
    for (var existing in root.savedSettings)
      next[existing] = root.savedSettings[existing]
    for (var key in values) next[key] = values[key]

    root.savedSettings = next
    settingsFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  function setPulseColor(value) {
    if (!isPulseColor(value)) return
    var color = normalizedPulseColor(value)
    persistSettings({ pulseColor: color })
    customColorField.text = color
  }

  function applyPulseColor(value) {
    if (!isPulseColor(value)) return
    setPulseColor(value)
    root.close()
  }

  function resetPulse() {
    pulseAnimation.stop()
    root.pulseOpacity = 1
    root.pulseScale = 1
  }

  function setAnimationEnabled(enabled) {
    persistSettings({ animation: enabled })
    if (!enabled) resetPulse()
  }

  function setShowSingleLayout(enabled) {
    persistSettings({ showSingleLayout: enabled })
    if (!enabled && !root.multipleLayouts) root.close()
  }

  function setPerWindowLayouts(enabled) {
    persistSettings({ perWindowLayouts: enabled })
    syncLayoutTracker()
  }

  function syncLayoutTracker() {
    if (root.perWindowLayouts) {
      if (!layoutTracker.running) layoutTracker.running = true
      return
    }

    trackerRestartTimer.stop()
    automaticRestoreTimer.stop()
    root.automaticRestoreLayout = -1
    if (layoutTracker.running) layoutTracker.running = false
  }

  function expectAutomaticRestore(line) {
    var match = String(line || "").trim().match(/^restore:([0-9]+)$/)
    if (!match) return
    root.automaticRestoreLayout = Number(match[1])
    automaticRestoreTimer.restart()
  }

  function selectPresetColor(value) {
    root.customColorEditorVisible = false
    setPulseColor(value)
    keyCatcher.forceActiveFocus()
  }

  function openCustomColorEditor() {
    root.customColorEditorVisible = true
    customColorField.text = root.pulseColor
    Qt.callLater(function() {
      customColorField.selectAll()
      customColorField.forceActiveFocus()
    })
  }

  function updateKeyboardConfig(raw) {
    var lines = String(raw || "").split("\n")
    var commentedLine = 1

    for (var index = 0; index < lines.length; index++) {
      if (/^\s*kb_options\s*=/.test(lines[index])) {
        root.keyboardOptionsLine = index + 1
        return
      }
      if (/kb_options\s*=/.test(lines[index])) commentedLine = index + 1
    }

    root.keyboardOptionsLine = commentedLine
  }

  function openSettings() {
    root.settingsPage = true
    customColorField.text = root.pulseColor
    root.customColorEditorVisible
      = root.presetForColor(root.pulseColor) === "custom"
  }

  function closeSettings() {
    root.settingsPage = false
    root.customColorEditorVisible = false
    keyCatcher.forceActiveFocus()
  }

  function editKeyboardShortcut() {
    root.close()
    Quickshell.execDetached([
      "omarchy-launch-terminal",
      "nvim",
      "+" + String(root.keyboardOptionsLine),
      "+normal! zz",
      root.keyboardConfigPath
    ])
  }

  function typingKeyboards(keyboards) {
    var physical = keyboards.filter(function(keyboard) {
      return !String(keyboard.name).startsWith("hl-virtual-keyboard")
    })
    var typing = physical.filter(function(keyboard) {
      var name = String(keyboard.name)
      // Hotkey-only devices do not follow layout group switches.
      return !name.endsWith("-system-control")
        && !name.endsWith("-consumer-control")
        && name !== "video-bus"
        && !name.startsWith("power-button")
        && !name.endsWith("-extra-buttons")
        && !name.endsWith("-wmi-hotkeys")
    })
    return typing.length > 0 ? typing : physical
  }

  function selectKeyboard(keyboards) {
    var typing = root.typingKeyboards(keyboards)
    return typing.find(function(keyboard) {
        return keyboard.name === root.keyboardName
      })
      || typing.find(function(keyboard) { return keyboard.main })
      || typing[0]
  }

  function updateKeyboards(keyboards) {
    var keyboard = root.selectKeyboard(keyboards)
    if (!keyboard || !keyboard.active_keymap) return

    var nextLayouts = String(keyboard.layout || "").split(",").filter(Boolean)
    var index = Number(keyboard.active_layout_index || 0)

    root.keyboardName = String(keyboard.name || "")
    root.keyboardNames = root.typingKeyboards(keyboards).map(function(item) {
      return String(item.name || "")
    }).filter(Boolean)
    root.deviceLayouts = nextLayouts
    root.activeLayoutIndex = index
    root.layoutFull = String(keyboard.active_keymap)
    root.updateLayouts()
  }

  function updateConfiguredLayouts(raw) {
    try {
      var value = String(JSON.parse(raw || "{}").str || "")
      root.configuredLayouts = value.split(",").filter(Boolean)
    } catch (error) {
      root.configuredLayouts = []
    }
    root.updateLayouts()
  }

  function updateLayouts() {
    var nextLayouts = root.configuredLayouts.length > 0
      ? root.configuredLayouts
      : root.deviceLayouts
    var nextLabel = nextLayouts[root.activeLayoutIndex]
      ? String(nextLayouts[root.activeLayoutIndex]).toUpperCase()
      : root.layoutFull.split(/\s+/)[0].substring(0, 3).toUpperCase()
    var changed = root.layoutLabel !== "" && root.layoutLabel !== nextLabel
    var automatic = changed
      && root.automaticRestoreLayout === root.activeLayoutIndex

    root.layouts = nextLayouts
    root.layoutLabel = nextLabel
    root.multipleLayouts = nextLayouts.length > 1
    if (automatic) {
      automaticRestoreTimer.stop()
      root.automaticRestoreLayout = -1
      resetPulse()
    } else if (changed && root.animationEnabled) {
      pulseAnimation.restart()
    }
  }

  function refresh() {
    if (!queryProcess.running) queryProcess.running = true
    if (!layoutProcess.running) layoutProcess.running = true
  }

  function switchLayouts(target) {
    if (!root.bar || root.keyboardNames.length === 0) return

    var commands = root.keyboardNames.map(function(name) {
      return "hyprctl switchxkblayout -- " + Util.shellQuote(name)
        + " " + Util.shellQuote(target)
    })
    root.bar.run(commands.join("; "))
    refreshTimer.restart()
  }

  function cycle(direction) {
    root.switchLayouts(direction)
  }

  function selectLayout(index) {
    if (index < 0 || index >= root.layouts.length) return
    root.switchLayouts(String(index))
    root.close()
  }

  function moveCursor(delta) {
    var itemCount = root.layouts.length + 1
    if (!root.cursorActive) {
      root.cursorActive = true
      return
    }
    root.cursorIndex = (root.cursorIndex + delta + itemCount) % itemCount
  }

  function activateCursor() {
    if (!root.cursorActive) return
    if (root.cursorIndex === root.layouts.length) root.openSettings()
    else root.selectLayout(root.cursorIndex)
  }

  onOpenedChanged: {
    if (!opened) return
    root.settingsPage = false
    root.cursorIndex = root.activeLayoutIndex
    root.cursorActive = false
    root.refresh()
    layoutShortcut.refresh()
  }

  onAnimationEnabledChanged: if (!animationEnabled) resetPulse()
  onPerWindowLayoutsChanged: syncLayoutTracker()

  Component.onCompleted: {
    settingsFile.reload()
    refresh()
  }

  Shortcuts.XkbGroupOption {
    id: layoutShortcut
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event) return
      var name = String(event.name || "")
      if (name.indexOf("activelayout") !== -1) {
        var device = String(event.data || "").split(",")[0]
        if (device && !device.startsWith("hl-virtual-keyboard"))
          root.keyboardName = device
      } else if (name !== "configreloaded") return
      root.refresh()
    }
  }

  Process {
    id: layoutProcess
    command: ["hyprctl", "-j", "getoption", "input:kb_layout"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateConfiguredLayouts(text)
    }
  }

  Process {
    id: queryProcess
    command: ["hyprctl", "-j", "devices"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.updateKeyboards(JSON.parse(text || "{}").keyboards || [])
        } catch (error) {
          root.layoutLabel = ""
        }
      }
    }
  }

  Process {
    id: layoutTracker
    command: [
      "setpriv",
      "--pdeathsig",
      "TERM",
      root.trackerPath
    ]
    stdout: SplitParser {
      onRead: function(line) { root.expectAutomaticRestore(line) }
    }
    onExited: {
      root.automaticRestoreLayout = -1
      if (root.perWindowLayouts) trackerRestartTimer.restart()
    }
  }

  FileView {
    id: settingsFile
    path: root.settingsPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadSettings(text())
    onLoadFailed: root.loadSettings("")
    onFileChanged: reload()
  }

  FileView {
    path: root.keyboardConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.updateKeyboardConfig(text())
    onFileChanged: reload()
  }

  Timer {
    id: refreshTimer
    interval: 600
    onTriggered: root.refresh()
  }

  Timer {
    id: trackerRestartTimer
    interval: 1000
    onTriggered: root.syncLayoutTracker()
  }

  Timer {
    id: automaticRestoreTimer
    interval: 1500
    onTriggered: root.automaticRestoreLayout = -1
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  SequentialAnimation {
    id: pulseAnimation
    loops: 3
    onStopped: {
      root.pulseOpacity = 1
      root.pulseScale = 1
    }
    ParallelAnimation {
      NumberAnimation {
        target: root
        property: "pulseOpacity"
        from: 0.65
        to: 1
        duration: 650
        easing.type: Easing.InOutSine
      }
      SequentialAnimation {
        NumberAnimation {
          target: root
          property: "pulseScale"
          from: 1
          to: 1.16
          duration: 325
          easing.type: Easing.InOutSine
        }
        NumberAnimation {
          target: root
          property: "pulseScale"
          from: 1.16
          to: 1
          duration: 325
          easing.type: Easing.InOutSine
        }
      }
    }
  }

  visible: layoutLabel !== "" && (multipleLayouts || showSingleLayout)
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    hasVisualContent: root.layoutLabel !== ""
    labelVisible: false
    fixedWidth: Math.max(12, labelProbe.implicitWidth + Style.space(12))
    horizontalMargin: 6
    tooltipText: root.layoutFull
    onPressed: function(mouseButton) {
      if (mouseButton === Qt.LeftButton) root.toggle()
    }
    onWheelMoved: function(delta) {
      root.cycle(delta > 0 ? "next" : "prev")
    }
  }

  Text {
    id: labelProbe
    visible: false
    text: root.layoutLabel
    font.family: button.fontFamily
    font.pixelSize: Style.font.caption
  }

  Text {
    id: pulseLabel
    anchors.centerIn: button
    text: root.layoutLabel
    color: root.animationEnabled && pulseAnimation.running
      ? root.pulseColor
      : button.foreground
    opacity: root.pulseOpacity
    scale: root.pulseScale
    transformOrigin: Item.Center
    font.family: button.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: root.animationEnabled && pulseAnimation.running
    renderType: Text.NativeRendering
    layer.enabled: root.animationEnabled && pulseAnimation.running
    layer.smooth: true

    Behavior on color {
      ColorAnimation { duration: 160 }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(
      root.settingsPage ? 260 : 180))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.settingsPage
        && (colorDropdown.popupOpen
          || (root.customColorEditorVisible
            && customColorField.activeFocus))
      onMoveRequested: function(dx, dy) {
        if (!root.settingsPage) root.moveCursor(dy !== 0 ? dy : dx)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: {
        if (root.settingsPage) root.closeSettings()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: panelColumn
        width: parent.width
        spacing: Style.space(6)

        Column {
          id: layoutColumn
          visible: !root.settingsPage
          width: parent.width
          spacing: Style.space(6)

          Repeater {
            model: root.layouts

            Button {
              required property var modelData
              required property int index
              width: layoutColumn.width
              text: String(modelData).toUpperCase()
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              leftAlign: true
              bordered: true
              selected: root.activeLayoutIndex === index
              hasCursor: root.cursorActive && root.cursorIndex === index
              onClicked: root.selectLayout(index)
              onHovered: function(hovered) {
                if (!hovered) return
                root.cursorActive = true
                root.cursorIndex = index
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          Button {
            width: layoutColumn.width
            text: "Settings"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            leftAlign: true
            bordered: true
            hasCursor: root.cursorActive
              && root.cursorIndex === root.layouts.length
            onClicked: root.openSettings()
            onHovered: function(hovered) {
              if (!hovered) return
              root.cursorActive = true
              root.cursorIndex = root.layouts.length
            }
          }
        }

        Column {
          id: settingsColumn
          visible: root.settingsPage
          width: parent.width
          spacing: Style.space(8)

          Item {
            width: parent.width
            implicitHeight: Math.max(
              pulseColorHeader.implicitHeight,
              animationToggleRow.implicitHeight)

            PanelSectionHeader {
              id: pulseColorHeader
              text: "Pulse color"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Row {
              id: animationToggleRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(5)

              PanelSectionHeader {
                id: animationToggleLabel
                text: "Animation"
                foreground: root.animationEnabled
                  ? root.bar.foreground
                  : Color.muted
                fontFamily: root.bar.fontFamily
                anchors.verticalCenter: parent.verticalCenter
              }

              ToggleSwitch {
                id: animationToggle
                anchors.verticalCenter: animationToggleLabel.verticalCenter
                anchors.verticalCenterOffset: Math.round(
                  animationToggleLabel.topPadding / 2)
                trackHeight: Math.round(
                  animationToggleLabel.font.pixelSize * 1.2)
                cursorPad: Style.space(3)
                checked: root.animationEnabled
                foreground: root.bar.foreground
                onToggled: root.setAnimationEnabled(!checked)

                PanelToolTip {
                  visible: animationToggle.containsMouse
                  text: root.animationEnabled
                    ? "Disable the layout-change animation"
                    : "Enable the layout-change animation"
                  fontFamily: root.bar.fontFamily
                }
              }
            }
          }

          ColorDropdown {
            id: colorDropdown
            width: parent.width
            enabled: root.animationEnabled
            opacity: root.animationEnabled ? 1 : 0.35
            value: root.customColorEditorVisible
              ? "custom"
              : root.presetForColor(root.pulseColor)
            customColor: root.isPulseColor(customColorField.text)
              ? root.normalizedPulseColor(customColorField.text)
              : root.pulseColor
            presets: root.colorPresets
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            onChanged: function(value) {
              if (value === "custom") root.openCustomColorEditor()
              else root.selectPresetColor(value)
            }
          }

          Row {
            visible: root.customColorEditorVisible
            width: parent.width
            spacing: Style.space(6)
            enabled: root.animationEnabled
            opacity: root.animationEnabled ? 1 : 0.35

            TextField {
              id: customColorField
              width: parent.width - applyColorButton.width - parent.spacing
              placeholderText: "#RRGGBB"
              foreground: root.bar.foreground
              font.family: root.bar.fontFamily
              validator: RegularExpressionValidator {
                regularExpression: /^#[0-9a-fA-F]{6}$/
              }
              onAccepted: root.applyPulseColor(text)
              Keys.onEscapePressed: root.closeSettings()
            }

            Button {
              id: applyColorButton
              text: "Apply"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              bordered: true
              focusable: true
              enabled: customColorField.acceptableInput
              onClicked: root.applyPulseColor(customColorField.text)
            }
          }

          Text {
            visible: root.animationEnabled
              && root.customColorEditorVisible
              && customColorField.text !== ""
              && !customColorField.acceptableInput
            width: parent.width
            text: "Use #RRGGBB, for example #2aa198."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Text {
            visible: !root.animationEnabled
            width: parent.width
            text: "Please enable animations first."
            color: root.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          PanelSeparator { foreground: root.bar.foreground }

          PanelSectionHeader {
            text: "Keyboard layouts & shortcut"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(
              shortcutText.implicitHeight,
              editShortcutButton.implicitHeight)

            Text {
              id: shortcutText
              anchors.left: parent.left
              anchors.right: editShortcutButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: layoutShortcut.label
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            PanelActionButton {
              id: editShortcutButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "󰒓"
              tooltipText: "Edit layouts and keybinding shortcut"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.bodySmall
              size: Style.space(24)
              bordered: true
              focusable: true
              onClicked: root.editKeyboardShortcut()
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(
              singleLayoutHeader.implicitHeight,
              singleLayoutToggle.implicitHeight)

            PanelSectionHeader {
              id: singleLayoutHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: "Show with one layout"
              foreground: root.showSingleLayout
                ? root.bar.foreground
                : Color.muted
              fontFamily: root.bar.fontFamily
            }

            ToggleSwitch {
              id: singleLayoutToggle
              anchors.right: parent.right
              anchors.verticalCenter: singleLayoutHeader.verticalCenter
              anchors.verticalCenterOffset: Math.round(
                singleLayoutHeader.topPadding / 2)
              trackHeight: Math.round(
                singleLayoutHeader.font.pixelSize * 1.2)
              cursorPad: Style.space(3)
              checked: root.showSingleLayout
              foreground: root.bar.foreground
              onToggled: root.setShowSingleLayout(!checked)

              PanelToolTip {
                visible: singleLayoutToggle.containsMouse
                text: root.showSingleLayout
                  ? "Hide when only one layout is configured"
                  : "Keep visible when only one layout is configured"
                fontFamily: root.bar.fontFamily
              }
            }
          }

          Item {
            width: parent.width
            implicitHeight: Math.max(
              perWindowHeader.implicitHeight,
              perWindowToggle.implicitHeight)

            PanelSectionHeader {
              id: perWindowHeader
              anchors.left: parent.left
              anchors.right: perWindowToggle.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: "Activate per-window layouts"
              elide: Text.ElideRight
              foreground: root.perWindowLayouts
                ? root.bar.foreground
                : Color.muted
              fontFamily: root.bar.fontFamily
            }

            ToggleSwitch {
              id: perWindowToggle
              anchors.right: parent.right
              anchors.verticalCenter: perWindowHeader.verticalCenter
              anchors.verticalCenterOffset: Math.round(
                perWindowHeader.topPadding / 2)
              trackHeight: Math.round(
                perWindowHeader.font.pixelSize * 1.2)
              cursorPad: Style.space(3)
              checked: root.perWindowLayouts
              foreground: root.bar.foreground
              onToggled: root.setPerWindowLayouts(!checked)

              PanelToolTip {
                visible: perWindowToggle.containsMouse
                text: root.perWindowLayouts
                  ? "Use one layout across all windows"
                  : "Remember the layout used in each window"
                fontFamily: root.bar.fontFamily
              }
            }
          }

          PanelSeparator { foreground: root.bar.foreground }

          Button {
            id: backButton
            width: Style.space(82)
            text: "Back"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            leftAlign: true
            bordered: true
            focusable: true
            onClicked: root.closeSettings()

            Text {
              anchors.right: parent.right
              anchors.rightMargin: backButton.horizontalPadding
              anchors.verticalCenter: parent.verticalCenter
              text: "󰅁"
              color: backButton.foreground
              font.family: backButton.fontFamily
              font.pixelSize: backButton.iconSize
            }
          }
        }
      }
    }
  }
}
