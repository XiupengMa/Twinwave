#import "Devices.h"

@interface TWAudio : NSObject
@property (copy) void (^changed)(BOOL input, TWDevice *device, NSString *status, BOOL micInUse);
- (void)start;
- (void)retry;
- (void)stop;
- (float)peakForInput:(BOOL)input data:(BOOL *)data;
@end
