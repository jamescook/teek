---
layout: default
title: Platform Quirks
nav_order: 90
---

# Platform Quirks

Cross-platform differences to be aware of when building Teek applications.

## macOS: Shared menu bar across windows

macOS has a single application-wide menu bar at the top of the screen. When a child window (e.g. a settings dialog) gets focus, Tk replaces the menu bar with its default "wish" menu unless the child explicitly shares the parent's menubar.

On Windows and Linux, each window has its own embedded menu bar. Sharing the parent's menu with child windows creates a visible duplicate.

**Fix:** Only share the menubar on macOS.

```ruby
top = '.settings'  # your toplevel path
if RUBY_PLATFORM =~ /darwin/
  parent_menu = app.command('.', :cget, '-menu') rescue nil
  app.command(top, :configure, menu: parent_menu) if parent_menu && !parent_menu.empty?
end
```
