# Native keyboard helpers

The per-window core comes from
[`hypr-type-flow-C`](https://github.com/Liran-shternberg/hypr-type-flow-C),
at upstream commit `f7bb627ba2f1c4d3a3740140e239e13e5327ffc6`.

The port keeps the event-driven behavior but replaces the fixed window table,
shell commands, and ad-hoc JSON parsing with:

- a small dynamic window-to-layout map;
- direct use of Hyprland's control and event sockets;
- `json-c` for bounded, typed parsing of `hyprctl` responses;
- explicit recovery from interrupted reads, oversized events, socket closure,
  and Hyprland configuration reloads; and
- unit-tested state transitions and response parsing.

The plugin's shell service starts one `keyboard-layoutd` process only while
**Activate per-window layouts** is enabled and stops it when the setting is
disabled or the shell exits. Build and test it with:

```bash
make
make test
make check-live
```

Generate clangd's local compilation database with `make compile-commands`. This
uses `jq` and does not rebuild the helper; the generated file remains untracked.

`check-live` only reads the active Hyprland window and keyboard state. It does
not start the daemon or switch layouts.

The bundled executable targets x86-64 and links to `json-c`, `libxkbcommon`,
and `libutf8proc`. The service checks its capabilities before starting native
features. Other architectures need a native build supplied explicitly; the
plugin does not compile during startup.

## Keymap description

`keyboard-layoutd --describe-keymap` reads one JSON request from stdin and emits
one JSON description. It operates independently of the tracking daemon and does
not connect to Hyprland or inject input. `--probe` reports the supported protocol
and native features without a compositor environment.

Example request:

```json
{
  "rules": "evdev",
  "model": "pc105",
  "layouts": "us,de",
  "variants": ",",
  "options": "caps:escape",
  "keymapFile": "",
  "group": 1
}
```

A nonempty `keymapFile` selects a compiled custom keymap instead of RMLVO names.
The group is checked against the resulting keymap. Requests are limited to
64 KiB, regular keymap files to 1 MiB, and responses to 1 MiB.

The description includes each physical key's eight Shift, Caps Lock and AltGr
states, resolved modifier labels, dead-key composition and accent choices.
`libxkbcommon` resolves key types and Compose tables; `libutf8proc` handles
Unicode classification. JSON encoding uses `json-c`.

The implementation is split into request/file handling (`keymap.c`), key states
and labels (`keymap_symbols.c`), and composition (`keymap_compose.c`).
Regression fixtures cover the resolved key data, with native tests for active
groups, remapping, custom files, malformed requests and bounded I/O.

The original MIT notice is preserved in [LICENSE](LICENSE).
