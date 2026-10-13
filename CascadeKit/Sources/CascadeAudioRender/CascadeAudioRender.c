//
//  CascadeAudioRender.c
//  CascadeKit
//

#include "CascadeAudioRender.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

// One translation unit. Create and Destroy (below the realtime section) use
// <stdlib.h> to allocate the state off the realtime thread; everything between
// "BEGIN REALTIME" and "END REALTIME" calls nothing outside <math.h>
// (isfinite, round, sin, cos), <string.h> (memcpy, memset) and <stdatomic.h>.

#define CASCADE_RENDER_MAX_CHANNELS  32u
#define CASCADE_RENDER_RAMP_SECONDS  0.005
#define CASCADE_RENDER_HALF_PI       1.57079632679489661923
#define CASCADE_RENDER_CACHE_LINE    64u
#define CASCADE_RENDER_MUTE_BIT      (UINT64_C(1) << 63)

/// CascadeAudioRender holds the kernel's whole state in three cache-line groups.
///
/// The atomics in the first group are written by control threads; the plain
/// fields after them belong to the realtime thread alone, so they need no
/// synchronisation and sharing nothing keeps the control side's stores from
/// invalidating the line the render loop is reading.
struct CascadeAudioRender {
    _Alignas(CASCADE_RENDER_CACHE_LINE)
    _Atomic uint64_t         command;               // Gain bits, sign bit = muted.
    _Atomic uint64_t         crossfadeWeights;      // Two float32 bit patterns: from | to << 32.
    _Atomic uint64_t         crossfadeRequest;      // Generation << 32 | frames.

    _Alignas(CASCADE_RENDER_CACHE_LINE)
    _Atomic uint64_t         callbackCount;
    _Atomic uint64_t         invalidSampleCount;

    _Alignas(CASCADE_RENDER_CACHE_LINE)
    CascadeAudioRenderFormat inputFormat;
    CascadeAudioRenderFormat outputFormat;
    uint32_t                 rampFrames;

    uint32_t                 destinationBuffers[CASCADE_RENDER_MAX_DESTINATIONS];
    uint32_t                 destinationCount;

    uint64_t                 seenCommand;
    double                   currentGain;
    double                   targetGain;
    double                   gainStep;
    uint32_t                 gainFramesRemaining;

    uint32_t                 seenCrossfadeGeneration;
    double                   crossfadeFrom;
    double                   crossfadeTo;
    double                   crossfadeWeight;
    uint32_t                 crossfadeTotalFrames;
    uint32_t                 crossfadeFramesRemaining;
};

// MARK: - Command encoding (pure, shared by both sides)

/// Packs (gain, muted) into one 64-bit word.
///
/// A gain in 0...1 never has the sign bit of its IEEE-754 double set, so that
/// bit carries `muted` and the gain keeps its full 53-bit precision. One word
/// means one atomic load gives the realtime thread a coherent pair.
static uint64_t encodeCommand(double gain, bool isMuted)
{
    if (!(gain > 0.0)) {
        gain = 0.0; // Negative, zero and NaN all collapse to a positive zero.
    }
    if (gain > 1.0) {
        gain = 1.0; // No boost, ever.
    }
    uint64_t gainBits;
    memcpy(&gainBits, &gain, sizeof gainBits);
    return isMuted ? (gainBits | CASCADE_RENDER_MUTE_BIT) : gainBits;
}

static double decodeTargetGain(uint64_t command)
{
    if ((command & CASCADE_RENDER_MUTE_BIT) != 0) {
        return 0.0;
    }
    double gain;
    memcpy(&gain, &command, sizeof gain);
    return gain;
}

static float clampedWeight(double weight)
{
    if (!(weight > 0.0)) {
        return 0.0f;
    }
    return weight > 1.0 ? 1.0f : (float)weight;
}

// MARK: - BEGIN REALTIME

