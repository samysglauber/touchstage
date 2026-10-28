#import "AirTabBarView.h"
#import "AirTheme.h"

@interface AirTabButton : NSButton
@property (nonatomic, assign) NSInteger pageIndex;
@property (nonatomic, assign) BOOL isActiveTab;
@property (nonatomic, weak) AirTabBarView *tabBar;
@end

@implementation AirTabButton

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.bordered = NO;
    }
    return self;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;

    if (self.isActiveTab) {
        // Active Tab Capsule Pill
        NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 2.0f, 4.0f) xRadius:6.0f yRadius:6.0f];
        [[NSColor colorWithCalibratedRed:0.04f green:0.52f blue:1.0f alpha:0.25f] setFill];
        [pill fill];
        [AirColorAccent() setStroke];
        [pill setLineWidth:1.5f];
        [pill stroke];
    } else {
        // Inactive Tab subtle hover / transparent
        NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(bounds, 2.0f, 4.0f) xRadius:6.0f yRadius:6.0f];
        [[NSColor colorWithCalibratedWhite:0.18f alpha:0.4f] setFill];
        [pill fill];
        [[NSColor colorWithCalibratedWhite:0.25f alpha:0.6f] setStroke];
        [pill setLineWidth:1.0f];
        [pill stroke];
    }

    // Icon + Text
    NSImage *icon = self.image;
    NSString *title = self.title ?: @"Screen";

    NSDictionary *attrs = @{
        NSForegroundColorAttributeName: (self.isActiveTab ? [NSColor whiteColor] : AirColorTextSecondary()),
        NSFontAttributeName: [NSFont systemFontOfSize:11.5f weight:(self.isActiveTab ? NSFontWeightBold : NSFontWeightMedium)]
    };
    NSSize textSize = [title sizeWithAttributes:attrs];

    CGFloat iconW = icon ? icon.size.width : 0;
    CGFloat spacing = 6.0f;
    CGFloat totalW = iconW + (icon ? spacing : 0) + textSize.width;

    CGFloat curX = round((bounds.size.width - totalW) / 2.0f);

    if (icon) {
        CGFloat iconY = round((bounds.size.height - icon.size.height) / 2.0f);
        NSRect iconRect = NSMakeRect(curX, iconY, icon.size.width, icon.size.height);
        [icon drawInRect:iconRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:(self.isActiveTab ? 1.0f : 0.7f) respectFlipped:YES hints:nil];
        curX += iconW + spacing;
    }

    CGFloat textY = round((bounds.size.height - textSize.height) / 2.0f);
    NSRect textRect = NSMakeRect(curX, textY, textSize.width, textSize.height);
    [title drawInRect:textRect withAttributes:attrs];
}

@end

@implementation AirTabBarView {
    NSScrollView *_scrollView;
    NSView *_container;
    NSButton *_btnAdd;
}

- (BOOL)isFlipped {
    return YES;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.wantsLayer = YES;

    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.hasVerticalScroller = NO;
    _scrollView.drawsBackground = NO;

    _container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, self.bounds.size.width, self.bounds.size.height)];
    _scrollView.documentView = _container;
    [self addSubview:_scrollView];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    // Bar background
    [[NSColor colorWithCalibratedRed:0.09f green:0.10f blue:0.13f alpha:1.0f] setFill];
    NSRectFill(self.bounds);

    // Bottom hairline divider
    [AirColorBorder() setStroke];
    NSBezierPath *line = [NSBezierPath bezierPath];
    [line moveToPoint:NSMakePoint(0, self.bounds.size.height - 0.5f)];
    [line lineToPoint:NSMakePoint(self.bounds.size.width, self.bounds.size.height - 0.5f)];
    [line setLineWidth:1.0f];
    [line stroke];
}

