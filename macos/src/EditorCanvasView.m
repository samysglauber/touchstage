#import "EditorCanvasView.h"

@implementation EditorCanvasView {
    BOOL _isDragging;
    BOOL _isResizing;
    NSPoint _dragStartMouse;
    NSRect _initialControlFrame;
    NSPoint _lastRightClickPoint;
}

- (BOOL)isFlipped {
    return YES; // (0,0) at top-left
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _layout = [LayoutModel referencePreset];
        [self setWantsLayer:YES];
    }
    return self;
}

- (void)setLayout:(LayoutModel *)layout {
    _layout = layout;
    _selectedControl = nil;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    // Background
    [[NSColor colorWithCalibratedRed:0.04f green:0.04f blue:0.06f alpha:1.0f] setFill];
    NSRectFill(self.bounds);

    // Grid lines (20px)
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.04f] setStroke];
    NSBezierPath *gridPath = [NSBezierPath bezierPath];
    for (CGFloat x = 0; x < self.bounds.size.width; x += 20.0f) {
        [gridPath moveToPoint:NSMakePoint(x, 0)];
        [gridPath lineToPoint:NSMakePoint(x, self.bounds.size.height)];
    }
    for (CGFloat y = 0; y < self.bounds.size.height; y += 20.0f) {
        [gridPath moveToPoint:NSMakePoint(0, y)];
        [gridPath lineToPoint:NSMakePoint(self.bounds.size.width, y)];
    }
    [gridPath stroke];

    // Draw Controls
    for (MidiControlModel *ctrl in self.layout.controls) {
        if ([ctrl.type isEqualToString:@"fader"]) {
            [self drawFader:ctrl];
        } else if ([ctrl.type isEqualToString:@"knob"]) {
            [self drawKnob:ctrl];
        } else if ([ctrl.type isEqualToString:@"button"]) {
            [self drawButton:ctrl];
        } else if ([ctrl.type isEqualToString:@"xypad"]) {
            [self drawXYPad:ctrl];
        } else if ([ctrl.type isEqualToString:@"label"]) {
            [self drawLabel:ctrl];
        }
    }

    // Draw Selection Box & Handles
    if (self.selectedControl) {
        NSRect r = self.selectedControl.frame;
        [[NSColor cyanColor] setStroke];
        NSBezierPath *outline = [NSBezierPath bezierPathWithRect:NSInsetRect(r, -2, -2)];
        [outline setLineWidth:2.0f];
        [outline stroke];

        // Bottom-right resize handle
        NSRect handleRect = NSMakeRect(NSMaxX(r) - 5, NSMaxY(r) - 5, 10, 10);
        [[NSColor cyanColor] setFill];
        NSRectFill(handleRect);
    }
}

