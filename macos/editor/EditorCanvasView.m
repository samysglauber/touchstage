#import "EditorCanvasView.h"
#import "AirTheme.h"

@implementation EditorCanvasView {
    BOOL _isDragging;
    BOOL _isResizing;
    NSInteger _resizeCorner; // 1: top-left, 2: top-right, 3: bottom-right, 4: bottom-left
    NSPoint _dragStartMouse;
    NSRect _initialControlFrame;
    NSMutableDictionary<NSString *, NSValue *> *_initialFramesByControlId;
    NSPoint _lastRightClickPoint;

    // Marquee / Rubberband Selection
    BOOL _isMarqueeSelecting;
    NSPoint _marqueeStartPoint;
    NSRect _marqueeRect;
    NSMutableArray<MidiControlModel *> *_initialSelectionBeforeMarquee;
    MidiControlModel *_clickedControlOnMouseDown;
    BOOL _clickedControlWasAlreadySelected;

    NSButton *_floatingSnapBtn;
    NSMutableArray<MidiControlModel *> *_copiedControls;
    NSMutableArray<NSArray<MidiControlModel *> *> *_undoStack;
    NSMutableArray<NSArray<MidiControlModel *> *> *_redoStack;
    NSArray<MidiControlModel *> *_mouseDownSnapshot;
    BOOL _hasDraggedOrResized;
}

static const NSInteger kMaxUndoSteps = 500;

@synthesize selectedControls = _selectedControls;

- (NSMutableArray<MidiControlModel *> *)selectedControls {
    if (!_selectedControls) {
        _selectedControls = [NSMutableArray array];
    }
    return _selectedControls;
}

- (MidiControlModel *)selectedControl {
    return self.selectedControls.lastObject;
}

- (void)setSelectedControl:(MidiControlModel *)selectedControl {
    [self.selectedControls removeAllObjects];
    if (selectedControl) {
        [self.selectedControls addObject:selectedControl];
    }
    [self setNeedsDisplay:YES];
}

- (void)selectAllControls {
    [self.selectedControls removeAllObjects];
    if (self.layout.controls.count > 0) {
        [self.selectedControls addObjectsFromArray:self.layout.controls];
    }
    [self.delegate canvasDidSelectControl:self.selectedControl];
    [self setNeedsDisplay:YES];
}

- (void)clearSelection {
    [self.selectedControls removeAllObjects];
    [self.delegate canvasDidSelectControl:nil];
    [self setNeedsDisplay:YES];
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _layout = [LayoutModel referencePreset];
        _selectedControls = [NSMutableArray array];
        _copiedControls = [NSMutableArray array];
        _initialFramesByControlId = [NSMutableDictionary dictionary];
        _snapToGrid = YES;
        _undoStack = [NSMutableArray array];
        _redoStack = [NSMutableArray array];

        [self setWantsLayer:YES];
        self.layer.backgroundColor = AirColorWindowBg().CGColor;

        // Floating Snap Grid Button pinned directly near canvas
        _floatingSnapBtn = [[NSButton alloc] initWithFrame:NSMakeRect(20, self.bounds.size.height - 48, 140, 30)];
        _floatingSnapBtn.autoresizingMask = NSViewMaxXMargin | NSViewMinYMargin;
        _floatingSnapBtn.bezelStyle = NSBezelStyleTexturedRounded;
        _floatingSnapBtn.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
        _floatingSnapBtn.image = AirSymbol(@"grid", 13.0f);
        _floatingSnapBtn.imagePosition = NSImageLeading;
        _floatingSnapBtn.target = self;
        _floatingSnapBtn.action = @selector(toggleSnapToGrid:);
        _floatingSnapBtn.toolTip = @"Toggle 20px Grid Snapping on Canvas";
        [self addSubview:_floatingSnapBtn];
        [self updateSnapButtonAppearance];
    }
    return self;
}

- (void)updateSnapButtonAppearance {
    _floatingSnapBtn.state = _snapToGrid ? NSControlStateValueOn : NSControlStateValueOff;
    _floatingSnapBtn.title = _snapToGrid ? @"Snap: ON (20px)" : @"Snap: OFF";
}

- (void)setLayout:(LayoutModel *)layout {
    _layout = layout;
    [self.selectedControls removeAllObjects];
    [_undoStack removeAllObjects];
    [_redoStack removeAllObjects];
    [self setNeedsDisplay:YES];
}

#pragma mark - Drawing

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect bounds = self.bounds;

    // 1. Studio Dark Backdrop
    [AirColorWindowBg() setFill];
    NSRectFill(bounds);

    // 2. Hardware Device Worksurface (Aspect-accurate canvas representation)
    CGFloat devW = self.layout.canvasWidth > 0 ? self.layout.canvasWidth : 920.0f;
    CGFloat devH = self.layout.canvasHeight > 0 ? self.layout.canvasHeight : 460.0f;

    // Calculate dynamic auto-fit zoom so the ENTIRE controller frame is visible inside window!
    CGFloat availW = MAX(100.0f, bounds.size.width - 60.0f);
    CGFloat availH = MAX(100.0f, bounds.size.height - 70.0f);
    CGFloat zoom = MIN(1.0f, MIN(availW / devW, availH / devH));

    CGFloat renderedDevW = devW * zoom;
    CGFloat renderedDevH = devH * zoom;

    CGFloat devX = (bounds.size.width - renderedDevW) / 2.0f;
    CGFloat devY = (bounds.size.height - 30.0f - renderedDevH) / 2.0f;
    if (devY < 18.0f) devY = 18.0f;
    NSRect devRect = NSMakeRect(devX, devY, renderedDevW, renderedDevH);

    // Drop Shadow under device
    [NSGraphicsContext saveGraphicsState];
    NSShadow *shadow = [[NSShadow alloc] init];
    shadow.shadowColor = [NSColor colorWithCalibratedWhite:0.0f alpha:0.6f];
    shadow.shadowBlurRadius = 24.0f;
    shadow.shadowOffset = NSMakeSize(0, -6.0f);
    [shadow set];

    // Device Bezel (Outer)
    CGFloat bezelPad = 12.0f * zoom;
    NSRect bezelRect = NSInsetRect(devRect, -bezelPad, -bezelPad);
    NSBezierPath *bezelPath = [NSBezierPath bezierPathWithRoundedRect:bezelRect xRadius:18.0f * zoom yRadius:18.0f * zoom];
    [[NSColor colorWithCalibratedRed:0.12f green:0.13f blue:0.16f alpha:1.0f] setFill];
    [bezelPath fill];
    [NSGraphicsContext restoreGraphicsState];

    // Bezel Border
    [[NSColor colorWithCalibratedWhite:0.25f alpha:1.0f] setStroke];
    [bezelPath setLineWidth:1.5f];
    [bezelPath stroke];

    // Device Screen / Surface (Inner)
    NSBezierPath *screenPath = [NSBezierPath bezierPathWithRoundedRect:devRect xRadius:10.0f * zoom yRadius:10.0f * zoom];
    [AirColorCanvasDeviceBg() setFill];
    [screenPath fill];
    [[NSColor colorWithCalibratedWhite:0.18f alpha:1.0f] setStroke];
    [screenPath setLineWidth:1.0f];
    [screenPath stroke];

    // 3. Render Controls (offset relative to device origin and scaled by zoom)
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    CGContextSaveGState(ctx);
    [screenPath addClip];

    CGContextTranslateCTM(ctx, devX, devY);
    CGContextScaleCTM(ctx, zoom, zoom);

    // Subtle 20px Grid Dots inside device screen
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.035f] setFill];
    for (CGFloat gx = 20.0f; gx < devW; gx += 20.0f) {
        for (CGFloat gy = 20.0f; gy < devH; gy += 20.0f) {
            NSRect dot = NSMakeRect(gx - 1.0f, gy - 1.0f, 2.0f, 2.0f);
            NSRectFill(dot);
        }
    }

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

    // 4. Selection Highlight & Floating HUD
    if (self.selectedControls.count > 0) {
        for (MidiControlModel *ctrl in self.selectedControls) {
            BOOL isPrimary = (ctrl == self.selectedControl);
            [self drawSelectionForControl:ctrl isPrimary:isPrimary];
        }
    }

    // 5. Marquee / Rubberband Selection Box
    if (_isMarqueeSelecting && !NSIsEmptyRect(_marqueeRect)) {
        NSBezierPath *marqueePath = [NSBezierPath bezierPathWithRoundedRect:_marqueeRect xRadius:4.0f yRadius:4.0f];
        [[AirColorAccent() colorWithAlphaComponent:0.18f] setFill];
        [marqueePath fill];
        [[AirColorAccent() colorWithAlphaComponent:0.85f] setStroke];
        [marqueePath setLineWidth:1.5f / zoom];
        CGFloat dash[2] = {4.0f / zoom, 3.0f / zoom};
        [marqueePath setLineDash:dash count:2 phase:0.0f];
        [marqueePath stroke];
    }

    CGContextRestoreGState(ctx);

    // 6. Minimalist Aspect Badge underneath device frame
    NSString *badgeText;
    if (zoom < 0.98f) {
        badgeText = [NSString stringWithFormat:@"%d × %d  •  %@ Canvas (%d%%)", (int)devW, (int)devH, (devH > devW) ? @"Portrait" : @"Landscape", (int)round(zoom * 100)];
    } else {
        badgeText = [NSString stringWithFormat:@"%d × %d  •  %@ Canvas", (int)devW, (int)devH, (devH > devW) ? @"Portrait" : @"Landscape"];
    }
    NSMutableParagraphStyle *pStyle = [[NSMutableParagraphStyle alloc] init];
    pStyle.alignment = NSTextAlignmentCenter;
    NSDictionary *badgeAttr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0f weight:NSFontWeightMedium],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.45f alpha:1.0f],
        NSParagraphStyleAttributeName: pStyle
    };
    NSRect badgeRect = NSMakeRect(devX, NSMaxY(devRect) + 12.0f, renderedDevW, 18.0f);
    [badgeText drawInRect:badgeRect withAttributes:badgeAttr];
}

#pragma mark - Control Renderers

