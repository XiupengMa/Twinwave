#import "Devices.h"

@implementation TWDevice
@end

AudioObjectPropertyAddress TWAddress(AudioObjectPropertySelector sel, AudioObjectPropertyScope scope) {
    return (AudioObjectPropertyAddress){sel, scope, kAudioObjectPropertyElementMain};
}

static AudioObjectPropertyAddress defaultAddress(BOOL input) {
    return TWAddress(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice,
                     kAudioObjectPropertyScopeGlobal);
}

AudioDeviceID TWDefault(BOOL input) {
    AudioDeviceID device = kAudioObjectUnknown;
    UInt32 size = sizeof(device);
    AudioObjectPropertyAddress address = defaultAddress(input);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &device);
    return device;
}

OSStatus TWSelect(AudioDeviceID device, BOOL input) {
    AudioObjectPropertyAddress address = defaultAddress(input);
    return AudioObjectSetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, sizeof(device), &device);
}

static UInt32 number(AudioObjectID object, AudioObjectPropertySelector sel, AudioObjectPropertyScope scope) {
    AudioObjectPropertyAddress address = TWAddress(sel, scope);
    UInt32 value = 0, size = sizeof(value);
    AudioObjectGetPropertyData(object, &address, 0, NULL, &size, &value);
    return value;
}

static NSString *string(AudioObjectID object, AudioObjectPropertySelector sel) {
    AudioObjectPropertyAddress address = TWAddress(sel, kAudioObjectPropertyScopeGlobal);
    CFStringRef value = NULL;
    UInt32 size = sizeof(value);
    AudioObjectGetPropertyData(object, &address, 0, NULL, &size, &value);
    return CFBridgingRelease(value) ?: @"";
}

static void classify(TWDevice *device, BOOL input, UInt32 transport) {
    NSString *name = device.name.lowercaseString;
    if ([name containsString:@"airpods"] || [name containsString:@"earbuds"] || [name containsString:@"earpods"]) {
        device.kind = @"Earbuds";
        device.symbol = @"earbuds";
    } else if ([name containsString:@"headphone"] || [name containsString:@"headset"]) {
        device.kind = @"Headset";
        device.symbol = @"headphones";
    } else if (input) {
        device.kind = transport == kAudioDeviceTransportTypeUSB ? @"USB mic" : @"Mic";
        device.symbol = @"mic.fill";
    } else if (transport == kAudioDeviceTransportTypeDisplayPort || transport == kAudioDeviceTransportTypeHDMI) {
        device.kind = @"Display";
        device.symbol = @"display";
    } else {
        device.kind = transport == kAudioDeviceTransportTypeUSB ? @"USB audio" : @"Speakers";
        device.symbol = @"hifispeaker.2.fill";
    }
}

NSArray<TWDevice *> *TWDevices(BOOL input) {
    AudioObjectPropertyAddress list = TWAddress(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal);
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &list, 0, NULL, &size) || !size) return @[];
    NSMutableData *storage = [NSMutableData dataWithLength:size];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &list, 0, NULL, &size, storage.mutableBytes)) return @[];
    const AudioObjectID *ids = storage.bytes;
    NSMutableArray *result = [NSMutableArray array];
    AudioObjectPropertyScope scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput;
    for (UInt32 i = 0; i < size / sizeof(*ids); i++) {
        AudioObjectID object = ids[i];
        if (!number(object, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal)) continue;
        if (!number(object, kAudioDevicePropertyDeviceCanBeDefaultDevice, scope)) continue;
        AudioObjectPropertyAddress streams = TWAddress(kAudioDevicePropertyStreams, scope);
        UInt32 bytes = 0;
        if (AudioObjectGetPropertyDataSize(object, &streams, 0, NULL, &bytes) || !bytes) continue;
        TWDevice *device = [TWDevice new];
        device.uid = string(object, kAudioDevicePropertyDeviceUID);
        if (!device.uid.length || [device.uid hasPrefix:@"local.twinwave.tap."]) continue;
        device.name = string(object, kAudioObjectPropertyName);
        device.objectID = object;
        device.streamCount = bytes / sizeof(AudioStreamID);
        AudioObjectPropertyAddress rate = TWAddress(kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal);
        Float64 sampleRate = 0;
        bytes = sizeof(sampleRate);
        AudioObjectGetPropertyData(object, &rate, 0, NULL, &bytes, &sampleRate);
        device.rate = sampleRate;
        classify(device, input, number(object, kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal));
        [result addObject:device];
    }
    return result;
}
