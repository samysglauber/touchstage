#import "EditorWindowController.h"
#import "AirTheme.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>

@interface AirPrimaryButton : NSButton
@end

@implementation AirPrimaryButton {
    BOOL _isPressed;
}

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

    // Background pill
    NSColor *bg = _isPressed ? [NSColor colorWithCalibratedRed:0.03f green:0.42f blue:0.85f alpha:1.0f] : AirColorAccent();
    [bg setFill];
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:6.0f yRadius:6.0f];
    [pill fill];

    // Centered Image + Title
    NSImage *img = self.image;
    NSString *title = self.title ?: @"";

    NSDictionary *attrs = @{
        NSForegroundColorAttributeName: [NSColor whiteColor],
        NSFontAttributeName: [NSFont systemFontOfSize:12.0f weight:NSFontWeightSemibold]
    };
    NSSize textSize = [title sizeWithAttributes:attrs];

    CGFloat spacing = 6.0f;
    CGFloat imgW = img ? img.size.width : 0;
    CGFloat imgH = img ? img.size.height : 0;
    CGFloat totalW = imgW + (img ? spacing : 0) + textSize.width;

    CGFloat curX = round((bounds.size.width - totalW) / 2.0f);

    if (img) {
        CGFloat imgY = round((bounds.size.height - imgH) / 2.0f);
        NSRect imgRect = NSMakeRect(curX, imgY, imgW, imgH);
        [img drawInRect:imgRect fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1.0f respectFlipped:YES hints:nil];
        curX += imgW + spacing;
    }

    CGFloat textY = round((bounds.size.height - textSize.height) / 2.0f);
    NSRect textRect = NSMakeRect(curX, textY, textSize.width, textSize.height);
    [title drawInRect:textRect withAttributes:attrs];
}

- (void)mouseDown:(NSEvent *)event {
    _isPressed = YES;
    [self setNeedsDisplay:YES];
    [super mouseDown:event];
    _isPressed = NO;
    [self setNeedsDisplay:YES];
}

@end

@interface AirHeaderBarView : NSVisualEffectView
@end

@implementation AirHeaderBarView

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    [super mouseDown:event];
    [self.window performWindowDragWithEvent:event];
}

@end

@interface TouchStageRecentRowButton : NSButton
@property (nonatomic, copy) NSString *projectPath;
@property (nonatomic, copy) NSString *projectName;
@property (nonatomic, copy) NSString *projectOrientation;
@property (nonatomic, strong) NSTrackingArea *trackingArea;
@property (nonatomic, assign) BOOL isHovered;
@end

@implementation TouchStageRecentRowButton

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.bordered = NO;
        self.wantsLayer = YES;
        self.title = @"";
        [self updateTrackingAreas];
    }
    return self;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (self.trackingArea) {
        [self removeTrackingArea:self.trackingArea];
    }
    self.trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                                     options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways
                                                       owner:self
                                                    userInfo:nil];
    [self addTrackingArea:self.trackingArea];
}

- (void)mouseEntered:(NSEvent *)event {
    self.isHovered = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseExited:(NSEvent *)event {
    self.isHovered = NO;
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    if (self.isHovered) {
        [[NSColor colorWithCalibratedWhite:1.0f alpha:0.08f] setFill];
        NSBezierPath *hoverBg = [NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:6.0f yRadius:6.0f];
        [hoverBg fill];
    }

    BOOL isPortrait = [self.projectOrientation isEqualToString:@"portrait"];
    NSString *iconSymbol = isPortrait ? @"rectangle.portrait.fill" : @"rectangle.fill";
    NSImage *icon = AirSymbol(iconSymbol, 18.0f);
    if (icon) {
        NSImage *tinted = [icon copy];
        [tinted lockFocus];
        [AirColorAccent() set];
        NSRectFillUsingOperation(NSMakeRect(0, 0, tinted.size.width, tinted.size.height), NSCompositingOperationSourceAtop);
        [tinted unlockFocus];
        [tinted drawInRect:NSMakeRect(14, (self.bounds.size.height - 18) / 2.0f, 18, 18) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:self.isHovered ? 1.0f : 0.85f];
    }

    NSDictionary *titleAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:13.0f weight:NSFontWeightSemibold],
        NSForegroundColorAttributeName: [NSColor whiteColor]
    };
    [self.projectName drawAtPoint:NSMakePoint(46, 8.0f) withAttributes:titleAttr];

    NSString *sub = isPortrait ? @"Vertical (460 × 920)" : @"Horizontal (920 × 460)";
    if ([self.projectPath isEqualToString:@"builtin_stage6"]) {
        sub = [sub stringByAppendingString:@" • Factory Preset"];
    } else if (self.projectPath.length > 0) {
        sub = [sub stringByAppendingFormat:@" • %@", [self.projectPath stringByDeletingLastPathComponent].lastPathComponent];
    }
    NSDictionary *subAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0f weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.6f alpha:1.0f]
    };
    [sub drawAtPoint:NSMakePoint(46, 26.0f) withAttributes:subAttr];

    NSImage *chevron = AirSymbol(@"chevron.right", 11.0f);
    if (chevron) {
        NSImage *tinted = [chevron copy];
        [tinted lockFocus];
        [[NSColor colorWithCalibratedWhite:0.75f alpha:1.0f] set];
        NSRectFillUsingOperation(NSMakeRect(0, 0, tinted.size.width, tinted.size.height), NSCompositingOperationSourceAtop);
        [tinted unlockFocus];
        [tinted drawInRect:NSMakeRect(self.bounds.size.width - 24, (self.bounds.size.height - 11) / 2.0f, 11, 11) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:self.isHovered ? 1.0f : 0.4f];
    }

    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.06f] setFill];
    NSRectFill(NSMakeRect(46, self.bounds.size.height - 1.0f, self.bounds.size.width - 46, 1.0f));
}
@end