- (void)drawFader:(MidiControlModel *)ctrl {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    NSRect frame = ctrl.frame;
    BOOL isHorizontal = [ctrl.orientation isEqualToString:@"horizontal"];
    CGFloat pillHeight = 26.0f;
    BOOL hasLabel = ctrl.hasLabel;
    BOOL isLabelBottom = [ctrl.labelPosition isEqualToString:@"bottom"];

    NSRect trackRect = frame;
    NSRect pillRect = NSZeroRect;

    if (isHorizontal) {
        if (hasLabel) {
            if (isLabelBottom) {
                pillRect = NSMakeRect(frame.origin.x, NSMaxY(frame) - pillHeight, frame.size.width, pillHeight);
                trackRect = NSMakeRect(frame.origin.x, frame.origin.y, frame.size.width, frame.size.height - pillHeight - 4.0f);
            } else {
                pillRect = NSMakeRect(frame.origin.x, frame.origin.y, frame.size.width, pillHeight);
                trackRect = NSMakeRect(frame.origin.x, frame.origin.y + pillHeight + 4.0f, frame.size.width, frame.size.height - pillHeight - 4.0f);
            }
        }
    } else {
        if (hasLabel) {
            if (isLabelBottom) {
                pillRect = NSMakeRect(frame.origin.x, NSMaxY(frame) - pillHeight, frame.size.width, pillHeight);
                trackRect = NSMakeRect(frame.origin.x, frame.origin.y, frame.size.width, frame.size.height - pillHeight - 8.0f);
            } else {
                pillRect = NSMakeRect(frame.origin.x, frame.origin.y, frame.size.width, pillHeight);
                trackRect = NSMakeRect(frame.origin.x, frame.origin.y + pillHeight + 8.0f, frame.size.width, frame.size.height - pillHeight - 8.0f);
            }
        }
    }

    if (trackRect.size.height < 24.0f) trackRect.size.height = 24.0f;
    if (trackRect.size.width < 24.0f) trackRect.size.width = 24.0f;

    // 1. Draw Label Pill (if enabled)
    if (hasLabel) {
        NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:pillRect xRadius:8.0f yRadius:8.0f];
        [[NSColor colorWithCalibratedRed:0.06f green:0.07f blue:0.09f alpha:1.0f] setFill];
        [pill fill];
        [[NSColor colorWithCalibratedWhite:0.18f alpha:1.0f] setStroke];
        [pill setLineWidth:1.0f];
        [pill stroke];

        // Label Text
        CGFloat fSize = (ctrl.fontSize > 0) ? ctrl.fontSize : 11.0f;
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.alignment = NSTextAlignmentCenter;
        NSDictionary *attr = @{
            NSFontAttributeName: [NSFont systemFontOfSize:fSize weight:NSFontWeightBold],
            NSForegroundColorAttributeName: [NSColor whiteColor],
            NSParagraphStyleAttributeName: style,
            NSKernAttributeName: @(1.2f)
        };
        NSRect textRect = NSMakeRect(pillRect.origin.x, pillRect.origin.y + (pillRect.size.height - fSize) / 2.0f - 1.0f, pillRect.size.width, fSize + 4.0f);
        [ctrl.label drawInRect:textRect withAttributes:attr];
    }

    CGFloat range = (ctrl.maxValue > ctrl.minValue) ? (ctrl.maxValue - ctrl.minValue) : 127.0f;
    CGFloat pct = (ctrl.value - ctrl.minValue) / range;
    pct = MAX(0.0f, MIN(1.0f, pct));
    NSString *fStyle = ctrl.faderStyle ? ctrl.faderStyle.lowercaseString : @"standard";

    if (isHorizontal) {
        // Horizontal Slot
        CGFloat slotH = 16.0f;
        CGFloat slotY = NSMidY(trackRect) - (slotH / 2.0f);
        NSRect slotRect = NSMakeRect(trackRect.origin.x + 4.0f, slotY, trackRect.size.width - 8.0f, slotH);

        // Graduation ticks above and below
        NSInteger numTicks = 9;
        CGFloat tickStep = slotRect.size.width / (CGFloat)(numTicks - 1);
        [[NSColor colorWithCalibratedWhite:0.25f alpha:0.7f] setStroke];
        for (NSInteger i = 0; i < numTicks; i++) {
            CGFloat tx = slotRect.origin.x + i * tickStep;
            NSBezierPath *topTick = [NSBezierPath bezierPath];
            [topTick moveToPoint:NSMakePoint(tx, slotY - 8.0f)];
            [topTick lineToPoint:NSMakePoint(tx, slotY - 2.0f)];
            [topTick setLineWidth:1.0f];
            [topTick stroke];

            NSBezierPath *botTick = [NSBezierPath bezierPath];
            [botTick moveToPoint:NSMakePoint(tx, NSMaxY(slotRect) + 2.0f)];
            [botTick lineToPoint:NSMakePoint(tx, NSMaxY(slotRect) + 8.0f)];
            [botTick setLineWidth:1.0f];
            [botTick stroke];
        }

        // Slot Deep Inset Background
        NSBezierPath *slotPath = [NSBezierPath bezierPathWithRoundedRect:slotRect xRadius:6.0f yRadius:6.0f];
        [[NSColor colorWithCalibratedRed:0.04f green:0.045f blue:0.06f alpha:1.0f] setFill];
        [slotPath fill];
        [[NSColor colorWithCalibratedWhite:0.14f alpha:1.0f] setStroke];
        [slotPath setLineWidth:1.0f];
        [slotPath stroke];

        CGFloat travelW = slotRect.size.width - 12.0f;
        CGFloat beamLeft = 0, beamRight = 0;
        CGFloat thumbW = 28.0f;
        CGFloat thumbH = MIN(frame.size.height + 4.0f, 60.0f);
        CGFloat thumbX = 0;

        if ([fStyle isEqualToString:@"inverted"]) {
            CGFloat fillW = travelW * pct;
            beamRight = NSMaxX(slotRect) - 6.0f;
            beamLeft = beamRight - fillW;
            thumbX = (NSMaxX(slotRect) - 6.0f) - fillW - (thumbW / 2.0f);
        } else if ([fStyle isEqualToString:@"centered"]) {
            // Center notch tick
            NSBezierPath *cTick = [NSBezierPath bezierPath];
            [cTick moveToPoint:NSMakePoint(NSMidX(slotRect), slotY - 6.0f)];
            [cTick lineToPoint:NSMakePoint(NSMidX(slotRect), NSMaxY(slotRect) + 6.0f)];
            [[NSColor colorWithCalibratedWhite:0.35f alpha:1.0f] setStroke];
            [cTick setLineWidth:1.5f];
            [cTick stroke];

            if (pct >= 0.5f) {
                beamLeft = NSMidX(slotRect);
                beamRight = beamLeft + (pct - 0.5f) * travelW;
            } else {
                beamRight = NSMidX(slotRect);
                beamLeft = beamRight - (0.5f - pct) * travelW;
            }
            thumbX = (slotRect.origin.x + 6.0f) + pct * travelW - (thumbW / 2.0f);
        } else {
            CGFloat fillW = travelW * pct;
            beamLeft = slotRect.origin.x + 6.0f;
            beamRight = beamLeft + fillW;
            thumbX = (slotRect.origin.x + 6.0f) + fillW - (thumbW / 2.0f);
        }

        // Illuminated Glowing Neon Beam inside Slot
        if (fabs(beamRight - beamLeft) > 2.0f) {
            CGFloat beamY = NSMidY(slotRect);
            NSBezierPath *beam = [NSBezierPath bezierPath];
            [beam moveToPoint:NSMakePoint(beamLeft, beamY)];
            [beam lineToPoint:NSMakePoint(beamRight, beamY)];
            [beam setLineCapStyle:NSLineCapStyleRound];

            CGContextSaveGState(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 12.0f, ctrl.accentColor.CGColor);
            [ctrl.accentColor setStroke];
            [beam setLineWidth:3.5f];
            [beam stroke];
            CGContextRestoreGState(ctx);

            [[NSColor whiteColor] setStroke];
            [beam setLineWidth:1.5f];
            [beam stroke];
        }

        // Horizontal Slider Thumb (Vertical orientation of thumb)
        thumbX = MAX(slotRect.origin.x - 2.0f, MIN(NSMaxX(slotRect) - thumbW + 2.0f, thumbX));
        CGFloat thumbY = NSMidY(trackRect) - (thumbH / 2.0f);
        NSRect thumbRect = NSMakeRect(thumbX, thumbY, thumbW, thumbH);

        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, -3.0f), 8.0f, [NSColor colorWithCalibratedWhite:0.0f alpha:0.75f].CGColor);
        NSBezierPath *thumbPath = [NSBezierPath bezierPathWithRoundedRect:thumbRect xRadius:4.5f yRadius:4.5f];

        NSGradient *metalGrad = [[NSGradient alloc] initWithColorsAndLocations:
            [NSColor colorWithCalibratedRed:0.28f green:0.30f blue:0.36f alpha:1.0f], 0.0f,
            [NSColor colorWithCalibratedRed:0.18f green:0.19f blue:0.23f alpha:1.0f], 0.20f,
            [NSColor colorWithCalibratedRed:0.13f green:0.14f blue:0.17f alpha:1.0f], 0.50f,
            [NSColor colorWithCalibratedRed:0.09f green:0.10f blue:0.12f alpha:1.0f], 1.0f, nil];
        [metalGrad drawInBezierPath:thumbPath angle:0.0f];
        CGContextRestoreGState(ctx);

        [[NSColor colorWithCalibratedWhite:0.35f alpha:0.7f] setStroke];
        [thumbPath setLineWidth:1.0f];
        [thumbPath stroke];

        // Vertical glowing neon slit
        CGFloat slitW = 3.0f;
        CGFloat slitH = 16.0f;
        NSRect slitRect = NSMakeRect(NSMidX(thumbRect) - slitW / 2.0f, NSMidY(thumbRect) - slitH / 2.0f, slitW, slitH);
        NSBezierPath *slitPath = [NSBezierPath bezierPathWithRoundedRect:slitRect xRadius:1.5f yRadius:1.5f];

        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 10.0f, ctrl.accentColor.CGColor);
        [ctrl.accentColor setFill];
        [slitPath fill];
        CGContextRestoreGState(ctx);

        NSRect slitCoreRect = NSInsetRect(slitRect, 0.5f, 2.0f);
        NSBezierPath *slitCorePath = [NSBezierPath bezierPathWithRoundedRect:slitCoreRect xRadius:1.0f yRadius:1.0f];
        [[NSColor whiteColor] setFill];
        [slitCorePath fill];
    } else {
        // Vertical Fader Slot (Groove / Recess)
        CGFloat slotW = 16.0f;
        CGFloat slotX = NSMidX(trackRect) - (slotW / 2.0f);
        NSRect slotRect = NSMakeRect(slotX, trackRect.origin.y + 4.0f, slotW, trackRect.size.height - 8.0f);

        // Scale graduation ticks on both sides of the slot
        NSInteger numTicks = 9;
        CGFloat tickStep = slotRect.size.height / (CGFloat)(numTicks - 1);
        [[NSColor colorWithCalibratedWhite:0.25f alpha:0.7f] setStroke];
        for (NSInteger i = 0; i < numTicks; i++) {
            CGFloat ty = slotRect.origin.y + i * tickStep;
            // Left tick
            NSBezierPath *leftTick = [NSBezierPath bezierPath];
            [leftTick moveToPoint:NSMakePoint(slotX - 10.0f, ty)];
            [leftTick lineToPoint:NSMakePoint(slotX - 3.0f, ty)];
            [leftTick setLineWidth:1.0f];
            [leftTick stroke];
            // Right tick
            NSBezierPath *rightTick = [NSBezierPath bezierPath];
            [rightTick moveToPoint:NSMakePoint(NSMaxX(slotRect) + 3.0f, ty)];
            [rightTick lineToPoint:NSMakePoint(NSMaxX(slotRect) + 10.0f, ty)];
            [rightTick setLineWidth:1.0f];
            [rightTick stroke];
        }

        // Slot Deep Inset Background
        NSBezierPath *slotPath = [NSBezierPath bezierPathWithRoundedRect:slotRect xRadius:6.0f yRadius:6.0f];
        [[NSColor colorWithCalibratedRed:0.04f green:0.045f blue:0.06f alpha:1.0f] setFill];
        [slotPath fill];
        [[NSColor colorWithCalibratedWhite:0.14f alpha:1.0f] setStroke];
        [slotPath setLineWidth:1.0f];
        [slotPath stroke];

        CGFloat travelH = slotRect.size.height - 12.0f;
        CGFloat beamBottom = 0, beamTop = 0;
        CGFloat thumbW = MIN(frame.size.width + 4.0f, 60.0f);
        CGFloat thumbH = 28.0f;
        CGFloat thumbX = NSMidX(trackRect) - (thumbW / 2.0f);
        CGFloat thumbY = 0;

        if ([fStyle isEqualToString:@"inverted"]) {
            CGFloat fillH = travelH * pct;
            beamTop = slotRect.origin.y + 6.0f;
            beamBottom = beamTop + fillH;
            thumbY = (slotRect.origin.y + 6.0f) + fillH - (thumbH / 2.0f);
        } else if ([fStyle isEqualToString:@"centered"]) {
            // Center notch tick
            NSBezierPath *cTick = [NSBezierPath bezierPath];
            [cTick moveToPoint:NSMakePoint(slotX - 6.0f, NSMidY(slotRect))];
            [cTick lineToPoint:NSMakePoint(NSMaxX(slotRect) + 6.0f, NSMidY(slotRect))];
            [[NSColor colorWithCalibratedWhite:0.35f alpha:1.0f] setStroke];
            [cTick setLineWidth:1.5f];
            [cTick stroke];

            if (pct >= 0.5f) {
                beamBottom = NSMidY(slotRect);
                beamTop = beamBottom - (pct - 0.5f) * travelH;
            } else {
                beamTop = NSMidY(slotRect);
                beamBottom = beamTop + (0.5f - pct) * travelH;
            }
            thumbY = (NSMaxY(slotRect) - 6.0f) - pct * travelH - (thumbH / 2.0f);
        } else {
            CGFloat fillH = travelH * pct;
            beamBottom = NSMaxY(slotRect) - 6.0f;
            beamTop = beamBottom - fillH;
            thumbY = (NSMaxY(slotRect) - 6.0f) - fillH - (thumbH / 2.0f);
        }

        // 3. Level & Illuminated Glowing Neon Beam inside Slot
        if (fabs(beamBottom - beamTop) > 2.0f) {
            CGFloat beamX = NSMidX(slotRect);
            NSBezierPath *beam = [NSBezierPath bezierPath];
            [beam moveToPoint:NSMakePoint(beamX, beamBottom)];
            [beam lineToPoint:NSMakePoint(beamX, beamTop)];
            [beam setLineCapStyle:NSLineCapStyleRound];

            // Glow Pass
            CGContextSaveGState(ctx);
            CGContextSetShadowWithColor(ctx, CGSizeZero, 12.0f, ctrl.accentColor.CGColor);
            [ctrl.accentColor setStroke];
            [beam setLineWidth:3.5f];
            [beam stroke];
            CGContextRestoreGState(ctx);

            // Bright Center Core Pass
            [[NSColor whiteColor] setStroke];
            [beam setLineWidth:1.5f];
            [beam stroke];
        }

        // 4. Machined Aluminum / Titanium Slider Thumb
        thumbY = MAX(slotRect.origin.y - 2.0f, MIN(NSMaxY(slotRect) - thumbH + 2.0f, thumbY));
        NSRect thumbRect = NSMakeRect(thumbX, thumbY, thumbW, thumbH);

        // Drop Shadow under Thumb
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeMake(0, -3.0f), 8.0f, [NSColor colorWithCalibratedWhite:0.0f alpha:0.75f].CGColor);

        NSBezierPath *thumbPath = [NSBezierPath bezierPathWithRoundedRect:thumbRect xRadius:4.5f yRadius:4.5f];

        // Metallic Gunmetal Gradient
        NSGradient *metalGrad = [[NSGradient alloc] initWithColorsAndLocations:
            [NSColor colorWithCalibratedRed:0.28f green:0.30f blue:0.36f alpha:1.0f], 0.0f,
            [NSColor colorWithCalibratedRed:0.18f green:0.19f blue:0.23f alpha:1.0f], 0.20f,
            [NSColor colorWithCalibratedRed:0.13f green:0.14f blue:0.17f alpha:1.0f], 0.50f,
            [NSColor colorWithCalibratedRed:0.09f green:0.10f blue:0.12f alpha:1.0f], 1.0f, nil];
        [metalGrad drawInBezierPath:thumbPath angle:90.0f];
        CGContextRestoreGState(ctx);

        // Thumb Beveled Edge
        [[NSColor colorWithCalibratedWhite:0.35f alpha:0.7f] setStroke];
        [thumbPath setLineWidth:1.0f];
        [thumbPath stroke];

        // Subtle horizontal brush line on thumb
        NSBezierPath *brushLine = [NSBezierPath bezierPath];
        [brushLine moveToPoint:NSMakePoint(thumbX + 4.0f, NSMidY(thumbRect))];
        [brushLine lineToPoint:NSMakePoint(thumbX + thumbW - 4.0f, NSMidY(thumbRect))];
        [[NSColor colorWithCalibratedWhite:1.0f alpha:0.06f] setStroke];
        [brushLine setLineWidth:1.0f];
        [brushLine stroke];

        // Center Illuminated Horizontal Glowing Neon Slit
        CGFloat slitW = 16.0f;
        CGFloat slitH = 3.0f;
        NSRect slitRect = NSMakeRect(NSMidX(thumbRect) - slitW / 2.0f, NSMidY(thumbRect) - slitH / 2.0f, slitW, slitH);
        NSBezierPath *slitPath = [NSBezierPath bezierPathWithRoundedRect:slitRect xRadius:1.5f yRadius:1.5f];

        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 10.0f, ctrl.accentColor.CGColor);
        [ctrl.accentColor setFill];
        [slitPath fill];
        CGContextRestoreGState(ctx);

        // Bright core in slit
        NSRect slitCoreRect = NSInsetRect(slitRect, 2.0f, 0.5f);
        NSBezierPath *slitCorePath = [NSBezierPath bezierPathWithRoundedRect:slitCoreRect xRadius:1.0f yRadius:1.0f];
        [[NSColor whiteColor] setFill];
        [slitCorePath fill];
    }
}

