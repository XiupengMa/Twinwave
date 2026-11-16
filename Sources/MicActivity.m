#import "MicActivity.h"
#import "Devices.h"
#import <unistd.h>

// HAL object lists can change between the size query and the read.
static OSStatus objectList(AudioObjectID object, AudioObjectPropertyAddress address, NSData **result) {
    for (int attempt = 0; attempt < 2; attempt++) {
        UInt32 bytes = 0;
        OSStatus err = AudioObjectGetPropertyDataSize(object, &address, 0, NULL, &bytes);
        if (err) return err;
        NSMutableData *data = [NSMutableData dataWithLength:bytes];
        if (bytes) err = AudioObjectGetPropertyData(object, &address, 0, NULL, &bytes, data.mutableBytes);
        if (err == kAudioHardwareBadPropertySizeError) continue;
        if (err) return err;
        data.length = bytes;
        *result = data;
        return noErr;
    }
    return kAudioHardwareBadPropertySizeError;
}

static OSStatus scalar(AudioObjectID object, AudioObjectPropertySelector selector, void *value) {
    AudioObjectPropertyAddress address = TWAddress(selector, kAudioObjectPropertyScopeGlobal);
    UInt32 bytes = sizeof(UInt32);
    return AudioObjectGetPropertyData(object, &address, 0, NULL, &bytes, value);
}

TWMicActivity TWOtherMicActivity(AudioDeviceID selected) {
    if (!selected) return TWMicIdle;
    NSData *processes;
    if (objectList(kAudioObjectSystemObject, TWAddress(kAudioHardwarePropertyProcessObjectList,
                   kAudioObjectPropertyScopeGlobal), &processes)) return TWMicActivityUnknown;
    const AudioObjectID *ids = processes.bytes;
    TWMicActivity result = TWMicIdle;
    for (NSUInteger i = 0; i < processes.length / sizeof(*ids); i++) {
        UInt32 running = 0;
        pid_t pid = 0;
        OSStatus err = scalar(ids[i], kAudioProcessPropertyIsRunningInput, &running);
        if (!err && !running) continue;
        if (!err) err = scalar(ids[i], kAudioProcessPropertyPID, &pid);
        if (!err && pid == getpid()) continue;
        NSData *devices = nil;
        if (!err) err = objectList(ids[i], TWAddress(kAudioProcessPropertyDevices,
                                   kAudioObjectPropertyScopeInput), &devices);
        if (err) {
            // A disappearing process no longer owns a stream. Other failures are inconclusive.
            if (err != kAudioHardwareBadObjectError) result = TWMicActivityUnknown;
            continue;
        }
        const AudioDeviceID *inputs = devices.bytes;
        for (NSUInteger j = 0; j < devices.length / sizeof(*inputs); j++) {
            if (inputs[j] == selected) return TWMicInUse;
        }
    }
    return result;
}