@implementation EditorWindowController {
    EditorCanvasView *_canvasView;
    InspectorView *_inspectorView;
    AirTabBarView *_tabBarView;
    NSPopUpButton *_presetsPopup;
    NSSegmentedControl *_orientationSegment;
    NSWindow *_launcherSheetWindow;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(100, 100, 1260, 750);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskMiniaturizable |
                                                              NSWindowStyleMaskResizable |
                                                              NSWindowStyleMaskFullSizeContentView)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"TouchStage Editor";
    window.titleVisibility = NSWindowTitleHidden;
    window.titlebarAppearsTransparent = YES;
    window.backgroundColor = AirColorWindowBg();
    window.movableByWindowBackground = NO;
    window.minSize = NSMakeSize(1020, 600);

    self = [super initWithWindow:window];
    if (self) {
        _layout = [LayoutModel referencePreset];
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    NSView *contentView = self.window.contentView;
    NSRect bounds = contentView.bounds;

    CGFloat topBarH = 52.0f;
    CGFloat tabBarH = 38.0f;
    CGFloat inspectorW = 315.0f;
    CGFloat canvasW = bounds.size.width - inspectorW;
    CGFloat bodyH = bounds.size.height - topBarH - tabBarH;

    // 1. Frosted Glass Top Header Bar
    AirHeaderBarView *topBar = [[AirHeaderBarView alloc] initWithFrame:NSMakeRect(0, bounds.size.height - topBarH, bounds.size.width, topBarH)];
    topBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    topBar.material = NSVisualEffectMaterialHeaderView;
    topBar.blendingMode = NSVisualEffectBlendingModeWithinWindow;
    topBar.state = NSVisualEffectStateActive;
    [contentView addSubview:topBar];

    // Bottom hairline divider for header
    NSView *hairline = [[NSView alloc] initWithFrame:NSMakeRect(0, topBarH - 1.0f, bounds.size.width, 1.0f)];
    hairline.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    hairline.wantsLayer = YES;
    hairline.layer.backgroundColor = AirColorBorder().CGColor;
    [topBar addSubview:hairline];

    // --- LEFT GROUP: Preset Capsule & Save Preset (offset x=84 for traffic lights) ---
    _presetsPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(84, 12, 160, 28) pullsDown:NO];
    _presetsPopup.bezelStyle = NSBezelStyleTexturedRounded;
    _presetsPopup.font = [NSFont systemFontOfSize:12.0f weight:NSFontWeightMedium];
    _presetsPopup.target = self;
    _presetsPopup.action = @selector(onPresetSelected:);
    [self reloadPresetsMenu];
    [topBar addSubview:_presetsPopup];

    NSButton *btnSavePreset = [self createToolbarButtonWithTitle:@"Save Preset"
                                                          symbol:@"bookmark"
                                                         tooltip:@"Save current layout into preset library"
                                                           frame:NSMakeRect(252, 12, 104, 28)
                                                          action:@selector(onSavePresetClicked:)];
    btnSavePreset.autoresizingMask = NSViewMaxXMargin;
    [topBar addSubview:btnSavePreset];

    NSButton *btnDeletePreset = [self createToolbarButtonWithTitle:@"Delete"
                                                            symbol:@"trash"
                                                           tooltip:@"Delete selected user preset from library"
                                                             frame:NSMakeRect(362, 12, 80, 28)
                                                            action:@selector(onDeletePresetClicked:)];
    btnDeletePreset.autoresizingMask = NSViewMaxXMargin;
    [topBar addSubview:btnDeletePreset];

    // --- RIGHT GROUP: File Open/Save & Primary Sync Action ---
    // Primary "Sync to Devices" Button with pixel-perfect custom alignment
    AirPrimaryButton *btnSync = [[AirPrimaryButton alloc] initWithFrame:NSMakeRect(bounds.size.width - 170, 11, 154, 30)];
    btnSync.autoresizingMask = NSViewMinXMargin;
    btnSync.title = @"Sync to Devices";
    btnSync.image = AirSymbol(@"antenna.radiowaves.left.and.right", 12.0f);
    btnSync.toolTip = @"Send layout directly to TouchStage Bridge and connected mobile devices";
    btnSync.target = self;
    btnSync.action = @selector(onSendToBridgeClicked:);
    [topBar addSubview:btnSync];

    // Hairline divider
    NSView *rightDivider = [[NSView alloc] initWithFrame:NSMakeRect(bounds.size.width - 182, 15, 1.0f, 22.0f)];
    rightDivider.autoresizingMask = NSViewMinXMargin;
    rightDivider.wantsLayer = YES;
    rightDivider.layer.backgroundColor = AirColorBorder().CGColor;
    [topBar addSubview:rightDivider];

    // Save File Button (Icon + Text)
    NSButton *btnExport = [self createToolbarButtonWithTitle:@"Save File"
                                                      symbol:@"square.and.arrow.up"
                                                     tooltip:@"Save Layout to JSON File (⌘S)"
                                                       frame:NSMakeRect(bounds.size.width - 290, 12, 96, 28)
                                                      action:@selector(onSaveLayoutClicked:)];
    btnExport.autoresizingMask = NSViewMinXMargin;
    [topBar addSubview:btnExport];

    // Open File Button (Icon + Text)
    NSButton *btnImport = [self createToolbarButtonWithTitle:@"Open"
                                                      symbol:@"folder"
                                                     tooltip:@"Open Layout from JSON File (⌘O)"
                                                       frame:NSMakeRect(bounds.size.width - 378, 12, 80, 28)
                                                      action:@selector(onOpenLayoutClicked:)];
    btnImport.autoresizingMask = NSViewMinXMargin;
    [topBar addSubview:btnImport];

    // New Project Button (Icon + Text)
    NSButton *btnNew = [self createToolbarButtonWithTitle:@"New Project"
                                                   symbol:@"plus"
                                                  tooltip:@"Create a new blank layout (⌘N)"
                                                    frame:NSMakeRect(bounds.size.width - 496, 12, 110, 28)
                                                   action:@selector(onNewLayoutClicked:)];
    btnNew.autoresizingMask = NSViewMinXMargin;
    [topBar addSubview:btnNew];

    // Orientation Toggle (Landscape / Portrait)
    _orientationSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Landscape", @"Portrait"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(onOrientationChanged:)];
    _orientationSegment.frame = NSMakeRect(bounds.size.width - 660, 12, 154, 28);
    _orientationSegment.segmentStyle = NSSegmentStyleTexturedRounded;
    _orientationSegment.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    _orientationSegment.selectedSegment = (_layout.canvasHeight > _layout.canvasWidth) ? 1 : 0;
    _orientationSegment.autoresizingMask = NSViewMinXMargin;
    [topBar addSubview:_orientationSegment];

    // 2. Multi-Screen Tab Bar
    _tabBarView = [[AirTabBarView alloc] initWithFrame:NSMakeRect(0, bounds.size.height - topBarH - tabBarH, canvasW, tabBarH)];
    _tabBarView.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _tabBarView.layout = _layout;
    _tabBarView.delegate = self;
    [_tabBarView reloadTabs];
    [contentView addSubview:_tabBarView];

    // 3. Hardware-grade Canvas View
    _canvasView = [[EditorCanvasView alloc] initWithFrame:NSMakeRect(0, 0, canvasW, bodyH)];
    _canvasView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _canvasView.layout = _layout;
    _canvasView.delegate = self;
    [contentView addSubview:_canvasView];

    // 4. Pro Sidebar Inspector View
    _inspectorView = [[InspectorView alloc] initWithFrame:NSMakeRect(bounds.size.width - inspectorW, 0, inspectorW, bounds.size.height - topBarH)];
    _inspectorView.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
    _inspectorView.delegate = self;
    [contentView addSubview:_inspectorView];
}