- (void)drawKnob:(MidiControlModel *)ctrl {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    NSRect frame = ctrl.frame;
    CGFloat pillHeight = 26.0f;
    BOOL hasLabel = ctrl.hasLabel;
    BOOL isLabelTop = [ctrl.labelPosition isEqualToString:@"top"];

    NSRect dialArea = frame;
    NSRect pillRect = NSZeroRect;

    if (hasLabel) {
        if (isLabelTop) {
            pillRect = NSMakeRect(frame.origin.x, frame.origin.y, frame.size.width, pillHeight);
            dialArea = NSMakeRect(frame.origin.x, frame.origin.y + pillHeight + 6.0f, frame.size.width, frame.size.height - pillHeight - 6.0f);
        } else {
            pillRect = NSMakeRect(frame.origin.x, NSMaxY(frame) - pillHeight, frame.size.width, pillHeight);
            dialArea = NSMakeRect(frame.origin.x, frame.origin.y, frame.size.width, frame.size.height - pillHeight - 6.0f);
        }
    }

    CGFloat dialSize = MIN(dialArea.size.width, dialArea.size.height);
    CGFloat cx = NSMidX(dialArea);
    CGFloat cy = NSMidY(dialArea);
    CGFloat radius = dialSize * 0.44f;

    // 1. Recessed Circular Well
    NSBezierPath *well = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(cx - radius, cy - radius, radius * 2.0f, radius * 2.0f)];
    [[NSColor colorWithCalibratedRed:0.05f green:0.06f blue:0.08f alpha:1.0f] setFill];
    [well fill];
    [[NSColor colorWithCalibratedWhite:0.15f alpha:1.0f] setStroke];
    [well setLineWidth:1.0f];
    [well stroke];

    // 2. Glowing Neon Arc Meter / Outer Ring
    CGFloat haloRadius = radius * 0.90f;
    CGFloat range = (ctrl.maxValue > ctrl.minValue) ? (ctrl.maxValue - ctrl.minValue) : 127.0f;
    CGFloat pct = (ctrl.value - ctrl.minValue) / range;
    pct = MAX(0.0f, MIN(1.0f, pct));

    // Inactive track (dark charcoal) - sweeps from bottom-left (135°) to bottom-right (45°) through top (270°)
    NSBezierPath *trackArc = [NSBezierPath bezierPath];
    [trackArc appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy) radius:haloRadius startAngle:135.0f endAngle:45.0f clockwise:NO];
    [[NSColor colorWithCalibratedRed:0.12f green:0.14f blue:0.18f alpha:1.0f] setStroke];
    [trackArc setLineWidth:4.0f];
    [trackArc setLineCapStyle:NSLineCapStyleRound];
    [trackArc stroke];

    // Active Glowing Arc and Needle based on knobStyle
    NSString *style = ctrl.knobStyle ? ctrl.knobStyle.lowercaseString : @"standard";
    NSBezierPath *activeArc = [NSBezierPath bezierPath];
    CGFloat needleAngle = 135.0f + (pct * 270.0f);

    if ([style isEqualToString:@"inverted"]) {
        // Sweeps backwards from bottom-right (405°)
        if (pct > 0.01f) {
            [activeArc appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy) radius:haloRadius startAngle:405.0f endAngle:(405.0f - pct * 270.0f) clockwise:YES];
        }
        needleAngle = 405.0f - (pct * 270.0f);
    } else if ([style isEqualToString:@"centered"]) {
        // Bipolar: Center tick at top 12 o'clock (270°)
        NSBezierPath *centerTick = [NSBezierPath bezierPath];
        [centerTick moveToPoint:NSMakePoint(cx, cy - haloRadius - 3.0f)];
        [centerTick lineToPoint:NSMakePoint(cx, cy - haloRadius + 4.0f)];
        [[NSColor colorWithCalibratedWhite:0.35f alpha:1.0f] setStroke];
        [centerTick setLineWidth:1.5f];
        [centerTick stroke];

        if (pct >= 0.5f) {
            CGFloat sweep = (pct - 0.5f) * 270.0f;
            if (sweep > 1.0f) {
                [activeArc appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy) radius:haloRadius startAngle:270.0f endAngle:(270.0f + sweep) clockwise:NO];
            }
        } else {
            CGFloat sweep = (0.5f - pct) * 270.0f;
            if (sweep > 1.0f) {
                [activeArc appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy) radius:haloRadius startAngle:270.0f endAngle:(270.0f - sweep) clockwise:YES];
            }
        }
        needleAngle = 135.0f + (pct * 270.0f);
    } else {
        // Standard: sweeps clockwise from bottom-left (135°) to bottom-right (45°)
        if (pct > 0.01f) {
            [activeArc appendBezierPathWithArcWithCenter:NSMakePoint(cx, cy) radius:haloRadius startAngle:135.0f endAngle:(135.0f + pct * 270.0f) clockwise:NO];
        }
        needleAngle = 135.0f + (pct * 270.0f);
    }

    if ([activeArc elementCount] > 0) {
        [activeArc setLineCapStyle:NSLineCapStyleRound];

        // Glow Pass
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 12.0f, ctrl.accentColor.CGColor);
        [ctrl.accentColor setStroke];
        [activeArc setLineWidth:4.0f];
        [activeArc stroke];
        CGContextRestoreGState(ctx);

        // Core bright pass
        [[NSColor whiteColor] setStroke];
        [activeArc setLineWidth:1.5f];
        [activeArc stroke];
    }

    // 3. Machined Aluminum Turned Metal Dial Face
    CGFloat dialFaceR = radius * 0.72f;
    NSRect faceRect = NSMakeRect(cx - dialFaceR, cy - dialFaceR, dialFaceR * 2.0f, dialFaceR * 2.0f);
    NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect:faceRect];

    // Drop shadow under dial
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeMake(0, -2.0f), 6.0f, [NSColor colorWithCalibratedWhite:0.0f alpha:0.7f].CGColor);

    // Turned metal multi-radial gradient
    NSGradient *dialGrad = [[NSGradient alloc] initWithColorsAndLocations:
        [NSColor colorWithCalibratedRed:0.25f green:0.27f blue:0.33f alpha:1.0f], 0.0f,
        [NSColor colorWithCalibratedRed:0.16f green:0.17f blue:0.21f alpha:1.0f], 0.35f,
        [NSColor colorWithCalibratedRed:0.10f green:0.11f blue:0.14f alpha:1.0f], 0.70f,
        [NSColor colorWithCalibratedRed:0.06f green:0.07f blue:0.09f alpha:1.0f], 1.0f, nil];
    [dialGrad drawInBezierPath:face angle:90.0f];
    CGContextRestoreGState(ctx);

    // Beveled rim
    [[NSColor colorWithCalibratedWhite:0.35f alpha:0.8f] setStroke];
    [face setLineWidth:1.0f];
    [face stroke];

    // Concentric brush groove
    NSRect innerGroove = NSInsetRect(faceRect, dialFaceR * 0.35f, dialFaceR * 0.35f);
    NSBezierPath *groovePath = [NSBezierPath bezierPathWithOvalInRect:innerGroove];
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.04f] setStroke];
    [groovePath setLineWidth:1.0f];
    [groovePath stroke];

    // 4. Indicator Needle (Glowing Neon Pointer)
    CGFloat rad = needleAngle * M_PI / 180.0f;
    CGFloat pStartX = cx + cos(rad) * (dialFaceR * 0.20f);
    CGFloat pStartY = cy + sin(rad) * (dialFaceR * 0.20f);
    CGFloat pEndX = cx + cos(rad) * (dialFaceR * 0.85f);
    CGFloat pEndY = cy + sin(rad) * (dialFaceR * 0.85f);

    NSBezierPath *needle = [NSBezierPath bezierPath];
    [needle moveToPoint:NSMakePoint(pStartX, pStartY)];
    [needle lineToPoint:NSMakePoint(pEndX, pEndY)];
    [needle setLineCapStyle:NSLineCapStyleRound];

    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 10.0f, ctrl.accentColor.CGColor);
    [ctrl.accentColor setStroke];
    [needle setLineWidth:3.5f];
    [needle stroke];
    CGContextRestoreGState(ctx);

    [[NSColor whiteColor] setStroke];
    [needle setLineWidth:1.5f];
    [needle stroke];

    // 5. Draw Pill Label (Matching "SYNTH FILTER" capsule at bottom right of screenshot)
    if (hasLabel) {
        NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:pillRect xRadius:13.0f yRadius:13.0f];
        [[NSColor colorWithCalibratedRed:0.06f green:0.07f blue:0.09f alpha:1.0f] setFill];
        [pill fill];

        // Glowing border on label capsule
        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0f, [ctrl.accentColor colorWithAlphaComponent:0.6f].CGColor);
        [ctrl.accentColor setStroke];
        [pill setLineWidth:1.2f];
        [pill stroke];
        CGContextRestoreGState(ctx);

        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.alignment = NSTextAlignmentCenter;
        NSDictionary *attr = @{
            NSFontAttributeName: [NSFont systemFontOfSize:11.0f weight:NSFontWeightBold],
            NSForegroundColorAttributeName: [NSColor whiteColor],
            NSParagraphStyleAttributeName: style,
            NSKernAttributeName: @(1.2f)
        };
        NSRect textRect = NSMakeRect(pillRect.origin.x, pillRect.origin.y + 5.0f, pillRect.size.width, 16.0f);
        [ctrl.label drawInRect:textRect withAttributes:attr];
    }
}