// -------------------------------------------------------------
// 1. Draw Fader (Matching Reference Image)
// -------------------------------------------------------------
- (void)drawFader:(MidiControlModel *)ctrl {
    NSRect frame = ctrl.frame;
    CGFloat pillHeight = 24.0f;
    CGFloat buttonSize = ctrl.hasBottomButton ? 54.0f : 0.0f;
    CGFloat trackHeight = frame.size.height - pillHeight - buttonSize - 16.0f;
    if (trackHeight < 40.0f) trackHeight = 40.0f;

    // A. Top Label Pill
    NSRect pillRect = NSMakeRect(frame.origin.x, frame.origin.y, frame.size.width, pillHeight);
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:pillRect xRadius:10 yRadius:10];
    [[NSColor blackColor] setFill];
    [pill fill];
    [[NSColor colorWithCalibratedWhite:0.25f alpha:1.0f] setStroke];
    [pill setLineWidth:1.0f];
    [pill stroke];

    // Label Text
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:11.0f],
        NSForegroundColorAttributeName: [NSColor whiteColor],
        NSParagraphStyleAttributeName: style
    };
    NSRect textRect = NSMakeRect(pillRect.origin.x, pillRect.origin.y + 4, pillRect.size.width, pillRect.size.height - 4);
    [ctrl.label drawInRect:textRect withAttributes:attr];

    // B. Vertical Track
    NSRect trackRect = NSMakeRect(frame.origin.x, frame.origin.y + pillHeight + 8.0f, frame.size.width, trackHeight);
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:trackRect xRadius:2 yRadius:2];
    [[NSColor colorWithCalibratedRed:0.08f green:0.08f blue:0.09f alpha:1.0f] setFill];
    [track fill];

    // Colored Active Fill
    CGFloat pct = (ctrl.value - ctrl.minValue) / (CGFloat)(ctrl.maxValue - ctrl.minValue);
    pct = MAX(0.0f, MIN(1.0f, pct));
    CGFloat fillH = trackHeight * pct;
    NSRect fillRect = NSMakeRect(trackRect.origin.x, NSMaxY(trackRect) - fillH, trackRect.size.width, fillH);
    NSBezierPath *fillPath = [NSBezierPath bezierPathWithRect:fillRect];
    [ctrl.color setFill];
    [fillPath fill];

    // Handle Thumb (Black box with white horizontal line '-')
    CGFloat thumbH = 42.0f;
    CGFloat thumbY = NSMaxY(trackRect) - fillH - (thumbH / 2.0f);
    thumbY = MAX(trackRect.origin.y, MIN(NSMaxY(trackRect) - thumbH, thumbY));
    NSRect thumbRect = NSMakeRect(trackRect.origin.x - 4.0f, thumbY, trackRect.size.width + 8.0f, thumbH);
    NSBezierPath *thumb = [NSBezierPath bezierPathWithRoundedRect:thumbRect xRadius:3 yRadius:3];
    [[NSColor colorWithCalibratedWhite:0.05f alpha:1.0f] setFill];
    [thumb fill];
    [[NSColor colorWithCalibratedWhite:0.25f alpha:1.0f] setStroke];
    [thumb setLineWidth:1.0f];
    [thumb stroke];

    // Center notch '-'
    NSRect notchRect = NSMakeRect(NSMidX(thumbRect) - 7.0f, NSMidY(thumbRect) - 1.0f, 14.0f, 2.0f);
    [[NSColor whiteColor] setFill];
    NSRectFill(notchRect);

    // C. Bottom LED Button (Concentric Rings)
    if (ctrl.hasBottomButton) {
        CGFloat btnY = NSMaxY(trackRect) + 8.0f;
        CGFloat btnX = NSMidX(frame) - (buttonSize / 2.0f);
        NSRect outerRect = NSMakeRect(btnX, btnY, buttonSize, buttonSize);
        NSBezierPath *outer = [NSBezierPath bezierPathWithOvalInRect:outerRect];
        [ctrl.color setStroke];
        [outer setLineWidth:4.0f];
        [outer stroke];

        NSRect innerRect = NSInsetRect(outerRect, 8.0f, 8.0f);
        NSBezierPath *inner = [NSBezierPath bezierPathWithOvalInRect:innerRect];
        if (ctrl.buttonValue) {
            [ctrl.accentColor setFill];
        } else {
            [[NSColor colorWithCalibratedWhite:0.1f alpha:1.0f] setFill];
        }
        [inner fill];
        [ctrl.color setStroke];
        [inner setLineWidth:2.0f];
        [inner stroke];
    }
}