- (NSButton *)createToolbarButtonWithTitle:(NSString *)title symbol:(NSString *)symbol tooltip:(NSString *)tooltip frame:(NSRect)frame action:(SEL)action {
    NSButton *btn = [[NSButton alloc] initWithFrame:frame];
    btn.bezelStyle = NSBezelStyleTexturedRounded;
    btn.title = title;
    btn.image = AirSymbol(symbol, 12.0f);
    btn.imagePosition = NSImageLeading;
    btn.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    btn.toolTip = tooltip;
    btn.target = self;
    btn.action = action;
    return btn;
}

- (void)showEditor {
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self showLauncherSheet];
    });
}

- (void)canvasDidSelectControl:(MidiControlModel *)control {
    [_inspectorView bindControl:control];
}

- (void)canvasDidChangeControl:(MidiControlModel *)control {
    [_inspectorView refreshValues];
}

- (void)canvasDidDeleteControl:(MidiControlModel *)control {
    [_inspectorView bindControl:nil];
}

- (void)inspectorWillChangeControl:(MidiControlModel *)control {
    [_canvasView pushUndoSnapshot];
}

- (void)inspectorDidUpdateControl:(MidiControlModel *)control {
    [_canvasView setNeedsDisplay:YES];
}

- (void)inspectorDidRequestDuplicate:(MidiControlModel *)control {
    [_canvasView duplicateSelected];
}

- (void)inspectorDidRequestDelete:(MidiControlModel *)control {
    [_canvasView deleteSelected];
}

#pragma mark - AirTabBarDelegate

- (void)tabBarDidSelectPageIndex:(NSInteger)index {
    if (index >= 0 && index < _layout.pages.count) {
        _layout.activePageIndex = index;
        _canvasView.selectedControl = nil;
        [_inspectorView bindControl:nil];
        [_tabBarView reloadTabs];
        [_canvasView setNeedsDisplay:YES];
    }
}

- (void)tabBarDidRequestAddPage {
    NSString *pageName = [NSString stringWithFormat:@"Screen %lu", (unsigned long)(_layout.pages.count + 1)];
    [_layout addPageWithName:pageName];
    _canvasView.selectedControl = nil;
    [_inspectorView bindControl:nil];
    [_tabBarView reloadTabs];
    [_canvasView setNeedsDisplay:YES];
}

- (void)tabBarDidRequestDeletePageIndex:(NSInteger)index {
    if (_layout.pages.count <= 1) return;
    [_layout removePageAtIndex:index];
    _canvasView.selectedControl = nil;
    [_inspectorView bindControl:nil];
    [_tabBarView reloadTabs];
    [_canvasView setNeedsDisplay:YES];
}

