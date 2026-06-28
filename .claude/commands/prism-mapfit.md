---
name: prism-mapfit
description: Allocate ROM banks for a new map and wire it into blockdata.asm / romx.link. Usage: /prism-mapfit <add|consolidate|status> [--spec file.toml] [--park]
---

Run `prism-mapfit` with the given arguments:

```bash
prism-mapfit $ARGUMENTS
```

Subcommands:
- `add --spec map.toml [--park]` — find a bank for the map's blockdata and wire it in. `--park` marks it as still-growing (temporary bank, not pinned).
- `consolidate --spec a.toml [--spec b.toml ...]` — re-pack multiple maps once their sizes have settled, finding tighter bank assignments.
- `status` — show current allocation state from `romx.link`.

The spec TOML (exportable via `prism-map MapName -o out.toml`) contains the map name, estimated blob sizes, and any pinned banks.

After running, summarize what changed: which banks were assigned, how much free space remains in each affected bank.