// -------------------------------------------------------------
// 2. Draw Knob / Pot (Matching Reference Image)
// -------------------------------------------------------------
- (void)drawKnob:(MidiControlModel *)ctrl {
    NSRect frame = ctrl.frame;
    CGFloat pillHeight = 24.0f;
    CGFloat dialSize = MIN(frame.size.width, frame.size.height - pillHeight - 8.0f);
    NSRect dialRect = NSMakeRect(NSMidX(frame) - dialSize / 2.0f, frame.origin.y, dialSize, dialSize);

    // Outer Arc Track
    CGFloat cx = NSMidX(dialRect);
    CGFloat cy = NSMidY(dialRect);
    CGFloat radius = dialSize * 0.42f;

    NSBezierPath *arcTrack = [NSBezierPath bezierPath];
    [arcTrack appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy) radius:radius startAngle:225 endAngle:-45 clockwise:YES];
    [[NSColor colorWithCalibratedRed:0.08f green:0.08f blue:0.12f alpha:1.0f] setStroke];
    [arcTrack setLineWidth:6.0f];
    [arcTrack setLineCapStyle:NSLineCapStyleRound];
    [arcTrack stroke];

    // Knob Face
    NSRect faceRect = NSInsetRect(dialRect, dialSize * 0.15f, dialSize * 0.15f);
    NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect:faceRect];
    [ctrl.color setFill];
    [face fill];

    // Knob Pointer Line
    CGFloat pct = (ctrl.value - ctrl.minValue) / (CGFloat)(ctrl.maxValue - ctrl.minValue);
    pct = MAX(0.0f, MIN(1.0f, pct));
    CGFloat angle = 225.0f - (pct * 270.0f);
    CGFloat rad = angle * M_PI / 180.0f;
    CGFloat px = cx + cos(rad) * (faceRect.size.width * 0.38f);
    CGFloat py = cy - sin(rad) * (faceRect.size.height * 0.38f);

    NSBezierPath *pointer = [NSBezierPath bezierPath];
    [pointer moveToPoint:NSMakePoint(cx, cy)];
    [pointer lineToPoint:NSMakePoint(px, py)];
    [[NSColor blackColor] setStroke];
    [pointer setLineWidth:4.0f];
    [pointer setLineCapStyle:NSLineCapStyleRound];
    [pointer stroke];

    // Bottom Label Pill
    NSRect pillRect = NSMakeRect(frame.origin.x, NSMaxY(frame) - pillHeight, frame.size.width, pillHeight);
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:pillRect xRadius:10 yRadius:10];
    [[NSColor blackColor] setFill];
    [pill fill];
    [[NSColor colorWithCalibratedWhite:0.25f alpha:1.0f] setStroke];
    [pill setLineWidth:1.0f];
    [pill stroke];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:11.0f],
        NSForegroundColorAttributeName: [NSColor whiteColor],
        NSParagraphStyleAttributeName: style
    };
    NSRect textRect = NSMakeRect(pillRect.origin.x, pillRect.origin.y + 4, pillRect.size.width, pillRect.size.height - 4);
    [ctrl.label drawInRect:textRect withAttributes:attr];
}

// -------------------------------------------------------------
// 3. Draw Button / Pad (Bells style)
// -------------------------------------------------------------
- (void)drawButton:(MidiControlModel *)ctrl {
    NSRect r = ctrl.frame;
    NSBezierPath *box = [NSBezierPath bezierPathWithRoundedRect:r xRadius:22 yRadius:22];
    [[NSColor blackColor] setFill];
    [box fill];

    [ctrl.accentColor setStroke];
    [box setLineWidth:5.0f];
    [box stroke];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:15.0f],
        NSForegroundColorAttributeName: ctrl.accentColor,
        NSParagraphStyleAttributeName: style
    };

    NSSize textSize = [ctrl.label sizeWithAttributes:attr];
    NSRect textRect = NSMakeRect(r.origin.x, NSMidY(r) - textSize.height / 2.0f, r.size.width, textSize.height);
    [ctrl.label drawInRect:textRect withAttributes:attr];
}

// -------------------------------------------------------------
// 4. Draw XY Pad
// -------------------------------------------------------------
- (void)drawXYPad:(MidiControlModel *)ctrl {
    NSRect r = ctrl.frame;
    NSBezierPath *box = [NSBezierPath bezierPathWithRoundedRect:r xRadius:12 yRadius:12];
    [[NSColor colorWithCalibratedRed:0.06f green:0.07f blue:0.09f alpha:1.0f] setFill];
    [box fill];
    [[NSColor colorWithCalibratedWhite:0.25f alpha:1.0f] setStroke];
    [box setLineWidth:2.0f];
    [box stroke];

    // Puck in center
    NSRect puck = NSMakeRect(NSMidX(r) - 10, NSMidY(r) - 10, 20, 20);
    NSBezierPath *puckPath = [NSBezierPath bezierPathWithOvalInRect:puck];
    [[NSColor cyanColor] setFill];
    [puckPath fill];
}

// -------------------------------------------------------------
// 5. Draw Label
// -------------------------------------------------------------
- (void)drawLabel:(MidiControlModel *)ctrl {
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [NSFont boldSystemFontOfSize:14.0f],
        NSForegroundColorAttributeName: [NSColor whiteColor],
        NSParagraphStyleAttributeName: style
    };
    [ctrl.label drawInRect:ctrl.frame withAttributes:attr];
}

