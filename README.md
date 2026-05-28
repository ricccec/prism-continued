# Pokémon Prism

Pokémon Prism is a mod of the Generation II game Pokémon Crystal. It is based on the [pokecrystal](https://github.com/pret/pokecrystal) disassembly. It is currently developed by [RainbowDevs][rainbow], a collective of passionate Pokémon Game Boy developers.

Updates are issued through the developer-run Pokémon Prism [subreddit](https://www.reddit.com/r/PokemonPrism/), [Twitter][rainbow] and community-run [Discord server](https://discord.com/invite/PewQHvy).

To set up the repository, see [**INSTALL.md**](INSTALL.md).

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
git clone --depth 1 --branch v0.7.0 https://github.com/gbdev/rgbds.git /tmp/rgbds-0.7.0
cd /tmp/rgbds-0.7.0
PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/bin:$PATH" \
  PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig" \
  CXXFLAGS="-I/opt/homebrew/include" \
  LDFLAGS="-L/opt/homebrew/lib" \
  make -j$(sysctl -n hw.ncpu)
```

Optionally install the binaries system-wide:

```bash
cp /tmp/rgbds-0.7.0/rgbasm /tmp/rgbds-0.7.0/rgbfix \
   /tmp/rgbds-0.7.0/rgblink /tmp/rgbds-0.7.0/rgbgfx \
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
make nodebug RGBDS="/tmp/rgbds-0.7.0/"
```

This produces `pokeprism_nodebug.gbc` (2 MB Game Boy Color ROM).

[rainbow]: https://twitter.com/rainbowdevs