#import <AppKit/AppKit.h>

/// A native dropdown for a nonactivating panel, including panels parked below the Dock.
@interface TWMenuPanel : NSPanel
- (instancetype)initWithMenu:(NSMenu *)menu accent:(NSColor *)accent;
- (void)showBeside:(NSWindow *)owner alignedAtX:(CGFloat)x;
- (void)dismiss;
@end
