# Teek::SDL2

GPU-accelerated 2D rendering for [Teek](https://github.com/jamescook/teek) via SDL2.

Embeds an SDL2 hardware-accelerated surface inside a Tk window. Draw with the GPU while keeping full access to Tk widgets, menus, dialogs, and layout.

## Quick Start

```ruby
require 'teek'
require 'teek/sdl2'

app = Teek::App.new
app.set_window_title('SDL2 Demo')

viewport = Teek::SDL2::Viewport.new(app, width: 800, height: 600)
viewport.pack(fill: :both, expand: true)

viewport.render do |r|
  r.clear(0, 0, 0)
  r.fill_rect(100, 100, 200, 150, 255, 0, 0)
  r.draw_rect(100, 100, 200, 150, 255, 255, 255)
end

app.mainloop
```

## Features

- **Viewport** -- SDL2 renderer embedded in a Tk frame
- **Renderer** -- hardware-accelerated drawing (rectangles, lines, textures)
- **Texture** -- streaming, static, and render-target textures
- **Image loading** -- PNG, JPG, BMP, WebP, GIF, and more via SDL2_image
- **Font** -- TrueType text rendering and measurement via SDL2_ttf
- **Keyboard input** -- poll key state with `viewport.key_down?('space')`

## Image Loading

```ruby
# Load an image file directly into a GPU texture
sprite = renderer.load_image("assets/player.png")
renderer.copy(sprite, nil, [x, y, sprite.width, sprite.height])

# Or use the Texture convenience constructor
bg = Teek::SDL2::Texture.from_file(renderer, "assets/background.jpg")
```

Supports PNG, JPG, BMP, GIF, WebP, TGA, and other formats via SDL2_image.

## Textures

```ruby
# Streaming texture for dynamic pixel data (e.g. emulators, video)
tex = Teek::SDL2::Texture.streaming(renderer, 256, 224)
tex.update(pixel_data)   # ARGB8888, 4 bytes per pixel
renderer.copy(tex)

# Copy a sub-region
renderer.copy(tex, [0, 0, 128, 112], [100, 100, 256, 224])
```

## Text Rendering

```ruby
font = renderer.load_font("/path/to/font.ttf", 16)

# One-shot draw
renderer.draw_text(10, 10, "Score: 100", font: font, r: 255, g: 255, b: 255)

# Measure for layout
w, h = font.measure("Score: 100")
```

## Keyboard Input

```ruby
# Tk keysym names, lowercase
viewport.key_down?('left')
viewport.key_down?('space')
viewport.key_down?('a')

# Or bind events directly
viewport.bind('KeyPress', :keysym) { |key| puts key }
```

## Requirements

- [teek](https://github.com/jamescook/teek) >= 0.1.0
- SDL2 development headers
- SDL2_image development headers (for image loading)
- SDL2_ttf development headers (for text rendering)

### macOS

```sh
brew install sdl2 sdl2_image sdl2_ttf
```

### Ubuntu/Debian

```sh
apt-get install libsdl2-dev libsdl2-image-dev libsdl2-ttf-dev
```

### Windows

SDL2 headers are needed at compile time. See the [SDL2 download page](https://github.com/libsdl-org/SDL/releases) for development libraries.

## Installation

```sh
gem install teek-sdl2
```

Or in your Gemfile:

```ruby
gem 'teek-sdl2'
```

## License

MIT