- (void)tabBarDidRenamePageIndex:(NSInteger)index toName:(NSString *)newName {
    if (index >= 0 && index < _layout.pages.count && newName.length > 0) {
        _layout.pages[index].name = newName;
        [_tabBarView reloadTabs];
    }
}

- (NSString *)presetsDirectoryPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES);
    NSString *appSupport = paths.firstObject ?: [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support"];
    NSString *dir = [appSupport stringByAppendingPathComponent:@"TouchStage Editor/Presets"];
    NSString *studioDir = [appSupport stringByAppendingPathComponent:@"TouchStage Studio/Presets"];
    NSString *legacyDir = [appSupport stringByAppendingPathComponent:@"AirMIDI Studio/Presets"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:studioDir] && ![fm fileExistsAtPath:dir]) {
        [fm copyItemAtPath:studioDir toPath:dir error:nil];
    } else if ([fm fileExistsAtPath:legacyDir] && ![fm fileExistsAtPath:dir]) {
        [fm copyItemAtPath:legacyDir toPath:dir error:nil];
    }
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return dir;
}

- (void)reloadPresetsMenu {
    [_presetsPopup removeAllItems];

    // Built-ins with SF Symbols (Only the primary template)
    NSMenuItem *item1 = [[NSMenuItem alloc] initWithTitle:@"Stage 6-Track" action:nil keyEquivalent:@""];
    item1.representedObject = @"builtin_stage6";
    item1.image = AirSymbol(@"slider.vertical.3", 12.0f);
    [_presetsPopup.menu addItem:item1];

    // User Presets
    NSString *dir = [self presetsDirectoryPath];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    NSMutableArray *presetFiles = [NSMutableArray array];
    for (NSString *file in files) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"json"]) {
            [presetFiles addObject:file];
        }
    }

    if (presetFiles.count > 0) {
        [_presetsPopup.menu addItem:[NSMenuItem separatorItem]];
        for (NSString *file in presetFiles) {
            NSString *title = [file stringByDeletingPathExtension];
            NSString *fullPath = [dir stringByAppendingPathComponent:file];
            NSMenuItem *uItem = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
            uItem.representedObject = fullPath;
            uItem.image = AirSymbol(@"doc.text", 12.0f);
            [_presetsPopup.menu addItem:uItem];
        }
    }

    if (_layout.name.length > 0) {
        [_presetsPopup selectItemWithTitle:_layout.name];
    }
}

- (void)onSavePresetClicked:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Save as Editor Preset";
    alert.informativeText = @"Enter a name for this layout to save it into your TouchStage Editor preset library:";
    alert.icon = AirSymbol(@"bookmark.circle.fill", 36.0f);
    [alert addButtonWithTitle:@"Save Preset"];
    [alert addButtonWithTitle:@"Cancel"];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)];
    input.stringValue = _layout.name ?: @"Custom Rig";
    alert.accessoryView = input;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *name = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (name.length == 0) name = @"Custom Rig";
            self->_layout.name = name;

            NSString *fileName = [NSString stringWithFormat:@"%@.json", name];
            NSString *filePath = [[self presetsDirectoryPath] stringByAppendingPathComponent:fileName];
            NSError *err = nil;
            NSData *data = [self->_layout toJSONDataWithError:&err];
            if (data) {
                [data writeToFile:filePath atomically:YES];
                [self reloadPresetsMenu];
                [self->_presetsPopup selectItemWithTitle:name];
                [self recordRecentProjectNamed:name path:filePath orientation:self->_layout.orientation];
            }
        }
    }];
}

- (void)onOrientationChanged:(id)sender {
    NSInteger sel = _orientationSegment.selectedSegment;
    if (sel == 1) { // Portrait
        _layout.orientation = @"portrait";
        _layout.canvasWidth = 460.0f;
        _layout.canvasHeight = 920.0f;
    } else { // Landscape
        _layout.orientation = @"landscape";
        _layout.canvasWidth = 920.0f;
        _layout.canvasHeight = 460.0f;
    }
    [_canvasView setNeedsDisplay:YES];
}

- (void)onPresetSelected:(id)sender {
    NSMenuItem *item = _presetsPopup.selectedItem;
    if (!item) return;

    id rep = item.representedObject;
    if ([rep isEqualToString:@"builtin_stage6"]) {
        _layout = [LayoutModel referencePreset];
        [self recordRecentProjectNamed:@"Stage 6-Track" path:@"builtin_stage6" orientation:@"landscape"];
    } else if ([rep isKindOfClass:[NSString class]]) {
        NSData *data = [NSData dataWithContentsOfFile:(NSString *)rep];
        NSError *err = nil;
        LayoutModel *loaded = [LayoutModel layoutFromJSONData:data error:&err];
        if (loaded) {
            _layout = loaded;
            [self recordRecentProjectNamed:loaded.name path:(NSString *)rep orientation:loaded.orientation];
        }
    }

    _orientationSegment.selectedSegment = (_layout.canvasHeight > _layout.canvasWidth) ? 1 : 0;
    _canvasView.layout = _layout;
    _tabBarView.layout = _layout;
    [_tabBarView reloadTabs];
    [_inspectorView bindControl:nil];
}

