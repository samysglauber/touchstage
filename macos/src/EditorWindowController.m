#import "EditorWindowController.h"

@implementation EditorWindowController {
    EditorCanvasView *_canvasView;
    InspectorView *_inspectorView;
    NSPopUpButton *_presetsPopup;
}

- (instancetype)init {
    NSRect frame = NSMakeRect(100, 100, 1220, 680);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"AirMIDI Studio - Editor Nativo de Layouts para macOS";
    window.minSize = NSMakeSize(900, 500);

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

    CGFloat topBarH = 44.0f;
    CGFloat inspectorW = 280.0f;
    CGFloat canvasW = bounds.size.width - inspectorW;
    CGFloat bodyH = bounds.size.height - topBarH;

    // 1. Top Toolbar Bar
    NSView *topBar = [[NSView alloc] initWithFrame:NSMakeRect(0, bounds.size.height - topBarH, bounds.size.width, topBarH)];
    topBar.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [topBar setWantsLayer:YES];
    topBar.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.12f green:0.13f blue:0.18f alpha:1.0f].CGColor;
    [contentView addSubview:topBar];

    // Presets Popup
    NSTextField *presetLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(14, 12, 55, 20)];
    presetLbl.stringValue = @"Preset:";
    presetLbl.editable = NO; presetLbl.selectable = NO; presetLbl.bezeled = NO; presetLbl.drawsBackground = NO;
    presetLbl.textColor = [NSColor whiteColor]; presetLbl.font = [NSFont boldSystemFontOfSize:12];
    [topBar addSubview:presetLbl];

    _presetsPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(70, 8, 200, 26) pullsDown:NO];
    [_presetsPopup addItemsWithTitles:@[@"⭐ Stage 6-Track (Foto)", @"🎛️ Mixer 8 Canais", @"🥁 Matriz 16 Pads"]];
    _presetsPopup.target = self;
    _presetsPopup.action = @selector(onPresetSelected:);
    [topBar addSubview:_presetsPopup];

    // Export Button
    NSButton *btnExport = [[NSButton alloc] initWithFrame:NSMakeRect(280, 8, 120, 28)];
    btnExport.title = @"💾 Salvar Layout...";
    btnExport.bezelStyle = NSBezelStyleRounded;
    btnExport.target = self;
    btnExport.action = @selector(onSaveLayoutClicked:);
    [topBar addSubview:btnExport];

    // Import Button
    NSButton *btnImport = [[NSButton alloc] initWithFrame:NSMakeRect(405, 8, 120, 28)];
    btnImport.title = @"📂 Abrir Layout...";
    btnImport.bezelStyle = NSBezelStyleRounded;
    btnImport.target = self;
    btnImport.action = @selector(onOpenLayoutClicked:);
    [topBar addSubview:btnImport];

    // Send to Phone Button
    NSButton *btnSend = [[NSButton alloc] initWithFrame:NSMakeRect(530, 8, 175, 28)];
    btnSend.title = @"📶 Sincronizar com Celular";
    btnSend.bezelStyle = NSBezelStyleRounded;
    btnSend.target = self;
    btnSend.action = @selector(onSendToPhoneClicked:);
    [topBar addSubview:btnSend];

    // Hint Label
    NSTextField *hintLbl = [[NSTextField alloc] initWithFrame:NSMakeRect(720, 12, 400, 20)];
    hintLbl.stringValue = @"💡 Clique com o botão direito na área do canvas para adicionar controles!";
    hintLbl.editable = NO; hintLbl.selectable = NO; hintLbl.bezeled = NO; hintLbl.drawsBackground = NO;
    hintLbl.textColor = [NSColor colorWithCalibratedRed:0.2f green:0.8f blue:1.0f alpha:1.0f];
    hintLbl.font = [NSFont systemFontOfSize:11.5f];
    [topBar addSubview:hintLbl];

    // 2. Canvas View (Main Area)
    _canvasView = [[EditorCanvasView alloc] initWithFrame:NSMakeRect(0, 0, canvasW, bodyH)];
    _canvasView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _canvasView.layout = _layout;
    _canvasView.delegate = self;
    [contentView addSubview:_canvasView];

    // 3. Inspector View (Right Sidebar)
    _inspectorView = [[InspectorView alloc] initWithFrame:NSMakeRect(bounds.size.width - inspectorW, 0, inspectorW, bodyH)];
    _inspectorView.autoresizingMask = NSViewMinXMargin | NSViewHeightSizable;
    _inspectorView.delegate = self;
    [contentView addSubview:_inspectorView];
}

