# Pokémon Prism

Pokémon Prism is a mod of the Generation II game Pokémon Crystal. It is based on the [pokecrystal](https://github.com/pret/pokecrystal) disassembly. It was originally developed by [RainbowDevs](https://rainbowdevs.com).

**This fork is my personal attempt to finish Pokémon Prism.** The last official release was v0.95 build 254. Development on the original stalled; this repo picks up from that point and continues the game toward completion.

## Documentation

The `docs/` directory contains in-depth technical documentation built alongside development:

| File | Contents |
|------|----------|
| [`docs/overview.md`](docs/overview.md) | Project structure, ROM layout, subsystem map |
| [`docs/build.md`](docs/build.md) | Build instructions, tool versions, build errors |
| [`docs/codebase-map.md`](docs/codebase-map.md) | Directory map — every subsystem and key file |
| [`docs/maps-and-events.md`](docs/maps-and-events.md) | Map files, NPCs, warps, event scripts |
| [`docs/data-formats.md`](docs/data-formats.md) | Pokémon stats, trainer parties, moves, items, wild tables |
| [`docs/memory-layout.md`](docs/memory-layout.md) | WRAM variables, GBC address space |
| [`docs/macros-and-constants.md`](docs/macros-and-constants.md) | Enum system, constant values, `farcall`/`predef` |
| [`docs/debug-mode.md`](docs/debug-mode.md) | In-game debug menus, `DEBUG_MODE` build flag |
| [`docs/code-conventions.md`](docs/code-conventions.md) | Coding conventions |

## Developer Tools

Python devtools for working with this codebase live in a separate repo: [**pokeprism-devtools**](https://github.com/ricccec/pokeprism-devtools). Install with:

```bash
pipx install -e <path-to-clone>
```

To set up the repository and build the ROM, see [**build.md**](docs/build.md). If something's missing, take a look at [**INSTALL.md**](INSTALL.md), which is the original installation guide.

## Building on macOS (tested on Apple Silicon, macOS 14+)

The project requires **RGBDS 0.7.0** specifically. Versions 0.8.x and later break the build due to
incompatible changes to symbol assignment syntax (`EQU`/`SET` without `DEF`). RGBDS 1.0.x will not
work at all.

### 1. Install dependencies

```bash
brew install python3 libpng pkg-config bison
pip3 install pypng
```

### 2. Build RGBDS 0.7.0 from source

The Homebrew formula only provides the latest RGBDS release, so build 0.7.0 manually:

```bash
git clone --depth 1 --branch v0.7.0 https://github.com/gbdev/rgbds.git ~/rgbds-0.7.0
cd ~/rgbds-0.7.0
PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH" \
  PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig" \
  CXXFLAGS="-I/opt/homebrew/include" \
  LDFLAGS="-L/opt/homebrew/lib" \
  make -j$(sysctl -n hw.ncpu)
```

> **Don't clone into `/tmp`** — its entries can be owned by `root` on macOS, which makes the
> in-place `make` fail with `Permission denied`. Build under your home directory instead.

Optionally install the binaries system-wide:

```bash
cp ~/rgbds-0.7.0/rgbasm ~/rgbds-0.7.0/rgbfix \
   ~/rgbds-0.7.0/rgblink ~/rgbds-0.7.0/rgbgfx \
   /usr/local/bin/
```

Or use [**rgbenv**](https://github.com/gbdev/rgbenv) to manage multiple RGBDS versions and set
`0.7.0` in a `.rgbds-version` file at the project root.

### 3. Build the ROM

If you installed the 0.7.0 binaries system-wide:

```bash
make nodebug
```

Otherwise, point make at the built binaries:

```bash
make nodebug RGBDS="$HOME/rgbds-0.7.0/"
```

This produces `pokeprism_nodebug.gbc` (2 MB Game Boy Color ROM).

#### Tip: skip retyping `RGBDS=`

The Makefile reads `RGBDS` from the environment, so export it once in your shell profile
(`~/.zshrc` or `~/.bashrc`) and every build picks it up automatically:

```bash
export RGBDS="$HOME/rgbds-0.7.0/"
```

After that, plain `make nodebug` (and `make prism`, `make gbs`, …) just work.

The build prints a flood of harmless `-Wobsolete` deprecation warnings, which can bury real
errors. A handy shell alias to surface only the errors (with their reason lines):

```bash
# build, showing only the actual errors
alias prism-errors='make nodebug 2>&1 | grep -A1 "^error:"'
```

RGBDS prints each error across two lines — the file/line trace, then the indented reason —
so `-A1` is what makes the reason visible.