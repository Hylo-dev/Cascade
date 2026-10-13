//
//  AudioSystemProbe.mm
//  AudioSystemProbe
//

#import <Foundation/Foundation.h>
#include <AudioToolbox/AudioToolbox.h>
#include <CoreAudio/CoreAudio.h>
#include <atomic>
#include <cstring>
#include <dlfcn.h>
#include <thread>
#include <unistd.h>

/// propertySnapshot reads documented UInt32 properties without guessing private payload layouts.
/// A property being present or writable is a capability observation, not evidence of audible effect.
static NSDictionary *propertySnapshot(
    AudioObjectID object,
    AudioObjectPropertySelector selector,
    AudioObjectPropertyScope scope
) {
    AudioObjectPropertyAddress address = { selector, scope, kAudioObjectPropertyElementMain };
    const bool present = AudioObjectHasProperty(object, &address);
    NSMutableDictionary *result = [@{ @"present": @(present) } mutableCopy];
    if (!present) return result;

    Boolean settable = false;
    UInt32 size      = 0;
    OSStatus accessStatus = AudioObjectIsPropertySettable(object, &address, &settable);
    OSStatus sizeStatus   = AudioObjectGetPropertyDataSize(object, &address, 0, nullptr, &size);
    result[@"settableStatus"] = @(accessStatus);
    result[@"settable"]       = @(settable);
    result[@"sizeStatus"]     = @(sizeStatus);
    result[@"size"]           = @(size);
    if (sizeStatus == noErr && size == sizeof(UInt32)) {
        UInt32 value = 0;
        OSStatus readStatus = AudioObjectGetPropertyData(object, &address, 0, nullptr, &size, &value);
        result[@"readStatus"] = @(readStatus);
        if (readStatus == noErr) result[@"value"] = @(value);
    }
    return result;
}

/// SilentStream owns three zero-filled buffers until AudioQueueDispose establishes quiescence.
/// The callback only returns an active buffer and increments lock-free counters; it never logs,
/// allocates sample storage or produces a signal. Retirement is published before Dispose because
/// queue disposal returns pending buffers while forbidding re-enqueue. Context remains alive until
/// synchronous disposal returns. The external runner bounds any stalled HAL call.
struct SilentStream {
    std::atomic<UInt32> callbacks            { 0 };
    std::atomic<UInt32> retiredCallbacks     { 0 };
    std::atomic<bool> isRetiring             { false };
    std::atomic<OSStatus> enqueueError       { noErr };
    std::atomic<OSStatus> retiringQueueError { noErr };
};

static void returnSilentBuffer(
    void *context,
    AudioQueueRef queue,
    AudioQueueBufferRef buffer
) {
    auto *stream = static_cast<SilentStream *>(context);
    stream->callbacks.fetch_add(1, std::memory_order_relaxed);
    if (stream->isRetiring.load(std::memory_order_acquire)) {
        stream->retiredCallbacks.fetch_add(1, std::memory_order_relaxed);
        return;
    }
    const OSStatus status = AudioQueueEnqueueBuffer(queue, buffer, 0, nullptr);
    if (status != noErr) {
        // A callback already in flight can race retirement after its initial check.
        auto &error = stream->isRetiring.load(std::memory_order_acquire)
            ? stream->retiringQueueError : stream->enqueueError;
        error.store(status, std::memory_order_relaxed);
    }
}

