#import "InspectorView.h"
#import "AirTheme.h"

@interface AirFlippedView : NSView
@end

@implementation AirFlippedView
- (BOOL)isFlipped { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
@end

@interface InspectorView () <NSTextFieldDelegate>
@end

@implementation InspectorView {
    NSVisualEffectView *_visualEffect;
    NSScrollView *_scrollView;
    AirFlippedView *_contentContainer;
    AirFlippedView *_emptyStateView;

    // Header Badge & Name
    NSView *_badgeRow;
    NSView *_colorDot;
    NSTextField *_badgeLabel;
    NSTextField *_labelField;

    NSTextField *_appearanceHeader;
    NSButton *_showLabelCheckbox;
    NSTextField *_labelPosLabel;
    NSSegmentedControl *_labelPosSegment;
    NSTextField *_fontSizeLabel;
    NSSlider *_fontSizeSlider;
    NSTextField *_buttonShapeLabel;
    NSSegmentedControl *_buttonShapeSegment;
    NSButton *_labelBgCheckbox;

    // Knob & Fader specific options
    NSTextField *_knobStyleLabel;
    NSSegmentedControl *_knobStyleSegment;
    NSTextField *_faderOrientationLabel;
    NSSegmentedControl *_faderOrientationSegment;
    NSTextField *_faderStyleLabel;
    NSSegmentedControl *_faderStyleSegment;

    NSTextField *_colorLabel;
    NSColorWell *_colorWell;

    // MIDI Mapping Section
    NSTextField *_midiHeader;
    NSTextField *_channelLabel;
    NSTextField *_midiTypeLabel;
    NSPopUpButton *_channelPopup;
    NSPopUpButton *_midiTypePopup;
    NSTextField *_midiNumLabel;
    NSTextField *_midiNumberField;
    NSTextField *_buttonModeLabel;
    NSSegmentedControl *_buttonModeSegment;

    // MIDI Range
    NSTextField *_rangeMinLabel;
    NSTextField *_rangeMaxLabel;
    NSTextField *_minValField;
    NSTextField *_maxValField;

    // Position & Size Section
    NSTextField *_posHeader;
    NSTextField *_xLabel;
    NSTextField *_yLabel;
    NSTextField *_wLabel;
    NSTextField *_hLabel;
    NSTextField *_xField;
    NSTextField *_yField;
    NSTextField *_wField;
    NSTextField *_hField;

    // Actions
    NSButton *_btnDuplicate;
    NSButton *_btnDelete;

    BOOL _updatingUI;
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
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    [self setWantsLayer:YES];

    // 1. Frosted Sidebar Material
    _visualEffect = [[NSVisualEffectView alloc] initWithFrame:self.bounds];
    _visualEffect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _visualEffect.material = NSVisualEffectMaterialSidebar;
    _visualEffect.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    _visualEffect.state = NSVisualEffectStateActive;
    [self addSubview:_visualEffect];

    // 2. Empty State View (Shown strictly when nothing is selected)
    _emptyStateView = [[AirFlippedView alloc] initWithFrame:self.bounds];
    _emptyStateView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    CGFloat emptyMidY = self.bounds.size.height / 2.0f - 60.0f;
    NSImageView *emptyIcon = [[NSImageView alloc] initWithFrame:NSMakeRect((self.bounds.size.width - 48) / 2.0f, emptyMidY, 48, 48)];
    emptyIcon.autoresizingMask = NSViewMinXMargin | NSViewMaxXMargin | NSViewMinYMargin | NSViewMaxYMargin;
    emptyIcon.image = AirSymbol(@"slider.vertical.3", 34.0f);
    emptyIcon.contentTintColor = [NSColor colorWithCalibratedWhite:0.35f alpha:1.0f];
    [_emptyStateView addSubview:emptyIcon];

    NSTextField *emptyTitle = [self createLabel:@"No Selection" frame:NSMakeRect(20, emptyMidY + 54.0f, self.bounds.size.width - 40, 20) bold:YES];
    emptyTitle.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    emptyTitle.alignment = NSTextAlignmentCenter;
    emptyTitle.font = [NSFont systemFontOfSize:13.5f weight:NSFontWeightSemibold];
    emptyTitle.textColor = AirColorTextSecondary();
    [_emptyStateView addSubview:emptyTitle];

    NSTextField *emptySub = [self createLabel:@"Select a control on canvas to inspect MIDI mapping and properties, or right-click canvas to add."
                                        frame:NSMakeRect(28, emptyMidY + 78.0f, self.bounds.size.width - 56, 50) bold:NO];
    emptySub.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    emptySub.alignment = NSTextAlignmentCenter;
    emptySub.font = [NSFont systemFontOfSize:11.0f];
    emptySub.textColor = AirColorTextMuted();
    [_emptyStateView addSubview:emptySub];

    [self addSubview:_emptyStateView];

    // 3. ScrollView for Inspector fields (hidden by default when no control is selected)
    _scrollView = [[NSScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.hasVerticalScroller = YES;
    _scrollView.autohidesScrollers = YES;
    _scrollView.drawsBackground = NO;
    _scrollView.hidden = YES;

    _contentContainer = [[AirFlippedView alloc] initWithFrame:NSMakeRect(0, 0, self.bounds.size.width, 600.0f)];
    _contentContainer.autoresizingMask = NSViewWidthSizable;
    _scrollView.documentView = _contentContainer;
    [self addSubview:_scrollView];

    // Build Subviews inside _contentContainer
    CGFloat pad = 16.0f;
    CGFloat w = self.bounds.size.width - (pad * 2);
    CGFloat halfW = (w - 10.0f) / 2.0f;

    // Header: Type Badge & Colored Dot
    _badgeRow = [[NSView alloc] initWithFrame:NSMakeRect(pad, 16, w, 24)];
    _colorDot = [[NSView alloc] initWithFrame:NSMakeRect(2, 6, 10, 10)];
    [_colorDot setWantsLayer:YES];
    _colorDot.layer.cornerRadius = 5.0f;
    _colorDot.layer.backgroundColor = AirColorAccent().CGColor;
    [_badgeRow addSubview:_colorDot];

    _badgeLabel = [self createLabel:@"CONTROL PROPERTIES" frame:NSMakeRect(18, 2, w - 20, 18) bold:YES];
    _badgeLabel.font = [NSFont systemFontOfSize:11.0f weight:NSFontWeightBold];
    _badgeLabel.textColor = AirColorAccent();
    [_badgeRow addSubview:_badgeLabel];
    [_contentContainer addSubview:_badgeRow];

    // Label Name Field
    _labelField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad, 44, w, 28)];
    _labelField.delegate = self;
    _labelField.target = self;
    _labelField.action = @selector(onFieldChanged:);
    _labelField.font = [NSFont systemFontOfSize:13.0f weight:NSFontWeightMedium];
    _labelField.focusRingType = NSFocusRingTypeNone;
    [_contentContainer addSubview:_labelField];

    // Appearance Section Header
    _appearanceHeader = [self createSectionHeader:@"APPEARANCE & STYLE" frame:NSMakeRect(pad, 80, w, 16)];
    [_contentContainer addSubview:_appearanceHeader];

    // Show Label Checkbox (fader & knob)
    _showLabelCheckbox = [NSButton checkboxWithTitle:@"Show Label Header" target:self action:@selector(onShowLabelToggled:)];
    _showLabelCheckbox.frame = NSMakeRect(pad, 104, w, 18);
    [_contentContainer addSubview:_showLabelCheckbox];

    // Label Position Segment (Top / Bottom)
    _labelPosLabel = [self createLabel:@"Label Position" frame:NSMakeRect(pad, 128, halfW, 14) bold:NO];
    [_contentContainer addSubview:_labelPosLabel];
    _labelPosSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Top", @"Bottom"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(onLabelPosChanged:)];
    _labelPosSegment.frame = NSMakeRect(pad + halfW + 10, 124, halfW, 24);
    _labelPosSegment.segmentStyle = NSSegmentStyleTexturedRounded;
    _labelPosSegment.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    [_contentContainer addSubview:_labelPosSegment];

    // Font Size Slider
    _fontSizeLabel = [self createLabel:@"Font Size: Auto" frame:NSMakeRect(pad, 154, halfW, 14) bold:NO];
    [_contentContainer addSubview:_fontSizeLabel];
    _fontSizeSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(pad + halfW + 10, 150, halfW, 20)];
    _fontSizeSlider.minValue = 0;
    _fontSizeSlider.maxValue = 32;
    _fontSizeSlider.target = self;
    _fontSizeSlider.action = @selector(onFontSizeChanged:);
    [_contentContainer addSubview:_fontSizeSlider];

    // Button Shape Segment (Square / Circle)
    _buttonShapeLabel = [self createLabel:@"Button Shape" frame:NSMakeRect(pad, 104, w, 14) bold:NO];
    [_contentContainer addSubview:_buttonShapeLabel];
    _buttonShapeSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Square", @"Circle (LED)"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(onButtonShapeChanged:)];
    _buttonShapeSegment.frame = NSMakeRect(pad, 122, w, 24);
    _buttonShapeSegment.segmentStyle = NSSegmentStyleTexturedRounded;
    _buttonShapeSegment.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    [_contentContainer addSubview:_buttonShapeSegment];

    // Label Capsule Background (Text Label)
    _labelBgCheckbox = [NSButton checkboxWithTitle:@"Capsule Background" target:self action:@selector(onLabelBgToggled:)];
    _labelBgCheckbox.frame = NSMakeRect(pad, 104, w, 18);
    [_contentContainer addSubview:_labelBgCheckbox];

    // Fader Orientation Segment (Vertical / Horizontal)
    _faderOrientationLabel = [self createLabel:@"Orientation" frame:NSMakeRect(pad, 104, w, 14) bold:NO];
    [_contentContainer addSubview:_faderOrientationLabel];
    _faderOrientationSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Vertical", @"Horizontal"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(onFaderOrientationChanged:)];
    _faderOrientationSegment.frame = NSMakeRect(pad, 122, w, 24);
    _faderOrientationSegment.segmentStyle = NSSegmentStyleTexturedRounded;
    _faderOrientationSegment.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    [_contentContainer addSubview:_faderOrientationSegment];

    // Fader Style Segment (Standard / Inverted / Centered)
    _faderStyleLabel = [self createLabel:@"Fader Behavior" frame:NSMakeRect(pad, 104, w, 14) bold:NO];
    [_contentContainer addSubview:_faderStyleLabel];
    _faderStyleSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Standard", @"Inverted", @"Centered"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(onFaderStyleChanged:)];
    _faderStyleSegment.frame = NSMakeRect(pad, 122, w, 24);
    _faderStyleSegment.segmentStyle = NSSegmentStyleTexturedRounded;
    _faderStyleSegment.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    [_contentContainer addSubview:_faderStyleSegment];

    // Knob Style Segment (Standard / Inverted / Centered)
    _knobStyleLabel = [self createLabel:@"Knob Behavior" frame:NSMakeRect(pad, 104, w, 14) bold:NO];
    [_contentContainer addSubview:_knobStyleLabel];
    _knobStyleSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Standard", @"Inverted", @"Centered"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(onKnobStyleChanged:)];
    _knobStyleSegment.frame = NSMakeRect(pad, 122, w, 24);
    _knobStyleSegment.segmentStyle = NSSegmentStyleTexturedRounded;
    _knobStyleSegment.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    [_contentContainer addSubview:_knobStyleSegment];

    // Single Color Picker (Gradients & Glows derived automatically)
    _colorLabel = [self createLabel:@"Control Color" frame:NSMakeRect(pad, 178, w, 14) bold:NO];
    [_contentContainer addSubview:_colorLabel];

    _colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(pad, 196, w, 28)];
    _colorWell.target = self;
    _colorWell.action = @selector(onColorChanged:);
    [_contentContainer addSubview:_colorWell];

    // MIDI Mapping Section Header
    _midiHeader = [self createSectionHeader:@"MIDI MAPPING" frame:NSMakeRect(pad, 214, w, 16)];
    [_contentContainer addSubview:_midiHeader];

    _channelLabel = [self createLabel:@"Channel" frame:NSMakeRect(pad, 234, halfW, 14) bold:NO];
    [_contentContainer addSubview:_channelLabel];
    _midiTypeLabel = [self createLabel:@"Message Type" frame:NSMakeRect(pad + halfW + 10, 234, halfW, 14) bold:NO];
    [_contentContainer addSubview:_midiTypeLabel];

    _channelPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(pad, 252, halfW, 26) pullsDown:NO];
    for (int ch = 1; ch <= 16; ch++) {
        [_channelPopup addItemWithTitle:[NSString stringWithFormat:@"Ch %d", ch]];
    }
    _channelPopup.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    _channelPopup.target = self;
    _channelPopup.action = @selector(onChannelChanged:);
    [_contentContainer addSubview:_channelPopup];

    _midiTypePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(pad + halfW + 10, 252, halfW, 26) pullsDown:NO];
    [_midiTypePopup addItemsWithTitles:@[@"Control (CC)", @"Note", @"Pitch Bend"]];
    _midiTypePopup.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    _midiTypePopup.target = self;
    _midiTypePopup.action = @selector(onMidiTypeChanged:);
    [_contentContainer addSubview:_midiTypePopup];

    _midiNumLabel = [self createLabel:@"CC / Note Number" frame:NSMakeRect(pad, 286, halfW, 14) bold:NO];
    [_contentContainer addSubview:_midiNumLabel];
    _midiNumberField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad, 304, halfW, 24)];
    _midiNumberField.target = self;
    _midiNumberField.action = @selector(onFieldChanged:);
    [_contentContainer addSubview:_midiNumberField];

    _buttonModeLabel = [self createLabel:@"Trigger Mode" frame:NSMakeRect(pad, 336, w, 14) bold:NO];
    [_contentContainer addSubview:_buttonModeLabel];
    _buttonModeSegment = [NSSegmentedControl segmentedControlWithLabels:@[@"Momentary", @"Toggle"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(onButtonModeChanged:)];
    _buttonModeSegment.frame = NSMakeRect(pad, 354, w, 24);
    _buttonModeSegment.segmentStyle = NSSegmentStyleTexturedRounded;
    _buttonModeSegment.font = [NSFont systemFontOfSize:11.5f weight:NSFontWeightMedium];
    [_contentContainer addSubview:_buttonModeSegment];

    // MIDI Range (0 - 127)
    _rangeMinLabel = [self createLabel:@"Min Value (0-127)" frame:NSMakeRect(pad, 384, halfW, 14) bold:NO];
    [_contentContainer addSubview:_rangeMinLabel];
    _rangeMaxLabel = [self createLabel:@"Max Value (0-127)" frame:NSMakeRect(pad + halfW + 10, 384, halfW, 14) bold:NO];
    [_contentContainer addSubview:_rangeMaxLabel];

    _minValField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad, 402, halfW, 24)];
    _minValField.target = self;
    _minValField.action = @selector(onRangeChanged:);
    [_contentContainer addSubview:_minValField];

    _maxValField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad + halfW + 10, 402, halfW, 24)];
    _maxValField.target = self;
    _maxValField.action = @selector(onRangeChanged:);
    [_contentContainer addSubview:_maxValField];

    // Position & Size Section Header
    _posHeader = [self createSectionHeader:@"POSITION & SIZE" frame:NSMakeRect(pad, 342, w, 16)];
    [_contentContainer addSubview:_posHeader];

    CGFloat qW = (w - 15.0f) / 4.0f;
    _xLabel = [self createLabel:@"X" frame:NSMakeRect(pad, 362, qW, 12) bold:NO];
    _yLabel = [self createLabel:@"Y" frame:NSMakeRect(pad + (qW + 5), 362, qW, 12) bold:NO];
    _wLabel = [self createLabel:@"Width" frame:NSMakeRect(pad + (qW + 5) * 2, 362, qW, 12) bold:NO];
    _hLabel = [self createLabel:@"Height" frame:NSMakeRect(pad + (qW + 5) * 3, 362, qW, 12) bold:NO];
    [_contentContainer addSubview:_xLabel];
    [_contentContainer addSubview:_yLabel];
    [_contentContainer addSubview:_wLabel];
    [_contentContainer addSubview:_hLabel];

    _xField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad, 378, qW, 22)];
    _xField.target = self; _xField.action = @selector(onFrameFieldChanged:);
    [_contentContainer addSubview:_xField];

    _yField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad + (qW + 5), 378, qW, 22)];
    _yField.target = self; _yField.action = @selector(onFrameFieldChanged:);
    [_contentContainer addSubview:_yField];

    _wField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad + (qW + 5) * 2, 378, qW, 22)];
    _wField.target = self; _wField.action = @selector(onFrameFieldChanged:);
    [_contentContainer addSubview:_wField];

    _hField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad + (qW + 5) * 3, 378, qW, 22)];
    _hField.target = self; _hField.action = @selector(onFrameFieldChanged:);
    [_contentContainer addSubview:_hField];

    // Action Buttons
    _btnDuplicate = [[NSButton alloc] initWithFrame:NSMakeRect(pad, 416, halfW, 30)];
    _btnDuplicate.title = @"Duplicate";
    _btnDuplicate.image = AirSymbol(@"plus.square.on.square", 12.0f);
    _btnDuplicate.imagePosition = NSImageLeading;
    _btnDuplicate.bezelStyle = NSBezelStyleRounded;
    _btnDuplicate.target = self;
    _btnDuplicate.action = @selector(onDuplicateClicked:);
    [_contentContainer addSubview:_btnDuplicate];

    _btnDelete = [[NSButton alloc] initWithFrame:NSMakeRect(pad + halfW + 10, 416, halfW, 30)];
    _btnDelete.title = @"Delete";
    _btnDelete.image = AirSymbol(@"trash", 12.0f);
    _btnDelete.imagePosition = NSImageLeading;
    _btnDelete.bezelStyle = NSBezelStyleRounded;
    _btnDelete.target = self;
    _btnDelete.action = @selector(onDeleteClicked:);
    [_contentContainer addSubview:_btnDelete];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    // Left Hairline Divider
    [AirColorBorder() setStroke];
    NSBezierPath *divider = [NSBezierPath bezierPath];
    [divider moveToPoint:NSMakePoint(0, 0)];
    [divider lineToPoint:NSMakePoint(0, self.bounds.size.height)];
    [divider setLineWidth:1.0f];
    [divider stroke];
}