- (void)onDeletePresetClicked:(id)sender {
    NSMenuItem *item = _presetsPopup.selectedItem;
    if (!item) return;

    id rep = item.representedObject;
    if ([rep isKindOfClass:[NSString class]] && [(NSString *)rep hasPrefix:@"builtin_"]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Cannot Delete Factory Preset";
        alert.informativeText = [NSString stringWithFormat:@"\"%@\" is a built-in factory preset and cannot be removed.", item.title];
        alert.icon = AirSymbol(@"lock.shield", 36.0f);
        [alert addButtonWithTitle:@"OK"];
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
        return;
    }

    if (![rep isKindOfClass:[NSString class]] || ![[NSFileManager defaultManager] fileExistsAtPath:(NSString *)rep]) {
        return;
    }

    NSString *filePath = (NSString *)rep;
    NSString *presetName = item.title;

    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = [NSString stringWithFormat:@"Delete Preset \"%@\"?", presetName];
    confirm.informativeText = @"Are you sure you want to permanently remove this preset from your library?";
    confirm.alertStyle = NSAlertStyleCritical;
    confirm.icon = AirSymbol(@"trash.circle.fill", 36.0f);
    [confirm addButtonWithTitle:@"Delete"];
    [confirm addButtonWithTitle:@"Cancel"];

    [confirm beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSError *err = nil;
            [[NSFileManager defaultManager] removeItemAtPath:filePath error:&err];

            // Switch back to factory default preset
            self->_layout = [LayoutModel referencePreset];
            self->_orientationSegment.selectedSegment = (self->_layout.canvasHeight > self->_layout.canvasWidth) ? 1 : 0;
            self->_canvasView.layout = self->_layout;
            self->_tabBarView.layout = self->_layout;
            [self->_tabBarView reloadTabs];
            [self->_inspectorView bindControl:nil];

            [self reloadPresetsMenu];
            [self->_presetsPopup selectItemAtIndex:0];
        }
    }];
}

- (IBAction)onNewLayoutClicked:(id)sender {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"New Project";
    alert.informativeText = @"Enter a name and screen orientation for your TouchStage project:";
    alert.icon = AirSymbol(@"doc.badge.plus", 36.0f);
    [alert addButtonWithTitle:@"Create Project"];
    [alert addButtonWithTitle:@"Cancel"];

    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 75)];

    NSTextField *labelName = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 52, 280, 16)];
    labelName.stringValue = @"Project Name:";
    labelName.font = [NSFont systemFontOfSize:11.0f weight:NSFontWeightMedium];
    labelName.textColor = [NSColor secondaryLabelColor];
    labelName.bezeled = NO;
    labelName.drawsBackground = NO;
    labelName.editable = NO;
    [container addSubview:labelName];

    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 26, 280, 22)];
    input.stringValue = @"Untitled Project";
    [container addSubview:input];

    NSSegmentedControl *orientChoice = [NSSegmentedControl segmentedControlWithLabels:@[@"Horizontal (Landscape)", @"Vertical (Portrait)"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
    orientChoice.frame = NSMakeRect(0, 0, 280, 22);
    orientChoice.segmentStyle = NSSegmentStyleTexturedRounded;
    orientChoice.font = [NSFont systemFontOfSize:11.0f];
    orientChoice.selectedSegment = (_orientationSegment.selectedSegment == 1) ? 1 : 0;
    [container addSubview:orientChoice];

    alert.accessoryView = container;

    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            NSString *name = [input.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if (name.length == 0) name = @"Untitled Project";
            BOOL isPortrait = (orientChoice.selectedSegment == 1);
            [self startNewProjectWithName:name isPortrait:isPortrait];
        }
    }];
}

- (void)startNewProjectWithName:(NSString *)name {
    [self startNewProjectWithName:name isPortrait:(_orientationSegment.selectedSegment == 1)];
}

- (void)startNewProjectWithName:(NSString *)name isPortrait:(BOOL)isPortrait {
    LayoutModel *newLayout = [[LayoutModel alloc] init];
    newLayout.name = name ?: @"Untitled Project";
    if (isPortrait) {
        newLayout.orientation = @"portrait";
        newLayout.canvasWidth = 460.0f;
        newLayout.canvasHeight = 920.0f;
    } else {
        newLayout.orientation = @"landscape";
        newLayout.canvasWidth = 920.0f;
        newLayout.canvasHeight = 460.0f;
    }
    _layout = newLayout;
    _orientationSegment.selectedSegment = isPortrait ? 1 : 0;
    _canvasView.layout = newLayout;
    _tabBarView.layout = newLayout;
    [_tabBarView reloadTabs];
    [_inspectorView bindControl:nil];
    [_presetsPopup selectItem:nil];
    [self recordRecentProjectNamed:newLayout.name path:@"" orientation:newLayout.orientation];
}

- (void)onSaveLayoutClicked:(id)sender {
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.title = @"Export TouchStage Layout File";
    savePanel.nameFieldStringValue = [NSString stringWithFormat:@"%@.json", [_layout.name.lowercaseString stringByReplacingOccurrencesOfString:@" " withString:@"_"]];

    [savePanel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSError *err = nil;
            NSData *data = [self->_layout toJSONDataWithError:&err];
            if (data) {
                [data writeToURL:savePanel.URL atomically:YES];
                [self recordRecentProjectNamed:self->_layout.name path:savePanel.URL.path orientation:self->_layout.orientation];
            }
        }
    }];
}

- (void)onOpenLayoutClicked:(id)sender {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    openPanel.title = @"Open TouchStage Layout File";

    [openPanel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSError *err = nil;
            NSData *data = [NSData dataWithContentsOfURL:openPanel.URL];
            LayoutModel *loaded = [LayoutModel layoutFromJSONData:data error:&err];
            if (loaded) {
                self->_layout = loaded;
                self->_orientationSegment.selectedSegment = (loaded.canvasHeight > loaded.canvasWidth) ? 1 : 0;
                self->_canvasView.layout = loaded;
                self->_tabBarView.layout = loaded;
                [self->_tabBarView reloadTabs];
                [self->_inspectorView bindControl:nil];
                [self->_presetsPopup selectItemWithTitle:loaded.name];
                [self recordRecentProjectNamed:loaded.name path:openPanel.URL.path orientation:loaded.orientation];
            }
        }
    }];
}

