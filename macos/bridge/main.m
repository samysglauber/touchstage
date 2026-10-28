#import <Cocoa/Cocoa.h>
#import "AirMIDIBridgeServer.h"

// --- Helper Functions ---
static NSImage *TouchStageSymbol(NSString *name, CGFloat size, NSFontWeight weight) {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:size weight:weight];
        NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        if (img) {
            NSImage *configured = [img imageWithSymbolConfiguration:config];
            configured.template = YES;
            return configured;
        }
    }
    return nil;
}

static NSImage *TouchStageSymbolWithLeftPadding(NSString *name, CGFloat size, NSFontWeight weight, CGFloat leftPad) {
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:size weight:weight];
        NSImage *img = [NSImage imageWithSystemSymbolName:name accessibilityDescription:nil];
        if (img) {
            NSImage *configured = [img imageWithSymbolConfiguration:config];
            if (leftPad <= 0.0f) {
                configured.template = YES;
                return configured;
            }
            NSSize newSize = NSMakeSize(configured.size.width + leftPad, configured.size.height);
            NSImage *padded = [NSImage imageWithSize:newSize flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
                [configured drawInRect:NSMakeRect(leftPad, 0, configured.size.width, configured.size.height)
                              fromRect:NSZeroRect
                             operation:NSCompositingOperationSourceOver
                              fraction:1.0f];
                return YES;
            }];
            padded.template = YES;
            return padded;
        }
    }
    return nil;
}

@interface TouchStageVisualEffectView : NSVisualEffectView
@end
@implementation TouchStageVisualEffectView
- (BOOL)isFlipped { return YES; }
@end

@interface TouchStageFlippedView : NSView
@end
@implementation TouchStageFlippedView
- (BOOL)isFlipped { return YES; }
@end

@interface TouchStageCardView : TouchStageFlippedView
@end
@implementation TouchStageCardView
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1.0f alpha:0.045f].CGColor;
        self.layer.borderColor = [NSColor colorWithCalibratedWhite:1.0f alpha:0.08f].CGColor;
        self.layer.borderWidth = 1.0f;
        self.layer.cornerRadius = 10.0f;
        self.layer.masksToBounds = YES;
    }
    return self;
}
@end

@interface TouchStagePopoverViewController : NSViewController
@property (nonatomic, weak) AirMIDIBridgeServer *bridgeServer;
@property (nonatomic, weak) NSPopover *popover;
- (void)reloadUI;
@end

@implementation TouchStagePopoverViewController {
    TouchStageCardView *_netCard;
    NSTextField *_devHeader;
    TouchStageCardView *_devicesContainer;
    NSScrollView *_devicesScrollView;
    TouchStageFlippedView *_devicesDocView;
    NSView *_bottomDivider;
    NSButton *_btnEditor;
    NSButton *_btnQuit;
    NSTextField *_ipValueLabel;
    NSButton *_btnCopyIp;
}

- (void)loadView {
    NSRect frame = NSMakeRect(0, 0, 320, 264);
    TouchStageVisualEffectView *visualEffect = [[TouchStageVisualEffectView alloc] initWithFrame:frame];
    visualEffect.material = NSVisualEffectMaterialPopover;
    visualEffect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    visualEffect.state = NSVisualEffectStateActive;
    visualEffect.wantsLayer = YES;

    self.view = visualEffect;
    self.preferredContentSize = NSMakeSize(320, 264);
    [self setupViewHierarchy];
}

