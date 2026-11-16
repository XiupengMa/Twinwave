#import <AppKit/AppKit.h>
#import "Audio.h"

@interface TWPanelController : NSObject
- (instancetype)initWithAudio:(TWAudio *)audio;
- (void)show;
@end
