#include "teek_sdl2.h"
#include <SDL2/SDL_mixer.h>

/* ---------------------------------------------------------
 * SDL2_mixer audio wrapper
 *
 * Provides Sound (Mix_Chunk) loading and playback.
 * Audio is independent of rendering — no Viewport needed.
 * --------------------------------------------------------- */

static VALUE cSound;
static VALUE cMusic;
static int mixer_initialized = 0;

static void
ensure_mixer_init(void)
{
    if (mixer_initialized) return;

    /* SDL audio subsystem must be initialized first */
    if (!(SDL_WasInit(SDL_INIT_AUDIO) & SDL_INIT_AUDIO)) {
        if (SDL_InitSubSystem(SDL_INIT_AUDIO) < 0) {
            rb_raise(rb_eRuntimeError, "SDL_InitSubSystem(AUDIO) failed: %s",
                     SDL_GetError());
        }
    }

    if (Mix_OpenAudio(44100, MIX_DEFAULT_FORMAT, 2, 2048) < 0) {
        rb_raise(rb_eRuntimeError, "Mix_OpenAudio failed: %s", Mix_GetError());
    }
    mixer_initialized = 1;
}

/* ---------------------------------------------------------
 * Sound (wraps Mix_Chunk)
 * --------------------------------------------------------- */

struct sdl2_sound {
    Mix_Chunk *chunk;
    int        destroyed;
};

static void
sound_free(void *ptr)
{
    struct sdl2_sound *s = ptr;
    if (!s->destroyed && s->chunk) {
        Mix_FreeChunk(s->chunk);
        s->chunk = NULL;
        s->destroyed = 1;
    }
    xfree(s);
}

static size_t
sound_memsize(const void *ptr)
{
    return sizeof(struct sdl2_sound);
}