- (void)setupViewHierarchy {
    CGFloat pad = 14.0f;
    CGFloat contentW = 320.0f - (pad * 2.0f); // 292 pt

    // 1. Card 1: CoreMIDI & Wi-Fi Server (y: 14, h: 70)
    _netCard = [[TouchStageCardView alloc] initWithFrame:NSMakeRect(pad, 14, contentW, 70)];
    _netCard.autoresizingMask = NSViewNotSizable;
    [self.view addSubview:_netCard];

    // Row 1: CoreMIDI
    NSImageView *midiIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 9, 16, 16)];
    midiIcon.image = TouchStageSymbol(@"pianokeys", 12.0f, NSFontWeightMedium) ?: TouchStageSymbol(@"waveform", 12.0f, NSFontWeightMedium);
    midiIcon.contentTintColor = [NSColor secondaryLabelColor];
    midiIcon.autoresizingMask = NSViewNotSizable;
    [_netCard addSubview:midiIcon];

    NSTextField *midiTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(34, 9, 80, 16)];
    midiTitle.stringValue = @"MIDI Port";
    midiTitle.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    midiTitle.textColor = [NSColor secondaryLabelColor];
    midiTitle.bezeled = NO;
    midiTitle.drawsBackground = NO;
    midiTitle.editable = NO;
    midiTitle.selectable = NO;
    midiTitle.autoresizingMask = NSViewNotSizable;
    [_netCard addSubview:midiTitle];

    NSTextField *midiVal = [[NSTextField alloc] initWithFrame:NSMakeRect(contentW - 165, 9, 153, 16)];
    midiVal.stringValue = @"TouchStage Controller";
    midiVal.alignment = NSTextAlignmentRight;
    midiVal.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightSemibold];
    midiVal.textColor = [NSColor whiteColor];
    midiVal.bezeled = NO;
    midiVal.drawsBackground = NO;
    midiVal.editable = NO;
    midiVal.selectable = NO;
    midiVal.autoresizingMask = NSViewNotSizable;
    [_netCard addSubview:midiVal];

    // Card internal divider
    NSView *cardDiv = [[NSView alloc] initWithFrame:NSMakeRect(12, 34, contentW - 24, 1)];
    cardDiv.wantsLayer = YES;
    cardDiv.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1.0f alpha:0.05f].CGColor;
    cardDiv.autoresizingMask = NSViewNotSizable;
    [_netCard addSubview:cardDiv];

    // Row 2: Wi-Fi Server
    NSImageView *wifiIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(12, 43, 16, 16)];
    wifiIcon.image = TouchStageSymbol(@"wifi", 12.0f, NSFontWeightMedium);
    wifiIcon.contentTintColor = [NSColor secondaryLabelColor];
    wifiIcon.autoresizingMask = NSViewNotSizable;
    [_netCard addSubview:wifiIcon];

    NSTextField *wifiTitle = [[NSTextField alloc] initWithFrame:NSMakeRect(34, 43, 70, 16)];
    wifiTitle.stringValue = @"Wi-Fi IP";
    wifiTitle.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    wifiTitle.textColor = [NSColor secondaryLabelColor];
    wifiTitle.bezeled = NO;
    wifiTitle.drawsBackground = NO;
    wifiTitle.editable = NO;
    wifiTitle.selectable = NO;
    wifiTitle.autoresizingMask = NSViewNotSizable;
    [_netCard addSubview:wifiTitle];

    _ipValueLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(90, 43, contentW - 156, 16)];
    _ipValueLabel.alignment = NSTextAlignmentRight;
    _ipValueLabel.font = [NSFont monospacedSystemFontOfSize:11.0f weight:NSFontWeightMedium];
    _ipValueLabel.textColor = [NSColor whiteColor];
    _ipValueLabel.bezeled = NO;
    _ipValueLabel.drawsBackground = NO;
    _ipValueLabel.editable = NO;
    _ipValueLabel.selectable = NO;
    _ipValueLabel.autoresizingMask = NSViewNotSizable;
    [_netCard addSubview:_ipValueLabel];

    _btnCopyIp = [[NSButton alloc] initWithFrame:NSMakeRect(contentW - 58, 41, 48, 20)];
    _btnCopyIp.bezelStyle = NSBezelStyleInline;
    _btnCopyIp.title = @"Copy";
    _btnCopyIp.font = [NSFont systemFontOfSize:10.5f weight:NSFontWeightMedium];
    _btnCopyIp.target = self;
    _btnCopyIp.action = @selector(onCopyIpClicked:);
    _btnCopyIp.autoresizingMask = NSViewNotSizable;
    [_netCard addSubview:_btnCopyIp];

    // 2. Section 2: Connected Devices Header (y: 96)
    _devHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(pad + 2, 96, contentW, 16)];
    _devHeader.stringValue = @"CONNECTED DEVICES";
    _devHeader.font = [NSFont systemFontOfSize:10.0f weight:NSFontWeightBold];
    _devHeader.textColor = [NSColor secondaryLabelColor];
    _devHeader.bezeled = NO;
    _devHeader.drawsBackground = NO;
    _devHeader.editable = NO;
    _devHeader.selectable = NO;
    _devHeader.autoresizingMask = NSViewNotSizable;
    [self.view addSubview:_devHeader];

    _devicesContainer = [[TouchStageCardView alloc] initWithFrame:NSMakeRect(pad, 116, contentW, 88)];
    _devicesContainer.autoresizingMask = NSViewNotSizable;
    [self.view addSubview:_devicesContainer];

    _devicesScrollView = [[NSScrollView alloc] initWithFrame:_devicesContainer.bounds];
    _devicesScrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _devicesScrollView.drawsBackground = NO;
    _devicesScrollView.autohidesScrollers = YES;
    _devicesScrollView.hasVerticalScroller = NO;
    [_devicesContainer addSubview:_devicesScrollView];

    _devicesDocView = [[TouchStageFlippedView alloc] initWithFrame:_devicesContainer.bounds];
    _devicesScrollView.documentView = _devicesDocView;

    // 3. Hairline divider (y: 216)
    _bottomDivider = [[NSView alloc] initWithFrame:NSMakeRect(0, 216, 320, 1)];
    _bottomDivider.wantsLayer = YES;
    _bottomDivider.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1.0f alpha:0.08f].CGColor;
    _bottomDivider.autoresizingMask = NSViewNotSizable;
    [self.view addSubview:_bottomDivider];

    // 4. Footer Actions (y: 226, h: 26) - Native inline capsule style with icon shifted slightly right
    _btnEditor = [[NSButton alloc] initWithFrame:NSMakeRect(pad, 226, 114, 26)];
    _btnEditor.bezelStyle = NSBezelStyleInline;
    _btnEditor.title = @" Open Editor";
    _btnEditor.image = TouchStageSymbolWithLeftPadding(@"slider.horizontal.2.square", 12.0f, NSFontWeightMedium, 5.0f);
    _btnEditor.imagePosition = NSImageLeading;
    _btnEditor.font = [NSFont systemFontOfSize:11.0f weight:NSFontWeightMedium];
    _btnEditor.target = self;
    _btnEditor.action = @selector(onOpenEditorClicked:);
    _btnEditor.autoresizingMask = NSViewNotSizable;
    [self.view addSubview:_btnEditor];

    _btnQuit = [[NSButton alloc] initWithFrame:NSMakeRect(320 - pad - 68, 226, 68, 26)];
    _btnQuit.bezelStyle = NSBezelStyleInline;
    _btnQuit.title = @" Quit";
    _btnQuit.image = TouchStageSymbolWithLeftPadding(@"power", 11.0f, NSFontWeightMedium, 5.0f);
    _btnQuit.imagePosition = NSImageLeading;
    _btnQuit.font = [NSFont systemFontOfSize:11.0f weight:NSFontWeightMedium];
    _btnQuit.target = self;
    _btnQuit.action = @selector(onQuitClicked:);
    _btnQuit.autoresizingMask = NSViewNotSizable;
    [self.view addSubview:_btnQuit];

    [self reloadUI];
}

