#import "Capture.h"
#import "AudioBufferSafety.h"
#import <string.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#import <AudioUnit/AudioUnit.h>
#import <Accelerate/Accelerate.h>
#import <stdatomic.h>
#import <math.h>

typedef struct {
    _Atomic(float) peak;
    atomic_bool received;
    AudioUnit mic;
    AudioBufferList micBuffer;
    UInt32 capacity;
} Meter;

static void measure(Meter *meter, const AudioBufferList *buffers) {
    if (!buffers) return;
    float peak = 0;
    bool received = false;
    for (UInt32 i = 0; i < buffers->mNumberBuffers; i++) {
        const AudioBuffer *buffer = &buffers->mBuffers[i];
        if (!buffer->mData || buffer->mDataByteSize < sizeof(float)) continue;
        received = true;
        float value = 0;
        vDSP_maxmgv(buffer->mData, 1, &value, buffer->mDataByteSize / sizeof(float));
        peak = fmaxf(peak, value);
    }
    float previous = atomic_load(&meter->peak);
    while (peak > previous && !atomic_compare_exchange_weak(&meter->peak, &previous, peak)) {}
    if (received) atomic_store(&meter->received, true);
}

static OSStatus micCallback(void *context, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time,
                            UInt32 bus, UInt32 frames, AudioBufferList *unused) {
    Meter *meter = context;
    UInt32 bytes = 0;
    if (!TWAudioBufferBytes(frames, meter->micBuffer.mBuffers[0].mNumberChannels, &bytes) ||
        bytes > meter->capacity) return kAudioUnitErr_TooManyFramesToProcess;
    meter->micBuffer.mBuffers[0].mDataByteSize = bytes;
    OSStatus status = AudioUnitRender(meter->mic, flags, time, bus, frames, &meter->micBuffer);
    if (!status) measure(meter, &meter->micBuffer);
    // Keep only the peak, not raw microphone samples between callbacks.
    if (meter->micBuffer.mBuffers[0].mData)
        memset_s(meter->micBuffer.mBuffers[0].mData, meter->capacity, 0, bytes);
    return status;
}

static OSStatus outputCallback(AudioDeviceID device, const AudioTimeStamp *now, const AudioBufferList *input,
                               const AudioTimeStamp *inputTime, AudioBufferList *output,
                               const AudioTimeStamp *outputTime, void *context) {
    measure(context, input);
    return noErr;
}

@implementation TWCapture {
    Meter _meter;
    AudioDeviceID _aggregate;
    AudioDeviceIOProcID _proc;
    NSMutableArray<NSNumber *> *_taps;
}

- (float)takePeakWithData:(BOOL *)received {
    *received = atomic_exchange(&_meter.received, false);
    return atomic_exchange(&_meter.peak, 0);
}

- (OSStatus)startMic:(TWDevice *)device {
    AudioComponentDescription desc = { kAudioUnitType_Output, kAudioUnitSubType_HALOutput, kAudioUnitManufacturer_Apple, 0, 0 };
    AudioComponent component = AudioComponentFindNext(NULL, &desc);
    if (!component) return kAudioUnitErr_FailedInitialization;
    OSStatus status = AudioComponentInstanceNew(component, &_meter.mic);
    if (status) return status;
    AudioUnit unit = _meter.mic;
    UInt32 on = 1, off = 0;
    status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &on, sizeof(on));
    if (status) return status;
    status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &off, sizeof(off));
    if (status) return status;
    AudioDeviceID selected = device.objectID;
    status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &selected, sizeof(selected));
    if (status) return status;
    AudioStreamBasicDescription hardware = {};
    UInt32 size = sizeof(hardware);
    status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size);
    if (status) return status;
    UInt32 channels = hardware.mChannelsPerFrame;
    UInt32 frameBytes = 0;
    if (!TWAudioBufferBytes(1, channels, &frameBytes)) return kAudioDeviceUnsupportedFormatError;
    AudioStreamBasicDescription format = {hardware.mSampleRate, kAudioFormatLinearPCM,
        kAudioFormatFlagsNativeFloatPacked, frameBytes, 1, frameBytes, channels, 32, 0};
    status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, sizeof(format));
    if (status) return status;
    AURenderCallbackStruct callback = {micCallback, &_meter};
    status = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0, &callback, sizeof(callback));
    if (status) return status;
    status = AudioUnitInitialize(unit);
    if (status) return status;
    UInt32 maxFrames = 0;
    size = sizeof(maxFrames);
    status = AudioUnitGetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, &size);
    if (status) return status;
    if (!maxFrames || !TWAudioBufferBytes(maxFrames, channels, &_meter.capacity))
        return kAudioDeviceUnsupportedFormatError;
    _meter.micBuffer.mNumberBuffers = 1;
    _meter.micBuffer.mBuffers[0] = (AudioBuffer){channels, _meter.capacity, calloc(1, _meter.capacity)};
    if (!_meter.micBuffer.mBuffers[0].mData) return memFullErr;
    return AudioOutputUnitStart(unit);
}