/// ownMuteRoundTrip changes only the calling process's documented physical-device mute.
/// It preserves the exact original value. No hardware master volume or other process is targeted.
static NSDictionary *ownMuteRoundTrip(AudioObjectID device) {
    AudioObjectPropertyAddress address = {
        kAudioDevicePropertyProcessMute,
        kAudioObjectPropertyScopeOutput,
        kAudioObjectPropertyElementMain
    };
    NSDictionary *before = propertySnapshot(device, address.mSelector, address.mScope);
    if (![before[@"settable"] boolValue] || !before[@"value"]) {
        return @{ @"attempted": @NO, @"before": before };
    }
    UInt32 original = [before[@"value"] unsignedIntValue];
    UInt32 muted    = 1;
    UInt32 unmuted  = 0;
    OSStatus muteStatus = AudioObjectSetPropertyData(
        device, &address, 0, nullptr, sizeof(muted), &muted
    );
    NSDictionary *whileMuted = propertySnapshot(device, address.mSelector, address.mScope);
    OSStatus unmuteStatus = AudioObjectSetPropertyData(
        device, &address, 0, nullptr, sizeof(unmuted), &unmuted
    );
    NSDictionary *whileUnmuted = propertySnapshot(device, address.mSelector, address.mScope);
    OSStatus restoreStatus = AudioObjectSetPropertyData(
        device, &address, 0, nullptr, sizeof(original), &original
    );
    NSDictionary *after = propertySnapshot(device, address.mSelector, address.mScope);
    return @{
        @"attempted"    : @YES,
        @"before"       : before,
        @"muteStatus"   : @(muteStatus),
        @"whileMuted"   : whileMuted,
        @"unmuteStatus" : @(unmuteStatus),
        @"whileUnmuted" : whileUnmuted,
        @"restoreStatus": @(restoreStatus),
        @"after"        : after
    };
}

