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

## Escape Hatch

Every session exposes the underlying `Teek::App` - nothing here is a sandbox:

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.app.command(:label, '.greeting', text: 'Hi there')
  ui.app.tcl_eval('pack .greeting')
end.run
```

## Interactive / REPL Use

`#run` blocks on the Tk event loop, which isn't REPL-friendly. `#run_async` shows the window and returns immediately instead - but it doesn't (yet) service the event loop automatically between prompts, so call `ui.app.update` yourself to process pending events while exploring:

```ruby
session = Teek::UI.app(title: 'Hello').run_async
session.app.update # process events after each change
```

## Timers

```ruby
Teek::UI.app(title: 'Hello') do |ui|
  ui.every(1000) { puts 'tick' }
  ui.after(500) { puts 'once' }
end.run
```
