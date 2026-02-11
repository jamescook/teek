#include "teek_sdl2.h"
#include <SDL2/SDL_image.h>

/* ---------------------------------------------------------
 * SDL2_image wrapper
 *
 * Loads image files (PNG, JPG, WebP, BMP, etc.) directly
 * into SDL2 textures via IMG_LoadTexture.
 * --------------------------------------------------------- */

static int img_initialized = 0;

static void
ensure_img_init(void)
{
    if (img_initialized) return;

    int flags = IMG_INIT_PNG | IMG_INIT_JPG;
    int initted = IMG_Init(flags);

    /* Not fatal if a specific codec is missing — IMG_LoadTexture
     * will fail at load time with a clear error message. We just
     * want to preload the common ones. */
    (void)initted;
    img_initialized = 1;
}

/*
 * Teek::SDL2::Renderer#load_image(path) -> Texture
 *
 * Load an image file into a GPU texture. Supports PNG, JPG, BMP,
 * GIF, WebP, TGA, and other formats via SDL2_image.
 *
 * The returned texture has alpha blending enabled and its width/height
 * set from the image dimensions.
 */
static VALUE
renderer_load_image(VALUE self, VALUE path)
{
    struct sdl2_renderer *ren = get_renderer(self);

    ensure_sdl2_init();
    ensure_img_init();

    StringValue(path);
    const char *cpath = StringValueCStr(path);

    SDL_Texture *texture = IMG_LoadTexture(ren->renderer, cpath);
    if (!texture) {
        rb_raise(rb_eRuntimeError, "IMG_LoadTexture failed: %s", IMG_GetError());
    }

    /* Query dimensions */
    int w, h;
    SDL_QueryTexture(texture, NULL, NULL, &w, &h);

    /* Enable alpha blending (common for PNGs with transparency) */
    SDL_SetTextureBlendMode(texture, SDL_BLENDMODE_BLEND);

    /* Wrap as a Texture object */
    VALUE klass = rb_const_get(mTeekSDL2, rb_intern("Texture"));
    VALUE obj = rb_obj_alloc(klass);

    struct sdl2_texture *t;
    TypedData_Get_Struct(obj, struct sdl2_texture, &texture_type, t);
    t->texture = texture;
    t->w = w;
    t->h = h;
    t->renderer_obj = self;

    return obj;
}

/* ---------------------------------------------------------
 * Init
 * --------------------------------------------------------- */

void
Init_sdl2image(VALUE mTeekSDL2)
{
    VALUE cRenderer = rb_const_get(mTeekSDL2, rb_intern("Renderer"));
    rb_define_method(cRenderer, "load_image", renderer_load_image, 1);
}