- (void)onSendToBridgeClicked:(id)sender {
    NSInteger syncedCount = [self pushLayoutToLocalBridgeSilently];
    NSAlert *alert = [[NSAlert alloc] init];

    if (syncedCount < 0) {
        alert.icon = AirSymbol(@"exclamationmark.triangle.fill", 36.0f);
        alert.messageText = @"TouchStage Bridge Not Found";
        alert.informativeText = @"TouchStage Bridge is not currently running.\n\nPlease launch TouchStage Bridge from your Applications to connect devices.";
        [alert addButtonWithTitle:@"OK"];
    } else if (syncedCount == 0) {
        alert.icon = AirSymbol(@"wifi.slash", 36.0f);
        alert.messageText = @"No Mobile Devices Connected";
        alert.informativeText = @"TouchStage Bridge is active, but no mobile device is currently connected to it.\n\nPlease open TouchStage on your mobile device (Android) and connect to this Mac first, then click Sync to Devices.";
        [alert addButtonWithTitle:@"OK"];
    } else {
        alert.icon = AirSymbol(@"checkmark.circle.fill", 36.0f);
        alert.messageText = @"Layout Synchronized";
        alert.informativeText = [NSString stringWithFormat:@"Layout \"%@\" was successfully transmitted to %ld connected mobile device(s).\n\nTap 'Update Layout' on your mobile screen to load it.", _layout.name, (long)syncedCount];
        [alert addButtonWithTitle:@"Done"];
    }

    [alert beginSheetModalForWindow:self.window completionHandler:nil];
}

- (NSInteger)pushLayoutToLocalBridgeSilently {
    int sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock < 0) return -1;

    struct timeval tv;
    tv.tv_sec = 1;
    tv.tv_usec = 500000;
    setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, (const char *)&tv, sizeof(tv));
    setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, (const char *)&tv, sizeof(tv));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(9000);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(sock);
        return -1;
    }

    NSString *json = [_layout toJSONString];
    json = [json stringByReplacingOccurrencesOfString:@"\r" withString:@""];
    json = [json stringByReplacingOccurrencesOfString:@"\n" withString:@" "];

    NSString *payload = [NSString stringWithFormat:@"SYNC_LAYOUT:%@\n", json];
    const char *bytes = payload.UTF8String;
    size_t total = strlen(bytes);
    size_t sent = 0;
    while (sent < total) {
        ssize_t n = send(sock, bytes + sent, total - sent, 0);
        if (n <= 0) break;
        sent += n;
    }

    char ackBuf[64];
    memset(ackBuf, 0, sizeof(ackBuf));
    ssize_t ackLen = recv(sock, ackBuf, sizeof(ackBuf) - 1, 0);
    close(sock);

    if (ackLen > 0) {
        NSString *ackStr = [NSString stringWithUTF8String:ackBuf];
        if ([ackStr hasPrefix:@"OK:SYNC:"]) {
            NSString *countStr = [ackStr substringFromIndex:8];
            return [countStr integerValue];
        }
        if ([ackStr hasPrefix:@"OK:SYNC"]) {
            return 1;
        }
    }

    return 0;
}

#pragma mark - Responder Chain Actions

- (void)undo:(id)sender {
    [_canvasView undo];
}

- (void)redo:(id)sender {
    [_canvasView redo];
}

- (void)selectAll:(id)sender {
    [_canvasView selectAllControls];
}

- (void)deleteSelected:(id)sender {
    [_canvasView deleteSelected];
}

#pragma mark - Recent Projects & Launcher Sheet

- (void)recordRecentProjectNamed:(NSString *)name path:(NSString *)path orientation:(NSString *)orientation {
    if (name.length == 0) return;
    NSMutableArray *recents = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"TouchStageRecentProjects"] mutableCopy];
    if (!recents) recents = [NSMutableArray array];

    for (NSInteger i = recents.count - 1; i >= 0; i--) {
        NSDictionary *dict = recents[i];
        if ((path.length > 0 && [dict[@"path"] isEqualToString:path]) || [dict[@"name"] isEqualToString:name]) {
            [recents removeObjectAtIndex:i];
        }
    }

    [recents insertObject:@{
        @"name": name,
        @"path": path ?: @"",
        @"orientation": orientation ?: @"landscape",
        @"date": [NSDate date]
    } atIndex:0];

    while (recents.count > 15) {
        [recents removeLastObject];
    }

    [[NSUserDefaults standardUserDefaults] setObject:recents forKey:@"TouchStageRecentProjects"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSArray<NSDictionary *> *)loadRecentProjects {
    NSMutableArray *results = [NSMutableArray array];

    // 1. Built-in Factory Preset
    [results addObject:@{
        @"name": @"Stage 6-Track",
        @"path": @"builtin_stage6",
        @"orientation": @"landscape"
    }];

    // 2. Presets Directory
    NSString *dir = [self presetsDirectoryPath];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    for (NSString *file in files) {
        if ([file.pathExtension.lowercaseString isEqualToString:@"json"]) {
            NSString *title = [file stringByDeletingPathExtension];
            NSString *fullPath = [dir stringByAppendingPathComponent:file];
            NSString *orient = @"landscape";
            NSData *d = [NSData dataWithContentsOfFile:fullPath];
            if (d) {
                NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
                if (dict[@"orientation"]) {
                    orient = dict[@"orientation"];
                } else if ([dict[@"canvasHeight"] doubleValue] > [dict[@"canvasWidth"] doubleValue]) {
                    orient = @"portrait";
                }
            }
            [results addObject:@{
                @"name": title,
                @"path": fullPath,
                @"orientation": orient
            }];
        }
    }

    // 3. Saved External Recents from NSUserDefaults
    NSArray *savedRecents = [[NSUserDefaults standardUserDefaults] arrayForKey:@"TouchStageRecentProjects"];
    if ([savedRecents isKindOfClass:[NSArray class]]) {
        for (NSDictionary *item in savedRecents) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                NSString *p = item[@"path"];
                if (p && ![[p lowercaseString] isEqualToString:@"builtin_stage6"]) {
                    BOOL alreadyAdded = NO;
                    for (NSDictionary *existing in results) {
                        if ([existing[@"path"] isEqualToString:p] || [existing[@"name"] isEqualToString:item[@"name"]]) {
                            alreadyAdded = YES;
                            break;
                        }
                    }
                    if (!alreadyAdded && (p.length == 0 || [[NSFileManager defaultManager] fileExistsAtPath:p])) {
                        [results addObject:item];
                    }
                }
            }
        }
    }

    return results;
}

