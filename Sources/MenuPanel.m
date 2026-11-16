#import "MenuPanel.h"
#import "Style.h"

static const CGFloat rowHeight = 28, padding = 5, tileSize = 20, labelX = 30, trailing = 22;

@interface TWMenuSurface : NSView
@end
@implementation TWMenuSurface
- (void)drawRect:(NSRect)dirty { TWDrawSurface(self); }
- (void)viewDidChangeEffectiveAppearance { [super viewDidChangeEffectiveAppearance]; self.needsDisplay = YES; }
- (void)viewDidChangeBackingProperties { [super viewDidChangeBackingProperties]; self.needsDisplay = YES; }
@end

@interface TWMenuTile : NSImageView
@property NSColor *accent;
@end
@implementation TWMenuTile
- (void)drawRect:(NSRect)dirty { TWDrawTile(self.bounds,self.image,self.accent,TWDarkAppearance(self)); }
@end

@interface TWMenuRow : NSTableRowView
@property NSColor *accent;
@end
@implementation TWMenuRow
- (NSBackgroundStyle)interiorBackgroundStyle { return NSBackgroundStyleNormal; }
- (void)drawSelectionInRect:(NSRect)dirty {
    TWFillRound(NSInsetRect(self.bounds,0,1),7,
                [self.accent colorWithAlphaComponent:TWDarkAppearance(self) ? 0.20 : 0.12]);
}
@end

@interface TWMenuTable : NSTableView
@end

@interface TWMenuPanel () <NSTableViewDataSource, NSTableViewDelegate>
- (void)chooseRow:(NSInteger)row;
@end

