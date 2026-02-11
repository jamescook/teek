# Changelog — teek-sdl2

> **Beta**: teek-sdl2 is functional but the API may change between minor versions.

All notable changes to teek-sdl2 will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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

[0.1.0]: https://github.com/jamescook/teek/releases/tag/teek-sdl2-v0.1.0
