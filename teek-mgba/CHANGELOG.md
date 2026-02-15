# Changelog — teek-mgba

> **Beta**: teek-mgba is functional but the API may change between minor versions.

All notable changes to teek-mgba will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- Frame blending (LCD ghosting) — 50/50 blend of current and previous frame, simulating the original GBA LCD's slow pixel response. Fixes games that use per-frame flickering for transparency effects (Golden Sun, F-Zero MV, Boktai). Toggle in Video settings.
- Per-game settings — save video, audio, and save state preferences per ROM. Toggle in settings window; config stored in per-ROM JSON files alongside save states.
- CLI `--frames N` option — run N frames then exit (requires ROM). Useful for automated testing and debugging.
- GBA emulation powered by libmgba — load and play .gba ROMs with full audio and video
- SDL2-based rendering with configurable window scale (1x–4x), pixel filtering (nearest/bilinear), and integer scaling
- GBA color correction — LUT-based gamma and color cross-talk correction matching the original GBA LCD
- Gamepad support with per-controller button mapping, persisted by GUID
- Keyboard input with rebindable controls
- Configurable hotkeys for save states, fast-forward, mute, fullscreen, reset, and volume
- Save states with 10 quick-save slots, automatic backup, and PNG screenshots
- Fast-forward with configurable turbo speed (2x–4x or uncapped) and turbo volume
- Settings window with Video, Audio, Gamepad, and Hotkeys tabs
- Toast notifications for save/load, settings changes, and errors
- JSON config persistence with automatic migration
- ROM info window showing title, game code, maker, platform, CRC32, and ROM size
- Locale support (English and Japanese) with auto-detection
- CLI with `--scale`, `--volume`, `--mute`, `--fullscreen`, `--show-fps`, `--turbo-speed`, `--locale`, `--no-sound`, and `--reset-config` options
- Audio fade-in on startup to avoid initial pop