- (void)reloadUI {
    NSString *ipText = [NSString stringWithFormat:@"%@:%ld", self.bridgeServer.localIP ?: @"127.0.0.1", (long)self.bridgeServer.port];
    _ipValueLabel.stringValue = ipText;

    // Refresh devices container subviews only
    for (NSView *sub in [_devicesDocView.subviews copy]) {
        [sub removeFromSuperview];
    }

    NSArray<ConnectedDevice *> *devices = self.bridgeServer.connectedDevices;
    CGFloat pad = 14.0f;
    CGFloat contentW = 320.0f - (pad * 2.0f); // 292 pt

    // Update Header Count
    if (devices.count > 0) {
        _devHeader.stringValue = [NSString stringWithFormat:@"CONNECTED DEVICES (%lu)", (unsigned long)devices.count];
    } else {
        _devHeader.stringValue = @"CONNECTED DEVICES";
    }

    // Adaptive card height with symmetrical margins (8 pt top, 8 pt bottom):
    // 0 devices -> 54 pt (compact waiting card)
    // 1 device  -> 45 pt (8 pt top, 29 pt row, 8 pt bottom)
    // 2 devices -> 82 pt (8 pt top, 29 pt row 1, 8 pt gap with divider, 29 pt row 2, 8 pt bottom)
    // 3+ devices -> 82 pt (maintains 2-device height and enables smooth vertical scroll)
    CGFloat devCardH;
    if (devices.count == 0) {
        devCardH = 54.0f;
    } else if (devices.count == 1) {
        devCardH = 45.0f;
    } else {
        devCardH = 82.0f;
    }

    _devicesContainer.frame = NSMakeRect(pad, 116, contentW, devCardH);
    _devicesScrollView.frame = _devicesContainer.bounds;

    CGFloat bottomDivY = 116 + devCardH + 12;
    _bottomDivider.frame = NSMakeRect(0, bottomDivY, 320, 1);

    CGFloat footerY = bottomDivY + 10;
    _btnEditor.frame = NSMakeRect(pad, footerY, 114, 26);
    _btnQuit.frame = NSMakeRect(320 - pad - 68, footerY, 68, 26);

    CGFloat totalH = footerY + 26 + 12;
    self.preferredContentSize = NSMakeSize(320, totalH);
    self.popover.contentSize = NSMakeSize(320, totalH);

    if (devices.count == 0) {
        _devicesScrollView.hasVerticalScroller = NO;
        _devicesDocView.frame = NSMakeRect(0, 0, contentW, devCardH);

        NSImageView *emptyIcon = [[NSImageView alloc] initWithFrame:NSMakeRect((contentW - 20) / 2.0f, 9, 20, 20)];
        emptyIcon.image = TouchStageSymbol(@"iphone.radiowaves.left.and.right", 17.0f, NSFontWeightLight);
        emptyIcon.contentTintColor = [NSColor colorWithCalibratedWhite:1.0f alpha:0.35f];
        emptyIcon.autoresizingMask = NSViewNotSizable;
        [_devicesDocView addSubview:emptyIcon];

        NSTextField *emptyLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 31, contentW - 20, 15)];
        emptyLbl.stringValue = @"Waiting for mobile devices...";
        emptyLbl.alignment = NSTextAlignmentCenter;
        emptyLbl.font = [NSFont systemFontOfSize:11.0f weight:NSFontWeightMedium];
        emptyLbl.textColor = [NSColor secondaryLabelColor];
        emptyLbl.bezeled = NO;
        emptyLbl.drawsBackground = NO;
        emptyLbl.editable = NO;
        emptyLbl.selectable = NO;
        emptyLbl.autoresizingMask = NSViewNotSizable;
        [_devicesDocView addSubview:emptyLbl];
    } else {
        CGFloat topPad = 8.0f;
        CGFloat rowContentH = 29.0f;
        CGFloat rowGap = 8.0f;
        CGFloat totalDocH = (devices.count * rowContentH) + ((devices.count - 1) * rowGap) + (topPad * 2.0f);
        if (devices.count <= 2) {
            totalDocH = devCardH;
        }

        _devicesDocView.frame = NSMakeRect(0, 0, contentW, totalDocH);
        _devicesScrollView.hasVerticalScroller = (devices.count > 2);

        CGFloat curY = topPad;

        for (NSUInteger i = 0; i < devices.count; i++) {
            ConnectedDevice *d = devices[i];

            // Divider between devices centered in rowGap
            if (i > 0) {
                NSView *sep = [[NSView alloc] initWithFrame:NSMakeRect(36, curY - (rowGap / 2.0f), contentW - 48, 1)];
                sep.wantsLayer = YES;
                sep.layer.backgroundColor = [NSColor colorWithCalibratedWhite:1.0f alpha:0.05f].CGColor;
                [_devicesDocView addSubview:sep];
            }

            NSImageView *devIcon = [[NSImageView alloc] initWithFrame:NSMakeRect(12, curY + 5, 18, 18)];
            devIcon.image = TouchStageSymbol(@"iphone", 14.0f, NSFontWeightMedium);
            devIcon.contentTintColor = [NSColor colorWithSRGBRed:0.0f green:0.9f blue:1.0f alpha:1.0f]; // TouchStage Cyan
            devIcon.autoresizingMask = NSViewNotSizable;
            [_devicesDocView addSubview:devIcon];

            NSTextField *nameLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(36, curY, contentW - 105, 16)];
            nameLbl.stringValue = d.name ?: @"Android Device";
            nameLbl.font = [NSFont systemFontOfSize:12.0f weight:NSFontWeightSemibold];
            nameLbl.textColor = [NSColor whiteColor];
            nameLbl.bezeled = NO;
            nameLbl.drawsBackground = NO;
            nameLbl.editable = NO;
            nameLbl.selectable = NO;
            nameLbl.autoresizingMask = NSViewNotSizable;
            [_devicesDocView addSubview:nameLbl];

            NSTextField *ipLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(36, curY + 15, contentW - 105, 14)];
            ipLbl.stringValue = [NSString stringWithFormat:@"%@ • Connected", d.ipAddress ?: @"Wi-Fi"];
            ipLbl.font = [NSFont systemFontOfSize:10.0f weight:NSFontWeightRegular];
            ipLbl.textColor = [NSColor secondaryLabelColor];
            ipLbl.bezeled = NO;
            ipLbl.drawsBackground = NO;
            ipLbl.editable = NO;
            ipLbl.selectable = NO;
            ipLbl.autoresizingMask = NSViewNotSizable;
            [_devicesDocView addSubview:ipLbl];

            NSView *pill = [[TouchStageFlippedView alloc] initWithFrame:NSMakeRect(contentW - 58, curY + 5, 48, 18)];
            pill.wantsLayer = YES;
            pill.layer.cornerRadius = 9.0f;
            pill.layer.backgroundColor = [NSColor colorWithSRGBRed:0.2f green:0.82f blue:0.4f alpha:0.15f].CGColor;
            pill.autoresizingMask = NSViewNotSizable;
            [_devicesDocView addSubview:pill];

            NSTextField *pillTxt = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 2, 48, 14)];
            pillTxt.stringValue = @"Ready";
            pillTxt.alignment = NSTextAlignmentCenter;
            pillTxt.font = [NSFont systemFontOfSize:9.5f weight:NSFontWeightBold];
            pillTxt.textColor = [NSColor colorWithSRGBRed:0.25f green:0.85f blue:0.45f alpha:1.0f];
            pillTxt.bezeled = NO;
            pillTxt.drawsBackground = NO;
            pillTxt.editable = NO;
            pillTxt.selectable = NO;
            pillTxt.autoresizingMask = NSViewNotSizable;
            [pill addSubview:pillTxt];

            curY += rowContentH + rowGap;
        }
    }
}

