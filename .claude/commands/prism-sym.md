---
name: prism-sym
description: Query the RGBDS .sym file by label name or address. Usage: /prism-sym <label|--addr BB:AAAA|--prefix STR>
---

Run `prism-sym` with the given arguments:

```bash
prism-sym $ARGUMENTS
```

Print the output. If no results are found, try a substring search:

```bash
prism-sym --search $ARGUMENTS
```

Address format is `BB:AAAA` (bank:address in hex, e.g. `2c:5924`).
Common flags: `--prefix STR`, `--search STR`, `--addr BB:AAAA`, `--region SRAM|WRAM0|WRAMX|ROMX`, `-n N` to cap results.