/// privateSymbols checks loader visibility only; no private function pointer is cast or invoked.
static NSDictionary *privateSymbols(void) {
    const char *path = "/System/Library/PrivateFrameworks/MediaExperience.framework/MediaExperience";
    void *framework = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    const char *loaderError = framework ? nullptr : dlerror();
    NSMutableDictionary *symbols = [NSMutableDictionary dictionary];
    const char *names[] = {
        "AudioDeviceDuck",
        "FigRoutingContextCopyAllAudioContexts",
        "FigRoutingContextCopyContextForUUID",
        "FigRoutingContextCopySystemAudioContext",
        "FigRoutingContextCreateAudioContext",
        "FigRoutingContextGetTypeID",
        "FigVolumeControllerCopySharedControllerRemote",
        "FigVolumeControllerGetTypeID",
        "MXSessionCreate",
        "MXSessionCreateWithOptions",
        "MXSessionCopyProperty",
        "MXSessionSetProperty",
        "kFigRoutingContextCreateOption_ClientPID",
        "kFigVolumeControllerMasterVolumeKey_RoutingContextUUID",
        "kFigVolumeControllerMasterVolumeKey_Volume",
        "kMXSessionProperty_ClientPID",
        "kMXSessionProperty_IsOutputMuted",
        "kMXSessionProperty_UserVolume"
    };
    for (const char *name : names) {
        void *symbol = dlsym(RTLD_DEFAULT, name);
        if (!symbol && framework) symbol = dlsym(framework, name);
        symbols[@(name)] = @(symbol != nullptr);
    }
    NSDictionary *result = @{
        @"frameworkLoaded": @(framework != nullptr),
        @"loaderError"    : loaderError ? @(loaderError) : @"",
        @"symbols"        : symbols,
        @"functionsCalled": @0
    };
    if (framework) dlclose(framework);
    return result;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        const bool runStream = argc == 2 && std::strcmp(argv[1], "--silent-stream") == 0;
        NSMutableDictionary *report = [NSMutableDictionary dictionary];
        report[@"schemaVersion"] = @1;
        report[@"osVersion"]     = NSProcessInfo.processInfo.operatingSystemVersionString;
#if defined(__arm64__)
        report[@"architecture"] = @"arm64";
#elif defined(__x86_64__)
        report[@"architecture"] = @"x86_64";
#else
        report[@"architecture"] = @"unknown";
#endif
        report[@"private"]       = privateSymbols();

        AudioObjectID device = kAudioObjectUnknown;
        UInt32 size = sizeof(device);
        AudioObjectPropertyAddress outputAddress = {
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        OSStatus deviceStatus = AudioObjectGetPropertyData(
            kAudioObjectSystemObject, &outputAddress, 0, nullptr, &size, &device
        );
        report[@"defaultOutputStatus"] = @(deviceStatus);
        report[@"defaultOutputID"]     = @(device);

        SilentStream stream;
        AudioQueueRef queue = nullptr;
        report[@"counterLockFree"] = @(
            stream.callbacks.is_lock_free() && stream.isRetiring.is_lock_free()
                && stream.enqueueError.is_lock_free()
        );
        if (runStream && deviceStatus == noErr && device != kAudioObjectUnknown) {
            AudioStreamBasicDescription format = {};
            format.mSampleRate       = 48000;
            format.mFormatID         = kAudioFormatLinearPCM;
            format.mFormatFlags      = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
            format.mBytesPerPacket   = 2 * sizeof(Float32);
            format.mFramesPerPacket  = 1;
            format.mBytesPerFrame    = 2 * sizeof(Float32);
            format.mChannelsPerFrame = 2;
            format.mBitsPerChannel   = 32;
            OSStatus createStatus = AudioQueueNewOutput(
                &format, returnSilentBuffer, &stream, nullptr, nullptr, 0, &queue
            );
            report[@"queueCreateStatus"] = @(createStatus);
            if (createStatus == noErr) {
                OSStatus prepareStatus = noErr;
                for (int index = 0; index < 3 && prepareStatus == noErr; ++index) {
                    AudioQueueBufferRef buffer = nullptr;
                    prepareStatus = AudioQueueAllocateBuffer(queue, 512 * format.mBytesPerFrame, &buffer);
                    if (prepareStatus != noErr) break;
                    std::memset(buffer->mAudioData, 0, buffer->mAudioDataBytesCapacity);
                    buffer->mAudioDataByteSize = buffer->mAudioDataBytesCapacity;
                    prepareStatus = AudioQueueEnqueueBuffer(queue, buffer, 0, nullptr);
                }
                report[@"queuePrepareStatus"] = @(prepareStatus);
                if (prepareStatus == noErr) {
                    OSStatus startStatus = AudioQueueStart(queue, nullptr);
                    report[@"queueStartStatus"] = @(startStatus);
                    if (startStatus == noErr) std::this_thread::sleep_for(std::chrono::milliseconds(200));
                }
            }
        }

        pid_t ownPID = getpid();
        AudioObjectID process = kAudioObjectUnknown;
        size = sizeof(process);
        AudioObjectPropertyAddress processAddress = {
            kAudioHardwarePropertyTranslatePIDToProcessObject,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        OSStatus processStatus = AudioObjectGetPropertyData(
            kAudioObjectSystemObject, &processAddress, sizeof(ownPID), &ownPID, &size, &process
        );
        report[@"ownProcessStatus"] = @(processStatus);
        report[@"ownProcessID"]     = @(process);
        if (processStatus == noErr && process != kAudioObjectUnknown) {
            report[@"ownProcessRunningOutput"] = propertySnapshot(
                process, kAudioProcessPropertyIsRunningOutput, kAudioObjectPropertyScopeGlobal
            );
            report[@"deviceMuteOnProcessObject"] = propertySnapshot(
                process, kAudioDevicePropertyProcessMute, kAudioObjectPropertyScopeGlobal
            );
        }
        report[@"ownProcessAudible"] = propertySnapshot(
            kAudioObjectSystemObject, kAudioHardwarePropertyProcessIsAudible, kAudioObjectPropertyScopeGlobal
        );
        if (deviceStatus == noErr && device != kAudioObjectUnknown) {
            report[@"deviceProcessMute"] = propertySnapshot(
                device, kAudioDevicePropertyProcessMute, kAudioObjectPropertyScopeOutput
            );
            if (runStream && queue) report[@"ownMuteRoundTrip"] = ownMuteRoundTrip(device);
        }
        if (queue) {
            stream.isRetiring.store(true, std::memory_order_release);
            report[@"queueDisposeStatus"] = @(AudioQueueDispose(queue, true));
        }
        report[@"callbacks"] = @(stream.callbacks.load(std::memory_order_relaxed));
        report[@"retiredCallbacks"] = @(stream.retiredCallbacks.load(std::memory_order_relaxed));
        report[@"callbackEnqueueStatus"] = @(stream.enqueueError.load(std::memory_order_relaxed));
        report[@"retiringQueueStatus"] = @(stream.retiringQueueError.load(std::memory_order_relaxed));
        report[@"silentStreamRequested"] = @(runStream);
        report[@"audibleEffectMeasured"] = @NO;
        report[@"otherProcessSettersCalled"] = @0;

        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
        if (!json) {
            fprintf(stderr, "Unable to serialize probe result: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        fwrite(json.bytes, 1, json.length, stdout);
        fputc('\n', stdout);
        return 0;
    }
}