// Actions
- (void)onCopyIpClicked:(NSButton *)sender {
    NSString *ipStr = [NSString stringWithFormat:@"%@:%ld", self.bridgeServer.localIP ?: @"127.0.0.1", (long)self.bridgeServer.port];
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:ipStr forType:NSPasteboardTypeString];

    sender.title = @"✓ Copied";
    sender.contentTintColor = [NSColor colorWithSRGBRed:0.25f green:0.85f blue:0.45f alpha:1.0f];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        sender.title = @"Copy";
        sender.contentTintColor = nil;
    });
}

- (void)onOpenEditorClicked:(id)sender {
    [self.popover performClose:nil];

    NSString *bundleDir = [[NSBundle mainBundle] bundlePath].stringByDeletingLastPathComponent;
    NSString *editorPath = [bundleDir stringByAppendingPathComponent:@"TouchStage Editor.app"];
    if (![[NSFileManager defaultManager] fileExistsAtPath:editorPath]) {
        editorPath = @"/Applications/TouchStage Editor.app";
    }

    if ([[NSFileManager defaultManager] fileExistsAtPath:editorPath]) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:editorPath]];
    } else {
        NSURL *appUrl = [[NSWorkspace sharedWorkspace] URLForApplicationWithBundleIdentifier:@"com.touchstage.editor"];
        if (appUrl) {
            [[NSWorkspace sharedWorkspace] openApplicationAtURL:appUrl configuration:[NSWorkspaceOpenConfiguration configuration] completionHandler:nil];
        }
    }
}

