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

## macOS: `<Deactivate>` event never fires

Tk's `<Activate>` fires (repeatedly) when a window gains focus, but `<Deactivate>` **never fires** when the app loses focus (e.g. Cmd-Tab away). `<FocusOut>` has the same problem.

**Root cause** (confirmed in Tk source, `macosx/tkMacOSXWindowEvent.c`):

The `windowActivation:` handler responds to `NSWindowDidBecomeKeyNotification` by calling `GenerateActivateEvents(winPtr, true)` — this is why `<Activate>` works. But the corresponding `NSWindowDidResignKeyNotification` handler only reassigns the key window; it **never calls `GenerateActivateEvents(winPtr, false)`**. The app-level `applicationDeactivate:` handler also skips event generation — it only cleans up zombie TouchBar windows.

```
// BecomeKey → fires Activate ✓
if (winPtr && Tk_IsMapped(winPtr)) {
    GenerateActivateEvents(winPtr, true);
}

// ResignKey → only reassigns key window, no Deactivate event ✗
if (![NSApp keyWindow] && [NSApp isActive]) {
    TkMacOSXAssignNewKeyWindow(...);
}

// applicationDeactivate: → only TouchBar cleanup, no events ✗
```

`::tk::mac::OnHide` / `OnShow` only fire for explicit Cmd-H, not app switching.

**Workaround:** Poll with `osascript` to check if your app is frontmost.

```ruby
app.after(500, repeat: true) do
  frontmost = `osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null`.strip
  is_active = frontmost == "wish" || frontmost == "YourAppName"
end
```
