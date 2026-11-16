#import "Panel.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property TWAudio *audio;
@property TWPanelController *controller;
@end
@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)note {
    self.audio = [TWAudio new];
    self.controller = [[TWPanelController alloc] initWithAudio:self.audio];
    [self.controller show];
    [self.audio start];
}
- (void)applicationWillTerminate:(NSNotification *)note { [self.audio stop]; }
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        AppDelegate * __attribute__((objc_precise_lifetime)) delegate = [AppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
