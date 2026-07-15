# Changelog — teek-ui

> **Alpha**: teek-ui is early and the API will change between minor versions.

All notable changes to teek-ui will be documented in this file. See the README for full usage - this is a feature list, not a tutorial.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

Nothing has shipped yet - this section is a snapshot of the current API, not a running log.

- Retained-mode build: `Teek::UI.app { |ui| ... }.run`, Tk-free until realize.
- Widgets: `ui.<widget>` for every leaf/container type, addressable via `ui[:name]`.
- Realize/validation: atomic realize; tree-wide validation surfaces every problem at once, including a grid child missing `g.cell(...)`; build methods raise `ClosedBuilderError` once realized, redirecting to `session.add`.
- Scrolling: native widgets (`list`/`text_area`/`table`/`tree`) auto-attach a scrollbar (`scroll:` opt-out, 3-level default); `canvas` opts in instead; `ui.scrollable` wraps arbitrary content; both auto-hide and support mouse wheel.
- Layout: `column`/`row` flow containers (`gap:`/`align:`/`pad:`/`grow:`), `ui.grid` for the rest, `cv.overlay(at: anchor)` to float a widget over a `ui.canvas`.
- Handles: one handle type across both phases - `.path`/`.configure`.
- Events: `on_click`/`on_right_click`/`on_drag`/`on_key`, queue before realize, wire immediately after.
- Close handling: `on_close` on windows, overridable default-destroy.
- Escape hatch: `session.app`/`#every`/`#after` post-realize, `ui.raw { |app| }` pre-realize.
- Reactive variables: `ui.var`, `bind:`, `#value`/`#value=`, `#on_change`.
- Menus: `menu_bar`/`menu`/`context_menu`, shared `item`/`separator`/`checkbox`/`radio` vocabulary.
- Windows: `ui.window`/`ui.dialog` - managed toplevels with `show`/`hide`/`modal`.
- Tabs: `ui.tabs`/`t.tab(label, name)` - `ttk::notebook`, `on_tab_changed` event.
- Split panes: `ui.split(name, orientation:)`/`s.pane(name, weight:)` - `ttk::panedwindow` with a draggable sash.
- Screens: `ui.screens` - push/pop stack for swapping displayed content.
- Modal stacking: `ui.modal` - push/pop stack for stacked dialogs, with enter/exit/focus-change callbacks.
- Dynamic UIs: `session.add` builds and realizes a subtree into an already-running app.
- Canvas items: `line`/`oval`/`polygon`/`rectangle`/`text`/`arc`/`bitmap` on a canvas handle, each returning a `CanvasItem` - `.move`/`.coords`/`.coords=`/`.configure`/`[]`/`[]=`/`.delete`/`.bring_to_front`/`.send_to_back`/`.scale`/`.bounds`; `tags:` at creation plus `.tagged(tag)` address a shared group the same way as a single item; `on_click`/`on_right_click`/`on_drag` scoped to that item/tag; `draggable` for drag-to-move with no coordinate math.
- Dialogs: `ui.open_file`/`ui.save_file`/`ui.message`/`ui.choose_color`/`ui.choose_dir`, realize-only - thin over teek core's own dialog wrappers.