/// Plane describes where the channels of one side live, as seen by the render loop.
///
/// Interleaved or planar, every channel is a base pointer plus a byte stride per
/// frame, so the loop never branches on layout. `frameCapacity` is how many
/// frames the buffers really hold, which is what keeps a short buffer from
/// being overrun when the caller asks for more frames than it provided.
typedef struct {
    uint8_t *bases[CASCADE_RENDER_MAX_CHANNELS];
    uint32_t strides[CASCADE_RENDER_MAX_CHANNELS];
    uint32_t channelCount;
    uint32_t frameCapacity;
} Plane;

static void buildPlane(
    Plane                          *plane,
    const AudioBuffer              *buffers,
    uint32_t                        bufferCount,
    const CascadeAudioRenderFormat *format,
    bool                            takesTrailingBuffers
)
{
    uint32_t bytesPerSample = format->float64 ? 8u : 4u;

    plane->channelCount  = 0;
    plane->frameCapacity = 0;

    if (bufferCount == 0) {
        return;
    }

    if (format->interleaved) {
        const AudioBuffer *buffer = &buffers[takesTrailingBuffers ? bufferCount - 1 : 0];
        if (buffer->mData == NULL) {
            return;
        }

        uint64_t actualChannels = buffer->mNumberChannels != 0 ? buffer->mNumberChannels : format->channels;
        uint64_t frameBytes     = actualChannels * bytesPerSample;
        if (frameBytes > 4096) {
            return; // Not a buffer this kernel was built for; treated as absent.
        }

        uint32_t exposed = actualChannels < CASCADE_RENDER_MAX_CHANNELS
            ? (uint32_t)actualChannels
            : CASCADE_RENDER_MAX_CHANNELS;
        for (uint32_t channel = 0; channel < exposed; channel++) {
            plane->bases[channel]   = (uint8_t *)buffer->mData + (size_t)channel * bytesPerSample;
            plane->strides[channel] = (uint32_t)frameBytes;
        }
        plane->channelCount  = exposed;
        plane->frameCapacity = (uint32_t)(buffer->mDataByteSize / frameBytes);
        return;
    }

    uint32_t channelCount = format->channels < bufferCount ? format->channels : bufferCount;
    uint32_t firstBuffer  = takesTrailingBuffers ? bufferCount - channelCount : 0;
    uint32_t capacity     = UINT32_MAX;

    for (uint32_t channel = 0; channel < channelCount; channel++) {
        const AudioBuffer *buffer = &buffers[firstBuffer + channel];
        if (buffer->mData == NULL) {
            return; // A planar side with a hole is treated as absent as a whole.
        }
        uint32_t bufferFrames = buffer->mDataByteSize / bytesPerSample;
        if (bufferFrames < capacity) {
            capacity = bufferFrames;
        }
        plane->bases[channel]   = (uint8_t *)buffer->mData;
        plane->strides[channel] = bytesPerSample;
    }
    plane->channelCount  = channelCount;
    plane->frameCapacity = channelCount == 0 ? 0 : capacity;
}

static inline double loadSample(const uint8_t *location, bool isFloat64)
{
    if (isFloat64) {
        double value;
        memcpy(&value, location, sizeof value);
        return value;
    }
    float value;
    memcpy(&value, location, sizeof value);
    return (double)value;
}

static inline void storeSample(uint8_t *location, bool isFloat64, double value)
{
    if (isFloat64) {
        memcpy(location, &value, sizeof value);
        return;
    }
    float narrowed = (float)value;
    memcpy(location, &narrowed, sizeof narrowed);
}

