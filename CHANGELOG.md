# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-07-16

### Added

- `Teek::Window` — one object per toplevel window (via `App#window(path = '.')`), grouping the `wm` subcommands with window-lifecycle helpers: `on_close { }`, `grab_set`/`grab_release`, and `modal(global:) { }` (grab-and-focus for dialogs, auto-released if the window is destroyed or the setup block raises; `global:` defaults to false). The existing flat `App` window/`wm` methods now delegate to it and stay for compatibility — `app.window(path)` is preferred for new code. `Widget` itself gained the same `#window`/`#grab_set`/`#grab_release`/`#modal` as direct delegates, so a widget handle for a toplevel doesn't need `app.window(widget.path)` spelled out.
- `App#choose_dir` — the native "choose directory" dialog (`tk_chooseDirectory`), rounding out the standard dialog wrappers alongside `#choose_open_file`/`#choose_save_file`/`#message_box`/`#choose_color`. Returns `nil` on cancel, same as the other file/color pickers.
- `App#clipboard` (`Teek::Clipboard`) — `#set`/`#get`/`#clear` over Tk's `clipboard` command; `#get` returns `nil` on an empty clipboard instead of raising. Text widgets' own copy/cut/paste already work via Tk's built-in bindings, so nothing there needed wiring.
- `Teek::CallbackRegistry#counts_by_tag` — a live snapshot of tracked callback ids grouped by container tag (`:bind`, `:menu`, `:canvas_bind`, `:tag_bind`, `:widget_option`, `:wm_protocol`, ...), for diagnosing whether an app is leaking callbacks and where. A tag with nothing currently tracked is absent from the result rather than present at zero.

### Fixed

- Canvas item bindings that use `%`-substitution codes (`CanvasItem#on_drag`, `#on_right_click` with a menu) no longer leak their callback on rebuild/delete — the leak-reconcile regex only matched a bare `ruby_callback <id>` with nothing after it, so any binding carrying substitution codes silently stopped matching and its id was never released.

## [0.2.0] - 2026-07-12

### Added

