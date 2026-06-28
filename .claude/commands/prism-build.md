---
name: prism-build
description: Build the pokeprism ROM (nodebug/release). Runs prism-make alias.
---

Build the release ROM using the `prism-make` alias:

```bash
prism-make
```

After the build completes, report whether it succeeded or failed. If it failed, show the relevant error lines (RGBDS errors look like `file.asm(line): error: message`). If it succeeded, confirm the ROM was emitted.