- (void)drawButton:(MidiControlModel *)ctrl {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    NSRect r = ctrl.frame;
    BOOL isCircle = [ctrl.shape isEqualToString:@"circle"];
    BOOL isLit = (ctrl.value > 0);

    if (isCircle) {
        CGFloat size = MIN(r.size.width, r.size.height);
        CGFloat x = NSMidX(r) - size / 2.0f;
        CGFloat y = NSMidY(r) - size / 2.0f;
        NSRect outerRect = NSMakeRect(x, y, size, size);

        // Circular Recessed Well
        NSBezierPath *well = [NSBezierPath bezierPathWithOvalInRect:outerRect];
        [[NSColor colorWithCalibratedRed:0.06f green:0.07f blue:0.09f alpha:1.0f] setFill];
        [well fill];
        [[NSColor colorWithCalibratedWhite:0.16f alpha:1.0f] setStroke];
        [well setLineWidth:1.0f];
        [well stroke];

        // 360° Neon Halo Ring
        NSRect ringRect = NSInsetRect(outerRect, 4.0f, 4.0f);
        NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:ringRect];

        CGContextSaveGState(ctx);
        CGFloat glowRadius = isLit ? 14.0f : 6.0f;
        CGContextSetShadowWithColor(ctx, CGSizeZero, glowRadius, [ctrl.accentColor colorWithAlphaComponent:isLit ? 0.95f : 0.45f].CGColor);
        [ctrl.accentColor setStroke];
        [ring setLineWidth:3.0f];
        [ring stroke];
        CGContextRestoreGState(ctx);

        // Inner Face (Turned Aluminum Dial or Active Fill)
        NSRect faceRect = NSInsetRect(ringRect, 4.0f, 4.0f);
        NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect:faceRect];
        if (isLit) {
            [ctrl.color setFill];
            [face fill];
            NSGradient *glowGrad = [[NSGradient alloc] initWithStartingColor:[ctrl.accentColor colorWithAlphaComponent:0.6f]
                                                                endingColor:[ctrl.color colorWithAlphaComponent:0.9f]];
            [glowGrad drawInBezierPath:face relativeCenterPosition:NSZeroPoint];
        } else {
            NSGradient *dialGrad = [[NSGradient alloc] initWithColorsAndLocations:
                [NSColor colorWithCalibratedRed:0.22f green:0.24f blue:0.29f alpha:1.0f], 0.0f,
                [NSColor colorWithCalibratedRed:0.12f green:0.13f blue:0.16f alpha:1.0f], 0.5f,
                [NSColor colorWithCalibratedRed:0.08f green:0.09f blue:0.11f alpha:1.0f], 1.0f, nil];
            [dialGrad drawInBezierPath:face angle:-45.0f];
        }
        [[NSColor colorWithCalibratedWhite:0.28f alpha:0.8f] setStroke];
        [face setLineWidth:1.0f];
        [face stroke];
    } else {
        // Rounded Square Pad (Matching the reference middle pads and top-right BELLS pad)
        CGFloat cornerR = 12.0f;
        NSRect padRect = r;

        // Outer Ambient Glow Bloom
        CGContextSaveGState(ctx);
        CGFloat glowRadius = isLit ? 16.0f : 8.0f;
        CGFloat glowAlpha = isLit ? 0.85f : 0.35f;
        CGContextSetShadowWithColor(ctx, CGSizeZero, glowRadius, [ctrl.accentColor colorWithAlphaComponent:glowAlpha].CGColor);

        NSBezierPath *padPath = [NSBezierPath bezierPathWithRoundedRect:padRect xRadius:cornerR yRadius:cornerR];

        // Pad Interior Face
        if (isLit) {
            NSGradient *glassGrad = [[NSGradient alloc] initWithStartingColor:[ctrl.accentColor colorWithAlphaComponent:0.85f]
                                                                  endingColor:[ctrl.color colorWithAlphaComponent:0.95f]];
            [glassGrad drawInBezierPath:padPath relativeCenterPosition:NSMakePoint(0.0f, 0.1f)];
        } else {
            NSGradient *darkGrad = [[NSGradient alloc] initWithColorsAndLocations:
                [NSColor colorWithCalibratedRed:0.16f green:0.17f blue:0.21f alpha:1.0f], 0.0f,
                [NSColor colorWithCalibratedRed:0.10f green:0.11f blue:0.14f alpha:1.0f], 0.6f,
                [NSColor colorWithCalibratedRed:0.07f green:0.08f blue:0.10f alpha:1.0f], 1.0f, nil];
            [darkGrad drawInBezierPath:padPath angle:-90.0f];
        }

        // Glowing Neon Rim
        [ctrl.accentColor setStroke];
        [padPath setLineWidth:3.0f];
        [padPath stroke];
        CGContextRestoreGState(ctx);

        // Inner beveled highlight
        NSRect innerHighlightRect = NSInsetRect(padRect, 2.0f, 2.0f);
        NSBezierPath *innerHighlight = [NSBezierPath bezierPathWithRoundedRect:innerHighlightRect xRadius:cornerR - 2.0f yRadius:cornerR - 2.0f];
        [[NSColor colorWithCalibratedWhite:1.0f alpha:isLit ? 0.35f : 0.08f] setStroke];
        [innerHighlight setLineWidth:1.0f];
        [innerHighlight stroke];

        // Button Text Label
        if (ctrl.label.length > 0) {
            CGFloat fSize = (ctrl.fontSize > 0) ? ctrl.fontSize : 13.0f;
            NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
            style.alignment = NSTextAlignmentCenter;
            NSDictionary *attr = @{
                NSFontAttributeName: [NSFont systemFontOfSize:fSize weight:NSFontWeightBold],
                NSForegroundColorAttributeName: (isLit ? [NSColor whiteColor] : [ctrl.accentColor colorWithAlphaComponent:0.9f]),
                NSParagraphStyleAttributeName: style,
                NSKernAttributeName: @(1.2f)
            };
            NSRect textRect = NSMakeRect(r.origin.x + 4.0f, NSMidY(r) - (fSize + 4.0f) / 2.0f, r.size.width - 8.0f, fSize + 6.0f);
            [ctrl.label drawInRect:textRect withAttributes:attr];
        }
    }
}

