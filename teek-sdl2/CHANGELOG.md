# Changelog — teek-sdl2

> **Beta**: teek-sdl2 is functional but the API may change between minor versions.

All notable changes to teek-sdl2 will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

## [0.2.1] - 2026-02-19

### Fixed

- **macOS: SDL2 Metal subview not removed on foreign window destroy** — SDL2's Metal backend leaves an `SDL_cocoametalview` on Tk-owned windows after `SDL_DestroyRenderer`, preventing Tk widgets from becoming visible again. The renderer destroy path now removes the Metal subview via ObjC.

## [0.2.0] - 2026-02-17

### Removed

- **SDL2_gfx dependency and all drawing primitives** — circles, ellipses, arcs, pies, polygons, triangles, beziers, thick/AA lines, pixel/hline/vline methods have been removed from `Renderer`. SDL2_gfx has no SDL3 port and was problematic to install on Linux. The custom `fill_rounded_rect` and `draw_rounded_rect` methods (pure SDL2, no gfx dependency) are retained.

## [0.1.3] - 2026-02-16

### Added

- `Texture#scale_mode=` / `Texture#scale_mode` — get/set texture scaling filter (`:nearest` for sharp pixels, `:linear` for smooth bilinear)

## [0.1.2] - 2026-02-14

### Added

- `Teek::SDL2::AudioStream` — push-based real-time PCM audio output for emulators, synthesizers, and procedural audio. Supports `:s16`, `:f32`, and `:u8` sample formats with configurable frequency and channels
- `fill_rounded_rect`, `draw_rounded_rect` — rectangles with rounded corners
- `Texture#blend_mode=` / `Texture#blend_mode` — get/set texture blend mode (`:none`, `:blend`, `:add`, `:mod`, or custom)
- `SDL2.compose_blend_mode` — create custom blend modes with configurable source/destination factors and operations
- `Viewport.new` accepts `vsync:` keyword (default `true`). Pass `false` for applications that manage their own frame pacing
- `Gamepad#guid` — controller GUID string for per-controller config persistence
- `Gamepad.update_state` — refresh controller state without pumping the platform event loop (avoids macOS Cocoa run loop stealing Tk events)
- `Font#ascent` — maximum pixel ascent for glyph cropping and text layout

### Changed

- `Font#render_text` now premultiplies alpha automatically, fixing transparent-region artifacts with custom blend modes
- `Renderer#fill_rect`, `draw_rect`, `draw_line` now auto-enable alpha blending when alpha < 255

### Fixed

- Gamepad events now fire even when the SDL2 window doesn't have focus (e.g. when a Tk settings window is active)

## [0.1.1] - 2026-02-11

### Added

- `Teek::SDL2::Gamepad` — Xbox-style controller input via SDL2's GameController API with polling, event callbacks, hot-plug, dead zone helper, and virtual gamepad for testing
- `Teek::SDL2::Sound` — short sound effect playback via SDL2_mixer (WAV, OGG, etc.)
- `Teek::SDL2::Music` — streaming music playback via SDL2_mixer (MP3, OGG, etc.) with play/pause/resume/stop and volume control
- `Teek::SDL2.start_audio_capture` / `stop_audio_capture` — record mixed audio output to WAV
- Gamepad viewer sample

### Fixed

- extconf.rb now detects UCRT vs MINGW64 Ruby and shows correct MSYS2 package names

## [0.1.0] - 2026-02-11

Initial release.

### Added

- `Teek::SDL2::Viewport` — embed an SDL2 GPU-accelerated surface inside a Tk frame via `SDL_CreateWindowFrom`
- `Teek::SDL2::Renderer` — draw commands: `clear`, `fill_rect`, `draw_rect`, `draw_line`, `copy`, `present`, plus keyword-arg wrappers `fill`, `outline`, `line`, `blit`
- `Renderer#read_pixels` — read GPU framebuffer as raw RGBA8888 bytes
- `Renderer#save_png` — save framebuffer to PNG via ImageMagick
- `Renderer#render` — block-based draw-and-present
- `Renderer#create_texture` — create ARGB8888 textures (static, streaming, or target access)
- `Renderer#load_image` — load PNG/JPG/BMP/WebP/GIF into GPU texture via SDL2_image
- `Renderer#output_size` — query renderer dimensions
- `Teek::SDL2::Texture` — GPU texture with `update`, `width`, `height`, `destroy`
- `Teek::SDL2::Font` — TTF font rendering to textures via SDL2_ttf
- `Viewport` keyboard input tracking — `key_down?`, `bind`, `focus`
- SDL2 event source integration with Tk mainloop
- Screenshot-based visual regression testing via `assert_sdl2_screenshot`
- SDL2 demo sample

[Unreleased]: https://github.com/jamescook/teek/compare/teek-sdl2-v0.2.1...HEAD
[0.2.1]: https://github.com/jamescook/teek/compare/teek-sdl2-v0.2.0...teek-sdl2-v0.2.1
[0.2.0]: https://github.com/jamescook/teek/compare/teek-sdl2-v0.1.3...teek-sdl2-v0.2.0
[0.1.3]: https://github.com/jamescook/teek/compare/teek-sdl2-v0.1.2...teek-sdl2-v0.1.3
[0.1.2]: https://github.com/jamescook/teek/releases/tag/teek-sdl2-v0.1.2
