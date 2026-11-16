#import <Foundation/Foundation.h>
#import <CoreAudio/CoreAudio.h>

@interface TWDevice : NSObject
@property AudioDeviceID objectID;
@property (copy) NSString *uid, *name, *kind, *symbol;
@property UInt32 streamCount;
@property double rate;
@end

NSArray<TWDevice *> *TWDevices(BOOL input);
AudioDeviceID TWDefault(BOOL input);
OSStatus TWSelect(AudioDeviceID device, BOOL input);
AudioObjectPropertyAddress TWAddress(AudioObjectPropertySelector selector, AudioObjectPropertyScope scope);