- (void)showLauncherSheet {
    if (_launcherSheetWindow) {
        return;
    }

    NSRect sheetFrame = NSMakeRect(0, 0, 650, 420);
    NSWindow *sheet = [[NSWindow alloc] initWithContentRect:sheetFrame
                                                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView
                                                    backing:NSBackingStoreBuffered
                                                      defer:NO];
    sheet.titlebarAppearsTransparent = YES;
    sheet.titleVisibility = NSWindowTitleHidden;
    sheet.movableByWindowBackground = YES;

    NSVisualEffectView *vibrant = [[NSVisualEffectView alloc] initWithFrame:sheetFrame];
    vibrant.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    vibrant.material = NSVisualEffectMaterialUnderWindowBackground;
    vibrant.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    vibrant.state = NSVisualEffectStateActive;
    sheet.contentView = vibrant;

    // --- LEFT COLUMN (Actions & Branding) ---
    NSView *leftCol = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 225, 420)];
    leftCol.wantsLayer = YES;
    leftCol.layer.backgroundColor = [NSColor colorWithCalibratedWhite:0.06f alpha:0.75f].CGColor;
    [vibrant addSubview:leftCol];

    NSView *leftDivider = [[NSView alloc] initWithFrame:NSMakeRect(224, 0, 1, 420)];
    leftDivider.wantsLayer = YES;
    leftDivider.layer.backgroundColor = AirColorBorder().CGColor;
    [leftCol addSubview:leftDivider];

    NSImageView *iconView = [[NSImageView alloc] initWithFrame:NSMakeRect(24, 326, 56, 56)];
    NSImage *appIcon = [NSImage imageNamed:NSImageNameApplicationIcon];
    if (!appIcon) {
        NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"AppIcon" ofType:@"icns"];
        if (iconPath) appIcon = [[NSImage alloc] initWithContentsOfFile:iconPath];
    }
    iconView.image = appIcon ?: AirSymbol(@"slider.vertical.3", 44.0f);
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    [leftCol addSubview:iconView];

    NSTextField *titleLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 290, 180, 26)];
    titleLbl.stringValue = @"TouchStage";
    titleLbl.font = [NSFont systemFontOfSize:18.0f weight:NSFontWeightBold];
    titleLbl.textColor = [NSColor whiteColor];
    titleLbl.bezeled = NO;
    titleLbl.drawsBackground = NO;
    titleLbl.editable = NO;
    [leftCol addSubview:titleLbl];

    NSTextField *subLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 270, 180, 18)];
    subLbl.stringValue = @"MIDI Layout Editor";
    subLbl.font = [NSFont systemFontOfSize:11.0f weight:NSFontWeightMedium];
    subLbl.textColor = [NSColor secondaryLabelColor];
    subLbl.bezeled = NO;
    subLbl.drawsBackground = NO;
    subLbl.editable = NO;
    [leftCol addSubview:subLbl];

    NSView *brandHairline = [[NSView alloc] initWithFrame:NSMakeRect(24, 256, 177, 1)];
    brandHairline.wantsLayer = YES;
    brandHairline.layer.backgroundColor = AirColorBorder().CGColor;
    [leftCol addSubview:brandHairline];

    NSButton *btnNew = [[NSButton alloc] initWithFrame:NSMakeRect(24, 198, 177, 38)];
    btnNew.bezelStyle = NSBezelStyleTexturedRounded;
    btnNew.title = @"  New Project";
    btnNew.image = AirSymbol(@"plus.circle.fill", 15.0f);
    btnNew.imagePosition = NSImageLeading;
    btnNew.font = [NSFont systemFontOfSize:12.5f weight:NSFontWeightBold];
    btnNew.target = self;
    btnNew.action = @selector(onLauncherNewProject:);
    [leftCol addSubview:btnNew];

    NSButton *btnOpen = [[NSButton alloc] initWithFrame:NSMakeRect(24, 152, 177, 34)];
    btnOpen.bezelStyle = NSBezelStyleTexturedRounded;
    btnOpen.title = @"  Open Project...";
    btnOpen.image = AirSymbol(@"folder.fill", 13.0f);
    btnOpen.imagePosition = NSImageLeading;
    btnOpen.font = [NSFont systemFontOfSize:12.0f weight:NSFontWeightMedium];
    btnOpen.target = self;
    btnOpen.action = @selector(onLauncherOpenFile:);
    [leftCol addSubview:btnOpen];

    // --- RIGHT COLUMN (Recent Projects List) ---
    NSView *rightCol = [[NSView alloc] initWithFrame:NSMakeRect(225, 0, 425, 420)];
    [vibrant addSubview:rightCol];

    NSTextField *recentHeader = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 372, 220, 22)];
    recentHeader.stringValue = @"RECENT PROJECTS";
    recentHeader.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightBold];
    recentHeader.textColor = [NSColor secondaryLabelColor];
    recentHeader.bezeled = NO;
    recentHeader.drawsBackground = NO;
    recentHeader.editable = NO;
    [rightCol addSubview:recentHeader];

    NSButton *btnClose = [[NSButton alloc] initWithFrame:NSMakeRect(425 - 34, 368, 22, 22)];
    btnClose.bezelStyle = NSBezelStyleCircular;
    btnClose.image = AirSymbol(@"xmark", 10.0f);
    btnClose.imagePosition = NSImageOnly;
    btnClose.bordered = NO;
    btnClose.wantsLayer = YES;
    btnClose.toolTip = @"Close (Esc)";
    btnClose.keyEquivalent = @"\e";
    btnClose.target = self;
    btnClose.action = @selector(onCloseLauncherSheet:);
    [rightCol addSubview:btnClose];

    NSView *rightDivider = [[NSView alloc] initWithFrame:NSMakeRect(24, 358, 380, 1)];
    rightDivider.wantsLayer = YES;
    rightDivider.layer.backgroundColor = AirColorBorder().CGColor;
    [rightCol addSubview:rightDivider];

    NSArray *recents = [self loadRecentProjects];
    CGFloat rowH = 50.0f;
    CGFloat listContentH = MAX(330.0f, recents.count * rowH + 10.0f);

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 16, 388, 334)];
    scrollView.hasVerticalScroller = (recents.count * rowH > 330.0f);
    scrollView.drawsBackground = NO;
    scrollView.autohidesScrollers = YES;

    NSView *listDocView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 388, listContentH)];
    scrollView.documentView = listDocView;
    [rightCol addSubview:scrollView];

    CGFloat curY = listContentH - rowH - 6.0f;
    for (NSDictionary *item in recents) {
        TouchStageRecentRowButton *rowBtn = [[TouchStageRecentRowButton alloc] initWithFrame:NSMakeRect(4, curY, 380, rowH)];
        rowBtn.projectName = item[@"name"] ?: @"Untitled Project";
        rowBtn.projectPath = item[@"path"] ?: @"";
        rowBtn.projectOrientation = item[@"orientation"] ?: @"landscape";
        rowBtn.target = self;
        rowBtn.action = @selector(onRecentRowClicked:);
        [listDocView addSubview:rowBtn];
        curY -= rowH;
    }

    _launcherSheetWindow = sheet;
    [self.window beginSheet:sheet completionHandler:nil];
}