- (NSTextField *)createLabel:(NSString *)text frame:(NSRect)frame bold:(BOOL)bold {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text;
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = bold ? [NSFont systemFontOfSize:11.0f weight:NSFontWeightBold] : [NSFont systemFontOfSize:11.0f];
    label.textColor = AirColorTextSecondary();
    return label;
}

- (NSTextField *)createSectionHeader:(NSString *)title frame:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = title;
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = [NSFont systemFontOfSize:10.0f weight:NSFontWeightBold];
    label.textColor = AirColorTextMuted();
    return label;
}

- (void)bindControl:(MidiControlModel *)control {
    _currentControl = control;
    if (!control) {
        _emptyStateView.hidden = NO;
        _scrollView.hidden = YES;
        return;
    }

    _emptyStateView.hidden = YES;
    _scrollView.hidden = NO;
    [_scrollView.contentView scrollToPoint:NSMakePoint(0, 0)];

    [self refreshValues];
}

- (void)refreshValues {
    if (!_currentControl) return;
    _updatingUI = YES;

    NSString *typeDesc = _currentControl.type.uppercaseString;
    _badgeLabel.stringValue = [NSString stringWithFormat:@"%@ • %@", typeDesc, _currentControl.label ?: @""];
    _colorDot.layer.backgroundColor = _currentControl.color.CGColor ?: AirColorAccent().CGColor;

    _labelField.stringValue = _currentControl.label ?: @"";

    NSInteger chIdx = MAX(0, MIN(15, _currentControl.midiChannel - 1));
    [_channelPopup selectItemAtIndex:chIdx];

    if ([_currentControl.midiType isEqualToString:@"cc"]) [_midiTypePopup selectItemAtIndex:0];
    else if ([_currentControl.midiType isEqualToString:@"note"]) [_midiTypePopup selectItemAtIndex:1];
    else [_midiTypePopup selectItemAtIndex:2];

    _midiNumberField.integerValue = _currentControl.midiNumber;

    if ([_currentControl.mode isEqualToString:@"toggle"]) {
        _buttonModeSegment.selectedSegment = 1;
    } else {
        _buttonModeSegment.selectedSegment = 0;
    }

    _colorWell.color = _currentControl.color ?: AirColorAccent();

    _xField.integerValue = round(_currentControl.frame.origin.x);
    _yField.integerValue = round(_currentControl.frame.origin.y);
    _wField.integerValue = round(_currentControl.frame.size.width);
    _hField.integerValue = round(_currentControl.frame.size.height);

    // Appearance values
    _showLabelCheckbox.state = _currentControl.hasLabel ? NSControlStateValueOn : NSControlStateValueOff;
    _labelPosSegment.selectedSegment = [_currentControl.labelPosition isEqualToString:@"bottom"] ? 1 : 0;
    _fontSizeSlider.doubleValue = _currentControl.fontSize;
    _fontSizeLabel.stringValue = (_currentControl.fontSize > 0) ? [NSString stringWithFormat:@"Font Size: %d pt", (int)_currentControl.fontSize] : @"Font Size: Auto";
    _buttonShapeSegment.selectedSegment = [_currentControl.shape isEqualToString:@"circle"] ? 1 : 0;
    _labelBgCheckbox.state = _currentControl.hasBackground ? NSControlStateValueOn : NSControlStateValueOff;

    // Fader & Knob behaviors
    _faderOrientationSegment.selectedSegment = [_currentControl.orientation isEqualToString:@"horizontal"] ? 1 : 0;
    if ([_currentControl.faderStyle isEqualToString:@"inverted"]) {
        _faderStyleSegment.selectedSegment = 1;
    } else if ([_currentControl.faderStyle isEqualToString:@"centered"]) {
        _faderStyleSegment.selectedSegment = 2;
    } else {
        _faderStyleSegment.selectedSegment = 0;
    }

    if ([_currentControl.knobStyle isEqualToString:@"inverted"]) {
        _knobStyleSegment.selectedSegment = 1;
    } else if ([_currentControl.knobStyle isEqualToString:@"centered"]) {
        _knobStyleSegment.selectedSegment = 2;
    } else {
        _knobStyleSegment.selectedSegment = 0;
    }

    // MIDI Range
    _minValField.integerValue = _currentControl.minValue;
    _maxValField.integerValue = _currentControl.maxValue;

    // Relayout fields dynamically based on control type
    [self layoutFieldsForControl:_currentControl];

    _updatingUI = NO;
}

