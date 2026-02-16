#include "teek_mgba.h"
#include <mgba/core/config.h>
#include <mgba/core/serialize.h>
#include <ruby/thread.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <fcntl.h>

/*
 * Forward declarations for blip_buf (audio buffer API).
 * These functions are part of libmgba but the header may
 * not be in the installed include path.
 */
struct blip_t;
int blip_samples_avail(const struct blip_t *);
int blip_read_samples(struct blip_t *, short out[], int count, int stereo);
void blip_set_rates(struct blip_t *, double clock_rate, double sample_rate);

VALUE mTeek;
VALUE mTeekMGBA;
static VALUE cCore;

/* No-op logger — prevents segfault when mGBA tries to log
 * without a logger configured (the default is NULL). */
static void
null_log(struct mLogger *logger, int category, enum mLogLevel level,
         const char *format, va_list args)
{
    (void)logger; (void)category; (void)level;
    (void)format; (void)args;
}

static struct mLogger s_null_logger = {
    .log = null_log,
    .filter = NULL,
};

/* GBA key indices (bit positions for set_keys bitmask).
 * Matches mGBA's GBA_KEY_* enum. */
#define TEEK_GBA_KEY_A      0
#define TEEK_GBA_KEY_B      1
#define TEEK_GBA_KEY_SELECT 2
#define TEEK_GBA_KEY_START  3
#define TEEK_GBA_KEY_RIGHT  4
#define TEEK_GBA_KEY_LEFT   5
#define TEEK_GBA_KEY_UP     6
#define TEEK_GBA_KEY_DOWN   7
#define TEEK_GBA_KEY_R      8
#define TEEK_GBA_KEY_L      9

/* --------------------------------------------------------- */
/* Core wrapper struct                                       */
/* --------------------------------------------------------- */

/* --------------------------------------------------------- */
/* GBA color correction (Pokefan531 / Color Mangler formula)  */
/*                                                           */
/* The GBA LCD has a non-standard gamma (~3.2) and channel   */
/* cross-talk. Games were designed with exaggerated colors    */
/* to compensate. This LUT maps raw mGBA ARGB8888 output to  */
/* corrected sRGB values that approximate the original GBA    */
/* LCD appearance.                                           */
/*                                                           */
/* 32x32x32 entries (one per RGB555 input color) = 128KB.    */
/* Built once on enable; applied per-pixel in video_buffer_argb. */
/*                                                           */
/* Reference: libretro gba-color.glsl (public domain)        */
/*   https://github.com/libretro/glsl-shaders/blob/master/   */
/*   handheld/shaders/color/gba-color.glsl                   */
/* --------------------------------------------------------- */

static uint32_t gba_color_lut[32][32][32];
static int gba_color_lut_built = 0;

static void
build_gba_color_lut(void)
{
    const double target_gamma  = 2.2;
    const double darken_screen = 1.0;
    const double display_gamma = 2.2;
    const double lum           = 0.94;
    const double input_gamma   = target_gamma + darken_screen; /* 3.2 */

    for (int ri = 0; ri < 32; ri++) {
        for (int gi = 0; gi < 32; gi++) {
            for (int bi = 0; bi < 32; bi++) {
                double r = pow(ri / 31.0, input_gamma) * lum;
                double g = pow(gi / 31.0, input_gamma) * lum;
                double b = pow(bi / 31.0, input_gamma) * lum;
                if (r > 1.0) r = 1.0;
                if (g > 1.0) g = 1.0;
                if (b > 1.0) b = 1.0;

                /* Pokefan531 mixing matrix */
                double nr =  0.82  * r + 0.125 * g + 0.195 * b;
                double ng =  0.24  * r + 0.665 * g + 0.075 * b;
                double nb = -0.06  * r + 0.21  * g + 0.73  * b;

                if (nr < 0.0) nr = 0.0; if (nr > 1.0) nr = 1.0;
                if (ng < 0.0) ng = 0.0; if (ng > 1.0) ng = 1.0;
                if (nb < 0.0) nb = 0.0; if (nb > 1.0) nb = 1.0;

                nr = pow(nr, 1.0 / display_gamma);
                ng = pow(ng, 1.0 / display_gamma);
                nb = pow(nb, 1.0 / display_gamma);

                uint8_t or8 = (uint8_t)(nr * 255.0 + 0.5);
                uint8_t og8 = (uint8_t)(ng * 255.0 + 0.5);
                uint8_t ob8 = (uint8_t)(nb * 255.0 + 0.5);

                gba_color_lut[ri][gi][bi] =
                    0xFF000000 | ((uint32_t)or8 << 16) |
                    ((uint32_t)og8 << 8) | (uint32_t)ob8;
            }
        }
    }
    gba_color_lut_built = 1;
}