- (void)onQuitClicked:(id)sender {
    [self.bridgeServer stop];
    [NSApp terminate:nil];
}

@end

// --- Application Delegate ---
@interface BridgeAppDelegate : NSObject <NSApplicationDelegate>
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSPopover *popover;
@property (strong, nonatomic) TouchStagePopoverViewController *popoverController;
@property (strong, nonatomic) AirMIDIBridgeServer *bridgeServer;
@end

@implementation BridgeAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // 1. Initialize Server
    self.bridgeServer = [[AirMIDIBridgeServer alloc] initWithPort:9000];
    [self.bridgeServer start];

    // 2. Setup Popover with fixed dimensions (264 pt)
    self.popover = [[NSPopover alloc] init];
    self.popover.contentSize = NSMakeSize(320, 264);
    self.popover.behavior = NSPopoverBehaviorTransient;
    self.popover.animates = NO;

    self.popoverController = [[TouchStagePopoverViewController alloc] init];
    self.popoverController.bridgeServer = self.bridgeServer;
    self.popoverController.popover = self.popover;
    self.popover.contentViewController = self.popoverController;

    // 3. Status Bar Item (Minimalist Apple-like Icon)
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    NSImage *icon = TouchStageSymbol(@"slider.vertical.3", 14.5f, NSFontWeightMedium);
    if (!icon) {
        icon = [self createFallbackIcon];
    }
    icon.template = YES;
    self.statusItem.button.image = icon;
    self.statusItem.button.toolTip = @"TouchStage Bridge";
    self.statusItem.button.target = self;
    self.statusItem.button.action = @selector(togglePopover:);

    // 4. Update on device changes
    __weak typeof(self) weakSelf = self;
    self.bridgeServer.deviceListChanged = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.popoverController reloadUI];
        });
    };
}