/// Picks up a changed command or crossfade request. Runs once per Process call.
///
/// A new gain target starts a ramp from wherever the gain is right now (maybe
/// halfway through the previous ramp) over a fixed 5 ms, so the slope is the
/// same for a tiny nudge and a full mute, and nothing ever steps.
static void applyPendingControl(CascadeAudioRender *renderer)
{
    uint64_t command = atomic_load_explicit(&renderer->command, memory_order_acquire);
    if (command != renderer->seenCommand) {
        renderer->seenCommand = command;

        double newTarget = decodeTargetGain(command);
        if (newTarget != renderer->targetGain) {
            renderer->targetGain = newTarget;
            if (renderer->rampFrames == 0) {
                renderer->currentGain         = newTarget;
                renderer->gainFramesRemaining = 0;
            } else {
                renderer->gainStep            = (newTarget - renderer->currentGain) / (double)renderer->rampFrames;
                renderer->gainFramesRemaining = renderer->rampFrames;
            }
        }
    }

    uint64_t request    = atomic_load_explicit(&renderer->crossfadeRequest, memory_order_acquire);
    uint32_t generation = (uint32_t)(request >> 32);
    if (generation != renderer->seenCrossfadeGeneration) {
        uint64_t weights = atomic_load_explicit(&renderer->crossfadeWeights, memory_order_acquire);
        uint64_t confirm = atomic_load_explicit(&renderer->crossfadeRequest, memory_order_acquire);
        if (confirm != request) {
            return; // A newer request landed mid-read; take it whole on the next slice.
        }
        renderer->seenCrossfadeGeneration = generation;

        uint32_t fromBits = (uint32_t)weights;
        uint32_t toBits   = (uint32_t)(weights >> 32);
        float    from;
        float    to;
        memcpy(&from, &fromBits, sizeof from);
        memcpy(&to,   &toBits,   sizeof to);

        uint32_t frames = (uint32_t)request;
        renderer->crossfadeFrom = from;
        renderer->crossfadeTo   = to;
        if (frames == 0) {
            renderer->crossfadeWeight          = to;
            renderer->crossfadeFramesRemaining = 0;
        } else {
            renderer->crossfadeWeight          = from;
            renderer->crossfadeTotalFrames     = frames;
            renderer->crossfadeFramesRemaining = frames;
        }
    }
}

/// Advances the gain ramp and the crossfade by one frame and returns the scale for it.
///
/// Called once per frame, never per channel, so every channel of a frame gets the
/// same scale. Gain moves linearly; the crossfade weight follows a quarter sine
/// (fading in) or cosine (fading out) of the linear phase, which makes two
/// opposite pipelines' squared weights sum to 1. Both snap to their exact target
/// on the last frame so neither drifts and "settled" means exactly settled.
static inline double advanceScale(CascadeAudioRender *renderer)
{
    if (renderer->gainFramesRemaining > 0) {
        renderer->gainFramesRemaining--;
        renderer->currentGain = renderer->gainFramesRemaining == 0
            ? renderer->targetGain
            : renderer->currentGain + renderer->gainStep;
    }

    if (renderer->crossfadeFramesRemaining > 0) {
        renderer->crossfadeFramesRemaining--;
        if (renderer->crossfadeFramesRemaining == 0) {
            renderer->crossfadeWeight = renderer->crossfadeTo;
        } else {
            double phase = (double)(renderer->crossfadeTotalFrames - renderer->crossfadeFramesRemaining)
                         / (double)renderer->crossfadeTotalFrames
                         * CASCADE_RENDER_HALF_PI;
            double from  = renderer->crossfadeFrom;
            double to    = renderer->crossfadeTo;
            renderer->crossfadeWeight = to >= from
                ? from + (to - from) * sin(phase)
                : to   + (from - to) * cos(phase);
        }
    }

    return renderer->currentGain * renderer->crossfadeWeight;
}

