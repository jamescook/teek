# Changelog — teek-ui

> **Alpha**: teek-ui is early and the API will change between minor versions.

All notable changes to teek-ui will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

Nothing has shipped yet - this section is a snapshot of the current API, not a running log. It gets folded/rewritten as the shape settles rather than appended to bead-by-bead.

- **Retained-mode build.** `Teek::UI.app(title:, **app_opts, &block)` builds a `Session` and yields it - Tk-free, no interpreter exists yet. `session.document` (a `Node`/`Document` tree) is constructible and traversable with no display, which is what makes UI structure testable headlessly.
- **Widgets.** `ui.<widget>` methods declare widgets into the tree. Leaf: `text_box`, `text_area`, `label`, `button`, `checkbox`, `radio`, `slider`, `dropdown`, `number_box`, `list`, `table`, `tree`, `progress`, `divider`. Containers (block-scoped children): `panel`/`box`, `group`, `canvas`, `window`. A name makes a widget addressable later via `ui[:name]`, without holding a reference.
- **Realize.** `#realize` (also called by `#run`/`#run_async`) creates the underlying `Teek::App` and walks the build tree into it, idempotently and atomically - the root window stays withdrawn until the whole tree realizes, so a mid-realize error never shows a half-built window (the app is destroyed and the session is left as if realize had never been called). Layout is a placeholder for now: children just pack top-to-bottom with no options, since there's no layout DSL yet to say otherwise.
- **Handles.** One handle type across both phases - `.path`/`.configure` raise `NotRealizedError` until a widget is realized, then act on the live widget at its real, hierarchical Tk path (derived from the widget's name, nested under its parent's path).
- **Events (mechanism only, no DSL yet).** A node can carry `EventBinding`s (`event`, `handler`, `target:`); realize wires them via `Teek::App#bind`, resolving a `target:` name against any widget in the whole tree - including ones declared later in the build - since every name is realized before any binding is wired. There's no friendly `on_click`-style surface to produce these yet.
- **Runtime escape hatch.** `session.app`, `#every`, `#after` reach the real `Teek::App` - all raise `NotRealizedError` before realize rather than queuing.
