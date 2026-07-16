# Changelog — teek-ui

> **Alpha**: teek-ui is early and the API will change between minor versions.

All notable changes to teek-ui will be documented in this file. See the README for full usage - this is a feature list, not a tutorial.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.1.0] - 2026-07-16

- Retained-mode build: `Teek::UI.app { |ui| ... }.run`, Tk-free until realize.
- Widgets: `ui.<widget>` for every leaf/container type, addressable via `ui[:name]`.
- Components: `ui.component { }` opens a scope so local names never collide with another component's (or the top level's) same name - splices its content into whatever's already open, not an extra container; plain threaded-builder methods (`def foo(ui) = ...`) need none of this and keep working unchanged. Returns a facade (`.handle(:name)`/`[]`) so a parent can address the component's own named widgets from outside it without reaching through the global `ui[]`. Mountable more than once, including several times directly under one shared parent, with no Tk path collision even when every instance reuses the same local names.
- Realize/validation: atomic realize; tree-wide validation surfaces every problem at once, including a grid child missing `g.cell(...)`; build methods raise `ClosedBuilderError` once realized, redirecting to `session.add`.
- Scrolling: native widgets (`list`/`text_area`/`table`/`tree`) auto-attach a scrollbar (`scroll:` opt-out, 3-level default); `canvas` opts in instead; `ui.scrollable` wraps arbitrary content; both auto-hide and support mouse wheel.
- Layout: `column`/`row` flow containers (`gap:`/`align:`/`pad:`/`grow:`), `ui.grid` for the rest, `cv.overlay(at: anchor)` to float a widget over a `ui.canvas`.
- Handles: one handle type across both phases - `.path`/`.configure`/`.enable`/`.disable`/`.destroy!` (auto-defers to the next idle point when called from inside a callback, so a widget can safely tear down its own containing window from its own click handler - `defer:` overrides either way).
- Events: `on_click`/`on_right_click`/`on_drag`/`on_key`, queue before realize, wire immediately after.
- Close handling: `on_close` on windows, overridable default-destroy.
- Escape hatch: `session.app` post-realize, `ui.raw { |app| }` pre-realize.
- Timers: `#every`/`#after` - queue-then-wire like events, declarable inside the build block or after realize.
- Reactive variables: `ui.var`, `bind:`, `#value`/`#value=`, `#on_change`.
- Event bus: `ui.on`/`ui.emit`/`ui.off` - in-process pub/sub for decoupled widgets, app-scoped (not a global singleton), works before realize.
- Menus: `menu_bar`/`menu`/`context_menu`, shared `item`/`separator`/`checkbox`/`radio` vocabulary; named `item`/`checkbox`/`radio` entries are addressable via `ui[:name]`, immune to entry renumbering.
- Windows: `ui.window`/`ui.dialog` - managed toplevels with `show`/`hide`/`modal`.
- Tabs: `ui.tabs`/`t.tab(label, name)` - `ttk::notebook`, `on_tab_changed` event.
- Split panes: `ui.split(name, orientation:)`/`s.pane(name, weight:)` - `ttk::panedwindow` with a draggable sash.
- Screens: `ui.screens` - push/pop stack for swapping displayed content. A `lazy: true` panel/window isn't realized until first pushed; `.pop` returns the popped screen, and `handle.destroy!` tears it down for good (`ui.screens.pop&.destroy!`).
- Modal stacking: `ui.modal` - push/pop stack for stacked dialogs, with enter/exit/focus-change callbacks. Same `lazy: true`/`.pop&.destroy!` support as `ui.screens` (`document:` on `ModalStack.new`).
- Dynamic UIs: `session.add` builds and realizes a subtree into an already-running app.
- Canvas items: `line`/`ellipse`/`polygon`/`rectangle`/`text`/`arc`/`bitmap` on a canvas handle, each returning a `CanvasItem` - `.move`/`.points`/`.points=`/`.configure`/`[]`/`[]=`/`.delete`/`.bring_to_front`/`.send_to_back`/`.scale`/`.bounds`; `tags:` at creation plus `.tagged(tag)` address a shared group the same way as a single item; `on_click`/`on_right_click`/`on_drag` scoped to that item/tag; `draggable` for drag-to-move with no coordinate math.
- Images: `ui.image(path)` - queue-then-load like `ui.var`; pass the result as `image:` on a `label`/`button`, swap it later via `configure(image: ...)`. GC-owned via teek core's `Teek::Photo` (`.photo` reaches the live one).
- Dialogs: `ui.open_file`/`ui.save_file`/`ui.message`/`ui.choose_color`/`ui.choose_dir`, realize-only - thin over teek core's own dialog wrappers.
- Clipboard: `ui.clipboard.set`/`.get`/`.clear`, realize-only; `text_box`/`text_area` copy/cut/paste already work via Tk's own built-in key bindings, nothing to wire up.
- Toast: `session.toast(message, duration:)` - transient auto-dismissing notification, replaces rather than stacks.
- Busy cursor: `session.busy(window:) { }` - thin block wrapper over teek core's `App#busy`.
- Text content: `handle.text_content` on a `text_area` - insert/get/delete/replace/value/value=/clear; named formats (`format`/`apply_format`/`clear_format`/`delete_format`/`format_ranges`, leak-safe `on_format_click`/`on_format`); markers (`add_marker`/`remove_marker`/`markers`); `search`; `scroll_to`/`cursor`/`cursor=`/`read_only`/`read_only=`; `insert_image`. Every method has a Tk-named alias (`tag_configure`, `mark_set`, `see`, ...).
- Debug info: `session.debug_info` - live callback counts by kind, for spotting leaks; `run(debug:)`/`run_async(debug:)` print the same summary to stderr.
- Introspection: `session.find_by_path(path)` - reverse path-to-widget lookup; `handle.events` - live event bindings; `handle.options` - live Tk option dump.
- Build-phase debugging: `Teek::UI::TreeInspector` - ASCII tree of the current build + opt-in assembly trace; `builder.current_path` - build-parent breadcrumb.
- Friendly/Tk aliasing: every wrapped Tk concept is reachable by both a friendly name and its original Tk name (`ellipse`/`oval`, `points`/`coords`, `release_focus`/`grab_release`, `shortcut:`/`accelerator:`, ...) - see the README's alias table.