/* Apply LUT to an ARGB8888 pixel. The GBA only outputs 15-bit color
 * (RGB555), so we quantize each 8-bit channel to 5 bits for lookup. */
static inline uint32_t
color_correct_pixel(uint32_t argb)
{
    int r5 = (int)((argb >> 16) & 0xFF) >> 3;
    int g5 = (int)((argb >>  8) & 0xFF) >> 3;
    int b5 = (int)((argb      ) & 0xFF) >> 3;
    return gba_color_lut[r5][g5][b5];
}

struct mgba_core {
    struct mCore *core;
    color_t *video_buffer;
    uint32_t *prev_frame;
    int width;
    int height;
    int destroyed;
    int color_correction;
    int frame_blending;
    /* Rewind ring buffer */
    int rewind_capacity;       /* number of slots (0 = disabled) */
    int rewind_head;           /* next write index */
    int rewind_count;          /* number of valid snapshots */
    size_t rewind_state_size;  /* bytes per snapshot */
    void **rewind_slots;       /* array of rewind_capacity void* buffers */
};

static void
mgba_rewind_free(struct mgba_core *mc)
{
    if (mc->rewind_slots) {
        for (int i = 0; i < mc->rewind_capacity; i++) {
            if (mc->rewind_slots[i]) {
                free(mc->rewind_slots[i]);
                mc->rewind_slots[i] = NULL;
            }
        }
        free(mc->rewind_slots);
        mc->rewind_slots = NULL;
    }
    mc->rewind_capacity = 0;
    mc->rewind_head = 0;
    mc->rewind_count = 0;
    mc->rewind_state_size = 0;
}

static void
mgba_core_cleanup(struct mgba_core *mc)
{
    mgba_rewind_free(mc);
    if (!mc->destroyed && mc->core) {
        mc->core->deinit(mc->core);
        mc->core = NULL;
    }
    if (mc->video_buffer) {
        free(mc->video_buffer);
        mc->video_buffer = NULL;
    }
    if (mc->prev_frame) {
        free(mc->prev_frame);
        mc->prev_frame = NULL;
    }
    mc->destroyed = 1;
}

static void
mgba_core_dfree(void *ptr)
{
    struct mgba_core *mc = ptr;
    mgba_core_cleanup(mc);
    xfree(mc);
}

static size_t
mgba_core_memsize(const void *ptr)
{
    const struct mgba_core *mc = ptr;
    size_t size = sizeof(struct mgba_core);
    if (mc->video_buffer) {
        size += (size_t)mc->width * mc->height * sizeof(color_t);
    }
    if (mc->prev_frame) {
        size += (size_t)mc->width * mc->height * sizeof(uint32_t);
    }
    if (mc->rewind_slots) {
        size += (size_t)mc->rewind_capacity * mc->rewind_state_size;
        size += (size_t)mc->rewind_capacity * sizeof(void *);
    }
    return size;
}

