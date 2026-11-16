#import "Panel.h"
#import "Style.h"
#import "MenuPanel.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat height = 62, inset = 9, tile = 20, meterWidth = 71, rail = 18;
static const NSInteger barCount = 12;
static CGFloat textWidth(NSString *text, NSFont *font) {
    return ceil([text sizeWithAttributes:@{NSFontAttributeName:font}].width);
}
static void drawText(NSString *text, NSFont *font, NSColor *color, NSRect rect) {
    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    [text drawInRect:rect withAttributes:@{NSFontAttributeName:font, NSForegroundColorAttributeName:color,
                                            NSParagraphStyleAttributeName:style}];
}
static NSString *displayKey(NSScreen *screen) {
    CGDirectDisplayID display = [screen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    CFUUIDRef uuid = CGDisplayCreateUUIDFromDisplayID(display);
    if (!uuid) return nil;
    NSString *key = CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
    CFRelease(uuid);
    return key;
}
static CGFloat clamp(CGFloat n, CGFloat low, CGFloat high) { return MIN(MAX(n, low), MAX(low, high)); }

@interface TWPanel : NSPanel
@end
@implementation TWPanel
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
- (NSRect)constrainFrameRect:(NSRect)frame toScreen:(NSScreen *)screen { return frame; }
@end

// A transparent native button supplies normal mouse-up tracking, menu targets and VoiceOver actions.
@interface TWButton : NSButton
@end
@implementation TWButton
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)rightMouseDown:(NSEvent *)event { [self.superview rightMouseDown:event]; }
- (void)mouseDown:(NSEvent *)event {
    if (event.modifierFlags & NSEventModifierFlagControl) [self rightMouseDown:event];
    else [super mouseDown:event];
}
- (void)drawRect:(NSRect)rect {}
- (void)resetCursorRects { [self addCursorRect:self.bounds cursor:NSCursor.pointingHandCursor]; }
@end

@class TWBody;
@interface TWPanelController ()
@property TWPanel *panel;
@property TWBody *body;
@property TWAudio *audio;
@property BOOL expanded, right, manual;
@property (copy) NSString *display;
@property CGFloat edgeOffset, bottomOffset;
@property NSTimer *animation;
- (void)dragTo:(NSPoint)point;
- (void)finishDrag;
- (NSMenu *)contextMenu;
- (void)showMenu:(NSMenu *)menu accent:(NSColor *)accent alignedAtX:(CGFloat)x;
- (void)toggle:(id)sender;
- (void)pick:(TWButton *)sender;
- (void)resizeForDevices;
@end

@interface TWBody : NSView
@property (weak) TWPanelController *owner;
- (instancetype)initWithOwner:(TWPanelController *)owner;
- (void)setDevice:(TWDevice *)device status:(NSString *)status input:(BOOL)input micInUse:(BOOL)inUse;
- (CGFloat)compactWidth;
- (CGFloat)fullWidth;
- (void)sample;
- (void)cancelGesture;
@end