- (void)showEditor {
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

// -------------------------------------------------------------
// Canvas & Inspector Delegates
// -------------------------------------------------------------
- (void)canvasDidSelectControl:(MidiControlModel *)control {
    [_inspectorView bindControl:control];
}

- (void)canvasDidChangeControl:(MidiControlModel *)control {
    [_inspectorView refreshValues];
    [self.editorDelegate editorDidUpdateLayout:_layout];
}

- (void)canvasDidDeleteControl:(MidiControlModel *)control {
    [_inspectorView bindControl:nil];
    [self.editorDelegate editorDidUpdateLayout:_layout];
}

- (void)inspectorDidUpdateControl:(MidiControlModel *)control {
    [_canvasView setNeedsDisplay:YES];
    [self.editorDelegate editorDidUpdateLayout:_layout];
}

- (void)inspectorDidRequestDuplicate:(MidiControlModel *)control {
    [_canvasView duplicateSelected];
}

- (void)inspectorDidRequestDelete:(MidiControlModel *)control {
    [_canvasView deleteSelected];
}

// -------------------------------------------------------------
// Actions
// -------------------------------------------------------------
- (void)onPresetSelected:(id)sender {
    NSInteger idx = _presetsPopup.indexOfSelectedItem;
    if (idx == 0) _layout = [LayoutModel referencePreset];
    else if (idx == 1) _layout = [LayoutModel mixer8Preset];
    else _layout = [LayoutModel drumPadPreset];

    _canvasView.layout = _layout;
    [_inspectorView bindControl:nil];
    [self.editorDelegate editorDidUpdateLayout:_layout];
}

- (void)onSaveLayoutClicked:(id)sender {
    NSSavePanel *savePanel = [NSSavePanel savePanel];
    savePanel.title = @"Salvar Layout AirMIDI";
    savePanel.nameFieldStringValue = [NSString stringWithFormat:@"%@.json", [_layout.name.lowercaseString stringByReplacingOccurrencesOfString:@" " withString:@"_"]];
    savePanel.allowedFileTypes = @[@"json"];

    [savePanel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSError *err = nil;
            NSData *data = [self->_layout toJSONDataWithError:&err];
            if (data) {
                [data writeToURL:savePanel.URL atomically:YES];
            } else {
                NSAlert *a = [NSAlert alertWithError:err];
                [a runModal];
            }
        }
    }];
}

- (void)onOpenLayoutClicked:(id)sender {
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    openPanel.title = @"Abrir Layout AirMIDI (.json)";
    openPanel.allowedFileTypes = @[@"json"];

    [openPanel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK) {
            NSError *err = nil;
            NSData *data = [NSData dataWithContentsOfURL:openPanel.URL];
            LayoutModel *loaded = [LayoutModel layoutFromJSONData:data error:&err];
            if (loaded) {
                self->_layout = loaded;
                self->_canvasView.layout = loaded;
                [self->_inspectorView bindControl:nil];
                [self.editorDelegate editorDidUpdateLayout:loaded];
            } else {
                NSAlert *a = [NSAlert alertWithError:err];
                [a runModal];
            }
        }
    }];
}

- (void)onSendToPhoneClicked:(id)sender {
    [self.editorDelegate editorDidRequestSendLayoutToPhone:_layout];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Layout Sincronizado!";
    alert.informativeText = @"O layout atual foi transmitido para o aplicativo Android na sua rede Wi-Fi.";
    [alert runModal];
}

@end
