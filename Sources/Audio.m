#import "Audio.h"
#import "Capture.h"
#import "MicActivity.h"
#import <AVFoundation/AVFoundation.h>

@implementation TWAudio {
    dispatch_queue_t _queue;
    dispatch_source_t _timer;
    TWCapture *_meters[2];
    NSString *_signatures[2];
    TWDevice *_input;
    TWMicActivity _activity;
    AVAuthorizationStatus _authorization;
    NSUInteger _poll;
    BOOL _requestingMic, _stopped;
    AudioObjectPropertyListenerBlock _listener;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("local.twinwave.routing", DISPATCH_QUEUE_SERIAL);
        for (int i = 0; i < 2; i++) _meters[i] = [TWCapture new];
    }
    return self;
}

- (void)publish:(TWDevice *)device input:(BOOL)input status:(NSString *)status micInUse:(BOOL)inUse {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.changed) self.changed(input, device, status, inUse);
    });
}

- (void)pollInput:(BOOL)force {
    if (_stopped) return;
    TWMicActivity activity = TWOtherMicActivity(_input.objectID);
    AVAuthorizationStatus auth = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if (!force && _activity == activity && _authorization == auth) return;
    _activity = activity;
    _authorization = auth;
    [_meters[0] stop];
    NSString *status = nil;
    if (!_input) {
        status = @"No input";
    } else if (auth == AVAuthorizationStatusDenied || auth == AVAuthorizationStatusRestricted) {
        status = @"Mic blocked";
    } else if (activity == TWMicActivityUnknown) {
        status = @"Use unknown";
    } else if (activity == TWMicInUse) {
        if (auth == AVAuthorizationStatusAuthorized) {
            status = [_meters[0] startDevice:_input input:YES];
        } else {
            status = @"Allow mic";
            if (!_requestingMic) {
                _requestingMic = YES;
                [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) {
                    dispatch_async(self->_queue, ^{
                        self->_requestingMic = NO;
                        [self refresh:NO]; // Re-read both the selected mic and its clients.
                    });
                }];
            }
        }
    }
    [self publish:_input input:YES status:status micInUse:activity == TWMicInUse];
}

- (void)refresh:(BOOL)force {
    if (_stopped) return;
    for (int i = 0; i < 2; i++) {
        BOOL input = i == 0;
        AudioDeviceID current = TWDefault(input);
        TWDevice *device = nil;
        for (TWDevice *candidate in TWDevices(input)) {
            if (candidate.objectID == current) { device = candidate; break; }
        }
        NSString *signature = [NSString stringWithFormat:@"%u/%@/%@/%.2f/%u", current, device.uid,
                               device.name, device.rate, device.streamCount];
        BOOL routeChanged = ![_signatures[i] isEqual:signature];
        _signatures[i] = signature;
        if (input) {
            _input = device;
            [self pollInput:force || routeChanged];
        } else if (force || routeChanged) {
            [_meters[1] stop];
            NSString *status = device ? [_meters[1] startDevice:device input:NO] : @"No output";
            [self publish:device input:NO status:status micInUse:NO];
        }
    }
}

- (void)tick {
    // Notifications refresh routes immediately. Reconcile names and formats every two seconds.
    if (_poll++ % 8 == 0 || TWDefault(YES) != _input.objectID) [self refresh:NO];
    else [self pollInput:NO];
}

- (void)start {
    __weak TWAudio *weakSelf = self;
    _listener = ^(UInt32 count, const AudioObjectPropertyAddress *addresses) { [weakSelf refresh:NO]; };
    for (NSNumber *sel in @[@(kAudioHardwarePropertyDefaultInputDevice), @(kAudioHardwarePropertyDefaultOutputDevice),
                              @(kAudioHardwarePropertyDevices)]) {
        AudioObjectPropertyAddress addr = TWAddress(sel.unsignedIntValue, kAudioObjectPropertyScopeGlobal);
        AudioObjectAddPropertyListenerBlock(kAudioObjectSystemObject, &addr, _queue, _listener);
    }
    // Also recover from same-ID format changes and a missing HAL notification after wake.
    _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _queue);
    dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC, 20 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(_timer, ^{ [weakSelf tick]; });
    dispatch_resume(_timer);
}

- (void)retry { dispatch_async(_queue, ^{ [self refresh:YES]; }); }

- (float)peakForInput:(BOOL)input data:(BOOL *)data {
    return [_meters[input ? 0 : 1] takePeakWithData:data];
}

- (void)stop {
    dispatch_source_cancel(_timer);
    for (NSNumber *sel in @[@(kAudioHardwarePropertyDefaultInputDevice), @(kAudioHardwarePropertyDefaultOutputDevice),
                              @(kAudioHardwarePropertyDevices)]) {
        AudioObjectPropertyAddress addr = TWAddress(sel.unsignedIntValue, kAudioObjectPropertyScopeGlobal);
        AudioObjectRemovePropertyListenerBlock(kAudioObjectSystemObject, &addr, _queue, _listener);
    }
    dispatch_sync(_queue, ^{
        self->_stopped = YES;
        for (int i = 0; i < 2; i++) [self->_meters[i] stop];
    });
}
@end
