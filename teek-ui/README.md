# Teek::UI

A DSL for building [Teek](https://github.com/jamescook/teek) (Tk) apps - sugar over teek, not a wall around it.

> **Alpha**: teek-ui is early. Right now it only wraps app bootstrap and the run loop; the widget, layout, and event DSL are still being built out.

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

## Escape Hatch

Once realized, every session exposes the underlying `Teek::App` - nothing here is a sandbox:

```ruby
session = Teek::UI.app(title: 'Hello').run_async
session.app.command(:label, '.greeting', text: 'Hi there')
session.app.tcl_eval('pack .greeting')
```

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