- (NSImage *)createFallbackIcon {
    NSSize size = NSMakeSize(18, 18);
    NSImage *img = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        [[NSColor blackColor] setStroke];
        for (int i = 0; i < 3; i++) {
            CGFloat x = 4.0f + (i * 5.0f);
            NSBezierPath *track = [NSBezierPath bezierPath];
            [track moveToPoint:NSMakePoint(x, 2)];
            [track lineToPoint:NSMakePoint(x, 16)];
            [track setLineWidth:1.5f];
            [track stroke];

            CGFloat thumbY = (i == 0 ? 8 : (i == 1 ? 4 : 11));
            NSRect thumb = NSMakeRect(x - 2, thumbY, 4, 3);
            [[NSColor blackColor] setFill];
            NSRectFill(thumb);
        }
        return YES;
    }];
    img.template = YES;
    return img;
}

- (void)togglePopover:(id)sender {
    if (self.popover.isShown) {
        [self.popover performClose:sender];
    } else {
        [self.popoverController reloadUI];
        [self.popover showRelativeToRect:self.statusItem.button.bounds
                                  ofView:self.statusItem.button
                           preferredEdge:NSRectEdgeMinY];
        [self.popover.contentViewController.view.window makeKeyWindow];
        [NSApp activateIgnoringOtherApps:YES];
    }
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];
        BridgeAppDelegate *delegate = [[BridgeAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
