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

#else
/* No-op on non-macOS */
void sdl2_macos_cleanup_metal_view(SDL_Window *window) { (void)window; }
#endif
