# Build System

## Requirements

| Tool | Required version | Notes |
|------|-----------------|-------|
| RGBASM / RGBLINK / RGBFIX / RGBGFX | **0.7.0 exactly** | 0.8+ breaks old-style `EQU`/`SET`; 1.0+ is a hard error |
| GNU Make | 3.81+ | macOS ships with 3.81, which works |
| Python 3 | 3.x | For `gfx.py` and `dedenc.py` |
| pypng | any | `pip3 install pypng` |
| libpng | any | Required to build RGBDS from source |
| bison | 3.x | System bison (2.3) is too old to build RGBDS from source |

> **Why 0.7.0?** The codebase uses ~427 old-style symbol assignments (`sym EQU value`,
> `sym = value` without the `DEF` keyword). These were deprecated in 0.8.x and
> fully removed in 1.0.0.

---

## Installing RGBDS 0.7.0 on macOS

```bash
# Homebrew dependencies
brew install libpng pkg-config bison

# Clone and build
git clone --depth 1 --branch v0.7.0 https://github.com/gbdev/rgbds.git /tmp/rgbds-0.7.0
cd /tmp/rgbds-0.7.0
PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH" \
  PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig" \
  CXXFLAGS="-I/opt/homebrew/include" \
  LDFLAGS="-L/opt/homebrew/lib" \
  make -j$(sysctl -n hw.ncpu)
```

Optionally copy the binaries somewhere permanent:
```bash
sudo cp /tmp/rgbds-0.7.0/rgbasm /tmp/rgbds-0.7.0/rgbfix \
        /tmp/rgbds-0.7.0/rgblink /tmp/rgbds-0.7.0/rgbgfx \
        /usr/local/bin/
```

Or use [rgbenv](https://github.com/gbdev/rgbenv) (a RGBDS version manager) and add a
`.rgbds-version` file containing `0.7.0` to the project root.

---

## Build Targets

```bash
make nodebug                    # Release ROM (recommended starting point)
make nodebug RGBDS="/path/to/"  # Use a specific RGBDS install
make all                        # nodebug + debug ROM + GBS music file + freespace report
make gbs                        # GBS music-only export
make patch                      # IPS patch (needs baserom.gbc — Crystal 1.1)
make genimages                  # Render GIF previews of maps
make clean                      # Remove all generated files
make tidy                       # Remove ROMs and object files only
```

Output files after `make nodebug`:
- `pokeprism_nodebug.gbc` — the playable 2MB ROM
- `pokeprism_nodebug.sym` — symbol table (useful for debugging in emulators)
- `pokeprism_nodebug.map` — linker map

---

## Build Pipeline (step by step)

### 1 — Build C utilities (`utils/`)

The Makefile automatically runs `make -C utils/` before anything else.
This compiles: `scaninc`, `bankends`, `bspcomp`, `gbspatch`, `gbstrim`,
`ipspatch`, `lzcomp`, `pngtrim`, `pokepic`, `qrconv`, `rendergifs`.

`scaninc` is critical: it walks `INCLUDE` directives to build dependency graphs
so Make knows when to recompile `.o` files.

### 2 — Generate graphics assets

PNG files under `gfx/` are converted on demand:

| Input | Rule | Output |
|-------|------|--------|
| `gfx/*/pic/*.png` | `utils/pokepic` | `front.2bpp`, `back.2bpp`, `*.pal`, `frames.asm`, etc. |
| `gfx/battle/*.png` | `python3 gfx.py 2bpp` | `.2bpp` |
| `gfx/tilesets/*.png` | `rgbgfx` | `.2bpp` |
| `*.png` (generic) | `rgbgfx` | `.2bpp` or `.1bpp` |
| `gfx/qrcodes/*.asm` | `utils/qrconv` | `.1bpp` |

Converted graphics are then LZ-compressed to `.lz` by `utils/lzcomp`.

### 3 — Generate audio assets

`.wav` files under `audio/ded/` → `.ded` (DED-encoded) via `python3 dedenc.py`.

### 4 — Assemble object files

Six translation units are assembled with `rgbasm`:

| Object file | Source | Flags |
|-------------|--------|-------|
| `audio_nodebug.o` | `audio.asm` | — |
| `gfx_nodebug.o` | `gfx.asm` | — |
| `main_nodebug.o` | `main.asm` | — |
| `maps_nodebug.o` | `maps.asm` | — |
| `text_nodebug.o` | `text.asm` | — |
| `wram_nodebug.o` | `wram.asm` | — |

(The debug build adds `-DDEBUG_MODE` to all of these.)

### 5 — Link

`rgblink` combines the six objects using `contents/contents.link` (which itself
includes the other `.link` files) and produces the raw ROM.

### 6 — Fix ROM header

`rgbfix` writes the Game Boy cartridge header: title, CGB flag, licensee, MBC
type, ROM/RAM sizes, checksums.

---

## Python Scripts

### `gfx.py`
Converts PNG → Game Boy 2BPP tile format. Reads `data/base_stats/*.asm` to
extract Pokémon sprite dimensions before conversion.

### `dedenc.py`
Compresses WAV audio using DED (Delta-Encoded, Huffman-packed).
Steps: resample → 4-bit delta → build Huffman tree → emit bytecode.
Output is loaded by `home/ded.asm` at runtime.

### `png.py`
Minimal PNG I/O library used internally by `gfx.py`.

---

## Common Build Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Undefined macro '__enum__'` | RGBDS ≥ 1.0 — old `sym = value` syntax removed | Use RGBDS 0.7.0 |
| `'ROUTE_78' is not constant at assembly time` | RGBDS 0.8–0.9 — `EQU` without `DEF` broken | Use RGBDS 0.7.0 |
| `Permission denied: utils/coll2bin.sh` | Missing execute bit after fresh clone | `chmod +x utils/*.sh` |
| `png.h not found` (building RGBDS) | libpng headers missing | `brew install libpng` |
| `Bison 2.3 is not supported` (building RGBDS) | System bison too old | Use Homebrew bison |
