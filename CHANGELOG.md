# Changelog

Notable changes to Keyboard Layout Pulse are documented here.

## Unreleased

- Keep the left border of dropdowns at fractional display scales.

## 0.2.5 - 2026-11-04

- Refresh the preview with separate layout menu, settings, and keyboard panels.
- Clarify the optional on-screen keyboard in the marketplace description.

## 0.2.4 - 2026-11-03

- Add an interactive keyboard viewer with sticky modifiers, dead keys, and
  accent selection.
- Add custom layout labels, contributed by
  [plasmaStray](https://github.com/plasmaStray) in
  [#21](https://github.com/omarchy-QOL/omarchy-keyboard-layout/pull/21).
- Add an optional keycap style for the bar label, disabled by default.
- Select layouts from a dropdown that keeps the main menu open after a change.
- Place Emoji and View together above the separator and Settings. Both menus
  share a width, and either mouse button opens the layout menu.
- Keep viewer legends within their keys across layouts and font fallbacks.
- Fix Qt 6.12 colors, QML scopes, and laptop keyboard tracking, contributed by
  [Haamed](https://github.com/hamedemamimeybodi) in
  [#22](https://github.com/omarchy-QOL/omarchy-keyboard-layout/pull/22).
- Preserve per-window layout changes made through keyd.
- Retry pending shortcut queries after process launch failures and open the
  keyboard configuration at the shortcut's owning line.

## 0.2.3 - 2026-09-21

- Show variants in the bar and picker, such as `US(intl)` and `US(dvorak)`.
- Pulse on layout switches even when labels match or the keyboard changes.

## 0.2.2 - 2026-09-13

- Follow layout events from the physical keyboard in use and ignore hotkey-only
  devices, contributed by Alex Takitani (@alextakitani) in PR #13.
- Keep preferences in Omarchy's inline plugin settings and migrate legacy
  settings without overwriting newer values.
- Close the color menu from its trigger and after choosing a color.
- Run one per-window layout tracker across all displays through the Omarchy
  service API.
- Disable per-window tracking safely on non-x86-64 systems while keeping layout
  selection available.
- Add reproducible C and QML formatting and analysis tooling.
- Correct the installation URL and clarify runtime requirements.

## 0.2.1 - 2026-08-15

- Display Scroll Lock with a readable shortcut label.
- Clarify the available settings and per-window helper lifecycle.

## 0.2.0 - 2026-08-14

- Add optional per-window keyboard layout memory.
- Show the effective layout shortcut and refresh it whenever the menu opens.
- Add a single-layout visibility toggle and dim unavailable settings.
- Share shortcut formatting with other Omarchy QOL plugins.
- Add the plugin demo and refine its marketplace description.

## 0.1.1 - 2026-08-12

- Track configured layouts and the active physical keyboard reliably.
- Support keyboard device names beginning with a dash.
- Store preferences inside the plugin directory for clean removal.

## 0.1.0 - 2026-08-12

- Add the pulsing keyboard layout indicator, picker, color controls, and
  keyboard navigation.
