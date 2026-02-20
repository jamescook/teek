# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.5] - 2026-02-19

### Fixed

- Fixed wrong `msys2_mingw_dependencies` value in gemspec (Windows/MSYS2 builds)

## [0.1.4] - 2026-02-15

### Added

- Native file drop target support — `App#register_drop_target(widget)` enables OS-level drag-and-drop onto Tk windows. Generates `<<DropFile>>` virtual events with the file path in event data. macOS (Cocoa), Windows (OLE IDropTarget), and Linux (X11 XDND) supported.
- `:data` bind substitution for virtual event data (Tk 8.6+)

### Changed

- API docs "View source" now displays the actual C source for C-backed methods (previously showed nothing)

### Fixed

- Tcl interpreter bootstrap on Fedora and other distros that ship Tcl symbols in a separate shared library from the Tk combined library

## [0.1.3] - 2026-02-11

### Added

- `App#every(ms, on_error:)` — repeating timer with cancellation, drift tracking, and configurable error handling (`:raise`, `Proc`, or `nil`)
- `App#after` now accepts `on_error:` keyword for one-shot timer error handling
- `App#initialize` accepts `title:` keyword argument
- `App#add_debug_console` — toggle the built-in Tk console with a keyboard shortcut (macOS/Windows)

## [0.1.2] - 2026-02-11

### Added

- `Teek::Photo` — pixel buffer API wrapping Tk photo images: `put_block`, `put_zoomed_block`, `get_image`, `get_pixel`, `get_size`, `set_size`, `expand`, `blank` with RGBA/ARGB format support and composite modes
- `Interp#native_window_handle` — platform-native window handle (NSWindow*/X Window ID/HWND) for SDL2 embedding
- `Interp#get_root_coords`, `Interp#coords_to_window` — window coordinate queries and hit testing
- Paint demo sample
- **teek-sdl2** gem (beta) — GPU-accelerated SDL2 rendering inside Tk frames. See [teek-sdl2/CHANGELOG.md](teek-sdl2/CHANGELOG.md)

### Changed

- `BackgroundWork` (Ractor mode) — clearer error message when the work block references outside variables like `app`

### Fixed

- Ractor-related hang on Windows — fixed broken test skips and Ractor shutdown

## [0.1.1] - 2026-02-09

### Added

- `Teek::Widget` — thin wrapper around Tk widget paths with `command`, `pack`, `grid`, `bind`, `unbind`, `destroy`, and `exist?`
- `App#create_widget` — creates widgets with auto-generated paths derived from widget type (e.g. `ttk::button` produces `.ttkbtn1`)
- `Debugger#add_watch` / `Debugger#remove_watch` — public API for programmatic variable watches

### Fixed

- `BackgroundRactor4x::BackgroundWork#close` — use Ruby 4.x Ractor API (was using removed 3.x methods)
- `Debugger#remove_watch` — now correctly deletes the watch tree item

## [0.1.0] - 2026-02-08

### Added

- C extension wrapping Tcl/Tk interpreter (Tcl 8.6+ and 9.0)
- `Teek::App` — single-interpreter interface with `tcl_eval`, `command`, and automatic Ruby-to-Tcl value conversion
- Callback support — procs become Tcl commands, with `throw :teek_break` / `:teek_continue` / `:teek_return` control flow
- `bind` / `unbind` helpers with event substitution support
- `after` / `after_idle` / `after_cancel` timer helpers
- Window management — `show`, `hide`, `set_window_title`, `set_window_geometry`, `set_window_resizable`
- Tcl variable access — `set_variable`, `get_variable`
- Package management — `require_package`, `add_package_path`, `package_names`, `package_present?`, `package_versions`
- `destroy`, `busy`, `update`, `update_idletasks`
- Font introspection — `font_families`, `font_metrics`, `font_measure`, `font_actual`, `font_configure`
- List operations — `make_list`, `split_list`
- Boolean conversion — `tcl_to_bool`, `bool_to_tcl`
- `BackgroundWork` — thread and Ractor modes for background tasks with progress callbacks
- Built-in debugger (`debug: true`) with widget tree, variable inspector, and watches
- Widget tracking via Tcl execution traces (`app.widgets`)
- Samples: calculator, concurrency demo, rube goldberg demo
- API documentation site with search

[0.1.5]: https://github.com/jamescook/teek/compare/v0.1.4...v0.1.5
[0.1.4]: https://github.com/jamescook/teek/compare/v0.1.3...v0.1.4
[0.1.3]: https://github.com/jamescook/teek/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/jamescook/teek/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/jamescook/teek/releases/tag/v0.1.1
[0.1.0]: https://github.com/jamescook/teek/releases/tag/v0.1.0