void CascadeAudioRenderProcess(
    CascadeAudioRender    *renderer,
    const AudioBufferList *input,
    AudioBufferList       *output,
    uint32_t               frames
)
{
    atomic_fetch_add_explicit(&renderer->callbackCount, 1, memory_order_relaxed);

    if (output == NULL) {
        return;
    }

    applyPendingControl(renderer);

    const bool inputIsFloat64  = renderer->inputFormat.float64;
    const bool outputIsFloat64 = renderer->outputFormat.float64;
    const bool outputInterleaved = renderer->outputFormat.interleaved;
    const uint32_t outputBufferCount = output->mNumberBuffers;
    const AudioBuffer *outputBuffers = output->mBuffers;
    const uint32_t destinationCount  = renderer->destinationCount;

    Plane inputPlane;
    inputPlane.channelCount  = 0;
    inputPlane.frameCapacity = 0;

    if (input != NULL) {
        buildPlane(&inputPlane, input->mBuffers, input->mNumberBuffers, &renderer->inputFormat, true);
    }

    // One plane per destination, each looking at the output list from its own first buffer. A
    // destination whose first buffer is past the end stays empty (channelCount 0, capacity 0),
    // and the render loop skips it by its capacity.
    Plane    destinations[CASCADE_RENDER_MAX_DESTINATIONS];
    uint32_t longestCapacity = 0;
    for (uint32_t index = 0; index < destinationCount; index++) {
        destinations[index].channelCount  = 0;
        destinations[index].frameCapacity = 0;

        uint32_t firstBuffer = renderer->destinationBuffers[index];
        if (firstBuffer >= outputBufferCount) {
            continue;
        }
        buildPlane(
            &destinations[index],
            outputBuffers + firstBuffer,
            outputBufferCount - firstBuffer,
            &renderer->outputFormat,
            false
        );
        if (destinations[index].frameCapacity > longestCapacity) {
            longestCapacity = destinations[index].frameCapacity;
        }
    }

    uint32_t frameCount = frames < longestCapacity ? frames : longestCapacity;
    uint32_t inputChannels  = inputPlane.channelCount;
    uint64_t invalidSamples = 0;
    double   inputFrame[CASCADE_RENDER_MAX_CHANNELS];

    for (uint32_t frame = 0; frame < frameCount; frame++) {
        // Once per frame, whatever the number of destinations: the gain ramp and the
        // crossfade are time, and the same instant must sound the same on every device.
        double scale = advanceScale(renderer);

        if (frame < inputPlane.frameCapacity) {
            for (uint32_t channel = 0; channel < inputChannels; channel++) {
                double sample = loadSample(
                    inputPlane.bases[channel] + (size_t)frame * inputPlane.strides[channel],
                    inputIsFloat64
                );
                if (!isfinite(sample)) {
                    sample = 0.0;
                    invalidSamples++;
                }
                inputFrame[channel] = sample;
            }
        } else {
            for (uint32_t channel = 0; channel < inputChannels; channel++) {
                inputFrame[channel] = 0.0;
            }
        }

        for (uint32_t index = 0; index < destinationCount; index++) {
            const Plane *destination = &destinations[index];
            if (frame >= destination->frameCapacity) {
                continue; // Absent, or a shorter buffer than its siblings.
            }

            // Each device maps the same frame to ITS channel count: a mono speaker next to a
            // stereo headset gets the mix, not the left channel.
            uint32_t outputChannels = destination->channelCount;
            for (uint32_t channel = 0; channel < outputChannels; channel++) {
                double sample;
                if (outputChannels == 1 && inputChannels == 2) {
                    sample = (inputFrame[0] + inputFrame[1]) * 0.5;
                } else if (outputChannels == 2 && inputChannels == 1) {
                    sample = inputFrame[0];
                } else {
                    sample = channel < inputChannels ? inputFrame[channel] : 0.0;
                }

                // A settled mute must be a positive zero, not -0.0 from a negative sample.
                double scaled = scale == 0.0 ? 0.0 : sample * scale;
                storeSample(
                    destination->bases[channel] + (size_t)frame * destination->strides[channel],
                    outputIsFloat64,
                    scaled
                );
            }
        }
    }

    if (invalidSamples != 0) {
        atomic_fetch_add_explicit(&renderer->invalidSampleCount, invalidSamples, memory_order_relaxed);
    }

    // Every output byte is ours to write: the tail of a used buffer and every buffer no
    // destination owns (a device's extra streams) become zeros. A buffer is used by the
    // destination that starts there (interleaved) or covers it (planar), for as many frames
    // as that destination really got.
    uint32_t bytesPerSample = outputIsFloat64 ? 8u : 4u;
    for (uint32_t index = 0; index < outputBufferCount; index++) {
        const AudioBuffer *buffer = &outputBuffers[index];
        if (buffer->mData == NULL) {
            continue;
        }

        size_t usedBytes = 0;
        for (uint32_t owner = 0; owner < destinationCount; owner++) {
            const Plane *destination = &destinations[owner];
            if (destination->channelCount == 0) {
                continue;
            }

            uint32_t firstBuffer = renderer->destinationBuffers[owner];
            uint32_t written     = frameCount < destination->frameCapacity ? frameCount : destination->frameCapacity;
            size_t   ownedBytes  = 0;
            if (outputInterleaved) {
                if (index == firstBuffer) {
                    ownedBytes = (size_t)written * destination->strides[0];
                }
            } else if (index >= firstBuffer && index - firstBuffer < destination->channelCount) {
                ownedBytes = (size_t)written * bytesPerSample;
            }
            if (ownedBytes > usedBytes) {
                usedBytes = ownedBytes;
            }
        }
        if (buffer->mDataByteSize > usedBytes) {
            memset((uint8_t *)buffer->mData + usedBytes, 0, buffer->mDataByteSize - usedBytes);
        }
    }
}

