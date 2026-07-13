# Changelog — teek-ui

> **Alpha**: teek-ui is early and the API will change between minor versions.

All notable changes to teek-ui will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- `Teek::UI.app(title:, **app_opts, &block)` — constructs the underlying `Teek::App`, yields a `Teek::UI::Session` to the block, and returns that same session so `.run`/`.run_async` can be chained directly off the call.
- `Session#run` — shows the window and enters the Tk event loop (blocks until the app exits).
- `Session#run_async` — shows the window and returns immediately, for interactive/REPL use. Does not yet service the event loop automatically between prompts; call `ui.app.update` yourself in the meantime.
- `Session#app` — the escape hatch to the underlying `Teek::App`.
- `Session#every` / `Session#after` — thin delegates to `Teek::App#every`/`#after`.
