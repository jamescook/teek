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

## Authoring the Build Block

The block passed to `Teek::UI.app` is plain Ruby, run via a single `.call` - not parsed, not a mini-language of its own. Loops, conditionals, and helper methods are all welcome; they just decide which `ui.<widget>` calls actually run, and in what order:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.column do |c|
    %w[Start Pause Reset].each { |label| c.button(text: label) }
    c.label(text: 'Ready') if some_condition
  end
end.run
```

A couple of things follow from that:

- Keep the block itself pure and fast - it decides *what* gets built, so it shouldn't also be doing network/file I/O. Anything slow belongs behind an event handler (`on_click { ... }`), not inline in the build.
- Build on one thread. The stack `ui.<container> { }` pushes/pops to track "what's the current parent" isn't synchronized - calling DSL methods on the same session from multiple threads at once will corrupt it.

The build only ever gets walked into Tk once, at realize. Calling a build method (`ui.button`, `ui.panel`, `ui.raw`, `ui.var`, ...) on a session that's already realized raises `Teek::UI::ClosedBuilderError` rather than silently appending a node that will never show up - use `session.add(parent_name) { }` instead for anything you need to build after the app is already running.

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

## Canvas Items

A `canvas` handle draws shapes directly - closer to SVG's persistent, addressable elements than HTML5 `<canvas>`'s paint-and-forget pixels: every shape method returns a live `CanvasItem` you can move, restyle, or delete later, not just ink on a bitmap.

```ruby
session = Teek::UI.app(title: 'Hello') do |ui|
  ui.canvas(:board, width: 400, height: 300)
end.run

ball = session[:board].oval(10, 10, 40, 40, fill: 'red', tags: 'movable')
ball.move(20, 0)              # relative shift
ball.coords = [10, 10, 60, 60]  # replace the coordinate list outright
ball[:fill] = 'blue'          # read/write a single option
ball.configure(outline: 'black', width: 2) # or several at once
ball.bring_to_front           # stacking order (send_to_back is the opposite)
ball.delete
```

Shape methods - `line`, `oval`, `polygon`, `rectangle`, `text`, `arc`, `bitmap` - take coordinates flat or nested (`line(0, 0, 10, 10)` and `line([0, 0], [10, 10])` are equivalent) plus real Tk item options (`fill:`, `outline:`, `width:`, `font:`, ...) passed straight through, same as every other widget option in the DSL.

`tags:` at creation time groups items - `ui[:board].tagged('movable')` addresses every item currently carrying that tag as one `CanvasItem`, so `.move`/`.configure`/`.delete` apply to the whole group at once. A single-item handle from a shape method and a tag-scoped group handle from `tagged` are the same type, working identically either way (this mirrors how Tk's own canvas commands already treat a tag and an id the same way) - `.exists?` tells you whether a tag currently matches anything.

Items also take the same `on_click`/`on_right_click`/`on_drag` vocabulary as widgets, scoped to that specific item/tag rather than the whole canvas:

```ruby
ball.on_click { ball[:fill] = 'green' }
ball.on_drag { |x, y| ball.coords = [x - 15, y - 15, x + 15, y + 15] }
```

For the common case of "let the user drag this around", `draggable` does that `on_drag` delta math for you:

```ruby
ball.draggable
```

A canvas can also float ordinary widgets on top of its own content - a status readout, a button bar - via `overlay`, a "use sparingly" escape valve for the one legitimate absolute-position case:

```ruby
ui.canvas(:board, width: 400, height: 300) do |cv|
  cv.overlay(at: :top_left) { ui.label(:status, text: 'Ready') }
  cv.overlay(at: :bottom_right) { ui.row { ui.button(:pause, text: 'Pause') } }