- (void)drawXYPad:(MidiControlModel *)ctrl {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    NSRect r = ctrl.frame;
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:r xRadius:14.0f yRadius:14.0f];
    [[NSColor colorWithCalibratedRed:0.05f green:0.06f blue:0.08f alpha:1.0f] setFill];
    [p fill];

    // Outer subtle glow rim
    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0f, [ctrl.accentColor colorWithAlphaComponent:0.4f].CGColor);
    [[NSColor colorWithCalibratedWhite:0.20f alpha:1.0f] setStroke];
    [p setLineWidth:1.5f];
    [p stroke];
    CGContextRestoreGState(ctx);

    // Crosshair Lines with neon accent
    CGFloat puckX = r.origin.x + (ctrl.value / 127.0f) * r.size.width;
    CGFloat puckY = r.origin.y + (1.0f - (ctrl.value / 127.0f)) * r.size.height;

    [[NSColor colorWithCalibratedWhite:0.18f alpha:0.8f] setStroke];
    NSBezierPath *cross = [NSBezierPath bezierPath];
    [cross moveToPoint:NSMakePoint(puckX, r.origin.y + 4.0f)];
    [cross lineToPoint:NSMakePoint(puckX, NSMaxY(r) - 4.0f)];
    [cross moveToPoint:NSMakePoint(r.origin.x + 4.0f, puckY)];
    [cross lineToPoint:NSMakePoint(NSMaxX(r) - 4.0f, puckY)];
    [cross setLineWidth:1.0f];
    [cross stroke];

    // Glowing Neon Puck
    NSRect puckRect = NSMakeRect(puckX - 11.0f, puckY - 11.0f, 22.0f, 22.0f);
    NSBezierPath *puck = [NSBezierPath bezierPathWithOvalInRect:puckRect];

    CGContextSaveGState(ctx);
    CGContextSetShadowWithColor(ctx, CGSizeZero, 14.0f, ctrl.accentColor.CGColor);
    [ctrl.accentColor setFill];
    [puck fill];
    CGContextRestoreGState(ctx);

    [[NSColor whiteColor] setFill];
    NSRect corePuck = NSInsetRect(puckRect, 4.0f, 4.0f);
    NSBezierPath *corePuckPath = [NSBezierPath bezierPathWithOvalInRect:corePuck];
    [corePuckPath fill];

    // Label
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentLeft;
    NSDictionary *attr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11.0f weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.65f alpha:1.0f],
        NSParagraphStyleAttributeName: style,
        NSKernAttributeName: @(1.2f)
    };
    [ctrl.label drawInRect:NSMakeRect(r.origin.x + 10.0f, r.origin.y + 8.0f, r.size.width - 20.0f, 16.0f) withAttributes:attr];
}

- (void)drawLabel:(MidiControlModel *)ctrl {
    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    NSRect r = ctrl.frame;

    if (ctrl.hasBackground) {
        NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:r xRadius:13.0f yRadius:13.0f];
        [[NSColor colorWithCalibratedRed:0.06f green:0.07f blue:0.09f alpha:1.0f] setFill];
        [pill fill];

        CGContextSaveGState(ctx);
        CGContextSetShadowWithColor(ctx, CGSizeZero, 8.0f, [ctrl.accentColor colorWithAlphaComponent:0.6f].CGColor);
        [ctrl.accentColor setStroke];
        [pill setLineWidth:1.2f];
        [pill stroke];
        CGContextRestoreGState(ctx);
    }

    CGFloat fSize = (ctrl.fontSize > 0) ? ctrl.fontSize : 12.0f;
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attr = @{
        NSFontAttributeName: [NSFont systemFontOfSize:fSize weight:NSFontWeightBold],
        NSForegroundColorAttributeName: [NSColor whiteColor],
        NSParagraphStyleAttributeName: style,
        NSKernAttributeName: @(1.4f)
    };
    NSRect textRect = NSMakeRect(r.origin.x, NSMidY(r) - (fSize + 4.0f) / 2.0f, r.size.width, fSize + 6.0f);
    [ctrl.label drawInRect:textRect withAttributes:attr];
}

- (void)drawSelectionForControl:(MidiControlModel *)ctrl isPrimary:(BOOL)isPrimary {
    NSRect r = ctrl.frame;

    // Glowing Apple Accent Blue Outline
    NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, -3.0f, -3.0f) xRadius:6.0f yRadius:6.0f];
    [AirColorAccent() setStroke];
    [outline setLineWidth:2.0f];
    [outline stroke];

    // Corner circular resize handles (only on primary control or when single control selected)
    if (self.selectedControls.count == 1 || isPrimary) {
        CGFloat hSize = 8.0f;
        NSPoint corners[4] = {
            NSMakePoint(NSMinX(r) - 3.0f, NSMinY(r) - 3.0f),
            NSMakePoint(NSMaxX(r) + 3.0f, NSMinY(r) - 3.0f),
            NSMakePoint(NSMaxX(r) + 3.0f, NSMaxY(r) + 3.0f),
            NSMinX(r) - 3.0f, NSMaxY(r) + 3.0f
        };

        for (int i = 0; i < 4; i++) {
            NSRect hRect = NSMakeRect(corners[i].x - hSize / 2.0f, corners[i].y - hSize / 2.0f, hSize, hSize);
            NSBezierPath *hPath = [NSBezierPath bezierPathWithOvalInRect:hRect];
            [[NSColor whiteColor] setFill];
            [hPath fill];
            [AirColorAccent() setStroke];
            [hPath setLineWidth:1.5f];
            [hPath stroke];
        }
    }

    // Floating Dimension Tag above control
    if (isPrimary) {
        NSString *tag;
        if (self.selectedControls.count > 1) {
            tag = [NSString stringWithFormat:@"%lu Selected  •  %d × %d",
                (unsigned long)self.selectedControls.count, (int)r.size.width, (int)r.size.height];
        } else {
            tag = [NSString stringWithFormat:@"%d × %d  •  Ch %ld #%ld",
                (int)r.size.width, (int)r.size.height, (long)ctrl.midiChannel, (long)ctrl.midiNumber];
        }

        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.alignment = NSTextAlignmentCenter;
        NSDictionary *attr = @{
            NSFontAttributeName: [NSFont systemFontOfSize:10.0f weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor whiteColor],
            NSParagraphStyleAttributeName: style
        };
        NSSize tagSize = [tag sizeWithAttributes:attr];
        NSRect tagRect = NSMakeRect(NSMidX(r) - (tagSize.width + 16.0f) / 2.0f, r.origin.y - 22.0f, tagSize.width + 16.0f, 18.0f);

        NSBezierPath *tagBg = [NSBezierPath bezierPathWithRoundedRect:tagRect xRadius:4.0f yRadius:4.0f];
        [[NSColor colorWithCalibratedRed:0.04f green:0.52f blue:1.0f alpha:0.95f] setFill];
        [tagBg fill];

        [tag drawInRect:NSMakeRect(tagRect.origin.x, tagRect.origin.y + 2.0f, tagRect.size.width, 14.0f) withAttributes:attr];
    }
}

- (void)drawSelectionForControl:(MidiControlModel *)ctrl {
    [self drawSelectionForControl:ctrl isPrimary:(ctrl == self.selectedControl)];
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (BOOL)becomeFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent *)event {
    NSString *chars = [event charactersIgnoringModifiers];
    if (chars.length > 0) {
        unichar c = [chars characterAtIndex:0];

        // 1. Standard Mac Delete
        if (c == NSDeleteCharacter || c == 0x7F || c == NSDeleteFunctionKey) {
            if (self.selectedControls.count > 0) {
                [self deleteSelected];
                return;
            }
        }

        // 2. Arrow Keys Movement (Nudge / Step)
        if (c == NSUpArrowFunctionKey || c == NSDownArrowFunctionKey ||
            c == NSLeftArrowFunctionKey || c == NSRightArrowFunctionKey) {
            if (self.selectedControls.count > 0) {
                [self pushUndoSnapshot];

                CGFloat step = 20.0f;
                if ([event modifierFlags] & NSEventModifierFlagOption) {
                    step = 1.0f; // Micro nudge
                } else if (!self.snapToGrid) {
                    step = ([event modifierFlags] & NSEventModifierFlagShift) ? 10.0f : 5.0f;
                } else if ([event modifierFlags] & NSEventModifierFlagShift) {
                    step = 40.0f;
                }

                CGFloat dx = 0.0f;
                CGFloat dy = 0.0f;
                if (c == NSUpArrowFunctionKey) dy = -step;
                else if (c == NSDownArrowFunctionKey) dy = step;
                else if (c == NSLeftArrowFunctionKey) dx = -step;
                else if (c == NSRightArrowFunctionKey) dx = step;

                for (MidiControlModel *ctrl in self.selectedControls) {
                    NSRect r = ctrl.frame;
                    r.origin.x += dx;
                    r.origin.y += dy;
                    if (self.snapToGrid && !([event modifierFlags] & NSEventModifierFlagOption)) {
                        r.origin.x = round(r.origin.x / 20.0f) * 20.0f;
                        r.origin.y = round(r.origin.y / 20.0f) * 20.0f;
                    }
                    ctrl.frame = r;
                    [self.delegate canvasDidChangeControl:ctrl];
                }
                [self setNeedsDisplay:YES];
                return;
            }
        }

        // 3. Command Shortcuts: Select All, Copy, Paste, Duplicate, Undo, Redo
        if ([event modifierFlags] & NSEventModifierFlagCommand) {
            NSString *lower = chars.lowercaseString;
            if ([lower isEqualToString:@"a"]) {
                [self selectAllControls];
                return;
            } else if ([lower isEqualToString:@"c"]) {
                [self copySelected];
                return;
            } else if ([lower isEqualToString:@"v"]) {
                [self pasteCopied];
                return;
            } else if ([lower isEqualToString:@"d"]) {
                [self duplicateSelected];
                return;
            } else if ([lower isEqualToString:@"z"]) {
                if ([event modifierFlags] & NSEventModifierFlagShift) {
                    [self redo];
                } else {
                    [self undo];
                }
                return;
            } else if ([lower isEqualToString:@"y"]) {
                [self redo];
                return;
            }
        }
    }
    [super keyDown:event];
}