- (void)layoutFieldsForControl:(MidiControlModel *)ctrl {
    CGFloat pad = 16.0f;
    CGFloat w = self.bounds.size.width - (pad * 2);
    CGFloat halfW = (w - 10.0f) / 2.0f;
    CGFloat y = 80.0f;

    _appearanceHeader.frame = NSMakeRect(pad, y, w, 16);
    y += 22.0f;

    BOOL isFader = [ctrl.type isEqualToString:@"fader"];
    BOOL isKnob = [ctrl.type isEqualToString:@"knob"];
    BOOL isButton = [ctrl.type isEqualToString:@"button"];
    BOOL isLabel = [ctrl.type isEqualToString:@"label"];

    // 1. Controls specific to Fader / Knob
    if (isFader || isKnob) {
        _showLabelCheckbox.hidden = NO;
        _showLabelCheckbox.title = isFader ? @"Show Label Header" : @"Show Label";
        _showLabelCheckbox.frame = NSMakeRect(pad, y, w, 18);
        y += 24.0f;

        if (ctrl.hasLabel) {
            _labelPosLabel.hidden = NO;
            _labelPosSegment.hidden = NO;
            _labelPosLabel.frame = NSMakeRect(pad, y + 4, halfW, 14);
            _labelPosSegment.frame = NSMakeRect(pad + halfW + 10, y, halfW, 24);
            y += 30.0f;
        } else {
            _labelPosLabel.hidden = YES;
            _labelPosSegment.hidden = YES;
        }
    } else {
        _showLabelCheckbox.hidden = YES;
        _labelPosLabel.hidden = YES;
        _labelPosSegment.hidden = YES;
    }

    // Font Size Slider (Labels and labeled controls)
    if (isLabel || ctrl.hasLabel || isButton) {
        _fontSizeLabel.hidden = NO;
        _fontSizeSlider.hidden = NO;
        _fontSizeLabel.frame = NSMakeRect(pad, y + 4, halfW, 14);
        _fontSizeSlider.frame = NSMakeRect(pad + halfW + 10, y, halfW, 20);
        y += 28.0f;
    } else {
        _fontSizeLabel.hidden = YES;
        _fontSizeSlider.hidden = YES;
    }

    // 2. Controls specific to Button
    if (isButton) {
        _buttonShapeLabel.hidden = NO;
        _buttonShapeSegment.hidden = NO;
        _buttonShapeLabel.frame = NSMakeRect(pad, y, w, 14);
        y += 18.0f;
        _buttonShapeSegment.frame = NSMakeRect(pad, y, w, 24);
        y += 32.0f;
    } else {
        _buttonShapeLabel.hidden = YES;
        _buttonShapeSegment.hidden = YES;
    }

    // Controls specific to Fader (Orientation & Style)
    if (isFader) {
        _faderOrientationLabel.hidden = NO;
        _faderOrientationSegment.hidden = NO;
        _faderOrientationLabel.frame = NSMakeRect(pad, y, w, 14);
        y += 18.0f;
        _faderOrientationSegment.frame = NSMakeRect(pad, y, w, 24);
        y += 30.0f;

        _faderStyleLabel.hidden = NO;
        _faderStyleSegment.hidden = NO;
        _faderStyleLabel.frame = NSMakeRect(pad, y, w, 14);
        y += 18.0f;
        _faderStyleSegment.frame = NSMakeRect(pad, y, w, 24);
        y += 32.0f;
    } else {
        _faderOrientationLabel.hidden = YES;
        _faderOrientationSegment.hidden = YES;
        _faderStyleLabel.hidden = YES;
        _faderStyleSegment.hidden = YES;
    }

    // Controls specific to Knob (Behavior / Style)
    if (isKnob) {
        _knobStyleLabel.hidden = NO;
        _knobStyleSegment.hidden = NO;
        _knobStyleLabel.frame = NSMakeRect(pad, y, w, 14);
        y += 18.0f;
        _knobStyleSegment.frame = NSMakeRect(pad, y, w, 24);
        y += 32.0f;
    } else {
        _knobStyleLabel.hidden = YES;
        _knobStyleSegment.hidden = YES;
    }

    // 3. Controls specific to Label
    if (isLabel) {
        _labelBgCheckbox.hidden = NO;
        _labelBgCheckbox.frame = NSMakeRect(pad, y, w, 18);
        y += 24.0f;
    } else {
        _labelBgCheckbox.hidden = YES;
    }

    // Single Color Picker (Glows & Gradients derived automatically)
    _colorLabel.frame = NSMakeRect(pad, y, w, 14);
    y += 18.0f;
    _colorWell.frame = NSMakeRect(pad, y, w, 28);
    y += 36.0f;

    // MIDI Section
    BOOL hasMidi = !isLabel;
    _midiHeader.hidden = !hasMidi;
    _channelLabel.hidden = !hasMidi;
    _midiTypeLabel.hidden = !hasMidi;
    _channelPopup.hidden = !hasMidi;
    _midiTypePopup.hidden = !hasMidi;
    _midiNumLabel.hidden = !hasMidi;
    _midiNumberField.hidden = !hasMidi;
    _buttonModeLabel.hidden = !(isButton);
    _buttonModeSegment.hidden = !(isButton);
    _rangeMinLabel.hidden = !hasMidi;
    _rangeMaxLabel.hidden = !hasMidi;
    _minValField.hidden = !hasMidi;
    _maxValField.hidden = !hasMidi;

    if (hasMidi) {
        _midiHeader.frame = NSMakeRect(pad, y, w, 16);
        y += 20.0f;

        _channelLabel.frame = NSMakeRect(pad, y, halfW, 14);
        _midiTypeLabel.frame = NSMakeRect(pad + halfW + 10, y, halfW, 14);
        y += 18.0f;

        _channelPopup.frame = NSMakeRect(pad, y, halfW, 26);
        _midiTypePopup.frame = NSMakeRect(pad + halfW + 10, y, halfW, 26);
        y += 34.0f;

        if (isButton) {
            _midiNumLabel.stringValue = @"Note Number";
            _midiNumLabel.frame = NSMakeRect(pad, y, halfW, 14);
            y += 18.0f;
            _midiNumberField.frame = NSMakeRect(pad, y, halfW, 24);
            y += 32.0f;

            _buttonModeLabel.frame = NSMakeRect(pad, y, w, 14);
            y += 18.0f;
            _buttonModeSegment.frame = NSMakeRect(pad, y, w, 24);
            y += 34.0f;
        } else {
            _midiNumLabel.stringValue = @"CC Number";
            _midiNumLabel.frame = NSMakeRect(pad, y, halfW, 14);
            y += 18.0f;
            _midiNumberField.frame = NSMakeRect(pad, y, halfW, 24);
            y += 34.0f;
        }

        // MIDI Range (0 - 127)
        _rangeMinLabel.frame = NSMakeRect(pad, y, halfW, 14);
        _rangeMaxLabel.frame = NSMakeRect(pad + halfW + 10, y, halfW, 14);
        y += 18.0f;

        _minValField.frame = NSMakeRect(pad, y, halfW, 24);
        _maxValField.frame = NSMakeRect(pad + halfW + 10, y, halfW, 24);
        y += 34.0f;
    }

    // Position & Size Section
    _posHeader.frame = NSMakeRect(pad, y, w, 16);
    y += 20.0f;

    CGFloat qW = (w - 15.0f) / 4.0f;
    _xLabel.frame = NSMakeRect(pad, y, qW, 12);
    _yLabel.frame = NSMakeRect(pad + (qW + 5), y, qW, 12);
    _wLabel.frame = NSMakeRect(pad + (qW + 5) * 2, y, qW, 12);
    _hLabel.frame = NSMakeRect(pad + (qW + 5) * 3, y, qW, 12);
    y += 16.0f;

    _xField.frame = NSMakeRect(pad, y, qW, 22);
    _yField.frame = NSMakeRect(pad + (qW + 5), y, qW, 22);
    _wField.frame = NSMakeRect(pad + (qW + 5) * 2, y, qW, 22);
    _hField.frame = NSMakeRect(pad + (qW + 5) * 3, y, qW, 22);
    y += 38.0f;

    // Actions
    _btnDuplicate.frame = NSMakeRect(pad, y, halfW, 30);
    _btnDelete.frame = NSMakeRect(pad + halfW + 10, y, halfW, 30);
    y += 44.0f;

    // Update container height
    _contentContainer.frame = NSMakeRect(0, 0, self.bounds.size.width, MAX(y, self.bounds.size.height));
}

