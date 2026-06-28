---
name: prism-maps
description: List all maps with metadata (dimensions, block sizes, NPC counts). Usage: /prism-maps [--filter STR] [--sort col]
---

Run `prism-maps` with the given arguments:

```bash
prism-maps $ARGUMENTS
```

Prints a filterable terminal table of every map: dimensions, compressed blockdata size, NPC count, and compression ratio. Does not require a built ROM — reads the source files directly.

Common flags:
- `--filter STR` — show only maps whose name contains STR (case-insensitive)
- `--sort name|size|npcs|ratio` — sort column
- `--min-size N` / `--max-size N` — filter by blockdata byte size
