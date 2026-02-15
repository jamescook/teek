# teek-mgba

A GBA emulator frontend powered by [teek](https://github.com/jamescook/teek) and [libmgba](https://github.com/mgba-emu/mgba).

Wraps libmgba's mCore C API and provides a full-featured player with SDL2
video/audio rendering, keyboard and gamepad input, save states, and a
Tk-based settings UI.

## Usage

```
teek-mgba [options] [ROM_FILE]
```

If no ROM file is given, the player opens empty — use the menu to load a ROM.

### Options

| Flag | Description |
|------|-------------|
| `-s, --scale N` | Window scale (1-4) |
| `-v, --volume N` | Volume (0-100) |
| `-m, --mute` | Start muted |
| `--no-sound` | Disable audio entirely |
| `-f, --fullscreen` | Start in fullscreen |
| `--show-fps` | Show FPS counter |
| `--turbo-speed N` | Fast-forward speed (0=uncapped, 2-4) |
| `--locale LANG` | Language (`en`, `ja`, `auto`) |
| `--reset-config` | Delete settings file and exit (keeps saves) |

## Features

- GBA emulation via libmgba
- SDL2 video rendering with configurable window scale (1x-4x)
- Integer scaling and nearest-neighbor/bilinear pixel filtering
- GBA color correction (Pokefan531 formula) for authentic LCD appearance
- Fullscreen support
- SDL2 audio with volume control and mute
- Keyboard and gamepad input with remappable controls and hotkeys
- Quick save/load and 10-slot save state picker with thumbnails
- Turbo/fast-forward mode
- ROM info viewer
- Persistent user configuration with settings UI

## Language Support

The UI supports multiple languages via YAML-based locale files. The active
language is auto-detected from the system environment (`LANG`) or can be
set manually in the config.

Currently supported:

| Language | Code |
|----------|------|
| English  | `en` |
| Japanese | `ja` |

To force a specific language:

```ruby
Teek::MGBA.user_config.locale = 'ja'
```

Adding a new language: create `lib/teek/mgba/locales/<code>.yml` following
the structure in `en.yml`.

## License

MIT. See [THIRD_PARTY_NOTICES](THIRD_PARTY_NOTICES) for bundled font licenses.