- (void)notifyWillChange {
    if (_updatingUI || !_currentControl) return;
    if ([self.delegate respondsToSelector:@selector(inspectorWillChangeControl:)]) {
        [self.delegate inspectorWillChangeControl:_currentControl];
    }
}

- (void)controlTextDidBeginEditing:(NSNotification *)obj {
    [self notifyWillChange];
}

- (void)controlTextDidChange:(NSNotification *)obj {
    if (_updatingUI || !_currentControl) return;
    if (obj.object == _labelField) {
        _currentControl.label = _labelField.stringValue;
        _badgeLabel.stringValue = [NSString stringWithFormat:@"%@ • %@", _currentControl.type.uppercaseString, _currentControl.label];
        [self.delegate inspectorDidUpdateControl:_currentControl];
    }
}

- (void)onShowLabelToggled:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    _currentControl.hasLabel = (_showLabelCheckbox.state == NSControlStateValueOn);
    [self layoutFieldsForControl:_currentControl];
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onLabelPosChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    _currentControl.labelPosition = (_labelPosSegment.selectedSegment == 1) ? @"bottom" : @"top";
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onButtonShapeChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    _currentControl.shape = (_buttonShapeSegment.selectedSegment == 1) ? @"circle" : @"square";
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onLabelBgToggled:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    _currentControl.hasBackground = (_labelBgCheckbox.state == NSControlStateValueOn);
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onFieldChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    _currentControl.label = _labelField.stringValue;
    _currentControl.midiNumber = _midiNumberField.integerValue;
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onFrameFieldChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    _currentControl.frame = NSMakeRect(_xField.doubleValue, _yField.doubleValue, _wField.doubleValue, _hField.doubleValue);
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onChannelChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    _currentControl.midiChannel = _channelPopup.indexOfSelectedItem + 1;
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onMidiTypeChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    NSInteger idx = _midiTypePopup.indexOfSelectedItem;
    if (idx == 0) _currentControl.midiType = @"cc";
    else if (idx == 1) _currentControl.midiType = @"note";
    else _currentControl.midiType = @"pitchbend";
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onButtonModeChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    _currentControl.mode = (_buttonModeSegment.selectedSegment == 1) ? @"toggle" : @"momentary";
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onKnobStyleChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    NSInteger idx = _knobStyleSegment.selectedSegment;
    if (idx == 1) _currentControl.knobStyle = @"inverted";
    else if (idx == 2) _currentControl.knobStyle = @"centered";
    else _currentControl.knobStyle = @"standard";
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onFaderStyleChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    NSInteger idx = _faderStyleSegment.selectedSegment;
    if (idx == 1) _currentControl.faderStyle = @"inverted";
    else if (idx == 2) _currentControl.faderStyle = @"centered";
    else _currentControl.faderStyle = @"standard";
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onFaderOrientationChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    BOOL makeHorizontal = (_faderOrientationSegment.selectedSegment == 1);
    NSString *newOrient = makeHorizontal ? @"horizontal" : @"vertical";
    if (![_currentControl.orientation isEqualToString:newOrient]) {
        _currentControl.orientation = newOrient;
        NSRect f = _currentControl.frame;
        if (makeHorizontal && f.size.height > f.size.width) {
            _currentControl.frame = NSMakeRect(f.origin.x, f.origin.y, f.size.height, f.size.width);
        } else if (!makeHorizontal && f.size.width > f.size.height) {
            _currentControl.frame = NSMakeRect(f.origin.x, f.origin.y, f.size.height, f.size.width);
        }
        _wField.integerValue = round(_currentControl.frame.size.width);
        _hField.integerValue = round(_currentControl.frame.size.height);
    }
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onRangeChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    NSInteger minV = MAX(0, MIN(127, _minValField.integerValue));
    NSInteger maxV = MAX(0, MIN(127, _maxValField.integerValue));
    if (minV > maxV) {
        if (sender == _minValField) maxV = minV;
        else minV = maxV;
    }
    _currentControl.minValue = (int)minV;
    _currentControl.maxValue = (int)maxV;
    _minValField.integerValue = minV;
    _maxValField.integerValue = maxV;
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onFontSizeChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    _currentControl.fontSize = round(_fontSizeSlider.doubleValue);
    _fontSizeLabel.stringValue = (_currentControl.fontSize > 0) ? [NSString stringWithFormat:@"Font Size: %d pt", (int)_currentControl.fontSize] : @"Font Size: Auto";
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onColorChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    [self notifyWillChange];
    _currentControl.color = _colorWell.color;
    _currentControl.accentColor = _colorWell.color;
    _colorDot.layer.backgroundColor = _colorWell.color.CGColor ?: AirColorAccent().CGColor;
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onDuplicateClicked:(id)sender {
    if (_currentControl) [self.delegate inspectorDidRequestDuplicate:_currentControl];
}

- (void)onDeleteClicked:(id)sender {
    if (_currentControl) [self.delegate inspectorDidRequestDelete:_currentControl];
}

@end