@implementation TWMenuTable {
    NSTrackingArea *_hover;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_hover) [self removeTrackingArea:_hover];
    _hover = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:NSTrackingInVisibleRect |
              NSTrackingMouseMoved | NSTrackingActiveAlways owner:self userInfo:nil];
    [self addTrackingArea:_hover];
}
- (void)mouseMoved:(NSEvent *)event {
    NSInteger row = [self rowAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
    if (row >= 0 && [self.delegate tableView:self shouldSelectRow:row])
        [self selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}
- (void)keyDown:(NSEvent *)event {
    switch (event.keyCode) {
        case 53: [(TWMenuPanel *)self.window dismiss]; return; // Escape
        case 36: case 76: case 49: [(TWMenuPanel *)self.window chooseRow:self.selectedRow]; return;
        default: [super keyDown:event];
    }
}
@end

@implementation TWMenuPanel {
    NSMenu *_menu;
    NSColor *_accent;
    TWMenuTable *_table;
    NSScrollView *_scroll;
    id _localMonitor, _globalMonitor;
}
- (instancetype)initWithMenu:(NSMenu *)menu accent:(NSColor *)accent {
    if ((self = [super initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless |
                 NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO])) {
        _menu = menu;
        _accent = accent;
        self.title = menu.title;
        self.releasedWhenClosed = NO;
        self.opaque = NO;
        self.backgroundColor = NSColor.clearColor;
        self.hasShadow = NO;
        self.hidesOnDeactivate = NO;
        self.canHide = NO;
        self.level = NSPopUpMenuWindowLevel;
        self.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
        self.animationBehavior = NSWindowAnimationBehaviorNone;
        TWMenuSurface *surface = [TWMenuSurface new];
        self.contentView = surface;

        _table = [TWMenuTable new];
        _table.headerView = nil;
        _table.style = NSTableViewStyleFullWidth;
        _table.intercellSpacing = NSZeroSize;
        _table.backgroundColor = NSColor.clearColor;
        _table.focusRingType = NSFocusRingTypeNone;
        _table.allowsEmptySelection = YES;
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"item"];
        [_table addTableColumn:column];
        _table.delegate = self;
        _table.dataSource = self;
        _table.target = self;
        _table.action = @selector(clickRow:);
        _table.accessibilityLabel = menu.title;

        _scroll = [NSScrollView new];
        _scroll.drawsBackground = NO;
        _scroll.hasVerticalScroller = YES;
        _scroll.autohidesScrollers = YES;
        _scroll.scrollerStyle = NSScrollerStyleOverlay;
        _scroll.documentView = _table;
        [surface addSubview:_scroll];
    }
    return self;
}
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
- (NSInteger)numberOfRowsInTableView:(NSTableView *)table { return _menu.numberOfItems; }
- (CGFloat)tableView:(NSTableView *)table heightOfRow:(NSInteger)row {
    return [_menu itemAtIndex:row].separatorItem ? 9 : rowHeight;
}
- (BOOL)tableView:(NSTableView *)table shouldSelectRow:(NSInteger)row {
    NSMenuItem *item = [_menu itemAtIndex:row];
    return !item.separatorItem && item.enabled;
}
- (NSString *)tableView:(NSTableView *)table typeSelectStringForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    return [_menu itemAtIndex:row].title;
}
- (NSTableRowView *)tableView:(NSTableView *)table rowViewForRow:(NSInteger)row {
    TWMenuRow *rowView = [TWMenuRow new];
    rowView.accent = _accent;
    return rowView;
}
- (NSView *)tableView:(NSTableView *)table viewForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSMenuItem *item = [_menu itemAtIndex:row];
    if (item.separatorItem) {
        NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0,0,column.width,9)];
        NSBox *line = [NSBox new];
        line.boxType = NSBoxSeparator;
        line.frame = NSMakeRect(7,4,MAX(0,column.width-14),1);
        line.autoresizingMask = NSViewWidthSizable;
        [view addSubview:line];
        return view;
    }
    NSTableCellView *cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0,0,column.width,rowHeight)];
    NSTextField *label = [NSTextField labelWithString:item.title];
    BOOL current = item.state == NSControlStateValueOn;
    label.font = TWLabelFont(current);
    label.textColor = item.enabled ? NSColor.labelColor : NSColor.disabledControlTextColor;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    CGFloat start = item.image ? labelX : 7;
    label.frame = NSMakeRect(start,round((rowHeight-label.intrinsicContentSize.height)/2),
                             MAX(0,column.width-start-trailing),label.intrinsicContentSize.height);
    label.autoresizingMask = NSViewWidthSizable;
    cell.textField = label;
    [cell addSubview:label];
    if (item.image) {
        TWMenuTile *icon = [[TWMenuTile alloc] initWithFrame:NSMakeRect(4,4,tileSize,tileSize)];
        icon.image = item.image;
        icon.accent = _accent;
        [icon setAccessibilityElement:NO];
        [cell addSubview:icon];
    }
    if (current) {
        NSImageView *mark = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"checkmark"
                                                                     accessibilityDescription:@"Current"]];
        mark.contentTintColor = _accent;
        mark.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:10 weight:NSFontWeightSemibold];
        mark.frame = NSMakeRect(column.width-17,8,12,12);
        mark.autoresizingMask = NSViewMinXMargin;
        [cell addSubview:mark];
    }
    return cell;
}
- (void)clickRow:(NSTableView *)sender { [self chooseRow:sender.clickedRow]; }
- (void)chooseRow:(NSInteger)row {
    if (row < 0 || row >= _menu.numberOfItems || ![self tableView:_table shouldSelectRow:row]) return;
    NSMenuItem *item = [_menu itemAtIndex:row];
    [self dismiss];
    [NSApp sendAction:item.action to:item.target from:item];
}
- (void)showBeside:(NSWindow *)owner alignedAtX:(CGFloat)x {
    NSScreen *screen = owner.screen ?: NSScreen.mainScreen;
    if (!screen) return;
    NSRect usable = NSInsetRect(screen.visibleFrame,4,4);
    NSRect anchor = owner.frame;
    CGFloat width = 148, contentHeight = 2*padding;
    for (NSMenuItem *item in _menu.itemArray) {
        CGFloat text = [item.title sizeWithAttributes:@{NSFontAttributeName:TWLabelFont(item.state == NSControlStateValueOn)}].width;
        width = MAX(width,ceil(text)+2*padding+labelX+trailing+4);
        contentHeight += item.separatorItem ? 9 : rowHeight;
    }
    width = MIN(width,NSWidth(usable));
    CGFloat above = NSMaxY(usable) - MAX(NSMaxY(anchor)+3,NSMinY(usable));
    CGFloat below = MIN(NSMinY(anchor)-3,NSMaxY(usable)) - NSMinY(usable);
    BOOL openAbove = below < contentHeight && above >= below;
    CGFloat h = MIN(contentHeight,MAX(rowHeight+2*padding, openAbove ? above : below));
    CGFloat y = openAbove ? MAX(NSMaxY(anchor)+3,NSMinY(usable)) : MIN(NSMinY(anchor)-3,NSMaxY(usable))-h;
    NSRect frame = NSMakeRect(MIN(MAX(x,NSMinX(usable)),NSMaxX(usable)-width),
                              MIN(MAX(y,NSMinY(usable)),NSMaxY(usable)-h),width,h);
    [self setFrame:frame display:NO];
    _scroll.frame = NSInsetRect(self.contentView.bounds,padding,padding);
    _table.tableColumns.firstObject.width = NSWidth(_scroll.frame);
    [_table reloadData];
    // Nonactivating panels can lose key status while the user is still choosing.
    // Keep the list visible until selection, Escape, or an actual outside click.
    [self orderFrontRegardless];
    [self makeKeyWindow];
    [self makeFirstResponder:_table];
    __weak TWMenuPanel *weakSelf = self;
    NSEventMask clicks = NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown;
    _localMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:clicks handler:^NSEvent *(NSEvent *event) {
        if (event.window != weakSelf) [weakSelf dismiss];
        return event;
    }];
    _globalMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:clicks handler:^(NSEvent *event) { [weakSelf dismiss]; }];
}
- (void)dismiss {
    if (_localMonitor) { [NSEvent removeMonitor:_localMonitor]; _localMonitor = nil; }
    if (_globalMonitor) { [NSEvent removeMonitor:_globalMonitor]; _globalMonitor = nil; }
    [self orderOut:nil];
}
@end