- (void)reloadTabs {
    // Clear old tab buttons
    for (NSView *v in _container.subviews.copy) {
        [v removeFromSuperview];
    }

    if (!self.layout) return;

    CGFloat curX = 16.0f;
    CGFloat tabH = 28.0f;
    CGFloat tabY = (self.bounds.size.height - tabH) / 2.0f;

    // Label: "SCREENS / PAGES:"
    NSTextField *tagLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(curX, tabY + 6.0f, 64, 16)];
    tagLabel.stringValue = @"SCREENS:";
    tagLabel.font = [NSFont systemFontOfSize:10.0f weight:NSFontWeightBold];
    tagLabel.textColor = AirColorTextMuted();
    tagLabel.editable = NO;
    tagLabel.selectable = NO;
    tagLabel.bezeled = NO;
    tagLabel.drawsBackground = NO;
    [_container addSubview:tagLabel];
    curX += 70.0f;

    for (NSInteger i = 0; i < self.layout.pages.count; i++) {
        LayoutPageModel *page = self.layout.pages[i];
        BOOL isActive = (i == self.layout.activePageIndex);

        // Estimate width based on title
        NSDictionary *attrs = @{ NSFontAttributeName: [NSFont systemFontOfSize:11.5f weight:NSFontWeightBold] };
        NSSize sz = [page.name sizeWithAttributes:attrs];
        CGFloat tabW = MAX(90.0f, sz.width + 36.0f);

        AirTabButton *tabBtn = [[AirTabButton alloc] initWithFrame:NSMakeRect(curX, tabY, tabW, tabH)];
        tabBtn.title = page.name;
        tabBtn.pageIndex = i;
        tabBtn.isActiveTab = isActive;
        tabBtn.tabBar = self;
        tabBtn.image = AirSymbol(isActive ? @"rectangle.split.2x1.fill" : @"rectangle", 11.0f);
        tabBtn.target = self;
        tabBtn.action = @selector(onTabClicked:);
        [_container addSubview:tabBtn];

        // Right-click context menu on tab
        NSMenu *tabMenu = [[NSMenu alloc] initWithTitle:@"Tab Options"];
        NSMenuItem *itemRename = [[NSMenuItem alloc] initWithTitle:@"Rename Screen..." action:@selector(onRenameTabClicked:) keyEquivalent:@""];
        itemRename.representedObject = @(i);
        itemRename.target = self;
        [tabMenu addItem:itemRename];

        if (self.layout.pages.count > 1) {
            NSMenuItem *itemDelete = [[NSMenuItem alloc] initWithTitle:@"Delete Screen" action:@selector(onDeleteTabClicked:) keyEquivalent:@""];
            itemDelete.representedObject = @(i);
            itemDelete.target = self;
            [tabMenu addItem:itemDelete];
        }
        tabBtn.menu = tabMenu;

        curX += tabW + 6.0f;
    }

    // Add "+" New Screen Button
    _btnAdd = [[NSButton alloc] initWithFrame:NSMakeRect(curX, tabY, 94.0f, tabH)];
    _btnAdd.bezelStyle = NSBezelStyleTexturedRounded;
    _btnAdd.title = @"+ Screen";
    _btnAdd.font = [NSFont systemFontOfSize:11.0f weight:NSFontWeightMedium];
    _btnAdd.image = AirSymbol(@"plus", 10.0f);
    _btnAdd.imagePosition = NSImageLeading;
    _btnAdd.toolTip = @"Add a new screen/page to this preset";
    _btnAdd.target = self;
    _btnAdd.action = @selector(onAddPageClicked:);
    [_container addSubview:_btnAdd];

    curX += 104.0f;
    _container.frame = NSMakeRect(0, 0, MAX(curX, self.bounds.size.width), self.bounds.size.height);
}

- (void)onTabClicked:(AirTabButton *)sender {
    if (self.delegate) {
        [self.delegate tabBarDidSelectPageIndex:sender.pageIndex];
    }
}

- (void)onAddPageClicked:(id)sender {
    if (self.delegate) {
        [self.delegate tabBarDidRequestAddPage];
    }
}

- (void)onDeleteTabClicked:(NSMenuItem *)sender {
    NSInteger idx = [sender.representedObject integerValue];
    if (self.delegate) {
        [self.delegate tabBarDidRequestDeletePageIndex:idx];
    }
}

- (void)onRenameTabClicked:(NSMenuItem *)sender {
    NSInteger idx = [sender.representedObject integerValue];
    if (idx < 0 || idx >= self.layout.pages.count) return;

    LayoutPageModel *page = self.layout.pages[idx];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Rename Screen";
    alert.informativeText = @"Enter a new name for this screen / tab:";
    alert.icon = AirSymbol(@"rectangle.and.pencil.and.ellipsis", 36.0f);
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    input.stringValue = page.name ?: @"Screen";
    alert.accessoryView = input;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *newName = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (newName.length > 0 && self.delegate) {
                [self.delegate tabBarDidRenamePageIndex:idx toName:newName];
            }
        }
    }];
}

@end
