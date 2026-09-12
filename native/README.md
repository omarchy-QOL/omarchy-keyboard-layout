# Native per-window layout core

This directory contains the bundled per-window layout helper, ported from
[`hypr-type-flow-C`](https://github.com/Liran-shternberg/hypr-type-flow-C),
based on upstream commit `f7bb627ba2f1c4d3a3740140e239e13e5327ffc6`.

The port keeps the event-driven behavior but replaces the fixed window table,
shell commands, and ad-hoc JSON parsing with:

- a small dynamic window-to-layout map;
- direct use of Hyprland's control and event sockets;
- `json-c` for bounded, typed parsing of `hyprctl` responses;
- explicit recovery from interrupted reads, oversized events, socket closure,
  and Hyprland configuration reloads; and
- unit-tested state transitions and response parsing.

The plugin starts `keyboard-layoutd` only while **Activate per-window layouts**
is enabled and stops it when the setting is disabled or the shell exits. Build
and test it with:

```bash
make
make test
make check-live
```

Generate clangd's local compilation database with `make compile-commands`. This
requires Bear; the generated file remains untracked.

`check-live` only reads the active Hyprland window and keyboard state. It does
not start the daemon or switch layouts.

The committed executable targets x86-64 and dynamically links to `json-c`, which
is included with a standard Omarchy installation.

The original MIT notice is preserved in [LICENSE](LICENSE).