// -------------------------------------------------------------
// MOUSE EVENTS: Selection, Dragging, Resizing
// -------------------------------------------------------------
- (MidiControlModel *)hitTestControl:(NSPoint)pt {
    for (NSInteger i = self.layout.controls.count - 1; i >= 0; i--) {
        MidiControlModel *m = self.layout.controls[i];
        if (NSPointInRect(pt, m.frame)) {
            return m;
        }
    }
    return nil;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint pt = [self convertPoint:event.locationInWindow fromView:nil];

    // Check resize handle on selected control
    if (self.selectedControl) {
        NSRect r = self.selectedControl.frame;
        NSRect handleRect = NSMakeRect(NSMaxX(r) - 10, NSMaxY(r) - 10, 15, 15);
        if (NSPointInRect(pt, handleRect)) {
            _isResizing = YES;
            _dragStartMouse = pt;
            _initialControlFrame = self.selectedControl.frame;
            return;
        }
    }

    MidiControlModel *hit = [self hitTestControl:pt];
    self.selectedControl = hit;
    if (hit) {
        _isDragging = YES;
        _dragStartMouse = pt;
        _initialControlFrame = hit.frame;
        [self.delegate canvasDidSelectControl:hit];
    } else {
        [self.delegate canvasDidSelectControl:nil];
    }
    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint pt = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat deltaX = pt.x - _dragStartMouse.x;
    CGFloat deltaY = pt.y - _dragStartMouse.y;

    if (_isDragging && self.selectedControl) {
        CGFloat newX = round((_initialControlFrame.origin.x + deltaX) / 5.0f) * 5.0f;
        CGFloat newY = round((_initialControlFrame.origin.y + deltaY) / 5.0f) * 5.0f;
        newX = MAX(0.0f, newX);
        newY = MAX(0.0f, newY);
        self.selectedControl.frame = NSMakeRect(newX, newY, _initialControlFrame.size.width, _initialControlFrame.size.height);
        [self.delegate canvasDidChangeControl:self.selectedControl];
        [self setNeedsDisplay:YES];
    } else if (_isResizing && self.selectedControl) {
        CGFloat newW = MAX(40.0f, round((_initialControlFrame.size.width + deltaX) / 5.0f) * 5.0f);
        CGFloat newH = MAX(40.0f, round((_initialControlFrame.size.height + deltaY) / 5.0f) * 5.0f);
        self.selectedControl.frame = NSMakeRect(_initialControlFrame.origin.x, _initialControlFrame.origin.y, newW, newH);
        [self.delegate canvasDidChangeControl:self.selectedControl];
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseUp:(NSEvent *)event {
    _isDragging = NO;
    _isResizing = NO;
}

// -------------------------------------------------------------
// RIGHT-CLICK CONTEXT MENU (Requested by user!)
// -------------------------------------------------------------
- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSPoint pt = [self convertPoint:event.locationInWindow fromView:nil];
    _lastRightClickPoint = pt;

    MidiControlModel *hit = [self hitTestControl:pt];
    if (hit) {
        self.selectedControl = hit;
        [self.delegate canvasDidSelectControl:hit];
        [self setNeedsDisplay:YES];
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"CanvasContextMenu"];

    if (hit) {
        NSMenuItem *itemTitle = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"Controle: %@", hit.label] action:nil keyEquivalent:@""];
        itemTitle.enabled = NO;
        [menu addItem:itemTitle];

        NSMenuItem *itemDup = [[NSMenuItem alloc] initWithTitle:@"📋 Duplicar Controle" action:@selector(duplicateSelected) keyEquivalent:@""];
        itemDup.target = self;
        [menu addItem:itemDup];

        NSMenuItem *itemDel = [[NSMenuItem alloc] initWithTitle:@"🗑️ Excluir Controle" action:@selector(deleteSelected) keyEquivalent:@""];
        itemDel.target = self;
        [menu addItem:itemDel];

        [menu addItem:[NSMenuItem separatorItem]];
    }

    NSMenuItem *addHeader = [[NSMenuItem alloc] initWithTitle:@"➕ ADICIONAR NOVO CONTROLE" action:nil keyEquivalent:@""];
    addHeader.enabled = NO;
    [menu addItem:addHeader];

    NSMenuItem *addFader = [[NSMenuItem alloc] initWithTitle:@"📊 Fader Vertical" action:@selector(onAddFader:) keyEquivalent:@""];
    addFader.target = self;
    [menu addItem:addFader];

    NSMenuItem *addKnob = [[NSMenuItem alloc] initWithTitle:@"🎚️ Knob / Potenciômetro" action:@selector(onAddKnob:) keyEquivalent:@""];
    addKnob.target = self;
    [menu addItem:addKnob];

    NSMenuItem *addBtn = [[NSMenuItem alloc] initWithTitle:@"🟩 Pad / Botão (Bells)" action:@selector(onAddButton:) keyEquivalent:@""];
    addBtn.target = self;
    [menu addItem:addBtn];

    NSMenuItem *addXY = [[NSMenuItem alloc] initWithTitle:@"🎯 Pad X/Y" action:@selector(onAddXYPad:) keyEquivalent:@""];
    addXY.target = self;
    [menu addItem:addXY];

    NSMenuItem *addLabel = [[NSMenuItem alloc] initWithTitle:@"🏷️ Rótulo / Texto" action:@selector(onAddLabel:) keyEquivalent:@""];
    addLabel.target = self;
    [menu addItem:addLabel];

    return menu;
}