- (IBAction)delete:(id)sender {
    if (self.selectedControls.count > 0) {
        [self deleteSelected];
    }
}

#pragma mark - Mouse Events

- (NSPoint)canvasPointFromEvent:(NSEvent *)event {
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat devW = self.layout.canvasWidth > 0 ? self.layout.canvasWidth : 920.0f;
    CGFloat devH = self.layout.canvasHeight > 0 ? self.layout.canvasHeight : 460.0f;
    CGFloat availW = MAX(100.0f, self.bounds.size.width - 60.0f);
    CGFloat availH = MAX(100.0f, self.bounds.size.height - 70.0f);
    CGFloat zoom = MIN(1.0f, MIN(availW / devW, availH / devH));

    CGFloat renderedDevW = devW * zoom;
    CGFloat renderedDevH = devH * zoom;
    CGFloat devX = (self.bounds.size.width - renderedDevW) / 2.0f;
    CGFloat devY = (self.bounds.size.height - 30.0f - renderedDevH) / 2.0f;
    if (devY < 18.0f) devY = 18.0f;

    return NSMakePoint((p.x - devX) / zoom, (p.y - devY) / zoom);
}

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    NSPoint mousePos = [self canvasPointFromEvent:event];
    NSEventModifierFlags flags = [event modifierFlags] | [NSEvent modifierFlags];
    BOOL isMultiSelect = ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagShift)) != 0);

    // Check resize handles if single control is selected
    if (self.selectedControls.count == 1 && self.selectedControl) {
        CGFloat devW = self.layout.canvasWidth > 0 ? self.layout.canvasWidth : 920.0f;
        CGFloat devH = self.layout.canvasHeight > 0 ? self.layout.canvasHeight : 460.0f;
        CGFloat availW = MAX(100.0f, self.bounds.size.width - 60.0f);
        CGFloat availH = MAX(100.0f, self.bounds.size.height - 70.0f);
        CGFloat zoom = MIN(1.0f, MIN(availW / devW, availH / devH));

        NSRect r = self.selectedControl.frame;
        CGFloat hArea = 18.0f / zoom;
        NSRect tlHandle = NSMakeRect(NSMinX(r) - hArea / 2.0f, NSMinY(r) - hArea / 2.0f, hArea, hArea);
        NSRect trHandle = NSMakeRect(NSMaxX(r) - hArea / 2.0f, NSMinY(r) - hArea / 2.0f, hArea, hArea);
        NSRect brHandle = NSMakeRect(NSMaxX(r) - hArea / 2.0f, NSMaxY(r) - hArea / 2.0f, hArea, hArea);
        NSRect blHandle = NSMakeRect(NSMinX(r) - hArea / 2.0f, NSMaxY(r) - hArea / 2.0f, hArea, hArea);

        if (NSPointInRect(mousePos, tlHandle)) {
            _isResizing = YES;
            _resizeCorner = 1;
            _dragStartMouse = mousePos;
            _initialControlFrame = r;
            _mouseDownSnapshot = [self currentControlsSnapshot];
            _hasDraggedOrResized = NO;
            return;
        } else if (NSPointInRect(mousePos, trHandle)) {
            _isResizing = YES;
            _resizeCorner = 2;
            _dragStartMouse = mousePos;
            _initialControlFrame = r;
            _mouseDownSnapshot = [self currentControlsSnapshot];
            _hasDraggedOrResized = NO;
            return;
        } else if (NSPointInRect(mousePos, brHandle)) {
            _isResizing = YES;
            _resizeCorner = 3;
            _dragStartMouse = mousePos;
            _initialControlFrame = r;
            _mouseDownSnapshot = [self currentControlsSnapshot];
            _hasDraggedOrResized = NO;
            return;
        } else if (NSPointInRect(mousePos, blHandle)) {
            _isResizing = YES;
            _resizeCorner = 4;
            _dragStartMouse = mousePos;
            _initialControlFrame = r;
            _mouseDownSnapshot = [self currentControlsSnapshot];
            _hasDraggedOrResized = NO;
            return;
        }
    }

    // Hit test controls (from front-most to back-most)
    MidiControlModel *hit = nil;
    for (NSInteger i = self.layout.controls.count - 1; i >= 0; i--) {
        MidiControlModel *m = self.layout.controls[i];
        if (NSPointInRect(mousePos, m.frame)) {
            hit = m;
            break;
        }
    }

    _clickedControlOnMouseDown = hit;
    _clickedControlWasAlreadySelected = NO;

    if (hit) {
        if (isMultiSelect) {
            // CMD / SHIFT + Click: Toggle individual item in/out of selection
            if ([self.selectedControls containsObject:hit]) {
                [self.selectedControls removeObject:hit];
                [self.delegate canvasDidSelectControl:self.selectedControl];
            } else {
                [self.selectedControls addObject:hit];
                [self.delegate canvasDidSelectControl:hit];
            }
        } else {
            // Normal Click:
            // If not in selectedControls, select only this item
            if (![self.selectedControls containsObject:hit]) {
                [self.selectedControls removeAllObjects];
                [self.selectedControls addObject:hit];
                [self.delegate canvasDidSelectControl:hit];
            } else {
                // If already in selectedControls, KEEP the multi-selection so user can drag all selected together!
                _clickedControlWasAlreadySelected = YES;
                [self.delegate canvasDidSelectControl:hit];
            }
        }

        // Prepare for dragging all selected controls
        _isDragging = YES;
        _dragStartMouse = mousePos;
        _mouseDownSnapshot = [self currentControlsSnapshot];
        _hasDraggedOrResized = NO;
        _initialFramesByControlId = [NSMutableDictionary dictionaryWithCapacity:self.selectedControls.count];
        for (MidiControlModel *ctrl in self.selectedControls) {
            _initialFramesByControlId[ctrl.controlId] = [NSValue valueWithRect:ctrl.frame];
        }
    } else {
        // Clicked on empty canvas space
        if (!isMultiSelect) {
            [self.selectedControls removeAllObjects];
            [self.delegate canvasDidSelectControl:nil];
        }

        _isMarqueeSelecting = YES;
        _marqueeStartPoint = mousePos;
        _marqueeRect = NSMakeRect(mousePos.x, mousePos.y, 0, 0);
        _initialSelectionBeforeMarquee = [self.selectedControls mutableCopy];
    }

    [self setNeedsDisplay:YES];
}

- (void)mouseDragged:(NSEvent *)event {
    NSPoint mousePos = [self canvasPointFromEvent:event];

    if (_isResizing && self.selectedControl) {
        if (!_hasDraggedOrResized) {
            _hasDraggedOrResized = YES;
            [self pushSnapshot:_mouseDownSnapshot];
        }

        CGFloat dx = mousePos.x - _dragStartMouse.x;
        CGFloat dy = mousePos.y - _dragStartMouse.y;
        NSRect initF = _initialControlFrame;
        CGFloat minW = 40.0f;
        CGFloat minH = 30.0f;

        CGFloat newX = initF.origin.x;
        CGFloat newY = initF.origin.y;
        CGFloat newW = initF.size.width;
        CGFloat newH = initF.size.height;

        if (_resizeCorner == 1) { // Top-Left
            newX = MIN(initF.origin.x + dx, NSMaxX(initF) - minW);
            newY = MIN(initF.origin.y + dy, NSMaxY(initF) - minH);
            if (self.snapToGrid && !([event modifierFlags] & NSEventModifierFlagOption)) {
                newX = round(newX / 20.0f) * 20.0f;
                newY = round(newY / 20.0f) * 20.0f;
            }
            newW = NSMaxX(initF) - newX;
            newH = NSMaxY(initF) - newY;
        } else if (_resizeCorner == 2) { // Top-Right
            newY = MIN(initF.origin.y + dy, NSMaxY(initF) - minH);
            if (self.snapToGrid && !([event modifierFlags] & NSEventModifierFlagOption)) {
                newY = round(newY / 20.0f) * 20.0f;
            }
            newH = NSMaxY(initF) - newY;
            newW = MAX(minW, initF.size.width + dx);
            if (self.snapToGrid && !([event modifierFlags] & NSEventModifierFlagOption)) {
                newW = round(newW / 20.0f) * 20.0f;
            }
        } else if (_resizeCorner == 3) { // Bottom-Right
            newW = MAX(minW, initF.size.width + dx);
            newH = MAX(minH, initF.size.height + dy);
            if (self.snapToGrid && !([event modifierFlags] & NSEventModifierFlagOption)) {
                newW = round(newW / 20.0f) * 20.0f;
                newH = round(newH / 20.0f) * 20.0f;
            }
        } else if (_resizeCorner == 4) { // Bottom-Left
            newX = MIN(initF.origin.x + dx, NSMaxX(initF) - minW);
            if (self.snapToGrid && !([event modifierFlags] & NSEventModifierFlagOption)) {
                newX = round(newX / 20.0f) * 20.0f;
            }
            newW = NSMaxX(initF) - newX;
            newH = MAX(minH, initF.size.height + dy);
            if (self.snapToGrid && !([event modifierFlags] & NSEventModifierFlagOption)) {
                newH = round(newH / 20.0f) * 20.0f;
            }
        }

        self.selectedControl.frame = NSMakeRect(newX, newY, newW, newH);
        [self.delegate canvasDidChangeControl:self.selectedControl];
        [self setNeedsDisplay:YES];
    } else if (_isDragging && self.selectedControls.count > 0) {
        if (!_hasDraggedOrResized) {
            _hasDraggedOrResized = YES;
            [self pushSnapshot:_mouseDownSnapshot];
        }

        CGFloat deltaX = mousePos.x - _dragStartMouse.x;
        CGFloat deltaY = mousePos.y - _dragStartMouse.y;

        if (self.snapToGrid && !([event modifierFlags] & NSEventModifierFlagOption)) {
            deltaX = round(deltaX / 20.0f) * 20.0f;
            deltaY = round(deltaY / 20.0f) * 20.0f;
        }

        for (MidiControlModel *ctrl in self.selectedControls) {
            NSValue *origVal = _initialFramesByControlId[ctrl.controlId];
            if (origVal) {
                NSRect origRect = [origVal rectValue];
                ctrl.frame = NSMakeRect(origRect.origin.x + deltaX, origRect.origin.y + deltaY, origRect.size.width, origRect.size.height);
                [self.delegate canvasDidChangeControl:ctrl];
            }
        }
        [self setNeedsDisplay:YES];
    } else if (_isMarqueeSelecting) {
        CGFloat minX = MIN(_marqueeStartPoint.x, mousePos.x);
        CGFloat minY = MIN(_marqueeStartPoint.y, mousePos.y);
        CGFloat width = fabs(mousePos.x - _marqueeStartPoint.x);
        CGFloat height = fabs(mousePos.y - _marqueeStartPoint.y);
        _marqueeRect = NSMakeRect(minX, minY, width, height);

        NSEventModifierFlags flags = [event modifierFlags] | [NSEvent modifierFlags];
        BOOL isMultiSelect = ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagShift)) != 0);
        if (isMultiSelect && _initialSelectionBeforeMarquee) {
            [self.selectedControls setArray:_initialSelectionBeforeMarquee];
        } else {
            [self.selectedControls removeAllObjects];
        }

        for (MidiControlModel *ctrl in self.layout.controls) {
            if (NSIntersectsRect(_marqueeRect, ctrl.frame)) {
                if (![self.selectedControls containsObject:ctrl]) {
                    [self.selectedControls addObject:ctrl];
                }
            }
        }

        [self.delegate canvasDidSelectControl:self.selectedControl];
        [self setNeedsDisplay:YES];
    }
}

