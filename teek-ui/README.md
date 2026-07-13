# Teek::UI

A DSL for building [Teek](https://github.com/jamescook/teek) (Tk) apps - sugar over teek, not a wall around it.

**This is the recommended entry point for building a teek app.** teek-ui depends on teek — installing teek-ui brings teek in automatically — and everything here compiles down to plain teek calls (`App#command`, `#bind`, and friends). Reach for bare teek directly only if you're embedding Tk in an existing app or building your own abstraction on top; most app authors want the DSL here instead.

> **Alpha**: teek-ui is early. Widgets declare into a real tree, `.run` realizes them into live Tk widgets, `column`/`row`/`grid` lay them out without touching Tk's own geometry vocabulary, `on_click`/`on_key`/etc. wire real events, `ui.var` gives widgets a shared reactive value, and `ui.menu_bar`/`ui.context_menu` cover menus - overlay layout isn't built yet.

## Quick Start

```ruby
require 'teek/ui'

Teek::UI.app(title: 'Hello') do |ui|
  # widget/layout DSL calls go here
end.run
```

`Teek::UI.app` returns the same `Teek::UI::Session` object it yields, so `.run` chains directly off the call.

## Building vs. Realizing

Building is Tk-free: the block passed to `Teek::UI.app` runs immediately, but nothing touches Tk yet - no `Teek::App`/interpreter exists until the session is **realized**. `#run` and `#run_async` both realize (create the app) before doing anything else; you can also call `#realize` directly. This is what makes a build constructible and inspectable (`session.document`) with no display, no Tk, no `package require Tk` - useful for testing UI structure in CI where teek's own Tk-backed suite can't run.

Because of this, `session.app` (and `#every`/`#after`) only work **after** realize - calling them from inside the build block itself raises `Teek::UI::NotRealizedError`, since the block runs before `.run`/`.run_async` is ever called:

```ruby
session = Teek::UI.app(title: 'Hello') do |ui|
  ui.document # fine - pure Ruby tree, no interpreter yet
  # ui.app would raise here - not realized yet
end

session.run_async
session.app.command(:label, '.greeting', text: 'Hi there') # fine now
```

Realize also validates the whole tree first - a build with a real problem (a dangling event target, two widgets in the same grid cell) raises one `Teek::UI::ValidationError` listing everything found, before any Tk call happens. A widget that's declared but never actually placed anywhere warns by default; pass `strict: true` to `#run`/`#run_async`/`#realize` to raise on that too.

## Widgets

`ui.<widget>` methods declare widgets by appending them to the build tree - they don't touch Tk until realize. A `name` makes a widget addressable later via `ui[:name]`, without holding a reference:

```ruby
session = Teek::UI.app(title: 'Hello') do |ui|
  ui.panel(:controls) do |p|
    p.text_box(:query)
    p.button(:go, text: 'Go')
  end
end
session.run # realizes the tree - .controls, .controls.query, .controls.go now exist and are visible
```

Paths are hierarchical and derived from widget names, not auto-incremented junk like `.ttkbtn7` - `ui[:go].path` above is `.controls.go`. An unnamed widget still gets a valid (if less meaningful) auto-generated path segment.

`ui[:query]` (from anywhere in the build, not just inside the block that declared it) returns a `Handle` - `.path`/`.configure` raise `Teek::UI::NotRealizedError` until realized, then act on the live widget:

```ruby
session[:query].configure(width: 40) # after session.run/.run_async/.realize
```

Leaf widgets (no children): `text_box`, `text_area`, `label`, `button`, `checkbox`, `radio`, `slider`, `dropdown`, `number_box`, `list`, `table`, `tree`, `progress`, `divider`.
Containers (take a block, nest children): `panel` (`box` is the same thing, spelled differently), `group`, `canvas`, `window`, and the layout containers below.

## Layout

`column`/`row` hide all three of Tk's geometry managers behind flexbox-style vocabulary - `pack`/`grid`/`sticky`/`anchor`/`rowconfigure`/`-weight` never appear in app code:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.column(:controls, gap: 8, align: :stretch, pad: 5) do |c|
    c.button(:start, text: 'Start')
    c.button(:pause, text: 'Pause')
    c.spacer                                  # flexible gap - pushes what follows to the bottom
    c.button(:about, text: 'About')
  end
end.run
```

- `column`/`row` - top-to-bottom / left-to-right.
- `gap:` - space between children (not before the first or after the last).
- `align:` - cross-axis placement: `:start` / `:center` / `:end` / `:stretch` (fills the cross axis) - plain words, never compass directions.
- `pad:` - margin around the whole stack.
- `grow: true` on any child (leaf or container) - it consumes leftover space along the main axis.
- `spacer` - a flexible gap (`grow: true` baked in) - the named replacement for the classic invisible "spring row" trick.

`ui.grid` is for the minority of screens flow doesn't fit - a labeled-field form, a table of inputs:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.grid(:form, gap: 4) do |g|
    g.cell(row: 0, col: 0) { g.label(text: 'Name:') }
    g.cell(row: 0, col: 1) { g.text_box(:name_field) }
    g.cell(row: 1, col: 0) { g.label(text: 'Email:') }
    g.cell(row: 1, col: 1) { g.text_box(:email_field) }
    g.stretch(columns: [1]) # the input column absorbs extra width
  end
end.run
```

- `g.cell(row:, col:, span: 1) { }` - positions the single widget its block declares. `span:` covers multiple columns.
- `g.stretch(columns:, rows:)` - which columns/rows absorb leftover space, in English instead of `columnconfigure -weight`.

`cell`/`stretch` only work directly inside a `ui.grid` block - both raise otherwise.

## Windows

`ui.window(title:, geometry:, resizable:, modal:) { }` is a managed toplevel - unlike the plain container types, it wires up the wm-level bookkeeping a secondary window actually needs (title, initial geometry, resizable, transient-to-its-parent, macOS's shared-menubar quirk) and starts **withdrawn** - it isn't shown until you call `.show`:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  settings = ui.window(:settings, title: 'Settings', geometry: '400x300', resizable: false) do |w|
    w.button(:close, text: 'Close').on_click { settings.hide }
  end
  ui.button(:open_settings, text: 'Settings...').on_click { settings.show }
end.run
```

`.show` positions the window just to the right of whichever window it's nested under (root, or an enclosing `ui.window`), deiconifies, raises it to the front, and - only if declared `modal: true` - grabs input and focus too (see `modal`/`grab_release` below). `.hide` releases any grab and withdraws it. `resizable:` takes a single Boolean for both axes, or a `[width, height]` pair.

`ui.dialog(...)` is `ui.window` with defaults flipped for the common "small modal window" case - `modal: true`, `resizable: false` - both still overridable:

```ruby
ui.dialog(:confirm) { |d| d.label(text: 'Discard changes?') }
session[:confirm].show   # grabs and focuses automatically - it's a dialog
```

Every other container (`panel`/`group`/`canvas`) still just packs its children top-to-bottom with no options - reach for `column`/`row`/`grid` when you actually want control over spacing/alignment/positions. Overlay layout isn't built yet.

## Events

A handle's `on_*` methods wire real Tk events - intent-named, so nobody needs to know Tk's own event syntax:

```ruby
session[:go].on_click { puts 'clicked' }
session[:go].on_right_click { show_context_menu }
session[:area].on_drag { |x, y| puts "#{x},#{y}" }        # Integer, canvas-converted when bound to a canvas
session[:query].on_key(:enter) { search }                  # friendly keysym
session[:query].on_key('Ctrl-s') { save }                   # "Ctrl"/"Alt"/"Shift"/"Cmd", spelled the obvious way
```

Called before realize (the normal case, right after declaring a widget), these queue on the widget and wire once the whole tree realizes. Called after, they wire immediately - same method, correct behavior either way.

A `ui.window` handle also gets `on_close`, for the titlebar close box (and its platform equivalents, Cmd-W/Alt-F4):

```ruby
settings = ui.window(:settings)
settings.on_close { session.app.destroy(settings.path) if confirm_discard_changes? }
```

The same `ui.window` handle also gets `modal`/`grab_release`, for dialogs that should block interaction with the rest of the app while open. Unlike the queue-then-wire events above, these only make sense once the window is actually realized (there's nothing to grab before it exists), so they raise `NotRealizedError` before that rather than queuing:

```ruby
settings.modal            # grabs input and focuses the window - stays grabbed
# ... later, from the window's own on_close/a Done button ...
settings.grab_release
```

`modal` also takes an optional block that runs with the grab already set (typically the rest of the window's own show sequence), and releases the grab immediately if that block raises, or if the window is destroyed while still grabbed - see `Teek::Window#modal` in base teek, which this delegates to entirely.

Teek's own default (destroy the window) only applies if nothing has claimed `on_close` - once a block is set, it decides whether the window actually closes.

## Reactive Variables

`ui.var(initial)` wraps a Tcl variable - bind it to more than one widget and they stay in sync for free, via Tk's own `-textvariable`/`-variable` machinery, no manual event wiring needed:

```ruby
session = Teek::UI.app(title: 'Hello') do |ui|
  speed = ui.var(5)
  ui.slider(:speed_slider, from: 1, to: 10, bind: speed)
  ui.label(:speed_label, bind: speed)     # updates automatically as the slider moves
  speed.on_change { |v| puts "speed is now #{v}" }
end
session.run
```

`var.value`/`var.value =` read and write it directly (typed to match the initial value - Integer/Float/Boolean, else String); `var.on_change { |v| }` fires with the coerced value on every change, regardless of whether Ruby or a bound widget caused it. `bind:` is mapped per widget type (`text_box`/`label`/`dropdown`/`number_box` use `-textvariable`; `checkbox`/`slider`/`progress` use `-variable`) - widgets without a sensible single bindable value (`text_area`, `list`, `table`/`tree`, `radio`, containers) raise if you try.

## Menus

`ui.menu_bar { }` declares a window's menu bar - the row of dropdowns (File/Edit/...) along its top edge - attaching automatically to whichever window it's declared in (the top level of the build, or directly inside `ui.window`). `.menu(label:) { }` is one recursive method for every dropdown, nested cascade, or submenu - there's no separate Tk `cascade`/`tearoff` vocabulary to learn:

```ruby
Teek::UI.app(title: 'Editor') do |ui|
  wrap = ui.var(false)

  ui.menu_bar do |mb|
    mb.menu(label: 'File') do |file|
      file.item(label: 'Open...', accelerator: 'Cmd+O') { open_file }
      file.separator
      file.menu(label: 'Recent') do |recent|
        recent.item(label: 'notes.txt') { open_recent('notes.txt') }
      end
      file.item(label: 'Quit') { exit }
    end
    mb.menu(label: 'Edit') do |edit|
      edit.checkbox(label: 'Word Wrap', bind: wrap)
    end
  end
end.run
```

Inside a `menu_bar`/`menu`/`context_menu` block, `item`/`separator`/`checkbox`/`radio` build entries - a deliberately separate, small vocabulary from the top-level widget DSL (`checkbox`/`radio` here mean menu entries, not the `ttk::checkbutton`/`ttk::radiobutton` *widgets* of the same name one level up). `checkbox`/`radio` reuse the same `bind:` reactive-variable convention widgets do; `radio` entries sharing one `bind:` var each set it to their own `value:` when chosen.

A **context menu** is a standalone popup, built the same way but not attached to anything automatically - wire it to a widget with `on_right_click`:

```ruby
Teek::UI.app(title: 'Editor') do |ui|
  ctx = ui.context_menu(:card_menu) { |m| m.item(label: 'Delete') { delete_card } }
  ui.canvas(:board).on_right_click(ctx)
end.run
```

`on_right_click` still takes a plain block too, same as before - a menu handle and a block are alternatives, not both at once.

## Escape Hatch

Nothing here is a sandbox - the DSL is sugar, not a wall, and there are two ways to drop to plain teek depending on when you need it.

**After realize**, every session exposes the live `Teek::App` directly:

```ruby
session = Teek::UI.app(title: 'Hello').run_async
session.app.command(:label, '.greeting', text: 'Hi there')
session.app.tcl_eval('pack .greeting')
```

**During build**, `session.app` doesn't exist yet (see "Building vs. Realizing" above) - a widget doesn't have a Tk path yet either, so there's nothing for `app.command(handle.path, ...)` to act on mid-build. `ui.raw { |app| ... }` is the build-time escape hatch instead: it records the block and defers it to realize, where it runs with the real, live app. It's a closure, so it can still reference sibling widgets by name even if they're declared later in the build - by the time any `ui.raw` block runs, the whole tree has already been realized once over, the same forward-reference guarantee event `target:` gets:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.raw { |app| app.command(ui[:later].path, :configure, text: 'Changed by raw') } # runs at realize
  ui.button(:later, text: 'Original') # declared after, still resolves - forward reference
end.run
```

So: `ui.raw` for build-time raw work, `session.app` (or a realized `Handle`) for anything after.

## Dynamic UIs

"Nothing happens until realize" describes the *initial* declaration only - `session.add(parent_name) { }` builds a subtree with the exact same widget DSL and realizes just that subtree immediately, as a child of an already-realized widget, for UIs that grow after the window is already up (adding rows to a list, rebuilding a menu on right-click):

```ruby
session = Teek::UI.app(title: 'Hello') { |ui| ui.column(:list) }.run_async

session.add(:list) { |a| a.button(:item1, text: 'Item 1').on_click { puts 'clicked!' } }
```

The new widgets route through the same `Teek::App#command`/leak-cleanup path the initial realize uses - destroying one reclaims its callbacks the normal way. `parent_name` must already be realized; calling `add` before the session itself is realized, or naming a widget that doesn't exist, raises.

## Interactive / REPL Use

`#run` blocks on the Tk event loop, which isn't REPL-friendly. `#run_async` realizes, shows the window, and returns immediately instead - but it doesn't (yet) service the event loop automatically between prompts, so call `ui.app.update` yourself to process pending events while exploring:

```ruby
session = Teek::UI.app(title: 'Hello').run_async
session.app.update # process events after each change
```

## Timers

`#every`/`#after` also require realize first:

```ruby
session = Teek::UI.app(title: 'Hello').run_async
session.every(1000) { puts 'tick' }
session.after(500) { puts 'once' }
session.app.mainloop
```