- (void)onAddFader:(id)sender {
    [self addControlOfType:@"fader" atPoint:_lastRightClickPoint];
}

- (void)onAddKnob:(id)sender {
    [self addControlOfType:@"knob" atPoint:_lastRightClickPoint];
}

- (void)onAddButton:(id)sender {
    [self addControlOfType:@"button" atPoint:_lastRightClickPoint];
}

- (void)onAddXYPad:(id)sender {
    [self addControlOfType:@"xypad" atPoint:_lastRightClickPoint];
}

- (void)onAddLabel:(id)sender {
    [self addControlOfType:@"label" atPoint:_lastRightClickPoint];
}

- (void)addControlOfType:(NSString *)type atPoint:(NSPoint)pt {
    MidiControlModel *m = [[MidiControlModel alloc] init];
    m.controlId = [NSString stringWithFormat:@"%@_%u", type, arc4random() % 10000];
    m.type = type;
    m.label = [type.uppercaseString stringByAppendingFormat:@" %lu", (unsigned long)self.layout.controls.count + 1];

    CGFloat w = [type isEqualToString:@"fader"] ? 78 : [type isEqualToString:@"knob"] ? 140 : [type isEqualToString:@"button"] ? 120 : 150;
    CGFloat h = [type isEqualToString:@"fader"] ? 400 : [type isEqualToString:@"knob"] ? 160 : [type isEqualToString:@"button"] ? 120 : 40;
    m.frame = NSMakeRect(pt.x, pt.y, w, h);

    m.color = [NSColor colorWithCalibratedRed:0.0f green:0.4f blue:0.45f alpha:1.0f];
    m.accentColor = [NSColor cyanColor];
    m.midiChannel = 1;
    m.midiType = [type isEqualToString:@"button"] ? @"note" : @"cc";
    m.midiNumber = 20 + (NSInteger)self.layout.controls.count;
    m.minValue = 0;
    m.maxValue = 127;
    m.value = 64;

    if ([type isEqualToString:@"fader"]) {
        m.hasBottomButton = YES;
        m.buttonMidiNumber = 60 + (NSInteger)self.layout.controls.count;
        m.buttonMode = @"toggle";
    }

    [self.layout.controls addObject:m];
    self.selectedControl = m;
    [self.delegate canvasDidSelectControl:m];
    [self setNeedsDisplay:YES];
}

- (void)duplicateSelected {
    if (!self.selectedControl) return;
    MidiControlModel *copy = [self.selectedControl copy];
    copy.controlId = [NSString stringWithFormat:@"%@_%u", copy.type, arc4random() % 10000];
    copy.label = [copy.label stringByAppendingString:@" CPY"];
    copy.frame = NSOffsetRect(copy.frame, 25, 25);
    if (copy.midiNumber < 127) copy.midiNumber += 1;

    [self.layout.controls addObject:copy];
    self.selectedControl = copy;
    [self.delegate canvasDidSelectControl:copy];
    [self setNeedsDisplay:YES];
}

- (void)deleteSelected {
    if (!self.selectedControl) return;
    MidiControlModel *target = self.selectedControl;
    [self.layout.controls removeObject:target];
    self.selectedControl = nil;
    [self.delegate canvasDidDeleteControl:target];
    [self setNeedsDisplay:YES];
}

@end
