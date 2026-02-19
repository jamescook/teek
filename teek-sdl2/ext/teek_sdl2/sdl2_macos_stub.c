#include "teek_sdl2.h"

/* No-op stub for non-macOS platforms. The real implementation
 * lives in sdl2_macos.m (ObjC) and is only compiled on Darwin. */
void
sdl2_macos_cleanup_metal_view(SDL_Window *window)
{
    (void)window;
}
