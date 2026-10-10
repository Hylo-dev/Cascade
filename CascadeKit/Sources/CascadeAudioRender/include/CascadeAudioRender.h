//
//  CascadeAudioRender.h
//  CascadeKit
//

#ifndef CASCADE_AUDIO_RENDER_H
#define CASCADE_AUDIO_RENDER_H

#include <CoreAudioTypes/CoreAudioTypes.h>
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma clang assume_nonnull begin

/// CascadeAudioRender is the realtime render kernel of one controlled app.
///
/// The app's audio flows tap -> private aggregate -> IOProc, and the IOProc calls
/// `CascadeAudioRenderProcess` on Core Audio's realtime thread. That function is
/// the ONLY code that runs there, so its contract is the strictest in Cascade:
///
///   - it allocates nothing (no malloc, no free, no Objective-C, no Swift runtime);
///   - it takes no lock and waits for nothing (commands arrive through atomics);
///   - it makes no system call (the only libraries it touches are <math.h>,
///     <string.h> for memset/memcpy and <stdatomic.h>);
///   - it writes every byte of every output buffer, so a half-initialised
///     buffer never reaches the speakers.
///
/// Everything else (Create, Destroy, SetCommand, SetCrossfade, the counters)
/// is for the control side and may be called from any thread, except that
/// `Destroy` must wait until the IOProc has been stopped.
typedef struct CascadeAudioRender CascadeAudioRender;

/// CascadeAudioRenderFormat describes one side (tap input or device output) of the kernel.
///
/// `interleaved` selects one buffer holding `channels` samples per frame versus
/// `channels` buffers of one channel each. `maxFrames` is the largest slice the
/// IOProc is expected to deliver; Process never trusts it and clamps to the
/// real buffer sizes instead. `channels` is limited to 32.
typedef struct {
    double   sampleRate;
    uint32_t channels;
    bool     interleaved;
    bool     float64;
    uint32_t maxFrames;
} CascadeAudioRenderFormat;

/// Creates a kernel settled on `gain` (0...1, clamped; NaN reads as 0) and `muted`.
/// Allocates, so call it off the realtime thread. Returns NULL on an invalid format.
CascadeAudioRender *_Nullable CascadeAudioRenderCreate(
    CascadeAudioRenderFormat input,
    CascadeAudioRenderFormat output,
    double                   gain,
    bool                     muted
);

/// Publishes a new (gain, muted) command. Any thread; one atomic store, lock-free.
/// The realtime thread starts a 5 ms linear ramp from its current value to the
/// new target on the next slice. Mute is a ramp to 0 followed by exact zeros.
void CascadeAudioRenderSetCommand(CascadeAudioRender *renderer, double gain, bool muted);

/// Starts an equal-power ramp of this pipeline's share, applied on top of the gain.
///
/// The weight travels from `fromWeight` to `toWeight` over `frames` frames along
/// a quarter sine (fading in) or cosine (fading out) of a linear phase, so two
/// pipelines fading in opposite directions have squared weights that sum to 1.
/// `frames == 0` jumps to `toWeight`. One control thread at a time may call it.
void CascadeAudioRenderSetCrossfade(
    CascadeAudioRender *renderer,
    double              fromWeight,
    double              toWeight,
    uint32_t            frames
);

/// Renders `frames` frames of the tap in `input` into `output`. REALTIME-SAFE.
///
/// The tap is the LAST input buffer (an aggregate lists a device's own input
/// streams first); planar taps are the trailing `channels` buffers. Channels map
/// mono<->stereo (stereo to mono averages), otherwise by index, with missing
/// inputs zero and extra outputs zeroed. NaN and infinite input samples are
/// written as 0 and counted. Unity gain settled is bit-exact; there is no
/// boost, limiter, EQ or gate.
void CascadeAudioRenderProcess(
    CascadeAudioRender *renderer,
    const AudioBufferList *_Nullable input,
    AudioBufferList       *_Nullable output,
    uint32_t                         frames
);

/// Number of Process calls so far. Atomic; the watchdog reads it to see the IOProc is alive.
uint64_t CascadeAudioRenderCallbackCount(const CascadeAudioRender *renderer);

/// Number of NaN or infinite input samples replaced by silence so far. Atomic.
uint64_t CascadeAudioRenderInvalidSampleCount(const CascadeAudioRender *renderer);

/// Frees the kernel. Only after the IOProc is stopped and has returned.
void CascadeAudioRenderDestroy(CascadeAudioRender *_Nullable renderer);

#pragma clang assume_nonnull end

#ifdef __cplusplus
}
#endif

#endif