/// How many frames a slice holds, as the IOProc knows it: the output's, else the tap's.
///
/// Core Audio hands an IOProc buffers, not a frame count, so the count is the largest capacity
/// among the destinations, in the output format. A device that gave no usable output buffer
/// falls back to the tap's capacity; `Process` still clamps to the real buffers either way.
static uint32_t ioProcFrameCount(
    const CascadeAudioRender *renderer,
    const AudioBufferList    *input,
    const AudioBufferList    *output
)
{
    Plane plane;
    plane.channelCount  = 0;
    plane.frameCapacity = 0;

    if (output != NULL) {
        uint32_t longestCapacity = 0;
        for (uint32_t index = 0; index < renderer->destinationCount; index++) {
            uint32_t firstBuffer = renderer->destinationBuffers[index];
            if (firstBuffer >= output->mNumberBuffers) {
                continue;
            }
            buildPlane(
                &plane,
                output->mBuffers + firstBuffer,
                output->mNumberBuffers - firstBuffer,
                &renderer->outputFormat,
                false
            );
            if (plane.frameCapacity > longestCapacity) {
                longestCapacity = plane.frameCapacity;
            }
        }
        if (longestCapacity != 0) {
            return longestCapacity;
        }
    }
    if (input != NULL) {
        buildPlane(&plane, input->mBuffers, input->mNumberBuffers, &renderer->inputFormat, true);
        return plane.frameCapacity;
    }
    return 0;
}

OSStatus CascadeAudioRenderIOProc(
    AudioObjectID          device,
    const AudioTimeStamp   *now,
    const AudioBufferList  *input,
    const AudioTimeStamp   *inputTime,
    AudioBufferList        *output,
    const AudioTimeStamp   *outputTime,
    void                   *client
)
{
    (void)device;
    (void)now;
    (void)inputTime;
    (void)outputTime;

    CascadeAudioRender *renderer = (CascadeAudioRender *)client;
    if (renderer == NULL) {
        return noErr;
    }

    CascadeAudioRenderProcess(renderer, input, output, ioProcFrameCount(renderer, input, output));
    return noErr;
}

// MARK: - END REALTIME

static bool isValidFormat(CascadeAudioRenderFormat format)
{
    return isfinite(format.sampleRate)
        && format.sampleRate > 0.0
        && format.channels   > 0
        && format.channels   <= CASCADE_RENDER_MAX_CHANNELS
        && format.maxFrames  > 0;
}