- (void)onLauncherNewProject:(id)sender {
    [self closeLauncherSheetWithCompletion:^{
        [self onNewLayoutClicked:nil];
    }];
}

- (void)onLauncherOpenFile:(id)sender {
    [self closeLauncherSheetWithCompletion:^{
        [self onOpenLayoutClicked:nil];
    }];
}

- (void)onRecentRowClicked:(TouchStageRecentRowButton *)sender {
    NSString *path = sender.projectPath;
    NSString *name = sender.projectName;
    [self closeLauncherSheetWithCompletion:^{
        [self openRecentProjectPath:path name:name];
    }];
}

- (void)onCloseLauncherSheet:(id)sender {
    [self closeLauncherSheetWithCompletion:nil];
}

- (void)closeLauncherSheetWithCompletion:(void(^)(void))completion {
    if (!_launcherSheetWindow) {
        if (completion) completion();
        return;
    }
    NSWindow *sheet = _launcherSheetWindow;
    _launcherSheetWindow = nil;
    [self.window endSheet:sheet];
    [sheet orderOut:nil];
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), completion);
    }
}

- (void)openRecentProjectPath:(NSString *)path name:(NSString *)name {
    if ([path isEqualToString:@"builtin_stage6"]) {
        _layout = [LayoutModel referencePreset];
    } else if (path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSData *data = [NSData dataWithContentsOfFile:path];
        NSError *err = nil;
        LayoutModel *loaded = [LayoutModel layoutFromJSONData:data error:&err];
        if (loaded) {
            _layout = loaded;
        } else {
            _layout = [LayoutModel referencePreset];
        }
    } else {
        _layout = [LayoutModel referencePreset];
    }

    _orientationSegment.selectedSegment = (_layout.canvasHeight > _layout.canvasWidth) ? 1 : 0;
    _canvasView.layout = _layout;
    _tabBarView.layout = _layout;
    [_tabBarView reloadTabs];
    [_inspectorView bindControl:nil];
    [self reloadPresetsMenu];
    if (_layout.name.length > 0) {
        [_presetsPopup selectItemWithTitle:_layout.name];
    }
    [self recordRecentProjectNamed:_layout.name path:path orientation:_layout.orientation];
}

@end
