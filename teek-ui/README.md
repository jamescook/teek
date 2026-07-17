# Teek::UI

**The friendly way to build Tk apps in Ruby.** A DSL over [Teek](https://github.com/jamescook/teek) — sugar over Tk's plumbing, not a wall around it.

**This is the recommended entry point for building a teek app.** teek-ui depends on teek — installing teek-ui brings teek in automatically — and everything compiles down to plain teek calls, so you can always drop to bare teek when you need to.

> **Alpha**: teek-ui is early, but real: widgets, flexbox-style layout, events, reactive vars, menus, canvas, windows/dialogs, rich text, and images all work. Overlay layout isn't built yet.

Method and option names are the newcomer-friendly ones; every Tk name still works as an alias (see [Friendly vs. Tk Names](#friendly-vs-tk-names)). Deep detail beyond this guide lives in the API docs.

## Quick Start

```ruby
require 'teek/ui'

Teek::UI.app(title: 'Hello') do |ui|
  # widget/layout DSL calls go here
end.run
```

`Teek::UI.app` returns the `Teek::UI::Session` it yields, so `.run` chains right off it.

## Your First App

A complete, runnable app using only the core — widgets, layout, an event, and a shared reactive value:

```ruby
require 'teek/ui'

Teek::UI.app(title: 'Greeter') do |ui|
  name = ui.var('')                              # a shared, reactive value

  ui.column(gap: 8, pad: 12, align: :stretch) do |c|
    c.label(text: "What's your name?")
    c.text_box(:name_field, bind: name)          # two-way bound to `name`
    c.button(:greet, text: 'Greet')
    c.label(:greeting)
  end

  greet = -> { ui[:greeting].configure(text: "Hello, #{name.value}!") }
  ui[:greet].on_click(&greet)                     # click the button...
  ui[:name_field].on_key(:enter, &greet)          # ...or just press Enter
end.run
```

You *describe* the UI in the block; `.run` *builds* it into real Tk widgets and starts the app — like writing HTML, then loading the page. The four sections that follow are the rest of that core; everything past **Going further** is optional.

## Widgets

`ui.<widget>` declares a widget in the build tree. A `name` makes it addressable via `ui[:name]` (returns a `Handle`) without holding a reference:

```ruby
session = Teek::UI.app(title: 'Hello') do |ui|
  ui.panel(:controls) do |p|
    p.text_box(:query)
    p.button(:go, text: 'Go')
  end
end.run

session[:query].configure(width: 40)  # after realize
session[:query].disable                # shorthand for configure(state: :disabled)
```

Paths derive from names (`ui[:go].path` is `.controls.go`), not `.ttkbtn7` junk.

Leaf widgets: `text_box`, `text_area`, `label`, `button`, `checkbox`, `radio`, `slider`, `dropdown`, `number_box`, `list`, `table`, `tree`, `progress`, `divider`.
Containers (take a block): `panel` (alias `box`), `group`, `canvas`, `window`, plus the layout containers below.

## Layout

`column`/`row` hide all three Tk geometry managers behind flexbox vocabulary — `pack`/`grid`/`sticky`/`-weight` never appear in app code:

```ruby
ui.column(:controls, gap: 8, align: :stretch, pad: 5) do |c|
  c.button(:start, text: 'Start')
  c.button(:pause, text: 'Pause')
  c.spacer                            # flexible gap - pushes what follows down
  c.button(:about, text: 'About')
end
```

- `gap:` — space between children. `pad:` — margin around the stack.
- `align:` — cross-axis: `:start` / `:center` / `:end` / `:stretch`.
- `grow: true` on any child — it consumes leftover space on the main axis (`spacer` is a child with `grow` baked in).

`ui.grid` is for what flow doesn't fit — forms, input tables:

```ruby
ui.grid(:form, gap: 4) do |g|
  g.cell(row: 0, col: 0) { g.label(text: 'Name:') }
  g.cell(row: 0, col: 1) { g.text_box(:name_field) }
  g.stretch(columns: [1])   # the input column absorbs extra width
end
```

`g.cell(row:, col:, span: 1)` positions the widget its block declares; `g.stretch(columns:, rows:)` picks which absorb slack. Both only work inside `ui.grid`.

## Events

`on_*` methods wire real Tk events under intent-named methods — no Tk event syntax:

```ruby
session[:go].on_click { puts 'clicked' }
session[:go].on_right_click { show_context_menu }
session[:query].on_key(:enter) { search }       # friendly keysym
session[:query].on_key('Ctrl-s') { save }        # Ctrl/Alt/Shift/Cmd, spelled out
session[:area].on_drag { |x, y| puts "#{x},#{y}" }
```

Declared before realize they queue and wire automatically; after realize they wire immediately — same method either way. A `ui.window` handle also gets `on_close` (titlebar/Cmd-W/Alt-F4) and `modal`/`release_focus` (input grab for dialogs). See the API docs for the modal grab lifecycle.

## Reactive Variables

`ui.var(initial)` wraps a Tcl variable — bind it to more than one widget and they stay in sync for free, no event wiring:

```ruby
speed = ui.var(5)
ui.slider(:speed_slider, from: 1, to: 10, bind: speed)
ui.label(:speed_label, bind: speed)     # updates as the slider moves
speed.on_change { |v| puts "speed is now #{v}" }
```

`var.value` / `var.value =` read and write directly (typed to the initial value); `on_change` fires on every change from either side. `bind:` works on the single-value widgets (`text_box`/`label`/`dropdown`/`number_box`/`checkbox`/`slider`/`progress`); multi-value widgets raise.

## Talking Between Widgets

Four tools, most-direct to most-decoupled — start at the top, move down only when you need the decoupling:

| Reach for | When |
| --- | --- |
| **A handle** — `ui[:name].configure(...)` | A one-off, direct update: this button updates that label. |
| **A reactive var** — `ui.var` + `bind:` | Widgets stay in sync with one value automatically. See [Reactive Variables](#reactive-variables). |
| **A component facade** — `ui.component` + `screen[:name]` | A parent reaches a reusable subtree's widgets without a global name. See [Components](#components). |
| **The event bus** — `ui.on` / `ui.emit` | Unrelated widgets react and the sender shouldn't know they exist. See [Event Bus](#event-bus). |

---

## Going further

Everything above is a complete app. The rest is power you reach for when a screen needs it — read it as needed, not in order.

## Building vs. Realizing

Building is Tk-free: the block runs immediately, but no `Teek::App`/interpreter exists until the session is **realized** by `#run`/`#run_async`/`#realize`. That's what makes a build inspectable (`session.document`) with no display — useful for headless testing.

A few things only work **after** realize and raise `Teek::UI::NotRealizedError` before it: `session.app`, `modal`/`release_focus`, the standard dialogs, and `ui.clipboard`. In practice this rarely bites, since they're normally called from an `on_*` handler (which only runs post-realize). Events and timers are the exception — they queue before realize and wire themselves, so they read fine inside the build block.

Realize validates the tree first: a real problem (dangling event target, two widgets in one grid cell) raises one `Teek::UI::ValidationError` listing everything. An unplaced widget warns; `strict: true` promotes that to a raise.

## Authoring the Build Block

The block is plain Ruby run via `.call` — loops, conditionals, and helper methods all work; they just decide which `ui.<widget>` calls run:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.column do |c|
    %w[Start Pause Reset].each { |label| c.button(text: label) }
    c.label(text: 'Ready') if some_condition
  end
end.run
```

Keep it pure and single-threaded (slow work belongs behind an event handler). Building on an already-realized session raises `ClosedBuilderError` — use `session.add(parent_name) { }` to grow the UI after it's running (see [Dynamic UIs](#dynamic-uis)).

## Components

A retained tree is a plain Ruby value, so splitting a big build across files is just splitting a value. Two ways, and most apps only need the first:

```ruby
# 1. A plain method that takes `ui` and appends into whatever's open:
def toolbar(ui, on_save:)
  ui.row(gap: 8) { |r| r.button(text: 'Save').on_click { on_save.call } }
end

# 2. `ui.component { }` when you also want name-scope isolation:
def sidebar(ui)
  ui.component { |c| c.button(:save, text: 'Save') }  # this :save can't collide
end

Teek::UI.app(title: 'Editor') do |ui|
  ui.panel(:top) { |p| toolbar(p, on_save: -> { save }) }
  screen = ui.panel(:side) { |p| sidebar(p) }
  screen[:save].on_click { save }   # facade: reach the component's own names
end.run
```

`ui.component` splices content in place (scope isolation, not a container) and returns a facade — `screen[:name]` reaches its named widgets from outside; the global `ui[:name]` can't see in. It's mountable more than once, each instance getting its own scope and facade. See the API docs for the scoping rules.

## Canvas Items

A `canvas` handle draws persistent, addressable shapes — closer to SVG than an HTML5 paint-and-forget `<canvas>`. Every shape method returns a live `CanvasItem`:

```ruby
board = session[:board]   # ui.canvas(:board, width: 400, height: 300)
ball = board.ellipse(10, 10, 40, 40, fill: 'red', tags: 'movable')
ball.move(20, 0)
ball.points = [10, 10, 60, 60]        # replace coordinates
ball[:fill] = 'blue'                  # read/write one option
ball.bring_to_front                   # (send_to_back is the opposite)
ball.on_click { ball[:fill] = 'green' }
ball.draggable                        # drag-to-move, no coordinate math
```

Shapes: `line`, `ellipse` (Tk: `oval`), `polygon`, `rectangle`, `text`, `arc`, `bitmap` — coordinates flat or nested, plus Tk item options passed straight through. `board.tagged('movable')` addresses every item with that tag as one `CanvasItem`. Items take the same `on_click`/`on_right_click`/`on_drag` as widgets.

`overlay` floats ordinary widgets over the canvas at a plain-English anchor (`:top_left`, `:center`, `:bottom_right`, ...), a "use sparingly" absolute-position escape valve:

```ruby
ui.canvas(:board, width: 400, height: 300) do |cv|
  cv.overlay(at: :top_left) { ui.label(:status, text: 'Ready') }
end
```

## Text Content

A `text_area` handle's `text_content` is its full rich-text API — text, named formats, markers, search, embedded images:

```ruby
log = session[:log].text_content        # ui.text_area(:log)
log.insert(:end, 'started up')
log.value                               # => "started up"

log.format(:error, foreground: 'red', font: ['Courier', 10, :bold])  # define
log.apply_format(:error, '3.0', '3.end')                             # apply to a range
log.on_format_click(:error) { ... }                                  # leak-safe binding
log.add_marker(:checkpoint, at: :cursor)
log.scroll_to(:end)
log.insert_image(:end, image: logo)
```

- **Indices** are Tk's own text-index strings passed through (`"1.0"`, `"end"`, `"insert +1 line"`, `"@12,34"`, a marker name); `:end` and `:cursor` are symbol shortcuts.
- **Content**: `insert`, `get`, `delete`, `replace`, `value`/`value=`, `clear`.
- **Formats** (Tk "tags", renamed — a reusable named style, like a CSS class): `format`, `apply_format`, `clear_format`, `delete_format`, `format_ranges`, `on_format_click`.
- **Markers** (floating bookmark positions): `add_marker`, `remove_marker`, `markers`.
- **Other**: `search`, `scroll_to`, `cursor`/`cursor=`, `read_only`/`read_only=`.

Mutating methods transparently work on a `state: :disabled` (read-only) widget — an appending read-only log pane just works with no state juggling. Every friendly name has a Tk alias (`tag_add`, `mark_set`, `see`, ...). Not wrapped (escape-hatch only): embedded live widgets, the undo/redo stack, `dump`, peer widgets.

## Images

`ui.image(path)` loads an image for a `label`/`button`'s `image:` — same build-then-realize shape as `ui.var`:

```ruby
icon = ui.image('assets/logo.png')
ui.label(:logo, image: icon)
# later: session[:logo].configure(image: another_icon)
```

Backed by teek's `Teek::Photo` (GC-owned — the Tk image frees itself, no manual bookkeeping); reach `icon.photo` for pixel-level access.

## Scrolling

A bare `list`/`text_area`/`table`/`tree` auto-attaches a scrollbar that appears only on overflow — no `-yscrollcommand` wiring:

```ruby
ui.list(:log)                 # already scrolls
ui.list(:log, scroll: false)  # opt out
```

`canvas` defaults to `scroll: false`. `x:`/`y:` pick the axis. Defaults resolve most-specific-first: widget `scroll:` → `Teek::UI.app(scroll:)` → global `Teek::UI.auto_scroll`. For a scrollbar around *arbitrary* content, wrap it in `ui.scrollable { }`. Mouse-wheel (incl. `Shift`+wheel for horizontal) works on all of it. See the API docs for the full precedence rules.

## Windows

`ui.window(title:, geometry:, resizable:, modal:) { }` is a managed toplevel — it handles the wm bookkeeping (title, geometry, transient-to-parent, macOS menubar quirk) and starts **withdrawn** until `.show`:

```ruby
settings = ui.window(:settings, title: 'Settings', geometry: '400x300') do |w|
  w.button(:close, text: 'Close').on_click { settings.hide }
end
ui.button(:open, text: 'Settings...').on_click { settings.show }
```

`.show` positions near its parent, raises, and (if `modal: true`) grabs input; `.hide` withdraws. `ui.dialog(...)` is `ui.window` with `modal: true, resizable: false` defaults. Plain containers (`panel`/`group`/`canvas`) just stack their children — use `column`/`row`/`grid` for real control.

## Navigation

Three ways to swap what's on screen — pick by how separate the new content is:

| Reach for | When |
| --- | --- |
| **`ui.window` / `ui.dialog`** | A separate top-level window with its own titlebar. See [Windows](#windows). |
| **`ui.screens`** | Full-content swaps *within one window* — a push/pop stack. |
| **`ui.modal`** | Stacked modal dialogs where dismissing one re-shows the one beneath. |

## Screens

`ui.screens` is a push/pop stack for swapping displayed content — pushing conceals the current screen, popping reverses it. Works against ordinary handles:

```ruby
ui.panel(:picker)   { |p| p.button(:play, text: 'Play').on_click { ui.screens.push(:emu, ui[:emu]) } }
ui.panel(:emu)      { |p| p.button(:back, text: 'Back').on_click { ui.screens.pop } }
```

`replace_current(handle)` swaps in place; `.current`/`.size`/`.active?` read state. A `lazy: true` container isn't realized until first pushed (avoids building every screen up front); `ui.screens.pop&.destroy!` closes one for good. See the API docs for the candidate-visibility gotcha and warm-conceal behavior.

## Modal Stacking

`ui.modal` stacks modal dialogs so one can push another and the previous re-shows on dismiss. Assign it yourself — its `on_enter:`/`on_exit:` hooks are mandatory (e.g. pause/resume what's underneath):

```ruby
ui.modal = Teek::UI::ModalStack.new(
  on_enter: ->(name) { pause },
  on_exit:  -> { resume },
)
ui.dialog(:settings) { |d| d.button(:replay).on_click { ui.modal.push(:replay, ui[:replay]) } }
```

`.push(name, handle)`/`.pop` reveal/conceal like `ui.screens`; push a `modal: true` handle (`ui.dialog` defaults to it) so `.show` grabs input. See the API docs for the `on_enter`/`on_exit`/`on_focus_change` firing rules and the fresh-dialog-per-open pattern.

## Tabs

`ui.tabs { }` is a `ttk::notebook`; `t.tab(label, name = nil) { }` declares a page:

```ruby
ui.tabs(:settings) do |t|
  t.tab('General')  { |g| g.checkbox(text: 'Dark mode') }
  t.tab('Advanced', :advanced_tab) { |a| a.label(text: 'Here be dragons') }
end
ui[:settings].on_tab_changed { |tab| puts "switched to #{tab}" }  # name, or index if unnamed
```

Tab content is an ordinary subtree; new tabs can be added at runtime via `session.add`.

## Split Panes

`ui.split(orientation: :horizontal) { }` is a `ttk::panedwindow`; `s.pane(weight: nil) { }` declares a draggable region:

```ruby
ui.split(:main, orientation: :horizontal) do |s|
  s.pane(weight: 1) { |a| a.list(:files) }
  s.pane(weight: 3) { |b| b.text_area(:editor) }
end
```

`weight:` sets how much slack a pane absorbs relative to its siblings.

## Event Bus

`ui.on`/`ui.emit` is in-process publish/subscribe — for widgets that react without holding a reference to whoever caused it:

```ruby
ui.on(:item_added) { |product| cart_badge.configure(text: "#{count += 1} items") }
add_button.on_click { ui.emit(:item_added, product) }   # no idea who's listening
```

`ui.off(:item_added, block)` unsubscribes. Each `Teek::UI.app` owns its own bus. See `sample/event_bus_demo.rb`.

## Menus

`ui.menu_bar { }` declares a window's menu bar, attaching to whatever window it's in. `.menu(label:)` is one recursive method for every dropdown/cascade/submenu:

```ruby
ui.menu_bar do |mb|
  mb.menu(label: 'File') do |file|
    file.item(label: 'Open...', shortcut: 'Cmd+O') { open_file }
    file.separator
    file.menu(label: 'Recent') { |r| r.item(label: 'notes.txt') { open_recent } }
  end
end
```

Inside a menu, `item`/`separator`/`checkbox`/`radio` build entries (menu entries, not the widgets of the same name). Name one to address it later (`.enable`/`.disable`/`.configure`). `shortcut:` (Tk: `accelerator:`) is display-only — wire the real key with `on_key`. A `ui.context_menu(:name) { }` is a standalone popup — attach it with `on_right_click`.

## Escape Hatch

The DSL is sugar, not a wall. **After realize**, `session.app` is the live `Teek::App`. **During build**, use `ui.raw { |app| ... }` — it records the block and runs it at realize with the live app (and can forward-reference widgets by name):

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.raw { |app| app.command(ui[:later].path, :configure, text: 'Changed') }
  ui.button(:later, text: 'Original')   # declared after, still resolves
end.run
```

Don't issue a raw `pack`/`grid` against a master the DSL already manages — Tk allows one geometry manager per master and raises a clear `Teek::TclError` if you mix them.

## Dynamic UIs

`session.add(parent_name) { }` builds a subtree with the same widget DSL and realizes it immediately under an already-realized widget — for UIs that grow after the window is up:

```ruby
session = Teek::UI.app(title: 'Hello') { |ui| ui.column(:list) }.run_async
session.add(:list) { |a| a.button(:item1, text: 'Item 1').on_click { puts 'clicked!' } }
```

New widgets route through the same leak-cleanup path; `parent_name` must already be realized.

## Timers

`#every`/`#after` queue-then-wire like events — declare a tick loop in the build block, next to the UI it drives:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.every(1000) { puts 'tick' }
  ui.after(500)  { puts 'once' }
end.run
```

Before realize they return `nil`; after realize they return the live, `.cancel`-able timer.

## Interactive / REPL Use

`#run` blocks the event loop, so it can't be used from IRB/Pry at all - it would freeze the REPL. `#run_async` shows the window and returns without blocking, but **driving a session interactively from IRB/Pry does not work properly on macOS**: nothing services Tk's event loop while the REPL sits waiting for your next line, so the window beachballs the moment you stop typing, no matter how often you call `ui.app.update` between statements - it only helps at the instant you call it, not while you're reading the screen or thinking about what to type next. Build and drive teek-ui apps from a script, not an interactive session.

## Dialogs

Standard native dialogs, directly on `ui` (realize-only):

```ruby
path   = ui.open_file(filetypes: [['Images', ['.png', '.jpg']]])
answer = ui.message(message: 'Delete this?', type: :yesno)   # => :yes / :no
color  = ui.choose_color(initial: '#3366ff')
dir    = ui.choose_dir(title: 'Pick a folder')
```

Each returns `nil` on cancel (`ui.message` returns the pressed button symbol). Also `ui.save_file`.

## Clipboard

`ui.clipboard` reads/writes directly (realize-only):

```ruby
ui.clipboard.set('copied text')
ui.clipboard.get   # => "copied text", or nil if empty
```

`text_box`/`text_area` already handle Ctrl/Cmd-C/X/V natively.

## Friendly vs. Tk Names

The litmus test for every name in this DSL: if decoding it needs Tk knowledge, the name is wrong. Where that meant renaming an underlying Tk concept, the Tk name still works too, as a plain alias - so a Tk man page, a Ruby-Tk migration, or plain muscle memory all still resolve correctly. The friendly name is primary (what the README/examples use); either name works identically everywhere.

| Friendly (primary) | Tk name (alias) | Where |
|---|---|---|
| `ellipse` | `oval` | canvas shape method |
| `points` / `points=` | `coords` / `coords=` | `CanvasItem` |
| `bring_to_front` | `tk_raise`* | `CanvasItem` |
| `send_to_back` | `lower` | `CanvasItem` |
| `bounds` | `bbox` | `CanvasItem` |
| `release_focus` | `grab_release` | `Handle` (window) |
| `shortcut:` | `accelerator:` | menu `item`/`checkbox`/`radio` |

\* Not plain `raise` - that would silently shadow `Kernel#raise` on every `CanvasItem`. `tk_raise` keeps the Tk association without the collision.

A few Tk names are kept as-is, deliberately not renamed - either genuinely universal (`configure`, `move`, `scale`, `value`), or Tk-specific enough that a forced rename would obscure more than it clarifies (`relief:`, `highlightthickness:`, `bitmap`, `tagged`).

The text widget has its own alias set (in [Text Content](#text-content) above): `format`/`apply_format`/`clear_format`/`delete_format`/`format_ranges`/`on_format_click` (Tk: `tag_*`), `add_marker`/`remove_marker`/`markers` (Tk: `mark_*`), `scroll_to` (Tk: `see`), `insert_image` (Tk: `image_create`).
