---
name: prism-usage
description: Show ROM bank usage from the RGBDS link map. Usage: /prism-usage [--bank N] [--section STR] [--free]
---

Run `prism-usage` with the given arguments:

```bash
prism-usage $ARGUMENTS
```

If no arguments are provided, show a summary of all banks sorted by free space (most full first):

```bash
prism-usage --sort used
```

Common flags:
- `--bank N` — show one bank (decimal or hex with 0x prefix)
- `--section STR` — filter sections by substring
- `--free` — show only free-space lines
- `--sort used|free|name` — sort order
- `--nodebug` / `--debug` — pick which link map to read (default: nodebug)

After running, summarize the key numbers: total used, total free, and any banks that are nearly full (< 200 bytes free).