static const rb_data_type_t sound_type = {
    .wrap_struct_name = "TeekSDL2::Sound",
    .function = {
        .dmark = NULL,
        .dfree = sound_free,
        .dsize = sound_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
sound_alloc(VALUE klass)
{
    struct sdl2_sound *s;
    VALUE obj = TypedData_Make_Struct(klass, struct sdl2_sound, &sound_type, s);
    s->chunk = NULL;
    s->destroyed = 0;
    return obj;
}

static struct sdl2_sound *
get_sound(VALUE self)
{
    struct sdl2_sound *s;
    TypedData_Get_Struct(self, struct sdl2_sound, &sound_type, s);
    if (s->destroyed || s->chunk == NULL) {
        rb_raise(rb_eRuntimeError, "sound has been destroyed");
    }
    return s;
}

/*
 * Teek::SDL2::Sound#initialize(path)
 *
 * Loads a WAV file. Automatically initializes the mixer if needed.
 */
static VALUE
sound_initialize(VALUE self, VALUE path)
{
    struct sdl2_sound *s;
    TypedData_Get_Struct(self, struct sdl2_sound, &sound_type, s);

    ensure_mixer_init();

    StringValue(path);
    Mix_Chunk *chunk = Mix_LoadWAV(StringValueCStr(path));
    if (!chunk) {
        rb_raise(rb_eRuntimeError, "Mix_LoadWAV failed: %s", Mix_GetError());
    }

    s->chunk = chunk;
    return self;
}

/*
 * Teek::SDL2::Sound#play(volume: nil, loops: 0, fade_ms: 0) -> Integer (channel)
 *
 * Plays the sound on the next available channel.
 * Optional volume (0..128, where 128 is full volume).
 * Optional loops: 0 = play once, N = play N extra times, -1 = loop forever.
 * Optional fade_ms: fade-in duration in milliseconds (0 = no fade).
 * Returns the channel number used.
 */
static VALUE
sound_play(int argc, VALUE *argv, VALUE self)
{
    struct sdl2_sound *s = get_sound(self);
    int loops = 0;
    int fade_ms = 0;

    VALUE kwargs;
    rb_scan_args(argc, argv, ":", &kwargs);

    if (!NIL_P(kwargs)) {
        ID keys[3];
        VALUE vals[3];
        keys[0] = rb_intern("volume");
        keys[1] = rb_intern("loops");
        keys[2] = rb_intern("fade_ms");

        rb_get_kwargs(kwargs, keys, 0, 3, vals);

        if (vals[0] != Qundef) {
            int vol = NUM2INT(vals[0]);
            if (vol < 0) vol = 0;
            if (vol > MIX_MAX_VOLUME) vol = MIX_MAX_VOLUME;
            Mix_VolumeChunk(s->chunk, vol);
        }

        if (vals[1] != Qundef) {
            loops = NUM2INT(vals[1]);
        }

        if (vals[2] != Qundef) {
            fade_ms = NUM2INT(vals[2]);
        }
    }

    int channel;
    if (fade_ms > 0) {
        channel = Mix_FadeInChannel(-1, s->chunk, loops, fade_ms);
    } else {
        channel = Mix_PlayChannel(-1, s->chunk, loops);
    }
    if (channel < 0) {
        rb_raise(rb_eRuntimeError, "Mix_PlayChannel failed: %s", Mix_GetError());
    }

    return INT2NUM(channel);
}

/*
 * Teek::SDL2.halt(channel) -> nil
 *
 * Immediately stops playback on the given channel.
 * Pass the channel number returned by Sound#play.
 */
static VALUE
mixer_halt_channel(VALUE mod, VALUE channel)
{
    Mix_HaltChannel(NUM2INT(channel));
    return Qnil;
}

/*
 * Teek::SDL2::Sound#volume = vol
 *
 * Sets the volume for this sound (0..128).
 */
static VALUE
sound_set_volume(VALUE self, VALUE vol)
{
    struct sdl2_sound *s = get_sound(self);
    int v = NUM2INT(vol);
    if (v < 0) v = 0;
    if (v > MIX_MAX_VOLUME) v = MIX_MAX_VOLUME;
    Mix_VolumeChunk(s->chunk, v);
    return vol;
}

/*
 * Teek::SDL2::Sound#volume -> Integer
 *
 * Returns the current volume for this sound (0..128).
 */
static VALUE
sound_get_volume(VALUE self)
{
    struct sdl2_sound *s = get_sound(self);
    /* Passing -1 queries without changing */
    return INT2NUM(Mix_VolumeChunk(s->chunk, -1));
}

/*
 * Teek::SDL2::Sound#destroy
 */
static VALUE
sound_destroy(VALUE self)
{
    struct sdl2_sound *s;
    TypedData_Get_Struct(self, struct sdl2_sound, &sound_type, s);
    if (!s->destroyed && s->chunk) {
        Mix_FreeChunk(s->chunk);
        s->chunk = NULL;
        s->destroyed = 1;
    }
    return Qnil;
}

/*
 * Teek::SDL2::Sound#destroyed? -> true/false
 */
static VALUE
sound_destroyed_p(VALUE self)
{
    struct sdl2_sound *s;
    TypedData_Get_Struct(self, struct sdl2_sound, &sound_type, s);
    return s->destroyed ? Qtrue : Qfalse;
}

/* ---------------------------------------------------------
 * Music (wraps Mix_Music — streaming playback for MP3/OGG/WAV)
 * --------------------------------------------------------- */

struct sdl2_music {
    Mix_Music *music;
    int        destroyed;
};

static void
music_free(void *ptr)
{
    struct sdl2_music *m = ptr;
    if (!m->destroyed && m->music) {
        Mix_FreeMusic(m->music);
        m->music = NULL;
        m->destroyed = 1;
    }
    xfree(m);
}

static size_t
music_memsize(const void *ptr)
{
    return sizeof(struct sdl2_music);
}

static const rb_data_type_t music_type = {
    .wrap_struct_name = "TeekSDL2::Music",
    .function = {
        .dmark = NULL,
        .dfree = music_free,
        .dsize = music_memsize,
    },
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static VALUE
music_alloc(VALUE klass)
{
    struct sdl2_music *m;
    VALUE obj = TypedData_Make_Struct(klass, struct sdl2_music, &music_type, m);
    m->music = NULL;
    m->destroyed = 0;
    return obj;
}

static struct sdl2_music *
get_music(VALUE self)
{
    struct sdl2_music *m;
    TypedData_Get_Struct(self, struct sdl2_music, &music_type, m);
    if (m->destroyed || m->music == NULL) {
        rb_raise(rb_eRuntimeError, "music has been destroyed");
    }
    return m;
}

/*
 * Teek::SDL2::Music#initialize(path)
 *
 * Loads a music file (MP3, OGG, WAV). Initializes mixer if needed.
 */
static VALUE
music_initialize(VALUE self, VALUE path)
{
    struct sdl2_music *m;
    TypedData_Get_Struct(self, struct sdl2_music, &music_type, m);

    ensure_mixer_init();

    StringValue(path);
    Mix_Music *mus = Mix_LoadMUS(StringValueCStr(path));
    if (!mus) {
        rb_raise(rb_eRuntimeError, "Mix_LoadMUS failed: %s", Mix_GetError());
    }

    m->music = mus;
    return self;
}

/*
 * Teek::SDL2::Music#play(loops: -1, fade_ms: 0) -> nil
 *
 * Starts playing the music. Only one music track plays at a time.
 * loops: -1 = loop forever (default), 0 = play once, N = play N extra times.
 * fade_ms: fade-in duration in milliseconds (0 = no fade).
 */
static VALUE
music_play(int argc, VALUE *argv, VALUE self)
{
    struct sdl2_music *m = get_music(self);
    int loops = -1;
    int fade_ms = 0;

    VALUE kwargs;
    rb_scan_args(argc, argv, ":", &kwargs);

    if (!NIL_P(kwargs)) {
        ID keys[2];
        VALUE vals[2];
        keys[0] = rb_intern("loops");
        keys[1] = rb_intern("fade_ms");

        rb_get_kwargs(kwargs, keys, 0, 2, vals);

        if (vals[0] != Qundef) {
            loops = NUM2INT(vals[0]);
        }

        if (vals[1] != Qundef) {
            fade_ms = NUM2INT(vals[1]);
        }
    }

    int result;
    if (fade_ms > 0) {
        result = Mix_FadeInMusic(m->music, loops, fade_ms);
    } else {
        result = Mix_PlayMusic(m->music, loops);
    }
    if (result < 0) {
        rb_raise(rb_eRuntimeError, "Mix_PlayMusic failed: %s", Mix_GetError());
    }

    return Qnil;
}

/*
 * Teek::SDL2::Music#stop -> nil
 *
 * Stops music playback.
 */
static VALUE
music_stop(VALUE self)
{
    get_music(self); /* validate not destroyed */
    Mix_HaltMusic();
    return Qnil;
}

/*
 * Teek::SDL2::Music#pause -> nil
 */
static VALUE
music_pause(VALUE self)
{
    get_music(self);
    Mix_PauseMusic();
    return Qnil;
}

/*
 * Teek::SDL2::Music#resume -> nil
 */
static VALUE
music_resume(VALUE self)
{
    get_music(self);
    Mix_ResumeMusic();
    return Qnil;
}

/*
 * Teek::SDL2::Music#playing? -> true/false
 */
static VALUE
music_playing_p(VALUE self)
{
    get_music(self);
    return Mix_PlayingMusic() ? Qtrue : Qfalse;
}

/*
 * Teek::SDL2::Music#paused? -> true/false
 */
static VALUE
music_paused_p(VALUE self)
{
    get_music(self);
    return Mix_PausedMusic() ? Qtrue : Qfalse;
}

/*
 * Teek::SDL2::Music#volume = vol
 *
 * Sets music volume (0..128).
 */
static VALUE
music_set_volume(VALUE self, VALUE vol)
{
    get_music(self);
    int v = NUM2INT(vol);
    if (v < 0) v = 0;
    if (v > MIX_MAX_VOLUME) v = MIX_MAX_VOLUME;
    Mix_VolumeMusic(v);
    return vol;
}

/*
 * Teek::SDL2::Music#volume -> Integer
 */
static VALUE
music_get_volume(VALUE self)
{
    get_music(self);
    return INT2NUM(Mix_VolumeMusic(-1));
}

/*
 * Teek::SDL2::Music#destroy
 */
static VALUE
music_destroy(VALUE self)
{
    struct sdl2_music *m;
    TypedData_Get_Struct(self, struct sdl2_music, &music_type, m);
    if (!m->destroyed && m->music) {
        Mix_HaltMusic();
        Mix_FreeMusic(m->music);
        m->music = NULL;
        m->destroyed = 1;
    }
    return Qnil;
}

/*
 * Teek::SDL2::Music#destroyed? -> true/false
 */
static VALUE
music_destroyed_p(VALUE self)
{
    struct sdl2_music *m;
    TypedData_Get_Struct(self, struct sdl2_music, &music_type, m);
    return m->destroyed ? Qtrue : Qfalse;
}

/*
 * Teek::SDL2.open_audio
 *
 * Explicitly initialize the audio mixer. Safe to call multiple times.
 */
static VALUE
mixer_open_audio(VALUE mod)
{
    ensure_mixer_init();
    return Qnil;
}

/*
 * Teek::SDL2.close_audio
 *
 * Shut down the audio mixer and free resources.
 */
static VALUE
mixer_close_audio(VALUE mod)
{
    if (mixer_initialized) {
        Mix_CloseAudio();
        mixer_initialized = 0;
    }
    return Qnil;
}

/* ---------------------------------------------------------
 * Audio capture (write mixed output to WAV file)
 *
 * Uses Mix_SetPostMix to tap the final mixed audio stream.
 * The callback runs in SDL's audio thread — pure C, no Ruby.
 * --------------------------------------------------------- */

static FILE   *capture_file       = NULL;
static Uint32  capture_data_bytes = 0;
static int     capture_freq       = 0;
static int     capture_channels   = 0;

/* Write a 44-byte WAV header. Call once at start (placeholder) and
 * once at stop (with real data_size) after seeking to byte 0. */
static void
write_wav_header(FILE *f, int freq, int channels, Uint32 data_size)
{
    Uint16 bits_per_sample = 16;
    Uint16 block_align     = (Uint16)(channels * (bits_per_sample / 8));
    Uint32 byte_rate       = (Uint32)(freq * block_align);
    Uint32 riff_size       = 36 + data_size;
    Uint32 fmt_size        = 16;
    Uint16 audio_fmt       = 1; /* PCM */
    Uint16 ch              = (Uint16)channels;
    Uint32 sr              = (Uint32)freq;

    fwrite("RIFF", 1, 4, f);
    fwrite(&riff_size, 4, 1, f);
    fwrite("WAVE", 1, 4, f);
    fwrite("fmt ", 1, 4, f);
    fwrite(&fmt_size, 4, 1, f);
    fwrite(&audio_fmt, 2, 1, f);
    fwrite(&ch, 2, 1, f);
    fwrite(&sr, 4, 1, f);
    fwrite(&byte_rate, 4, 1, f);
    fwrite(&block_align, 2, 1, f);
    fwrite(&bits_per_sample, 2, 1, f);
    fwrite("data", 1, 4, f);
    fwrite(&data_size, 4, 1, f);
}

/* Called by SDL's audio thread after all mixing is done. */
static void
capture_postmix(void *udata, Uint8 *stream, int len)
{
    (void)udata;
    if (capture_file && len > 0) {
        fwrite(stream, 1, (size_t)len, capture_file);
        capture_data_bytes += (Uint32)len;
    }
}

/*
 * Teek::SDL2.start_audio_capture(path) -> nil
 *
 * Begin recording the mixed audio output to a WAV file at +path+.
 * Everything that plays through the mixer (sounds, music) is captured.
 * Call {.stop_audio_capture} to finalize the file.
 */
static VALUE
mixer_start_capture(VALUE mod, VALUE path)
{
    if (capture_file) {
        rb_raise(rb_eRuntimeError, "audio capture already in progress");
    }

    ensure_mixer_init();

    int freq, channels;
    Uint16 format;
    if (!Mix_QuerySpec(&freq, &format, &channels)) {
        rb_raise(rb_eRuntimeError, "Mix_QuerySpec failed — mixer not open");
    }

    /* WAV files store little-endian PCM. We require the mixer opened
     * with a LE S16 format (the default on all modern platforms). */
    if (format != AUDIO_S16LSB) {
        rb_raise(rb_eRuntimeError,
                 "audio capture requires S16LE format (mixer opened with 0x%04x)",
                 (unsigned)format);
    }

    StringValue(path);
    capture_file = fopen(StringValueCStr(path), "wb");
    if (!capture_file) {
        rb_raise(rb_eRuntimeError, "cannot open capture file: %s",
                 StringValueCStr(path));
    }

    capture_freq       = freq;
    capture_channels   = channels;
    capture_data_bytes = 0;

    write_wav_header(capture_file, freq, channels, 0); /* placeholder */
    Mix_SetPostMix(capture_postmix, NULL);

    return Qnil;
}

/*
 * Teek::SDL2.stop_audio_capture -> nil
 *
 * Stop recording and finalize the WAV file. Safe to call even if
 * no capture is in progress (returns nil immediately).
 */
static VALUE
mixer_stop_capture(VALUE mod)
{
    if (!capture_file) return Qnil;

    Mix_SetPostMix(NULL, NULL);

    /* Rewrite header with actual data size */
    fseek(capture_file, 0, SEEK_SET);
    write_wav_header(capture_file, capture_freq, capture_channels,
                     capture_data_bytes);
    fclose(capture_file);
    capture_file       = NULL;
    capture_data_bytes = 0;

    return Qnil;
}

/* ---------------------------------------------------------
 * Channel and music helpers
 * --------------------------------------------------------- */

/*
 * Teek::SDL2.playing?(channel) -> true/false
 *
 * Returns true if the given channel is currently playing.
 */
static VALUE
mixer_channel_playing_p(VALUE mod, VALUE channel)
{
    return Mix_Playing(NUM2INT(channel)) ? Qtrue : Qfalse;
}

/*
 * Teek::SDL2.channel_paused?(channel) -> true/false
 *
 * Returns true if the given channel is paused.
 */
static VALUE
mixer_channel_paused_p(VALUE mod, VALUE channel)
{
    return Mix_Paused(NUM2INT(channel)) ? Qtrue : Qfalse;
}

/*
 * Teek::SDL2.pause_channel(channel) -> nil
 *
 * Pauses playback on the given channel.
 */
static VALUE
mixer_pause_channel(VALUE mod, VALUE channel)
{
    Mix_Pause(NUM2INT(channel));
    return Qnil;
}

/*
 * Teek::SDL2.resume_channel(channel) -> nil
 *
 * Resumes playback on a paused channel.
 */
static VALUE
mixer_resume_channel(VALUE mod, VALUE channel)
{
    Mix_Resume(NUM2INT(channel));
    return Qnil;
}

/*
 * Teek::SDL2.channel_volume(channel, vol = -1) -> Integer
 *
 * Sets or queries volume for a channel (0..128).
 * Pass -1 for vol (or omit) to query without changing.
 */
static VALUE
mixer_channel_volume(int argc, VALUE *argv, VALUE mod)
{
    VALUE ch, vol;
    rb_scan_args(argc, argv, "11", &ch, &vol);
    int v = NIL_P(vol) ? -1 : NUM2INT(vol);
    return INT2NUM(Mix_Volume(NUM2INT(ch), v));
}

/*
 * Teek::SDL2.fade_out_music(ms) -> nil
 *
 * Gradually fade out the currently playing music over +ms+ milliseconds.
 */
static VALUE
mixer_fade_out_music(VALUE mod, VALUE ms)
{
    Mix_FadeOutMusic(NUM2INT(ms));
    return Qnil;
}

/*
 * Teek::SDL2.fade_out_channel(channel, ms) -> nil
 *
 * Gradually fade out the given channel over +ms+ milliseconds.
 */
static VALUE
mixer_fade_out_channel(VALUE mod, VALUE channel, VALUE ms)
{
    Mix_FadeOutChannel(NUM2INT(channel), NUM2INT(ms));
    return Qnil;
}

/* Master volume — requires SDL2_mixer >= 2.6.0 */
#if (SDL_MIXER_MAJOR_VERSION > 2) || \
    (SDL_MIXER_MAJOR_VERSION == 2 && SDL_MIXER_MINOR_VERSION >= 6)
#define HAVE_MIX_MASTER_VOLUME 1
#endif

/*
 * Teek::SDL2.master_volume = vol -> Integer
 *
 * Sets the master volume (0..128). Returns the previous volume.
 * Raises NotImplementedError if SDL2_mixer < 2.6.
 */
static VALUE
mixer_set_master_volume(VALUE mod, VALUE vol)
{
#ifdef HAVE_MIX_MASTER_VOLUME
    int v = NUM2INT(vol);
    if (v < 0) v = 0;
    if (v > MIX_MAX_VOLUME) v = MIX_MAX_VOLUME;
    return INT2NUM(Mix_MasterVolume(v));
#else
    rb_raise(rb_eNotImpError,
             "master_volume requires SDL2_mixer >= 2.6 (you have %d.%d.%d)",
             SDL_MIXER_MAJOR_VERSION, SDL_MIXER_MINOR_VERSION,
             SDL_MIXER_PATCHLEVEL);
    return Qnil; /* unreachable */
#endif
}

/*
 * Teek::SDL2.master_volume -> Integer
 *
 * Returns the current master volume (0..128).
 * Raises NotImplementedError if SDL2_mixer < 2.6.
 */
static VALUE
mixer_get_master_volume(VALUE mod)
{
#ifdef HAVE_MIX_MASTER_VOLUME
    return INT2NUM(Mix_MasterVolume(-1));
#else
    rb_raise(rb_eNotImpError,
             "master_volume requires SDL2_mixer >= 2.6 (you have %d.%d.%d)",
             SDL_MIXER_MAJOR_VERSION, SDL_MIXER_MINOR_VERSION,
             SDL_MIXER_PATCHLEVEL);
    return Qnil;
#endif
}

/* ---------------------------------------------------------
 * Init
 * --------------------------------------------------------- */

void
Init_sdl2mixer(VALUE mTeekSDL2)
{
    /* Module-level audio functions */
    rb_define_module_function(mTeekSDL2, "open_audio", mixer_open_audio, 0);
    rb_define_module_function(mTeekSDL2, "close_audio", mixer_close_audio, 0);
    rb_define_module_function(mTeekSDL2, "halt", mixer_halt_channel, 1);
    rb_define_module_function(mTeekSDL2, "playing?", mixer_channel_playing_p, 1);
    rb_define_module_function(mTeekSDL2, "channel_paused?", mixer_channel_paused_p, 1);
    rb_define_module_function(mTeekSDL2, "pause_channel", mixer_pause_channel, 1);
    rb_define_module_function(mTeekSDL2, "resume_channel", mixer_resume_channel, 1);
    rb_define_module_function(mTeekSDL2, "channel_volume", mixer_channel_volume, -1);
    rb_define_module_function(mTeekSDL2, "fade_out_music", mixer_fade_out_music, 1);
    rb_define_module_function(mTeekSDL2, "fade_out_channel",
                              mixer_fade_out_channel, 2);
    rb_define_module_function(mTeekSDL2, "start_audio_capture",
                              mixer_start_capture, 1);
    rb_define_module_function(mTeekSDL2, "stop_audio_capture",
                              mixer_stop_capture, 0);

    rb_define_module_function(mTeekSDL2, "master_volume=",
                              mixer_set_master_volume, 1);
    rb_define_module_function(mTeekSDL2, "master_volume",
                              mixer_get_master_volume, 0);

    /* Sound class */
    cSound = rb_define_class_under(mTeekSDL2, "Sound", rb_cObject);
    rb_define_alloc_func(cSound, sound_alloc);
    rb_define_method(cSound, "initialize", sound_initialize, 1);
    rb_define_method(cSound, "play", sound_play, -1);
    rb_define_method(cSound, "volume=", sound_set_volume, 1);
    rb_define_method(cSound, "volume", sound_get_volume, 0);
    rb_define_method(cSound, "destroy", sound_destroy, 0);
    rb_define_method(cSound, "destroyed?", sound_destroyed_p, 0);

    /* Music class */
    cMusic = rb_define_class_under(mTeekSDL2, "Music", rb_cObject);
    rb_define_alloc_func(cMusic, music_alloc);
    rb_define_method(cMusic, "initialize", music_initialize, 1);
    rb_define_method(cMusic, "play", music_play, -1);
    rb_define_method(cMusic, "stop", music_stop, 0);
    rb_define_method(cMusic, "pause", music_pause, 0);
    rb_define_method(cMusic, "resume", music_resume, 0);
    rb_define_method(cMusic, "playing?", music_playing_p, 0);
    rb_define_method(cMusic, "paused?", music_paused_p, 0);
    rb_define_method(cMusic, "volume=", music_set_volume, 1);
    rb_define_method(cMusic, "volume", music_get_volume, 0);
    rb_define_method(cMusic, "destroy", music_destroy, 0);
    rb_define_method(cMusic, "destroyed?", music_destroyed_p, 0);
}