@implementation TWBody {
    TWDevice *_devices[2];
    NSString *_status[2];
    float _bars[2][12];
    NSTimeInterval _lastData[2];
    TWButton *_names[2], *_chevron;
    NSAccessibilityElement *_meterAX[2];
    NSPoint _down, _origin;
    BOOL _armed, _dragging, _micInUse;
}
- (TWButton *)button:(SEL)action label:(NSString *)label {
    TWButton *b = [TWButton new];
    b.bordered = NO; b.title = @""; b.target = _owner; b.action = action;
    b.focusRingType = NSFocusRingTypeNone;
    [b setAccessibilityLabel:label];
    [self addSubview:b];
    return b;
}
- (instancetype)initWithOwner:(TWPanelController *)owner {
    if ((self = [super initWithFrame:NSMakeRect(0,0,200,height)])) {
        _owner = owner;
        _chevron = [self button:@selector(toggle:) label:@"Expand Twinwave"];
        for (int i = 0; i < 2; i++) {
            _names[i] = [self button:@selector(pick:) label:i == 0 ? @"Choose input" : @"Choose output"];
            _names[i].tag = i;
            _meterAX[i] = [NSAccessibilityElement accessibilityElementWithRole:NSAccessibilityLevelIndicatorRole
                frame:NSZeroRect label:i == 0 ? @"Input meter" : @"Output meter" parent:self];
            _status[i] = @"Starting";
        }
        self.accessibilityRole = NSAccessibilityGroupRole;
        [self setAccessibilityElement:YES];
    }
    return self;
}
- (NSArray *)accessibilityChildren {
    NSMutableArray *items = [NSMutableArray array];
    for (int i = 0; i < 2; i++) {
        if (!_names[i].hidden) [items addObject:_names[i]];
        [items addObject:_meterAX[i]];
    }
    [items addObject:_chevron];
    return items;
}
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (NSString *)kind:(int)i { return _devices[i].kind ?: (i == 0 ? @"Mic" : @"Speakers"); }
- (NSString *)name:(int)i { return _devices[i].name ?: (i == 0 ? @"No input device" : @"No output device"); }
- (CGFloat)typeWidth { return MAX(textWidth([self kind:0], TWLabelFont(YES)), textWidth([self kind:1], TWLabelFont(YES))); }
- (CGFloat)compactWidth { return 2*inset + tile + 7 + self.typeWidth + 10 + meterWidth + rail; }
- (CGFloat)fullWidth {
    return self.compactWidth + MAX(textWidth([self name:0],TWLabelFont(NO)), textWidth([self name:1],TWLabelFont(NO))) + 22;
}
- (CGFloat)left { return inset + (_owner.right ? rail : 0); }
- (CGFloat)meterX { return NSWidth(self.bounds) - inset - meterWidth - (_owner.right ? 0 : rail); }

- (void)setDevice:(TWDevice *)device status:(NSString *)status input:(BOOL)input micInUse:(BOOL)inUse {
    int i = input ? 0 : 1;
    BOOL layoutChanged = ![[self name:i] isEqual:device.name] || ![[self kind:i] isEqual:device.kind];
    if (input) _micInUse = inUse;
    _devices[i] = device; _status[i] = status;
    memset(_bars[i], 0, sizeof(_bars[i]));
    _lastData[i] = NSProcessInfo.processInfo.systemUptime;
    _names[i].toolTip = [NSString stringWithFormat:@"Choose %@ · %@", input ? @"input" : @"output", [self name:i]];
    _names[i].accessibilityLabel = _names[i].toolTip;
    if (layoutChanged) [_owner resizeForDevices];
    self.needsLayout = YES; self.needsDisplay = YES;
}
- (void)sample {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    for (int i = 0; i < 2; i++) {
        BOOL data = NO;
        float peak = [_owner.audio peakForInput:i == 0 data:&data];
        if (data) _lastData[i] = now;
        if (i != 0 || _micInUse) {
            memmove(_bars[i], _bars[i] + 1, (barCount - 1) * sizeof(float));
            _bars[i][barCount-1] = peak;
        }
        NSString *state = [self status:i];
        if (i == 0 && !_micInUse && !state) state = @"Idle";
        _meterAX[i].accessibilityValue = state ?: (peak > 0 ? [NSString stringWithFormat:@"%.1f dBFS", 20*log10f(peak)] : @"Silent");
        _meterAX[i].accessibilityLabel = [NSString stringWithFormat:@"%@ meter, %@", i == 0 ? (_micInUse ? @"In-use input" : @"Input") : @"Output", [self name:i]];
        _meterAX[i].accessibilityFrame = [self.window convertRectToScreen:[self convertRect:NSMakeRect(self.meterX,i*31,meterWidth,31) toView:nil]];
    }
    self.needsDisplay = YES;
}
- (NSString *)status:(int)i {
    if (_status[i]) return _status[i];
    if (i == 0 && !_micInUse) return nil;
    return NSProcessInfo.processInfo.systemUptime - _lastData[i] > 2 ? @"No audio data" : nil;
}
- (void)layout {
    [super layout];
    CGFloat w = NSWidth(self.bounds);
    _chevron.frame = NSMakeRect(_owner.right ? 0 : w-rail,0,rail,height);
    _chevron.accessibilityLabel = _owner.expanded ? @"Collapse Twinwave" : @"Expand Twinwave";
    _chevron.toolTip = _chevron.accessibilityLabel;
    CGFloat start = self.left + tile + 7 + self.typeWidth + 8;
    for (int i = 0; i < 2; i++) {
        _names[i].frame = NSMakeRect(start, 2+i*28, MAX(0,self.meterX-6-start), 30);
        _names[i].hidden = !_owner.expanded || NSWidth(_names[i].frame) < 12;
    }
}
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    self.needsLayout = YES; self.needsDisplay = YES;
}
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }

- (void)drawRect:(NSRect)dirty {
    BOOL dark = TWDarkAppearance(self);
    CGFloat px = 1 / MAX(1,self.window.backingScaleFactor);
    NSRect b = self.bounds;
    TWDrawSurface(self);
    CGFloat left = self.left, meter = self.meterX;
    if (_micInUse) {
        NSColor *mint = dark ? [NSColor colorWithSRGBRed:0.10 green:0.30 blue:0.28 alpha:1]
                             : [NSColor colorWithSRGBRed:0.80 green:0.94 blue:0.88 alpha:1];
        TWFillRound(NSMakeRect(left-4,4,meter+meterWidth-left+8,25),8,mint);
    }
    [[NSColor.labelColor colorWithAlphaComponent:0.085] setFill];
    NSRectFillUsingOperation(NSMakeRect(left,31,meter + meterWidth-left,px),NSCompositingOperationSourceOver);
    for (int i = 0; i < 2; i++) {
        CGFloat cy = i == 0 ? 17 : 45;
        NSColor *accent = i == 0 ? NSColor.systemTealColor : NSColor.systemBlueColor;
        NSString *symbol = _devices[i].symbol ?: (i == 0 ? @"mic.fill" : @"speaker.wave.2.fill");
        TWDrawTile(NSMakeRect(left,cy-tile/2,tile,tile),
                   [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil],accent,dark);
        drawText([self kind:i], TWLabelFont(YES), NSColor.labelColor, NSMakeRect(left+tile+7,cy-7.5,self.typeWidth+1,16));
        if (!_names[i].hidden) {
            NSRect name = _names[i].frame;
            drawText([self name:i], TWLabelFont(NO), NSColor.secondaryLabelColor, NSMakeRect(name.origin.x,cy-7.5,MAX(0,name.size.width-10),16));
            drawText(@"⌄", TWLabelFont(NO), NSColor.tertiaryLabelColor, NSMakeRect(NSMaxX(name)-9,cy-8,10,16));
        }
        NSString *status = [self status:i];
        if (status) {
            drawText(status, [NSFont systemFontOfSize:10 weight:NSFontWeightMedium], NSColor.secondaryLabelColor,
                     NSMakeRect(meter,cy-6.5,meterWidth,15));
        } else {
            for (int j = 0; j < barCount; j++) {
                float p = _bars[i][j];
                CGFloat value = p > 0 ? clamp((20*log10f(p)+60)/60,0,1) : 0;
                CGFloat h = 3 + 16 * value;
                TWFillRound(NSMakeRect(meter+j*6,cy-h/2,4,h),2,[accent colorWithAlphaComponent:value > 0 ? 0.93 : 0.34]);
            }
        }
    }
    BOOL pointsRight = _owner.right == _owner.expanded;
    CGFloat cx = _owner.right ? 10 : NSWidth(b)-10, step = pointsRight ? 1 : -1;
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    [arrow moveToPoint:NSMakePoint(cx-1.5*step,28)]; [arrow lineToPoint:NSMakePoint(cx+1.5*step,31)];
    [arrow lineToPoint:NSMakePoint(cx-1.5*step,34)];
    arrow.lineWidth = 1.4; arrow.lineCapStyle = NSLineCapStyleRound; arrow.lineJoinStyle = NSLineJoinStyleRound;
    [NSColor.secondaryLabelColor setStroke]; [arrow stroke];
}
- (void)cancelGesture { _armed = NO; _dragging = NO; }
- (void)mouseDown:(NSEvent *)event {
    [self cancelGesture];
    if (event.modifierFlags & NSEventModifierFlagControl) { [self rightMouseDown:event]; return; }
    if (event.clickCount > 1) return;
    _down = [self.window convertPointToScreen:event.locationInWindow];
    _origin = self.window.frame.origin;
    _armed = YES;
}
- (void)mouseDragged:(NSEvent *)event {
    // Only a body mouse-down arms this gesture. mouseDragged: already identifies
    // a left drag, including events delivered by accessibility input devices.
    if (!_armed) return;
    NSPoint p = [self.window convertPointToScreen:event.locationInWindow];
    CGFloat dx = p.x-_down.x, dy = p.y-_down.y;
    if (!_dragging && hypot(dx,dy) < 4) return;
    _dragging = YES;
    [_owner dragTo:NSMakePoint(_origin.x+dx,_origin.y+dy)];
}
- (void)mouseUp:(NSEvent *)event {
    if (_dragging) [_owner finishDrag];
    [self cancelGesture];
}
- (void)rightMouseDown:(NSEvent *)event {
    [self cancelGesture];
    [_owner showMenu:[_owner contextMenu] accent:NSColor.secondaryLabelColor alignedAtX:[self.window convertPointToScreen:event.locationInWindow].x];
    [self cancelGesture];
}
@end