- `App#command` is now safe to use directly for every widget interaction, with no separate wrapper methods to know about. It consults `Teek::CommandInterceptors`, a registry of per-Tk-widget-type interceptors, before falling back to its generic handling — currently covering menu entries (`add`/`insert`/`entryconfigure`/`delete`, reconciled against Tk's live menu state after every mutating call, so callbacks don't leak when a menu is cleared and rebuilt in place), text/`ttk::treeview` tag bindings (`tag bind`/`tag delete`, reconciled against Tk's live tag state), and canvas item/tag bindings (`bind`/`delete`, reconciled by re-querying only the bindings it's already tracking, since canvas has no "list every live binding" command). A `command:` proc passed to a `ttk::treeview` column's `heading` call is tracked per column (so two columns' commands can't collide) by the same generic option-callback tracking every widget option already gets. Two interceptors matching the same call raises `Teek::AmbiguousCommandError` naming both, rather than silently picking one.
- `App#menu(path)` — creates (or reuses, tearoff disabled) a Tk menu and returns a `Widget`.
- `Teek::CallbackRegistry` — shared internal tracking for callbacks scoped to something narrower than a whole widget (event bindings, menu entries, widget option callbacks, tag bindings), released on overwrite, explicit removal, or the owning widget's destruction, regardless of which feature registered them.
- `Teek::TclError` now carries Tcl's own `errorInfo`/`errorCode` for the failing call, via `#tcl_backtrace` and `#tcl_error_code`, alongside the short one-line message it already had. `#tcl_backtrace` is a multi-line trace with a frame for each level of Tcl proc call the error unwound through, not just the innermost failure.
- `Teek::Photo` now registers a GC finalizer that deletes its underlying Tk image once nothing in Ruby references the wrapper anymore, so callers no longer need to hand-track image names and call `image delete` themselves to avoid leaking them — the same contract as `File`/`Socket`: keep the `Photo` object alive for as long as you need the image. The delete is routed through the cross-thread main-loop queue since finalizers can run on any thread. `Photo#delete` still works for deterministic cleanup and cancels the pending finalizer so a later-reused name can't be deleted out from under a new image. `Photo#command` is a generic passthrough (mirroring `Widget#command`) for photo subcommands with no dedicated method, such as `copy` (with `subsample:`/`zoom:`/etc.).
- `App#choose_open_file`, `#choose_save_file`, `#message_box`, `#choose_color`, and `#popup_menu` — safe wrappers for the standard Tk dialogs, built via `tcl_invoke` rather than string interpolation, so titles/paths/messages containing spaces or braces (exactly what breaks raw `tcl_eval("tk_getOpenFile -title #{title}")`-style calls) are passed through correctly. `filetypes:` accepts a plain Ruby array (`[["Images", [".png", ".jpg"]], ["All Files", "*"]]`) instead of a pre-quoted Tcl string. File/color pickers return `nil` on cancel (an array of paths if `multiple: true`); `message_box` returns the pressed button as a symbol.
- `App#on_close(window: '.') { }` (and `Widget#on_close`) — registers a `WM_DELETE_WINDOW` handler, tracked and released the same way `#bind` callbacks are, so it doesn't leak when the window is destroyed or the handler is replaced. Tk's default close behavior only applies when nothing else has claimed the protocol, so the block is entirely responsible for deciding whether the window actually closes (call `#destroy` yourself if you want it to).
- `App#winfo` — typed wrappers for Tk's `winfo` command family (`width`/`height`/`reqwidth`/`reqheight`/`rootx`/`rooty`/`x`/`y`/`pointerx`/`pointery`/`exists?`/`class_name`/`ismapped?`), grouped behind `Teek::Winfo` rather than added as more flat `App` methods, since `winfo` is itself one big, well-known Tcl command namespace — built via `tcl_invoke`, no string interpolation of the path. `Widget#width`/`#height` delegate here; `Widget#exist?` now goes through it too instead of its own raw `tcl_eval`.
- `App#wm` — the same treatment for Tk's `wm` command family: `Teek::Wm` groups `title`/`set_title`/`geometry`/`set_geometry`/`resizable`/`set_resizable`/`deiconify`/`withdraw`, built via `tcl_invoke`. Purely additive - `App`'s existing `set_window_title`/`window_title`/`set_window_geometry`/`window_geometry`/`set_window_resizable`/`window_resizable`/`show`/`hide` all still work exactly as before and now delegate here internally, which also fixes `set_window_title`'s raw-interpolation quoting bug for titles containing an unbalanced brace. `App#on_close`'s callback-tracking behavior stays a distinct top-level method rather than living on `Teek::Wm`, since it orchestrates more than a single `wm` subcommand.

### Fixed

- `App#bind` no longer leaks a Ruby callback each time an event is rebound on the same widget, and `App#unbind` now actually releases its callback (previously it never did). Destroying a widget also releases any bind callbacks it (or its descendants) held, even with `track_widgets: false`.
- `App#create_widget` and `Widget#command` no longer leak a Ruby callback for any Proc-valued option (`command:`, `validatecommand:`, etc.) — the callback is now released when the option is reconfigured or the widget is destroyed, instead of accumulating for the life of the process.
- `throw :teek_break`/`:teek_continue` inside a menu entry's or widget's `command:` proc no longer raises a Tcl error. These signals only mean something inside Tk's bind dispatch (confirmed against Tcl core: an unhandled `TCL_BREAK`/`TCL_CONTINUE` reaching the top of any other evaluation is rejected outright), so outside a bind callback they're now caught and treated as a normal return instead of being relayed to Tcl. `throw :teek_return` continues to work everywhere, as before.
- `App#set_variable`/`App#get_variable` no longer corrupt or fail on values containing Tcl-special characters (unbalanced braces, a trailing backslash, `$`, `[`) — they go through `Tcl_SetVar`/`Tcl_GetVar` directly instead of building and re-parsing a `set name {value}` string, so nothing needs escaping. Array-element (`arr(key)`) and namespaced (`::ns::var`) names both work as before.
- `App#command` no longer fails on a value containing an unbalanced `{` or `}` (e.g. `app.command(:label, path, text: "closing } brace")` previously raised `unknown option "brace}"` or `missing close-brace` depending on which side was unbalanced). The shared builder underneath `#command` and every interceptor now passes values through `tcl_invoke` (`Tcl_EvalObjv`) as a plain argv array instead of brace-quoting each one and handing a joined string to `tcl_eval` — nothing needs escaping, so there's no quoting scheme left to break out of. Array-valued options (e.g. a `ttk::treeview`'s `columns:`) now build a proper nested Tcl list via `Teek.make_list` rather than manual string joining.

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
