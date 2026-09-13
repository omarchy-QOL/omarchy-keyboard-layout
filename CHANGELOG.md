# Changelog

Notable changes to Keyboard Layout Pulse are documented here.

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
