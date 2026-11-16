#import <AppKit/AppKit.h>

static inline NSFont *TWLabelFont(BOOL emphasized) {
    return [NSFont systemFontOfSize:11.5 weight:emphasized ? NSFontWeightSemibold : NSFontWeightRegular];
}

static inline BOOL TWDarkAppearance(NSView *view) {
    return [[view.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]]
            isEqual:NSAppearanceNameDarkAqua];
}

static inline void TWFillRound(NSRect rect, CGFloat radius, NSColor *color) {
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:radius yRadius:radius] fill];
}

static inline void TWDrawSurface(NSView *view) {
    CGFloat pixel = 1 / MAX(1,view.window.backingScaleFactor);
    NSRect bounds = view.bounds;
    [NSColor.clearColor setFill];
    NSRectFillUsingOperation(bounds, NSCompositingOperationCopy);
    NSBezierPath *surface = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds,pixel/2,pixel/2)
                                                            xRadius:12 yRadius:12];
    [[NSColor.windowBackgroundColor colorWithAlphaComponent:1] setFill];
    [surface fill];
    [[NSColor.labelColor colorWithAlphaComponent:TWDarkAppearance(view) ? 0.21 : 0.17] setStroke];
    surface.lineWidth = pixel;
    [surface stroke];
}

static inline void TWDrawTile(NSRect rect, NSImage *image, NSColor *accent, BOOL dark) {
    TWFillRound(rect,6,[accent colorWithAlphaComponent:dark ? 0.17 : 0.10]);
    NSImageSymbolConfiguration *style = [[NSImageSymbolConfiguration configurationWithPointSize:11 weight:NSFontWeightMedium]
        configurationByApplyingConfiguration:[NSImageSymbolConfiguration configurationWithHierarchicalColor:accent]];
    NSImage *icon = [image imageWithSymbolConfiguration:style];
    NSSize size = icon.size;
    CGFloat scale = MIN(1,16/MAX(1,size.width));
    NSRect glyph = NSMakeRect(NSMidX(rect)-size.width*scale/2,NSMidY(rect)-size.height*scale/2,
                              size.width*scale,size.height*scale);
    [icon drawInRect:glyph fromRect:NSZeroRect operation:NSCompositingOperationSourceOver
            fraction:1 respectFlipped:YES hints:nil];
}
