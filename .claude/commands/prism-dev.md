---
name: prism-dev
description: Launch the ROM in SameBoy with a patched save state. Usage: /prism-dev [--map MapName] [--no-tui] [--inventory-only]
---

Run `prism-dev` with the given arguments:

```bash
prism-dev $ARGUMENTS
```

`prism-dev` patches `.devtools/state.json` into the save file and launches SameBoy. The TUI is shown by default when running on a TTY; pass `--no-tui` to skip it.

Common flags:
- `--map MapName` — teleport to this map on load (e.g. `--map MtEmberWest`)
- `--no-tui` — skip the questionary menu, apply state.json directly and launch
- `--inventory-only` — rebuild `inventory.json` from the current .sym without launching the emulator
- `--rebuild-inventory` — force inventory rebuild even if .sym hasn't changed
- `--debug` — use the debug ROM's .sym

The save state schema lives at `.devtools/state.json`. Presets can be stored in `.devtools/presets/*.json` and selected from the TUI.