CascadeAudioRender *CascadeAudioRenderCreate(
    CascadeAudioRenderFormat input,
    CascadeAudioRenderFormat output,
    double                   gain,
    bool                     muted,
    const uint32_t          *destinationBuffers,
    uint32_t                 destinationCount
)
{
    if (!isValidFormat(input) || !isValidFormat(output)) {
        return NULL;
    }

    size_t size = (sizeof(CascadeAudioRender) + CASCADE_RENDER_CACHE_LINE - 1)
                / CASCADE_RENDER_CACHE_LINE * CASCADE_RENDER_CACHE_LINE;
    CascadeAudioRender *renderer = aligned_alloc(CASCADE_RENDER_CACHE_LINE, size);
    if (renderer == NULL) {
        return NULL;
    }
    memset(renderer, 0, size);

    // Warm-up: the first sin/cos call may enter dyld to bind the symbol lazily, which is a
    // lock and possibly a file read. Making that call here, on the control thread, means the
    // first crossfade on the realtime thread finds them already bound. Both the argument and
    // the result are `volatile`: a constant argument would be folded at compile time and the
    // call would never happen, and an unused result would be deleted as dead.
    volatile double warmUpArgument = 0.5;
    volatile double warmUpResult   = sin(warmUpArgument) + cos(warmUpArgument);
    (void)warmUpResult;

    uint64_t command = encodeCommand(gain, muted);
    renderer->inputFormat     = input;
    renderer->outputFormat    = output;
    renderer->rampFrames      = (uint32_t)round(output.sampleRate * CASCADE_RENDER_RAMP_SECONDS);
    renderer->seenCommand     = command;
    renderer->currentGain     = decodeTargetGain(command);
    renderer->targetGain      = renderer->currentGain;
    renderer->crossfadeWeight = 1.0;
    renderer->crossfadeFrom   = 1.0;
    renderer->crossfadeTo     = 1.0;

    // No list means the single device at buffer 0, which is what a plain output looks like.
    if (destinationBuffers == NULL || destinationCount == 0) {
        renderer->destinationCount = 1;
    } else {
        renderer->destinationCount = destinationCount < CASCADE_RENDER_MAX_DESTINATIONS
            ? destinationCount
            : CASCADE_RENDER_MAX_DESTINATIONS;
        memcpy(
            renderer->destinationBuffers,
            destinationBuffers,
            (size_t)renderer->destinationCount * sizeof renderer->destinationBuffers[0]
        );
    }
    atomic_init(&renderer->command, command);
    atomic_init(&renderer->crossfadeWeights, 0);
    atomic_init(&renderer->crossfadeRequest, 0);
    atomic_init(&renderer->callbackCount, 0);
    atomic_init(&renderer->invalidSampleCount, 0);
    return renderer;
}

void CascadeAudioRenderSetCommand(CascadeAudioRender *renderer, double gain, bool muted)
{
    atomic_store_explicit(&renderer->command, encodeCommand(gain, muted), memory_order_release);
}

void CascadeAudioRenderSetCrossfade(
    CascadeAudioRender *renderer,
    double              fromWeight,
    double              toWeight,
    uint32_t            frames
)
{
    float    from = clampedWeight(fromWeight);
    float    to   = clampedWeight(toWeight);
    uint32_t fromBits;
    uint32_t toBits;
    memcpy(&fromBits, &from, sizeof fromBits);
    memcpy(&toBits,   &to,   sizeof toBits);

    // Weights first, then the request that names a new generation: the realtime
    // thread's acquire load of the request makes the weights visible with it.
    atomic_store_explicit(
        &renderer->crossfadeWeights,
        (uint64_t)fromBits | ((uint64_t)toBits << 32),
        memory_order_relaxed
    );
    uint64_t previous   = atomic_load_explicit(&renderer->crossfadeRequest, memory_order_relaxed);
    uint32_t generation = (uint32_t)(previous >> 32) + 1u;
    atomic_store_explicit(
        &renderer->crossfadeRequest,
        ((uint64_t)generation << 32) | frames,
        memory_order_release
    );
}

uint64_t CascadeAudioRenderCallbackCount(const CascadeAudioRender *renderer)
{
    return atomic_load_explicit(&((CascadeAudioRender *)renderer)->callbackCount, memory_order_relaxed);
}

uint64_t CascadeAudioRenderInvalidSampleCount(const CascadeAudioRender *renderer)
{
    return atomic_load_explicit(&((CascadeAudioRender *)renderer)->invalidSampleCount, memory_order_relaxed);
}

void CascadeAudioRenderDestroy(CascadeAudioRender *renderer)
{
    free(renderer);
}
