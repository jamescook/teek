#include "teek_sdl2.h"

/* No-op stubs for non-macOS platforms. The real implementations
 * live in sdl2_macos.m (ObjC) and are only compiled on Darwin. */
void
sdl2_macos_cleanup_metal_view(SDL_Window *window)
{
    (void)window;
}

void sdl2_macos_hide_cursor(void) { SDL_ShowCursor(SDL_DISABLE); }
void sdl2_macos_show_cursor(void) { SDL_ShowCursor(SDL_ENABLE); }