end
```

`at:` is a corner/edge/center anchor (`:top_left`, `:top`, `:top_right`, `:left`, `:center`, `:right`, `:bottom_left`, `:bottom`, `:bottom_right`) - plain English standing in for Tk's own `place -relx/-rely/-anchor`, so it stays correctly positioned across a canvas resize with nothing to redo by hand.

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

## Scrolling

A bare `list`/`text_area`/`table`/`tree` auto-attaches a working scrollbar wherever it's declared - no wrapper, no `-yscrollcommand`/`-xscrollcommand`/scrollbar widget wiring in app code:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.list(:log)                    # already scrolls
  ui.list(:log, scroll: false)     # opt out - a plain, unwrapped listbox, like every other widget
end.run
```

The scrollbar only shows up once content actually overflows - real "overflow: auto", not a bar that's always there whether it's needed or not. `canvas` defaults the other way (`scroll: false`) since it's as often fixed drawing as scrollable content; pass `scroll: true` to opt it in. `x:`/`y:` pick which axis gets a scrollbar (`y: true, x: false` by default).

Three levels decide the default, most specific wins: a widget's own `scroll:`, then `Teek::UI.app(scroll:)` for the whole build, then the global `Teek::UI.auto_scroll`/`Teek::UI.auto_scroll_canvas`:

```ruby
Teek::UI.auto_scroll = false                              # turn auto-scrolling off everywhere, app-wide default
Teek::UI.app(title: 'Hello', scroll: false) do |ui|        # ...or just for this one build
  ui.list(:log)                    # follows the app-level default (off)
  ui.list(:log2, scroll: true)     # a widget's own scroll: always wins
end.run
```

`ui.scrollable(x: false, y: true) { }` is for the other case: a scrollbar around *arbitrary* content, since a plain container has no Tk scrolling protocol of its own to hook a scrollbar into:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.scrollable { |s| s.column { |c| 50.times { |i| c.label(text: "Row #{i}") } } }
end.run
```

It wraps its content in an embedded frame that a scrollbar drives, filling the visible width automatically unless `x:` scrolling is on. Same `x:`/`y:` options, same auto-hide behavior.

Mouse-wheel scrolling works for both - over the scrollbar, the content, or any widget nested inside it - `<MouseWheel>` (Windows/macOS) and `<Button-4>`/`<Button-5>` (X11) all drive the same scroll, and `Shift`+wheel scrolls horizontally when `x:` is on.

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

## Tabs

`ui.tabs { }` is a `ttk::notebook`; `t.tab(label, name = nil) { }` declares one page, only valid directly inside it:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.tabs(:settings) do |t|
    t.tab('General') { |g| g.checkbox(text: 'Dark mode') }
    t.tab('Advanced', :advanced_tab) { |a| a.label(text: 'Here be dragons') }
  end
  ui[:settings].on_tab_changed { |tab| puts "switched to #{tab}" }  # :advanced_tab, or 0/1 if unnamed
end.run
```

A tab's content is an ordinary DSL subtree - name widgets inside it and address them the normal way. `on_tab_changed` surfaces Tk's `<<NotebookTabChanged>>`, delivering the newly selected tab's own name if it has one, otherwise its zero-based index. New tabs can be added at runtime via `session.add`.

## Split Panes

`ui.split(name = nil, orientation: :horizontal) { }` is a `ttk::panedwindow`; `s.pane(name = nil, weight: nil) { }` declares one region, only valid directly inside it:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.split(:main, orientation: :horizontal) do |s|
    s.pane(weight: 1) { |a| a.list(:files) }
    s.pane(weight: 3) { |b| b.text_area(:editor) }
  end
end.run
```

`:horizontal` lays panes out side by side with a vertical sash; `:vertical` stacks them with a horizontal sash - dragging the sash between two panes resizes them, same as any native split view. `weight:` sets how much of the leftover space a pane absorbs when the split is resized, relative to its sibling panes' weights (the same word `ttk::panedwindow` itself uses) - a pane left unset gets Tk's own default (fixed size until dragged). A pane's content is an ordinary DSL subtree - name widgets inside it and address them the normal way. New panes can be added at runtime via `session.add`.

## Screens

`ui.screens` is a push/pop stack for swapping which content is on display - pushing conceals whatever screen was on top (if any) before revealing the new one; popping reverses that. It works directly against ordinary handles, so there's no bespoke per-screen class to write:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.panel(:picker) { |p| p.button(:play, text: 'Play').on_click { ui.screens.push(:emulator, ui[:emulator]) } }
  ui.panel(:emulator) { |p| p.button(:back, text: 'Back').on_click { ui.screens.pop } }
end.run
```

