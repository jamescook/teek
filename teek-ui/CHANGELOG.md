# Changelog — teek-ui

> **Alpha**: teek-ui is early and the API will change between minor versions.

All notable changes to teek-ui will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

### Added

- `Teek::UI.app(title:, **app_opts, &block)` — builds a `Teek::UI::Session` and yields it to the block, and returns that same session so `.run`/`.run_async` can be chained directly off the call. Building is Tk-free: no `Teek::App`/interpreter is constructed until realize, so the block runs (and `session.document` is buildable/inspectable) with nothing touching Tk yet.
- `Teek::UI::Node` / `Teek::UI::Document` — the retained-mode tree the DSL builds into: plain Ruby, no Tk, so a build can be constructed and traversed with no interpreter (headless-testable). `Document#create` constructs and name-indexes a node without attaching it anywhere; the caller attaches it into the tree via `Node#add_child`. Duplicate explicit names raise immediately; unnamed nodes get a distinct auto-generated key. `Node#each` / `Document#each_node` give depth-first, pre-order traversal.
- `Session#document` — the build-phase tree, readable before or after realize.
- `Session#realize` — creates the underlying `Teek::App` (idempotent - safe to call more than once). Tree realization (walking `Document` nodes into live Tk widgets) isn't built yet; realize currently only creates the app.
- `Session#run` — realizes, shows the window, and enters the Tk event loop (blocks until the app exits).
- `Session#run_async` — realizes, shows the window, and returns immediately, for interactive/REPL use. Does not yet service the event loop automatically between prompts; call `ui.app.update` yourself in the meantime.
- `Session#app` — the escape hatch to the underlying `Teek::App`. Raises `Teek::UI::NotRealizedError` if called before realize.
- `Session#every` / `Session#after` — thin delegates to `Teek::App#every`/`#after`. Also raise `Teek::UI::NotRealizedError` before realize, rather than queuing.