@implementation TWPanelController {
    NSTimer *_meterTimer;
    TWMenuPanel *_menuPanel;
}
- (instancetype)initWithAudio:(TWAudio *)audio {
    if ((self = [super init])) {
        _audio = audio;
        NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:@"placement"];
        _manual = [saved[@"manual"] boolValue];
        _right = saved[@"right"] ? [saved[@"right"] boolValue] : YES;
        _display = saved[@"display"];
        _edgeOffset = [saved[@"edge"] doubleValue]; _bottomOffset = [saved[@"bottom"] doubleValue];
        _panel = [[TWPanel alloc] initWithContentRect:NSMakeRect(0,0,200,height)
            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered defer:NO];
        _panel.title = @"Twinwave";
        _panel.hasShadow = NO; _panel.opaque = NO; _panel.backgroundColor = NSColor.clearColor;
        _panel.hidesOnDeactivate = NO; _panel.movable = NO; _panel.movableByWindowBackground = NO;
        _panel.releasedWhenClosed = NO; _panel.animationBehavior = NSWindowAnimationBehaviorNone;
        _panel.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorStationary |
                                    NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorIgnoresCycle;
        _body = [[TWBody alloc] initWithOwner:self]; _panel.contentView = _body;
        __weak TWPanelController *weakSelf = self;
        _audio.changed = ^(BOOL input, TWDevice *device, NSString *status, BOOL inUse) {
            [weakSelf.body setDevice:device status:status input:input micInUse:inUse];
        };
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(displaysChanged:)
            name:NSApplicationDidChangeScreenParametersNotification object:nil];
        [NSWorkspace.sharedWorkspace.notificationCenter addObserver:self selector:@selector(woke:)
            name:NSWorkspaceDidWakeNotification object:nil];
    }
    return self;
}
- (void)woke:(NSNotification *)note { [_audio retry]; }
- (NSScreen *)screen {
    for (NSScreen *s in NSScreen.screens) if ([displayKey(s) isEqualToString:_display]) return s;
    return NSScreen.screens.firstObject;
}
- (void)save {
    if (!_display) return;
    [NSUserDefaults.standardUserDefaults setObject:@{@"display":_display, @"right":@(_right), @"manual":@(_manual),
        @"edge":@(_edgeOffset), @"bottom":@(_bottomOffset)} forKey:@"placement"];
}
- (void)applyLevel {
    _panel.level = _manual ? NSFloatingWindowLevel : NSNormalWindowLevel - 1;
}
- (CGFloat)margin:(NSScreen *)s {
    CGFloat strip = NSMinY(s.visibleFrame) - NSMinY(s.frame);
    if (strip < height) return strip > 1 ? 0 : 6;
    return round((strip-height)/2 * s.backingScaleFactor)/s.backingScaleFactor;
}
- (NSRect)target {
    NSScreen *s = self.screen;
    NSRect f = s.frame;
    CGFloat compact = MIN(NSWidth(f),_body.compactWidth);
    CGFloat side = _manual ? _edgeOffset : [self margin:s];
    side = clamp(side,0,NSWidth(f)-compact);
    CGFloat width = MIN(_expanded ? _body.fullWidth : compact, NSWidth(f)-side);
    CGFloat bottom = _manual ? _bottomOffset : side;
    CGFloat y = NSMinY(f)+clamp(bottom,0,NSHeight(f)-height);
    CGFloat x = _right ? NSMaxX(f)-side-width : NSMinX(f)+side;
    return NSMakeRect(x,y,width,height);
}
- (void)place:(BOOL)animate {
    if (!self.screen) return;
    [_animation invalidate]; _animation = nil;
    NSRect target = self.target, start = _panel.frame;
    if (!animate || NSWorkspace.sharedWorkspace.accessibilityDisplayShouldReduceMotion || NSEqualRects(start,target)) {
        [_panel setFrame:target display:YES];
        _body.needsLayout = YES; _body.needsDisplay = YES;
        return;
    }
    CFTimeInterval begin = CACurrentMediaTime();
    _animation = [NSTimer timerWithTimeInterval:1.0/120 repeats:YES block:^(NSTimer *timer) {
        CGFloat t = MIN(1,(CACurrentMediaTime()-begin)/0.16);
        CGFloat eased = t*t*(3-2*t);
        CGFloat w = start.size.width + (target.size.width-start.size.width)*eased;
        CGFloat x = self.right ? NSMaxX(target)-w : NSMinX(target);
        [self.panel setFrame:NSMakeRect(x,NSMinY(target),w,height) display:YES];
        if (t >= 1) { [timer invalidate]; self.animation = nil; }
    }];
    [NSRunLoop.mainRunLoop addTimer:_animation forMode:NSRunLoopCommonModes];
}
- (void)show {
    [self displaysChanged:nil];
    [self applyLevel]; [_panel orderFrontRegardless];
    _meterTimer = [NSTimer timerWithTimeInterval:0.09 repeats:YES block:^(NSTimer *timer) { [self.body sample]; }];
    [NSRunLoop.mainRunLoop addTimer:_meterTimer forMode:NSRunLoopCommonModes];
}
- (void)displaysChanged:(NSNotification *)note {
    [_menuPanel dismiss];
    NSScreen *s = self.screen;
    if (!s) return;
    _display = displayKey(s); [self place:NO]; [self save];
}
- (void)resizeForDevices { [self place:NO]; }
- (void)toggle:(id)sender {
    [_body cancelGesture];
    _expanded = !_expanded;
    _body.needsLayout = YES; [self place:YES];
}
- (void)dragTo:(NSPoint)origin {
    [_animation invalidate]; _animation = nil;
    if (!_manual) { _manual = YES; [self applyLevel]; [_panel orderFrontRegardless]; }
    [_panel setFrameOrigin:origin];
}
- (void)finishDrag {
    NSScreen *s = _panel.screen ?: self.screen;
    if (!s) return;
    _display = displayKey(s);
    NSRect frame = _panel.frame;
    _right = NSMidX(frame) >= NSMidX(s.frame);
    _edgeOffset = MAX(0,_right ? NSMaxX(s.frame)-NSMaxX(frame) : NSMinX(frame)-NSMinX(s.frame));
    _bottomOffset = NSMinY(frame)-NSMinY(s.frame);
    [self place:NO]; [self save];
}
- (void)pin:(NSMenuItem *)item {
    _display = displayKey(_panel.screen ?: self.screen);
    _right = item.tag == 1; _manual = NO; _expanded = NO;
    [self applyLevel]; [self place:NO]; [self save];
}
- (void)retry:(id)sender { [_audio retry]; }
- (void)quit:(id)sender { [NSApp terminate:nil]; }
- (void)showMenu:(NSMenu *)menu accent:(NSColor *)accent alignedAtX:(CGFloat)x {
    [_body cancelGesture];
    [_menuPanel dismiss];
    _menuPanel = [[TWMenuPanel alloc] initWithMenu:menu accent:accent];
    [_menuPanel showBeside:_panel alignedAtX:x];
}
- (NSMenu *)contextMenu {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Twinwave"];
    for (NSString *title in @[@"Bottom Left",@"Bottom Right"]) {
        NSMenuItem *item = [menu addItemWithTitle:title action:@selector(pin:) keyEquivalent:@""];
        item.target = self; item.tag = menu.numberOfItems-1;
        item.image = [NSImage imageWithSystemSymbolName:item.tag == 0 ? @"arrow.down.left" : @"arrow.down.right" accessibilityDescription:nil];
        item.state = !_manual && _right == (item.tag == 1) ? NSControlStateValueOn : NSControlStateValueOff;
    }
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *retry = [menu addItemWithTitle:@"Retry Audio Access" action:@selector(retry:) keyEquivalent:@""];
    retry.target = self;
    retry.image = [NSImage imageWithSystemSymbolName:@"arrow.clockwise" accessibilityDescription:nil];
    NSMenuItem *quit = [menu addItemWithTitle:@"Quit Twinwave" action:@selector(quit:) keyEquivalent:@""];
    quit.target = self;
    quit.image = [NSImage imageWithSystemSymbolName:@"power" accessibilityDescription:nil];
    return menu;
}
- (void)pick:(TWButton *)sender {
    [_body cancelGesture];
    BOOL input = sender.tag == 0;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:input ? @"Audio input" : @"Audio output"];
    menu.autoenablesItems = NO;
    AudioDeviceID current = TWDefault(input);
    for (TWDevice *device in TWDevices(input)) {
        NSMenuItem *item = [menu addItemWithTitle:device.name action:@selector(selectDevice:) keyEquivalent:@""];
        item.image = [NSImage imageWithSystemSymbolName:device.symbol accessibilityDescription:nil];
        item.target = self; item.representedObject = device; item.tag = sender.tag;
        item.state = device.objectID == current ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if (menu.numberOfItems == 0) {
        [menu addItemWithTitle:input ? @"No input devices" : @"No output devices" action:nil keyEquivalent:@""].enabled = NO;
    }
    NSRect button = [_panel convertRectToScreen:[sender convertRect:sender.bounds toView:nil]];
    [self showMenu:menu accent:input ? NSColor.systemTealColor : NSColor.systemBlueColor alignedAtX:NSMinX(button)];
}
- (void)selectDevice:(NSMenuItem *)item {
    BOOL input = item.tag == 0;
    TWDevice *selected = item.representedObject;
    for (TWDevice *live in TWDevices(input)) {
        if ([selected.uid isEqual:live.uid] && TWSelect(live.objectID,input) == noErr) return;
    }
    NSAlert *alert = [NSAlert new]; alert.messageText = @"Couldn’t switch audio devices";
    alert.informativeText = [NSString stringWithFormat:@"Check that %@ is connected, then choose it again.",selected.name];
    [alert runModal];
}
@end