A `ui.window` screen is revealed/concealed through its own `.show`/`.hide` (deiconify/raise/modal, or grab-release/withdraw); any other handle (`panel`/`box`/`group`/...) is packed to fill its parent, or pack-forgotten - the plain `pack`/`pack forget` primitive. `ui.screens.replace_current(handle)` swaps the current screen in-place without changing stack depth (same name, new content); `.current`/`.current_screen`/`.size`/`.active?` read the stack's state without mutating it.

A container is packed the normal way as soon as it's realized, regardless of `ui.screens` - so two sibling panels declared as candidate screens are *both* visible until `ui.screens` has touched them. Push every candidate once during setup (each push conceals whichever came before, so only the last one stays visible), or use `ui.window` for screens that shouldn't show up until pushed - it starts withdrawn already, with no setup-time push needed.

## Modal Stacking

`ui.modal` is a push/pop stack for modal dialog windows, so one dialog can push another (Settings → Replay Player) with the previous one automatically re-shown once the new one is dismissed. Unlike `ui.screens`, it isn't created automatically - assign it yourself, since its `on_enter:`/`on_exit:` callbacks are mandatory and app-specific (e.g. pausing/resuming whatever's running underneath):

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.modal = Teek::UI::ModalStack.new(
    on_enter: ->(name) { pause_emulation },
    on_exit: -> { unpause_emulation },
  )
  ui.dialog(:settings) { |d| d.button(:replay, text: 'Replay...').on_click { ui.modal.push(:replay, ui[:replay]) } }
  ui.dialog(:replay) { |d| d.button(:close, text: 'Close').on_click { ui.modal.pop } }
end.run
```

`.push(name, handle)`/`.pop` reveal/conceal exactly like `ui.screens` (it wraps one internally) - the difference is the lifecycle: `on_enter` fires once, the first time the stack goes from empty to non-empty; `on_exit` fires once, when the last dialog pops and the stack goes back to empty; `on_focus_change`, if given, fires with the new top's name on every push and every pop that still leaves a dialog underneath. `.current`/`.size`/`.active?` read the stack's state. Push a handle declared `modal: true` (`ui.dialog` already defaults to this) so `.show` actually grabs input - `ui.modal` itself doesn't grab anything on its own.

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

One caveat either way: don't issue a raw `pack`/`grid` call against a master the DSL already manages (a `column`/`row`/`grid`/etc.'s own Tk frame) - Tk allows exactly one geometry manager per master, and mixing them raises a clear `Teek::TclError` immediately rather than silently hanging, but the DSL has no way to catch the mistake for you up front since it can't see inside an escape-hatch block.

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

## Dialogs

The standard native dialogs are reachable directly on `ui` - also realize-only, same as the timers above:

```ruby
path = ui.open_file(filetypes: [['Images', ['.png', '.jpg']]])
ui.save_file(initialfile: 'export.png')
answer = ui.message(message: 'Delete this?', type: :yesno)
color = ui.choose_color(initial: '#3366ff')
dir = ui.choose_dir(title: 'Pick a project folder')
```

Each returns `nil` if the user cancels (`ui.message` returns the pressed button as a Symbol - `:ok`/`:yes`/`:no`/... - instead, since there's no single "cancelled" case across every button layout). See `Teek::App#choose_open_file`/`#choose_save_file`/`#message_box`/`#choose_color`/`#choose_dir` for every option.

## Clipboard

`ui.clipboard` reads/writes the clipboard directly - also realize-only:

```ruby
ui.clipboard.set('copied text')
ui.clipboard.get # => "copied text", or nil if empty
```

`text_box`/`text_area` don't need this at all for their own copy/cut/paste - the standard platform keys (Ctrl/Cmd-C/X/V) already work with zero wiring, since that's Tk's own built-in behavior on every text-editing widget.
