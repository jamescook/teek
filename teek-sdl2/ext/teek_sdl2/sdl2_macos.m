#include "teek_sdl2.h"

#ifdef __APPLE__
#import <Cocoa/Cocoa.h>
#include <SDL2/SDL_syswm.h>

/*
 * Remove any non-Tk subviews from the NSWindow's contentView and mark
 * it for redisplay.  Called from renderer_destroy() after
 * SDL_DestroyRenderer — SDL2's Metal backend fails to remove its
 * SDL_cocoametalview on foreign (Tk-owned) windows.
 *
 * Must be called BEFORE SDL_DestroyWindow (which NULLs the window
 * pointer in SDL_WindowData, making SDL_GetWindowWMInfo fail).
 */
void
sdl2_macos_cleanup_metal_view(SDL_Window *window)
{
    if (!window) return;

    SDL_SysWMinfo wminfo;
    SDL_VERSION(&wminfo.version);

    if (!SDL_GetWindowWMInfo(window, &wminfo)) return;
    if (wminfo.subsystem != SDL_SYSWM_COCOA) return;

    NSWindow *nswindow = wminfo.info.cocoa.window;
    NSView *contentView = [nswindow contentView];

    /* Remove any subviews that aren't part of Tk's view hierarchy.
     * Tk's own views are TKContentView (the contentView itself) and
     * occasionally internal Tk_ prefixed views.  The Metal subview is
     * SDL_cocoametalview.  Rather than matching class names, just
     * remove everything — Tk draws into the contentView directly, it
     * doesn't use subviews. */
    NSArray *subviews = [contentView.subviews copy];
    for (NSView *subview in subviews) {
        [subview removeFromSuperview];
    }

    [contentView setNeedsDisplay:YES];
}

/*
 * Cursor visibility — macOS path.
 *
 * Why not SDL_ShowCursor?
 *   SDL2 is embedded as a subview (SDL_cocoametalview) inside Tk's NSWindow.
 *   SDL_ShowCursor(SDL_DISABLE) internally calls [NSCursor hide], but only
 *   when SDL2 believes it has mouse focus — which it never does in subview
 *   mode because the NSWindow is owned by Tk, not SDL2.  The call is silently
 *   ignored.
 *
 * Why [NSCursor hide] directly?
 *   It is a global, application-wide operation that works regardless of which
 *   view or window currently has focus.  AppKit reference-counts hide/unhide
 *   calls, so we must balance them exactly — the guard flag ensures we call
 *   hide at most once and unhide exactly once in response.
 *
 * Why not Tk's `cursor none`?
 *   Tk's cursor:none also calls [NSCursor hide], but AppKit sends cursorUpdate:
 *   events to the SDL2 Metal subview as the mouse moves over it.  SDL2's view
 *   handles cursorUpdate: by resetting its own cursor, which can unbalance
 *   the hide refcount and make the cursor reappear.
 */
static int sdl2_macos_cursor_hidden = 0;

void
sdl2_macos_hide_cursor(void)
{
    if (!sdl2_macos_cursor_hidden) {
        sdl2_macos_cursor_hidden = 1;
        [NSCursor hide];
    }
}

void
sdl2_macos_show_cursor(void)
{
    if (sdl2_macos_cursor_hidden) {
        sdl2_macos_cursor_hidden = 0;
        [NSCursor unhide];
    }
}

#else
/*
 * Non-macOS cursor visibility.
 *
 * On Windows and Linux/X11, SDL2 creates its own child window (HWND or
 * X Window) inside the Tk frame rather than sharing the top-level window.
 * SDL2 therefore owns the cursor over its surface and SDL_ShowCursor works
 * as expected.  No platform-specific workaround needed.
 */
void sdl2_macos_cleanup_metal_view(SDL_Window *window) { (void)window; }
void sdl2_macos_hide_cursor(void) { SDL_ShowCursor(SDL_DISABLE); }
void sdl2_macos_show_cursor(void) { SDL_ShowCursor(SDL_ENABLE); }
#endif