static const rb_data_type_t mgba_core_type = {
    .wrap_struct_name = "TeekMGBA::Core",
    .function = {
        .dmark = NULL,
        .dfree = mgba_core_dfree,
        .dsize = mgba_core_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
mgba_core_alloc(VALUE klass)
{
    struct mgba_core *mc;
    VALUE obj = TypedData_Make_Struct(klass, struct mgba_core,
                                     &mgba_core_type, mc);
    mc->core = NULL;
    mc->video_buffer = NULL;
    mc->prev_frame = NULL;
    mc->width = 0;
    mc->height = 0;
    mc->destroyed = 0;
    mc->color_correction = 0;
    mc->frame_blending = 0;
    mc->rewind_capacity = 0;
    mc->rewind_head = 0;
    mc->rewind_count = 0;
    mc->rewind_state_size = 0;
    mc->rewind_slots = NULL;
    return obj;
}

static struct mgba_core *
get_mgba_core(VALUE self)
{
    struct mgba_core *mc;
    TypedData_Get_Struct(self, struct mgba_core, &mgba_core_type, mc);
    if (mc->destroyed || !mc->core) {
        rb_raise(rb_eRuntimeError, "mGBA core has been destroyed");
    }
    return mc;
}

/* --------------------------------------------------------- */
/* Core#initialize(rom_path, save_dir=nil)                   */
/* --------------------------------------------------------- */

static VALUE
mgba_core_initialize(int argc, VALUE *argv, VALUE self)
{
    VALUE rom_path, save_dir;
    rb_scan_args(argc, argv, "11", &rom_path, &save_dir);

    struct mgba_core *mc;
    TypedData_Get_Struct(self, struct mgba_core, &mgba_core_type, mc);

    Check_Type(rom_path, T_STRING);
    const char *path = StringValueCStr(rom_path);

    /* 1. Detect platform from ROM */
    struct mCore *core = mCoreFind(path);
    if (!core) {
        rb_raise(rb_eArgError, "mCoreFind failed — unsupported ROM: %s", path);
    }

    /* 2. Initialize core + config (required per mGBA Python bindings) */
    if (!core->init(core)) {
        rb_raise(rb_eRuntimeError, "mCore init failed");
    }
    mCoreInitConfig(core, NULL);

    /* 3. Get desired video dimensions */
    unsigned w, h;
    core->desiredVideoDimensions(core, &w, &h);
    mc->width = (int)w;
    mc->height = (int)h;

    /* 4. Allocate and set video buffer */
    mc->video_buffer = calloc((size_t)w * h, sizeof(color_t));
    if (!mc->video_buffer) {
        core->deinit(core);
        rb_raise(rb_eNoMemError, "failed to allocate video buffer");
    }
    core->setVideoBuffer(core, mc->video_buffer, w);

    /* 4b. Allocate previous-frame buffer for frame blending */
    mc->prev_frame = calloc((size_t)w * h, sizeof(uint32_t));
    if (!mc->prev_frame) {
        free(mc->video_buffer);
        mc->video_buffer = NULL;
        core->deinit(core);
        rb_raise(rb_eNoMemError, "failed to allocate prev_frame buffer");
    }

    /* 5. Set audio buffer size */
    core->setAudioBufferSize(core, 2048);

    /* 6. Load ROM (convenience function handles VFile internally) */
    if (!mCoreLoadFile(core, path)) {
        free(mc->video_buffer);
        mc->video_buffer = NULL;
        free(mc->prev_frame);
        mc->prev_frame = NULL;
        core->deinit(core);
        rb_raise(rb_eArgError, "failed to load ROM: %s", path);
    }

    /* 7. Override save directory if provided */
    if (!NIL_P(save_dir)) {
        Check_Type(save_dir, T_STRING);
        struct mCoreOptions opts = { 0 };
        opts.savegamePath = (char *)StringValueCStr(save_dir);
        mDirectorySetMapOptions(&core->dirs, &opts);
    }

    /* 8. Reset */
    core->reset(core);

    /* 9. Autoload save file (.sav alongside ROM, or in save_dir).
     * Creates the .sav if it doesn't exist yet. */
    mCoreAutoloadSave(core);

    /* 10. Set blip_buf output rate to 44100 Hz (must be after reset) */
    {
        double clock_rate = (double)core->frequency(core);
        struct blip_t *left  = core->getAudioChannel(core, 0);
        struct blip_t *right = core->getAudioChannel(core, 1);
        if (!left || !right) {
            free(mc->video_buffer);
            mc->video_buffer = NULL;
            free(mc->prev_frame);
            mc->prev_frame = NULL;
            core->deinit(core);
            rb_raise(rb_eRuntimeError, "mGBA audio channels not available");
        }
        blip_set_rates(left,  clock_rate, 44100.0);
        blip_set_rates(right, clock_rate, 44100.0);
    }

    mc->core = core;
    return self;
}

/* --------------------------------------------------------- */
/* Core#run_frame — releases GVL for ~16ms of CPU work       */
/* --------------------------------------------------------- */

struct run_frame_args {
    struct mCore *core;
};

static void *
run_frame_nogvl(void *arg)
{
    struct run_frame_args *a = arg;
    a->core->runFrame(a->core);
    return NULL;
}

static VALUE
mgba_core_run_frame(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    struct run_frame_args args = { .core = mc->core };
    rb_thread_call_without_gvl(run_frame_nogvl, &args, RUBY_UBF_IO, NULL);
    return Qnil;
}

/* --------------------------------------------------------- */
/* Core#video_buffer                                         */
/* --------------------------------------------------------- */

static VALUE
mgba_core_video_buffer(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    long size = (long)mc->width * mc->height * (long)sizeof(color_t);
    return rb_str_new((const char *)mc->video_buffer, size);
}

/* --------------------------------------------------------- */
/* Core#video_buffer_argb                                    */
/* Returns pixel data with R↔B swapped for SDL ARGB8888.     */
/* mGBA color_t is 0xAABBGGRR; SDL wants 0xAARRGGBB.        */
/* --------------------------------------------------------- */

static VALUE
mgba_core_video_buffer_argb(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    long npixels = (long)mc->width * mc->height;
    long size = npixels * (long)sizeof(uint32_t);
    VALUE str = rb_str_new(NULL, size);
    uint32_t *dst = (uint32_t *)RSTRING_PTR(str);
    const uint32_t *src = (const uint32_t *)mc->video_buffer;

    if (mc->color_correction && !gba_color_lut_built)
        build_gba_color_lut();

    for (long i = 0; i < npixels; i++) {
        uint32_t px = src[i];
        /* mGBA native color_t is mCOLOR_XBGR8 (0xXXBBGGRR) — the high
         * byte is unused padding, not alpha. Force it to 0xFF so
         * consumers that interpret byte 3 as alpha (Tk photo, PNG)
         * don't get transparent pixels.
         * Ref: https://github.com/mgba-emu/mgba/blob/c30aaa8f42b5b786924d955630b29cd990176968/include/mgba-util/image.h#L62 */
        uint32_t argb = 0xFF000000
               | ((px & 0x000000FF) << 16)
               | (px & 0x0000FF00)
               | ((px & 0x00FF0000) >> 16);

        if (mc->color_correction)
            argb = color_correct_pixel(argb);

        if (mc->frame_blending && mc->prev_frame) {
            uint32_t prev = mc->prev_frame[i];
            mc->prev_frame[i] = argb;  /* store unblended for next frame */
            argb = ((argb & 0xFEFEFEFE) >> 1)
                 + ((prev & 0xFEFEFEFE) >> 1)
                 + (argb & prev & 0x01010101);
        }

        dst[i] = argb;
    }
    return str;
}

/* --------------------------------------------------------- */
/* Core#audio_buffer                                         */
/* --------------------------------------------------------- */

static VALUE
mgba_core_audio_buffer(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);

    struct blip_t *left  = mc->core->getAudioChannel(mc->core, 0);
    struct blip_t *right = mc->core->getAudioChannel(mc->core, 1);
    if (!left || !right) {
        return rb_str_new(NULL, 0);
    }

    int avail = blip_samples_avail(left);
    if (avail <= 0) {
        return rb_str_new(NULL, 0);
    }

    /* Interleaved stereo int16: L R L R ... */
    long byte_size = (long)avail * 2 * (long)sizeof(int16_t);
    VALUE str = rb_str_new(NULL, byte_size);
    int16_t *buf = (int16_t *)RSTRING_PTR(str);

    /* stereo=1: write every other sample for interleaving */
    blip_read_samples(left,  buf,     avail, 1);
    blip_read_samples(right, buf + 1, avail, 1);

    return str;
}

/* --------------------------------------------------------- */
/* Core#set_keys(bitmask)                                    */
/* --------------------------------------------------------- */

static VALUE
mgba_core_set_keys(VALUE self, VALUE keys)
{
    struct mgba_core *mc = get_mgba_core(self);
    uint32_t bitmask = NUM2UINT(keys);
    mc->core->setKeys(mc->core, bitmask);
    return Qnil;
}

/* --------------------------------------------------------- */
/* Core#width, Core#height                                   */
/* --------------------------------------------------------- */

static VALUE
mgba_core_width(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    return INT2NUM(mc->width);
}

static VALUE
mgba_core_height(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    return INT2NUM(mc->height);
}

/* --------------------------------------------------------- */
/* Core#title                                                */
/* --------------------------------------------------------- */

static VALUE
mgba_core_title(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    char title[16];
    memset(title, 0, sizeof(title));
    mc->core->getGameTitle(mc->core, title);
    title[15] = '\0';

    /* strlen stops at first null; then trim trailing spaces */
    int len = (int)strlen(title);
    while (len > 0 && title[len - 1] == ' ') len--;
    return rb_str_new(title, len);
}

/* --------------------------------------------------------- */
/* Core#game_code                                            */
/* --------------------------------------------------------- */

static VALUE
mgba_core_game_code(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    char code[16];
    memset(code, 0, sizeof(code));
    mc->core->getGameCode(mc->core, code);
    code[15] = '\0';

    /* strlen stops at first null; then trim trailing spaces */
    int len = (int)strlen(code);
    while (len > 0 && code[len - 1] == ' ') len--;
    return rb_str_new(code, len);
}

/* --------------------------------------------------------- */
/* Core#checksum                                             */
/* Returns the CRC32 checksum of the loaded ROM.             */
/* --------------------------------------------------------- */

static VALUE
mgba_core_checksum(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    uint32_t crc = 0;
    mc->core->checksum(mc->core, &crc, mCHECKSUM_CRC32);
    return UINT2NUM(crc);
}

/* --------------------------------------------------------- */
/* Core#platform                                             */
/* Returns "GBA", "GB", or "Unknown".                        */
/* --------------------------------------------------------- */

static VALUE
mgba_core_platform(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    enum mPlatform p = mc->core->platform(mc->core);
    switch (p) {
    case mPLATFORM_GBA: return rb_str_new_cstr("GBA");
    case mPLATFORM_GB:  return rb_str_new_cstr("GB");
    default:            return rb_str_new_cstr("Unknown");
    }
}

/* --------------------------------------------------------- */
/* Core#rom_size                                             */
/* --------------------------------------------------------- */

static VALUE
mgba_core_rom_size(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    size_t sz = mc->core->romSize(mc->core);
    return SIZET2NUM(sz);
}

/* --------------------------------------------------------- */
/* Core#maker_code                                           */
/* Reads the 2-byte maker/publisher code from the GBA ROM    */
/* header at offset 0xB0. Uses busRead8 at 0x080000B0.      */
/* Returns empty string for non-GBA ROMs.                    */
/* --------------------------------------------------------- */

static VALUE
mgba_core_maker_code(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    if (mc->core->platform(mc->core) != mPLATFORM_GBA) {
        return rb_str_new_cstr("");
    }

    char maker[3];
    maker[0] = (char)mc->core->busRead8(mc->core, 0x080000B0);
    maker[1] = (char)mc->core->busRead8(mc->core, 0x080000B1);
    maker[2] = '\0';
    return rb_str_new(maker, (int)strlen(maker));
}

/* --------------------------------------------------------- */
/* Core#save_state_to_file(path)                             */
/* Save the complete emulator state to a file.               */
/* Returns true on success, false on failure.                */
/* --------------------------------------------------------- */

static VALUE
mgba_core_save_state_to_file(VALUE self, VALUE rb_path)
{
    struct mgba_core *mc = get_mgba_core(self);
    Check_Type(rb_path, T_STRING);
    const char *path = StringValueCStr(rb_path);

    struct VFile *vf = VFileOpen(path, O_CREAT | O_TRUNC | O_WRONLY);
    if (!vf) {
        rb_raise(rb_eRuntimeError, "Cannot open state file for writing: %s", path);
    }

    bool ok = mCoreSaveStateNamed(mc->core, vf, SAVESTATE_ALL);
    vf->close(vf);
    return ok ? Qtrue : Qfalse;
}

/* --------------------------------------------------------- */
/* Core#load_state_from_file(path)                           */
/* Load emulator state from a file.                          */
/* Returns true on success, false on failure.                */
/* --------------------------------------------------------- */

static VALUE
mgba_core_load_state_from_file(VALUE self, VALUE rb_path)
{
    struct mgba_core *mc = get_mgba_core(self);
    Check_Type(rb_path, T_STRING);
    const char *path = StringValueCStr(rb_path);

    struct VFile *vf = VFileOpen(path, O_RDONLY);
    if (!vf) {
        return Qfalse;
    }

    bool ok = mCoreLoadStateNamed(mc->core, vf, SAVESTATE_ALL);
    vf->close(vf);
    return ok ? Qtrue : Qfalse;
}

/* --------------------------------------------------------- */
/* Core#color_correction=, Core#color_correction?            */
/* --------------------------------------------------------- */

static VALUE
mgba_core_set_color_correction(VALUE self, VALUE val)
{
    struct mgba_core *mc = get_mgba_core(self);
    mc->color_correction = RTEST(val) ? 1 : 0;
    if (mc->color_correction && !gba_color_lut_built) {
        build_gba_color_lut();
    }
    return val;
}

static VALUE
mgba_core_color_correction_p(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    return mc->color_correction ? Qtrue : Qfalse;
}

/* --------------------------------------------------------- */
/* Core#frame_blending=, Core#frame_blending?                */
/* --------------------------------------------------------- */

static VALUE
mgba_core_set_frame_blending(VALUE self, VALUE val)
{
    struct mgba_core *mc = get_mgba_core(self);
    mc->frame_blending = RTEST(val) ? 1 : 0;
    return val;
}

static VALUE
mgba_core_frame_blending_p(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    return mc->frame_blending ? Qtrue : Qfalse;
}

/* --------------------------------------------------------- */
/* Rewind ring buffer                                        */
/* --------------------------------------------------------- */

/*
 * Core#rewind_init(capacity)
 * Allocate a ring buffer of `capacity` state snapshots.
 * Each slot is core->stateSize() bytes. Frees any existing buffer.
 */
static VALUE
mgba_core_rewind_init(VALUE self, VALUE rb_capacity)
{
    struct mgba_core *mc = get_mgba_core(self);
    int capacity = NUM2INT(rb_capacity);
    if (capacity <= 0)
        rb_raise(rb_eArgError, "rewind capacity must be positive");

    /* Free existing rewind buffer if reinitializing */
    mgba_rewind_free(mc);

    size_t state_size = mc->core->stateSize(mc->core);
    void **slots = calloc((size_t)capacity, sizeof(void *));
    if (!slots)
        rb_raise(rb_eNoMemError, "failed to allocate rewind slot array");

    for (int i = 0; i < capacity; i++) {
        slots[i] = malloc(state_size);
        if (!slots[i]) {
            /* Clean up already-allocated slots */
            for (int j = 0; j < i; j++) free(slots[j]);
            free(slots);
            rb_raise(rb_eNoMemError, "failed to allocate rewind slot %d", i);
        }
    }

    mc->rewind_capacity = capacity;
    mc->rewind_state_size = state_size;
    mc->rewind_slots = slots;
    mc->rewind_head = 0;
    mc->rewind_count = 0;
    return Qnil;
}

/*
 * Core#rewind_deinit
 * Free all rewind buffers.
 */
static VALUE
mgba_core_rewind_deinit(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    mgba_rewind_free(mc);
    return Qnil;
}

/*
 * Core#rewind_push
 * Save current state into the next ring buffer slot.
 * Returns true on success, false if rewind not initialized.
 */
static VALUE
mgba_core_rewind_push(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    if (!mc->rewind_slots || mc->rewind_capacity <= 0)
        return Qfalse;

    mc->core->saveState(mc->core, mc->rewind_slots[mc->rewind_head]);
    mc->rewind_head = (mc->rewind_head + 1) % mc->rewind_capacity;
    if (mc->rewind_count < mc->rewind_capacity)
        mc->rewind_count++;
    return Qtrue;
}

/*
 * Core#rewind_pop
 * Load the oldest snapshot and clear the buffer.
 * Jumps back to the earliest saved point (~N seconds ago).
 * Returns true on success, false if no snapshots available.
 */
static VALUE
mgba_core_rewind_pop(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    if (!mc->rewind_slots || mc->rewind_count <= 0)
        return Qfalse;

    /* oldest = head - count (wrapped) */
    int oldest = (mc->rewind_head - mc->rewind_count + mc->rewind_capacity)
                 % mc->rewind_capacity;
    mc->core->loadState(mc->core, mc->rewind_slots[oldest]);
    mc->rewind_head = 0;
    mc->rewind_count = 0;
    return Qtrue;
}

/*
 * Core#rewind_count
 * Returns the number of valid snapshots in the buffer.
 */
static VALUE
mgba_core_rewind_count(VALUE self)
{
    struct mgba_core *mc = get_mgba_core(self);
    return INT2NUM(mc->rewind_count);
}

/* --------------------------------------------------------- */
/* Core#destroy, Core#destroyed?                             */
/* --------------------------------------------------------- */

static VALUE
mgba_core_destroy(VALUE self)
{
    struct mgba_core *mc;
    TypedData_Get_Struct(self, struct mgba_core, &mgba_core_type, mc);
    mgba_core_cleanup(mc);
    return Qnil;
}

static VALUE
mgba_core_destroyed_p(VALUE self)
{
    struct mgba_core *mc;
    TypedData_Get_Struct(self, struct mgba_core, &mgba_core_type, mc);
    return mc->destroyed ? Qtrue : Qfalse;
}

/* --------------------------------------------------------- */
/* Teek::MGBA.toast_background(w, h, radius)                 */
/*                                                           */
/* Generates ARGB8888 pixel data for a toast notification     */
/* background with rounded corners.  For each pixel we        */
/* compute a signed distance to the rounded-rect edge, then   */
/* assign one of four zones based on that distance:           */
/*   outside       → transparent                              */
/*   outer fringe  → border color fading in (anti-alias)      */
/*   border band   → solid border color                       */
/*   inner fringe  → border blending to fill (anti-alias)     */
/*   interior      → solid fill color                         */
/* Returns a binary String of w*h*4 bytes.                   */
/* --------------------------------------------------------- */

/* Toast palette (non-premultiplied, for SDL_BLENDMODE_BLEND)
 *   Fill:   near-black, slight blue tint — readable over game art
 *   Border: blue-grey — subtle edge visible against dark scenes
 *   Alpha is 0–255: 180/255 ≈ 70% opaque, 210/255 ≈ 82% opaque */
enum {
    TOAST_FILL_R = 20,  TOAST_FILL_G = 20,  TOAST_FILL_B = 28,  TOAST_FILL_A = 180,
    TOAST_BDR_R  = 100, TOAST_BDR_G  = 110, TOAST_BDR_B  = 140, TOAST_BDR_A  = 210,
};

static inline uint32_t
toast_argb(uint8_t a, uint8_t r, uint8_t g, uint8_t b) {
    return ((uint32_t)a << 24) | ((uint32_t)r << 16) |
           ((uint32_t)g << 8)  | (uint32_t)b;
}

static VALUE
mgba_toast_background(VALUE mod, VALUE rb_w, VALUE rb_h, VALUE rb_rad)
{
    (void)mod;
    int w   = NUM2INT(rb_w);
    int h   = NUM2INT(rb_h);
    int rad = NUM2INT(rb_rad);

    if (w <= 0 || h <= 0) return rb_str_new(NULL, 0);
    if (rad < 0) rad = 0;
    if (rad > w / 2) rad = w / 2;
    if (rad > h / 2) rad = h / 2;

    long nbytes = (long)w * h * 4;
    VALUE str = rb_str_new(NULL, nbytes);
    uint32_t *pixels = (uint32_t *)RSTRING_PTR(str);
    memset(pixels, 0, nbytes);

    const uint32_t fill_color   = toast_argb(TOAST_FILL_A, TOAST_FILL_R, TOAST_FILL_G, TOAST_FILL_B);
    const uint32_t border_color = toast_argb(TOAST_BDR_A, TOAST_BDR_R, TOAST_BDR_G, TOAST_BDR_B);

    float border_w = 1.5f;  /* border thickness in pixels */
    float aa_w = 1.2f;      /* anti-aliasing width */
    float frad = (float)rad;

    for (int py = 0; py < h; py++) {
        for (int px = 0; px < w; px++) {
            /* Signed distance from the rounded-rect boundary (negative = inside).
             * SDF for a rounded rectangle per Inigo Quilez:
             * https://iquilezles.org/articles/distfunctions/ */
            float qx, qy;
            float cx = (float)px + 0.5f;
            float cy = (float)py + 0.5f;
            float hw = (float)w * 0.5f;
            float hh = (float)h * 0.5f;

            /* Distance from center, reduced by half-size minus radius */
            qx = fabsf(cx - hw) - (hw - frad);
            qy = fabsf(cy - hh) - (hh - frad);

            float dist;
            float mx = qx > 0.0f ? qx : 0.0f;
            float my = qy > 0.0f ? qy : 0.0f;
            float outside = sqrtf(mx * mx + my * my);
            float inside  = qx > qy ? qx : qy;
            if (inside < 0.0f) inside = 0.0f;
            dist = outside + (outside > 0.0f ? 0.0f : (qx > qy ? qx : qy)) - frad;

            uint32_t color;
            if (dist >= aa_w * 0.5f) {
                /* Outside: transparent */
                color = 0;
            } else if (dist >= -aa_w * 0.5f) {
                /* Outer AA fringe: fade border from transparent to full.
                 * Non-premultiplied: RGB stays at border color, alpha varies. */
                float t = 0.5f - dist / aa_w;  /* 0..1 */
                uint8_t a = (uint8_t)(TOAST_BDR_A * t + 0.5f);
                if (a < 8) { color = 0; }  /* suppress faint fringe dots */
                else { color = toast_argb(a, TOAST_BDR_R, TOAST_BDR_G, TOAST_BDR_B); }
            } else if (dist >= -(border_w - aa_w * 0.5f)) {
                /* Solid border */
                color = border_color;
            } else if (dist >= -(border_w + aa_w * 0.5f)) {
                /* Inner AA fringe: blend border → fill */
                float t = (dist + border_w + aa_w * 0.5f) / aa_w;  /* 1..0 inward */
                uint8_t a = (uint8_t)(TOAST_BDR_A * t + TOAST_FILL_A * (1.0f - t) + 0.5f);
                uint8_t r = (uint8_t)(TOAST_BDR_R * t + TOAST_FILL_R * (1.0f - t) + 0.5f);
                uint8_t g = (uint8_t)(TOAST_BDR_G * t + TOAST_FILL_G * (1.0f - t) + 0.5f);
                uint8_t b = (uint8_t)(TOAST_BDR_B * t + TOAST_FILL_B * (1.0f - t) + 0.5f);
                color = toast_argb(a, r, g, b);
            } else {
                /* Fill interior */
                color = fill_color;
            }

            pixels[py * w + px] = color;
        }
    }

    return str;
}

/* --------------------------------------------------------- */
/* XOR delta for recording                                   */
/* --------------------------------------------------------- */

/*
 * Teek::MGBA.xor_delta(current, previous) → String
 *
 * XOR two equal-length binary strings byte-by-byte.
 * Used for frame delta compression in recording.
 */
static VALUE
mgba_xor_delta(VALUE mod, VALUE a, VALUE b)
{
    (void)mod;
    StringValue(a);
    StringValue(b);

    long len = RSTRING_LEN(a);
    if (RSTRING_LEN(b) != len)
        rb_raise(rb_eArgError, "strings must be the same length");

    VALUE result = rb_str_new(NULL, len);
    const unsigned char *sa = (const unsigned char *)RSTRING_PTR(a);
    const unsigned char *sb = (const unsigned char *)RSTRING_PTR(b);
    unsigned char *dst = (unsigned char *)RSTRING_PTR(result);

    for (long i = 0; i < len; i++)
        dst[i] = sa[i] ^ sb[i];

    return result;
}

/*
 * Teek::MGBA.count_changed_pixels(delta) → Integer
 *
 * Count the number of non-zero 4-byte pixels in a delta string.
 * Used alongside xor_delta to measure per-frame change rates.
 */
static VALUE
mgba_count_changed_pixels(VALUE mod, VALUE delta)
{
    (void)mod;
    StringValue(delta);

    long len = RSTRING_LEN(delta);
    const uint32_t *pixels = (const uint32_t *)RSTRING_PTR(delta);
    long count = len / 4;
    long changed = 0;

    for (long i = 0; i < count; i++) {
        if (pixels[i] != 0) changed++;
    }

    return LONG2NUM(changed);
}

/* --------------------------------------------------------- */
/* Init                                                      */
/* --------------------------------------------------------- */

void
Init_teek_mgba(void)
{
    /* Install no-op logger before any mGBA calls */
    mLogSetDefaultLogger(&s_null_logger);

    /* Teek module (may already exist from teek gem) */
    mTeek = rb_define_module("Teek");

    /* Teek::MGBA module */
    mTeekMGBA = rb_define_module_under(mTeek, "MGBA");

    /* Teek::MGBA::Core class */
    cCore = rb_define_class_under(mTeekMGBA, "Core", rb_cObject);
    rb_define_alloc_func(cCore, mgba_core_alloc);

    rb_define_method(cCore, "initialize",  mgba_core_initialize, -1);
    rb_define_method(cCore, "run_frame",   mgba_core_run_frame, 0);
    rb_define_method(cCore, "video_buffer", mgba_core_video_buffer, 0);
    rb_define_method(cCore, "video_buffer_argb", mgba_core_video_buffer_argb, 0);
    rb_define_method(cCore, "audio_buffer", mgba_core_audio_buffer, 0);
    rb_define_method(cCore, "set_keys",    mgba_core_set_keys, 1);
    rb_define_method(cCore, "width",       mgba_core_width, 0);
    rb_define_method(cCore, "height",      mgba_core_height, 0);
    rb_define_method(cCore, "title",       mgba_core_title, 0);
    rb_define_method(cCore, "game_code",   mgba_core_game_code, 0);
    rb_define_method(cCore, "maker_code",  mgba_core_maker_code, 0);
    rb_define_method(cCore, "checksum",    mgba_core_checksum, 0);
    rb_define_method(cCore, "platform",    mgba_core_platform, 0);
    rb_define_method(cCore, "rom_size",    mgba_core_rom_size, 0);
    rb_define_method(cCore, "save_state_to_file", mgba_core_save_state_to_file, 1);
    rb_define_method(cCore, "load_state_from_file", mgba_core_load_state_from_file, 1);
    rb_define_method(cCore, "color_correction=", mgba_core_set_color_correction, 1);
    rb_define_method(cCore, "color_correction?", mgba_core_color_correction_p, 0);
    rb_define_method(cCore, "frame_blending=", mgba_core_set_frame_blending, 1);
    rb_define_method(cCore, "frame_blending?", mgba_core_frame_blending_p, 0);
    rb_define_method(cCore, "rewind_init",   mgba_core_rewind_init, 1);
    rb_define_method(cCore, "rewind_deinit", mgba_core_rewind_deinit, 0);
    rb_define_method(cCore, "rewind_push",   mgba_core_rewind_push, 0);
    rb_define_method(cCore, "rewind_pop",    mgba_core_rewind_pop, 0);
    rb_define_method(cCore, "rewind_count",  mgba_core_rewind_count, 0);
    rb_define_method(cCore, "destroy",     mgba_core_destroy, 0);
    rb_define_method(cCore, "destroyed?",  mgba_core_destroyed_p, 0);

    /* GBA key constants (bitmask values for set_keys) */
    rb_define_const(mTeekMGBA, "KEY_A",      INT2NUM(1 << TEEK_GBA_KEY_A));
    rb_define_const(mTeekMGBA, "KEY_B",      INT2NUM(1 << TEEK_GBA_KEY_B));
    rb_define_const(mTeekMGBA, "KEY_SELECT", INT2NUM(1 << TEEK_GBA_KEY_SELECT));
    rb_define_const(mTeekMGBA, "KEY_START",  INT2NUM(1 << TEEK_GBA_KEY_START));
    rb_define_const(mTeekMGBA, "KEY_RIGHT",  INT2NUM(1 << TEEK_GBA_KEY_RIGHT));
    rb_define_const(mTeekMGBA, "KEY_LEFT",   INT2NUM(1 << TEEK_GBA_KEY_LEFT));
    rb_define_const(mTeekMGBA, "KEY_UP",     INT2NUM(1 << TEEK_GBA_KEY_UP));
    rb_define_const(mTeekMGBA, "KEY_DOWN",   INT2NUM(1 << TEEK_GBA_KEY_DOWN));
    rb_define_const(mTeekMGBA, "KEY_R",      INT2NUM(1 << TEEK_GBA_KEY_R));
    rb_define_const(mTeekMGBA, "KEY_L",      INT2NUM(1 << TEEK_GBA_KEY_L));

    /* Toast background generator */
    rb_define_module_function(mTeekMGBA, "toast_background", mgba_toast_background, 3);

    /* XOR delta for recording */
    rb_define_module_function(mTeekMGBA, "xor_delta", mgba_xor_delta, 2);
    rb_define_module_function(mTeekMGBA, "count_changed_pixels", mgba_count_changed_pixels, 1);
}
