---
name: prism-map
description: Inspect a map's header, section banks, and blob sizes. Usage: /prism-map <MapName> [-o spec.toml]
---

Run `prism-map` with the given arguments:

```bash
prism-map $ARGUMENTS
```

This prints the full report for the named map: header fields (dimensions, tileset, palette, connections), which ROM banks hold its blockdata/header/events sections, and compressed blob sizes. If `-o file.toml` is given it also exports a `prism-mapfit` spec.

Map names match the `MAP_*` constant without the `MAP_` prefix, e.g. `OlcanDock`, `MtEmberWest`, `SenecaCavernsB1F`.