- (void)mouseUp:(NSEvent *)event {
    NSEventModifierFlags flags = [event modifierFlags] | [NSEvent modifierFlags];
    BOOL isMultiSelect = ((flags & (NSEventModifierFlagCommand | NSEventModifierFlagShift)) != 0);
    if (!_hasDraggedOrResized && _clickedControlWasAlreadySelected && _clickedControlOnMouseDown && !isMultiSelect) {
        // User clicked an already-selected item without dragging and without modifier keys:
        // Focus selection exclusively on this clicked item.
        [self.selectedControls removeAllObjects];
        [self.selectedControls addObject:_clickedControlOnMouseDown];
        [self.delegate canvasDidSelectControl:_clickedControlOnMouseDown];
    }

    _isDragging = NO;
    _isResizing = NO;
    _isMarqueeSelecting = NO;
    _clickedControlOnMouseDown = nil;
    _clickedControlWasAlreadySelected = NO;
    _marqueeRect = NSZeroRect;
    _initialSelectionBeforeMarquee = nil;
    [self.delegate canvasDidSelectControl:self.selectedControl];
    [self setNeedsDisplay:YES];
}

#pragma mark - Context Menu

- (NSMenu *)menuForEvent:(NSEvent *)event {
    NSPoint mousePos = [self canvasPointFromEvent:event];
    _lastRightClickPoint = mousePos;

    // Check if right-clicked a control
    MidiControlModel *hit = nil;
    for (NSInteger i = self.layout.controls.count - 1; i >= 0; i--) {
        MidiControlModel *m = self.layout.controls[i];
        if (NSPointInRect(mousePos, m.frame)) {
            hit = m;
            break;
        }
    }

    if (hit) {
        if (![self.selectedControls containsObject:hit]) {
            [self.selectedControls removeAllObjects];
            [self.selectedControls addObject:hit];
            [self.delegate canvasDidSelectControl:hit];
        }
        [self setNeedsDisplay:YES];
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Canvas Context"];

    // Add Options with Apple SF Symbols
    NSMenuItem *itemFader = [[NSMenuItem alloc] initWithTitle:@"Add Vertical Fader" action:@selector(onAddFader:) keyEquivalent:@""];
    itemFader.image = AirSymbol(@"slider.vertical.3", 13.0f);
    itemFader.target = self;
    [menu addItem:itemFader];

    NSMenuItem *itemHorizFader = [[NSMenuItem alloc] initWithTitle:@"Add Horizontal Fader" action:@selector(onAddHorizontalFader:) keyEquivalent:@""];
    itemHorizFader.image = AirSymbol(@"slider.horizontal.3", 13.0f);
    itemHorizFader.target = self;
    [menu addItem:itemHorizFader];

    NSMenuItem *itemKnob = [[NSMenuItem alloc] initWithTitle:@"Add Rotary Knob" action:@selector(onAddKnob:) keyEquivalent:@""];
    itemKnob.image = AirSymbol(@"dial.medium", 13.0f);
    itemKnob.target = self;
    [menu addItem:itemKnob];

    NSMenuItem *itemBtn = [[NSMenuItem alloc] initWithTitle:@"Add Button / Pad" action:@selector(onAddButton:) keyEquivalent:@""];
    itemBtn.image = AirSymbol(@"square.grid.2x2", 13.0f);
    itemBtn.target = self;
    [menu addItem:itemBtn];

    NSMenuItem *itemXY = [[NSMenuItem alloc] initWithTitle:@"Add XY Pad" action:@selector(onAddXYPad:) keyEquivalent:@""];
    itemXY.image = AirSymbol(@"dot.squareshape.split.2x2", 13.0f);
    itemXY.target = self;
    [menu addItem:itemXY];

    NSMenuItem *itemLbl = [[NSMenuItem alloc] initWithTitle:@"Add Text Label" action:@selector(onAddLabel:) keyEquivalent:@""];
    itemLbl.image = AirSymbol(@"textformat", 13.0f);
    itemLbl.target = self;
    [menu addItem:itemLbl];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *itemSnap = [[NSMenuItem alloc] initWithTitle:@"Snap to Grid (20px)" action:@selector(toggleSnapToGrid:) keyEquivalent:@""];
    itemSnap.state = self.snapToGrid ? NSControlStateValueOn : NSControlStateValueOff;
    itemSnap.image = AirSymbol(@"grid", 13.0f);
    itemSnap.target = self;
    [menu addItem:itemSnap];

    if (self.selectedControls.count > 0) {
        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *itemCopy = [[NSMenuItem alloc] initWithTitle:@"Copy" action:@selector(copySelected) keyEquivalent:@"c"];
        itemCopy.image = AirSymbol(@"doc.on.doc", 13.0f);
        itemCopy.target = self;
        [menu addItem:itemCopy];

        if (_copiedControls.count > 0) {
            NSMenuItem *itemPaste = [[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(pasteCopied) keyEquivalent:@"v"];
            itemPaste.image = AirSymbol(@"doc.on.clipboard", 13.0f);
            itemPaste.target = self;
            [menu addItem:itemPaste];
        }

        NSMenuItem *itemDup = [[NSMenuItem alloc] initWithTitle:@"Duplicate" action:@selector(duplicateSelected) keyEquivalent:@"d"];
        itemDup.image = AirSymbol(@"plus.square.on.square", 13.0f);
        itemDup.target = self;
        [menu addItem:itemDup];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *itemUndo = [[NSMenuItem alloc] initWithTitle:@"Undo" action:@selector(undo) keyEquivalent:@"z"];
        itemUndo.image = AirSymbol(@"arrow.uturn.backward", 13.0f);
        itemUndo.target = self;
        [menu addItem:itemUndo];

        NSMenuItem *itemRedo = [[NSMenuItem alloc] initWithTitle:@"Redo" action:@selector(redo) keyEquivalent:@"Z"];
        itemRedo.image = AirSymbol(@"arrow.uturn.forward", 13.0f);
        itemRedo.target = self;
        [menu addItem:itemRedo];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *itemFront = [[NSMenuItem alloc] initWithTitle:@"Bring to Front" action:@selector(bringSelectedToFront) keyEquivalent:@""];
        itemFront.image = AirSymbol(@"arrow.up.to.line", 13.0f);
        itemFront.target = self;
        [menu addItem:itemFront];

        NSMenuItem *itemBack = [[NSMenuItem alloc] initWithTitle:@"Send to Back" action:@selector(sendSelectedToBack) keyEquivalent:@""];
        itemBack.image = AirSymbol(@"arrow.down.to.line", 13.0f);
        itemBack.target = self;
        [menu addItem:itemBack];

        [menu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *itemDel = [[NSMenuItem alloc] initWithTitle:@"Delete" action:@selector(deleteSelected) keyEquivalent:@"\b"];
        itemDel.image = AirSymbol(@"trash", 13.0f);
        itemDel.target = self;
        [menu addItem:itemDel];
    } else if (_copiedControls.count > 0) {
        [menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *itemPaste = [[NSMenuItem alloc] initWithTitle:@"Paste" action:@selector(pasteCopied) keyEquivalent:@"v"];
        itemPaste.image = AirSymbol(@"doc.on.clipboard", 13.0f);
        itemPaste.target = self;
        [menu addItem:itemPaste];
    }

    return menu;
}

- (void)onAddFader:(id)sender { [self addControlOfType:@"fader" orientation:@"vertical" atPoint:_lastRightClickPoint]; }
- (void)onAddHorizontalFader:(id)sender { [self addControlOfType:@"fader" orientation:@"horizontal" atPoint:_lastRightClickPoint]; }
- (void)onAddKnob:(id)sender { [self addControlOfType:@"knob" orientation:@"vertical" atPoint:_lastRightClickPoint]; }
- (void)onAddButton:(id)sender { [self addControlOfType:@"button" orientation:@"vertical" atPoint:_lastRightClickPoint]; }
- (void)onAddXYPad:(id)sender { [self addControlOfType:@"xypad" orientation:@"vertical" atPoint:_lastRightClickPoint]; }
- (void)onAddLabel:(id)sender { [self addControlOfType:@"label" orientation:@"vertical" atPoint:_lastRightClickPoint]; }

- (void)toggleSnapToGrid:(id)sender {
    self.snapToGrid = !self.snapToGrid;
    [self updateSnapButtonAppearance];
    [self setNeedsDisplay:YES];
}

#pragma mark - Undo & Redo System

- (NSArray<MidiControlModel *> *)currentControlsSnapshot {
    NSMutableArray *snap = [NSMutableArray arrayWithCapacity:self.layout.controls.count];
    for (MidiControlModel *m in self.layout.controls) {
        [snap addObject:[m copy]];
    }
    return snap;
}

- (void)pushSnapshot:(NSArray<MidiControlModel *> *)snapshot {
    if (!snapshot) return;
    if (!_undoStack) _undoStack = [NSMutableArray array];
    if (!_redoStack) _redoStack = [NSMutableArray array];
    [_undoStack addObject:snapshot];
    while (_undoStack.count > kMaxUndoSteps) {
        [_undoStack removeObjectAtIndex:0];
    }
    [_redoStack removeAllObjects];
}

- (void)pushUndoSnapshot {
    [self pushSnapshot:[self currentControlsSnapshot]];
}

- (void)undo {
    if (_undoStack.count == 0) return;
    NSArray *previous = _undoStack.lastObject;
    [_undoStack removeLastObject];

    if (!_redoStack) _redoStack = [NSMutableArray array];
    [_redoStack addObject:[self currentControlsSnapshot]];
    while (_redoStack.count > kMaxUndoSteps) {
        [_redoStack removeObjectAtIndex:0];
    }

    [self restoreControlsFromSnapshot:previous];
}

- (void)redo {
    if (_redoStack.count == 0) return;
    NSArray *next = _redoStack.lastObject;
    [_redoStack removeLastObject];

    if (!_undoStack) _undoStack = [NSMutableArray array];
    [_undoStack addObject:[self currentControlsSnapshot]];
    while (_undoStack.count > kMaxUndoSteps) {
        [_undoStack removeObjectAtIndex:0];
    }

    [self restoreControlsFromSnapshot:next];
}

- (void)restoreControlsFromSnapshot:(NSArray<MidiControlModel *> *)snapshot {
    [self.layout.controls removeAllObjects];
    NSMutableArray *prevSelectedIds = [NSMutableArray array];
    for (MidiControlModel *m in self.selectedControls) {
        if (m.controlId) [prevSelectedIds addObject:m.controlId];
    }

    NSMutableArray *newSelectedList = [NSMutableArray array];
    for (MidiControlModel *m in snapshot) {
        MidiControlModel *copy = [m copy];
        [self.layout.controls addObject:copy];
        if ([prevSelectedIds containsObject:copy.controlId]) {
            [newSelectedList addObject:copy];
        }
    }
    [self.selectedControls setArray:newSelectedList];
    [self.delegate canvasDidSelectControl:self.selectedControl];
    [self setNeedsDisplay:YES];
}

- (void)undo:(id)sender {
    [self undo];
}

- (void)redo:(id)sender {
    [self redo];
}

- (void)copy:(id)sender {
    [self copySelected];
}

- (void)paste:(id)sender {
    [self pasteCopied];
}

- (void)selectAll:(id)sender {
    [self selectAllControls];
}

- (void)deleteSelected:(id)sender {
    [self deleteSelected];
}

#pragma mark - Clipboard (Copy / Paste)

- (void)copySelected {
    if (self.selectedControls.count == 0) return;
    [_copiedControls removeAllObjects];
    for (MidiControlModel *m in self.selectedControls) {
        [_copiedControls addObject:[m copy]];
    }
}

- (void)pasteCopied {
    if (_copiedControls.count == 0) return;
    [self pushUndoSnapshot];

    CGFloat offset = self.snapToGrid ? 20.0f : 15.0f;
    NSMutableArray *newSelection = [NSMutableArray array];
    for (MidiControlModel *orig in _copiedControls) {
        MidiControlModel *copy = [orig copy];
        copy.controlId = [NSString stringWithFormat:@"%@_%u", copy.type, arc4random() % 10000];
        copy.label = [copy.label stringByAppendingString:@" Copy"];
        copy.frame = NSOffsetRect(copy.frame, offset, offset);
        if (copy.midiNumber < 127) copy.midiNumber += 1;
        [self.layout.controls addObject:copy];
        [newSelection addObject:copy];
    }
    [self.selectedControls setArray:newSelection];
    [self.delegate canvasDidSelectControl:self.selectedControl];
    [self setNeedsDisplay:YES];
}

- (void)addControlOfTypeAtCenter:(NSString *)type {
    if ([type isEqualToString:@"xy"]) type = @"xypad";
    CGFloat devW = self.layout.canvasWidth > 0 ? self.layout.canvasWidth : 920.0f;
    CGFloat devH = self.layout.canvasHeight > 0 ? self.layout.canvasHeight : 460.0f;

    CGFloat w = [type isEqualToString:@"fader"] ? 78 : [type isEqualToString:@"knob"] ? 130 : [type isEqualToString:@"button"] ? 110 : [type isEqualToString:@"xypad"] ? 180 : 150;
    CGFloat h = [type isEqualToString:@"fader"] ? 380 : [type isEqualToString:@"knob"] ? 150 : [type isEqualToString:@"button"] ? 110 : [type isEqualToString:@"xypad"] ? 180 : 36;

    // Stagger slightly if controls exist
    CGFloat cx = (devW - w) / 2.0f + (self.layout.controls.count % 5) * 20.0f;
    CGFloat cy = (devH - h) / 2.0f + (self.layout.controls.count % 4) * 20.0f;

    [self addControlOfType:type orientation:@"vertical" atPoint:NSMakePoint(cx, cy)];
}

- (void)addControlOfType:(NSString *)type atPoint:(NSPoint)pt {
    [self addControlOfType:type orientation:@"vertical" atPoint:pt];
}

- (void)addControlOfType:(NSString *)type orientation:(NSString *)orientation atPoint:(NSPoint)pt {
    [self pushUndoSnapshot];

    if ([type isEqualToString:@"xy"]) type = @"xypad";
    MidiControlModel *m = [[MidiControlModel alloc] init];
    m.controlId = [NSString stringWithFormat:@"%@_%u", type, arc4random() % 10000];
    m.type = type;
    m.orientation = orientation ?: @"vertical";
    m.knobStyle = @"standard";
    m.label = [type.uppercaseString stringByAppendingFormat:@" %lu", (unsigned long)self.layout.controls.count + 1];

    BOOL isHoriz = [m.orientation isEqualToString:@"horizontal"];
    CGFloat w = [type isEqualToString:@"fader"] ? (isHoriz ? 320 : 78) : [type isEqualToString:@"knob"] ? 130 : [type isEqualToString:@"button"] ? 110 : [type isEqualToString:@"xypad"] ? 180 : 150;
    CGFloat h = [type isEqualToString:@"fader"] ? (isHoriz ? 78 : 380) : [type isEqualToString:@"knob"] ? 150 : [type isEqualToString:@"button"] ? 110 : [type isEqualToString:@"xypad"] ? 180 : 36;

    // Snap point to 20px
    CGFloat snappedX = round(pt.x / 20.0f) * 20.0f;
    CGFloat snappedY = round(pt.y / 20.0f) * 20.0f;
    m.frame = NSMakeRect(snappedX, snappedY, w, h);

    m.color = [NSColor colorWithCalibratedRed:0.0f green:0.45f blue:0.5f alpha:1.0f];
    m.accentColor = [NSColor colorWithCalibratedRed:0.0f green:0.8f blue:1.0f alpha:1.0f];
    m.midiChannel = 1;
    m.midiType = [type isEqualToString:@"button"] ? @"note" : @"cc";
    m.midiNumber = 20 + (NSInteger)self.layout.controls.count;
    m.minValue = 0;
    m.maxValue = 127;
    m.value = 64;

    if ([type isEqualToString:@"fader"]) {
        m.hasLabel = YES;
        m.labelPosition = @"top";
    } else if ([type isEqualToString:@"knob"]) {
        m.hasLabel = YES;
        m.labelPosition = @"bottom";
    } else if ([type isEqualToString:@"button"]) {
        m.shape = @"square";
        m.mode = @"momentary";
    }

    [self.layout.controls addObject:m];
    self.selectedControl = m;
    [self.delegate canvasDidSelectControl:m];
    [self setNeedsDisplay:YES];
}

- (void)duplicateSelected {
    if (self.selectedControls.count == 0) return;
    [self pushUndoSnapshot];

    CGFloat offset = self.snapToGrid ? 20.0f : 15.0f;
    NSMutableArray *newSelection = [NSMutableArray array];

    for (MidiControlModel *orig in self.selectedControls) {
        MidiControlModel *copy = [orig copy];
        copy.controlId = [NSString stringWithFormat:@"%@_%u", copy.type, arc4random() % 10000];
        copy.label = [copy.label stringByAppendingString:@" Copy"];
        copy.frame = NSOffsetRect(copy.frame, offset, offset);
        if (copy.midiNumber < 127) copy.midiNumber += 1;

        [self.layout.controls addObject:copy];
        [newSelection addObject:copy];
    }

    [self.selectedControls setArray:newSelection];
    [self.delegate canvasDidSelectControl:self.selectedControl];
    [self setNeedsDisplay:YES];
}

- (void)deleteSelected {
    if (self.selectedControls.count == 0) return;
    [self pushUndoSnapshot];

    NSArray *toDelete = [self.selectedControls copy];
    [self.selectedControls removeAllObjects];
    for (MidiControlModel *target in toDelete) {
        [self.layout.controls removeObject:target];
    }
    [self.delegate canvasDidDeleteControl:nil];
    [self setNeedsDisplay:YES];
}

- (void)bringSelectedToFront {
    if (self.selectedControls.count == 0) return;
    [self pushUndoSnapshot];

    NSArray *selected = [self.selectedControls copy];
    for (MidiControlModel *m in selected) {
        [self.layout.controls removeObject:m];
        [self.layout.controls addObject:m];
    }
    [self setNeedsDisplay:YES];
}

- (void)sendSelectedToBack {
    if (self.selectedControls.count == 0) return;
    [self pushUndoSnapshot];

    NSArray *selected = [self.selectedControls copy];
    for (NSInteger i = (NSInteger)selected.count - 1; i >= 0; i--) {
        MidiControlModel *m = selected[i];
        [self.layout.controls removeObject:m];
        [self.layout.controls insertObject:m atIndex:0];
    }
    [self setNeedsDisplay:YES];
}

@end