- (OSStatus)startOutput:(TWDevice *)device {
    _taps = [NSMutableArray array];
    NSMutableArray *subtaps = [NSMutableArray array];
    for (UInt32 index = 0; index < device.streamCount; index++) {
        CATapDescription *desc = [[CATapDescription alloc] initExcludingProcesses:@[] andDeviceUID:device.uid withStream:index];
        desc.name = @"Twinwave output";
        [desc setPrivate:YES];
        desc.muteBehavior = CATapUnmuted;
        AudioObjectID tap = 0;
        OSStatus status = AudioHardwareCreateProcessTap(desc, &tap);
        if (status) return status;
        [_taps addObject:@(tap)];
        [subtaps addObject:@{@kAudioSubTapUIDKey:desc.UUID.UUIDString, @kAudioSubTapDriftCompensationKey:@YES}];
    }
    NSDictionary *config = @{@kAudioAggregateDeviceNameKey:@"Twinwave meter",
        @kAudioAggregateDeviceUIDKey:[@"local.twinwave.tap." stringByAppendingString:NSUUID.UUID.UUIDString],
        @kAudioAggregateDeviceIsPrivateKey:@YES, @kAudioAggregateDeviceTapAutoStartKey:@YES,
        @kAudioAggregateDeviceTapListKey:subtaps};
    OSStatus status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)config, &_aggregate);
    if (status) return status;
    // Validate the virtual formats actually delivered to the aggregate's IOProc.
    AudioObjectPropertyAddress streams = TWAddress(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeInput);
    UInt32 size = 0;
    status = AudioObjectGetPropertyDataSize(_aggregate, &streams, 0, NULL, &size);
    if (status || !size) return status ?: kAudioHardwareUnspecifiedError;
    NSMutableData *data = [NSMutableData dataWithLength:size];
    status = AudioObjectGetPropertyData(_aggregate, &streams, 0, NULL, &size, data.mutableBytes);
    if (status) return status;
    const AudioStreamID *ids = data.bytes;
    for (UInt32 i = 0; i < size / sizeof(*ids); i++) {
        AudioObjectPropertyAddress addr = TWAddress(kAudioStreamPropertyVirtualFormat, kAudioObjectPropertyScopeGlobal);
        AudioStreamBasicDescription fmt = {};
        UInt32 bytes = sizeof(fmt);
        status = AudioObjectGetPropertyData(ids[i], &addr, 0, NULL, &bytes, &fmt);
        if (status) return status;
        if (fmt.mFormatID != kAudioFormatLinearPCM || !(fmt.mFormatFlags & kAudioFormatFlagIsFloat) ||
            fmt.mBitsPerChannel != 32) return kAudioDeviceUnsupportedFormatError;
    }
    status = AudioDeviceCreateIOProcID(_aggregate, outputCallback, &_meter, &_proc);
    if (status) return status;
    return AudioDeviceStart(_aggregate, _proc);
}

- (NSString *)startDevice:(TWDevice *)device input:(BOOL)input {
    OSStatus status = input ? [self startMic:device] : [self startOutput:device];
    if (!status) return nil;
    [self stop];
    NSLog(@"%@ capture failed (%d)", input ? @"Input" : @"Output", status);
    if (status == kAudioDevicePermissionsError) return @"Access denied";
    if (status == kAudioDeviceUnsupportedFormatError) return @"Audio format";
    return @"Unavailable";
}

- (void)stop {
    if (_meter.mic) {
        AudioOutputUnitStop(_meter.mic);
        AudioUnitUninitialize(_meter.mic);
        AudioComponentInstanceDispose(_meter.mic);
        _meter.mic = NULL;
        if (_meter.micBuffer.mBuffers[0].mData)
            memset_s(_meter.micBuffer.mBuffers[0].mData, _meter.capacity, 0, _meter.capacity);
        free(_meter.micBuffer.mBuffers[0].mData);
        _meter.micBuffer.mBuffers[0].mData = NULL;
    }
    if (_proc) {
        AudioDeviceStop(_aggregate, _proc);
        AudioDeviceDestroyIOProcID(_aggregate, _proc);
        _proc = NULL;
    }
    if (_aggregate) {
        AudioHardwareDestroyAggregateDevice(_aggregate);
        _aggregate = 0;
    }
    for (NSNumber *tap in _taps.reverseObjectEnumerator) AudioHardwareDestroyProcessTap(tap.unsignedIntValue);
    _taps = nil;
    atomic_store(&_meter.peak, 0);
    atomic_store(&_meter.received, false);
}

@end
