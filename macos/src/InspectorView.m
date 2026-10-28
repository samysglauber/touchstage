#import "InspectorView.h"

@interface InspectorView () <NSTextFieldDelegate>
@end

@implementation InspectorView {
    NSTextField *_titleLabel;
    NSTextField *_labelField;
    NSPopUpButton *_typePopup;
    NSPopUpButton *_channelPopup;
    NSPopUpButton *_midiTypePopup;
    NSTextField *_midiNumberField;
    NSTextField *_minField;
    NSTextField *_maxField;
    NSColorWell *_colorWell;
    NSColorWell *_accentColorWell;
    NSButton *_bottomButtonCheckbox;
    NSTextField *_bottomButtonNoteField;
    NSPopUpButton *_buttonModePopup;
    NSTextField *_xField;
    NSTextField *_yField;
    NSTextField *_wField;
    NSTextField *_hField;
    NSButton *_btnDuplicate;
    NSButton *_btnDelete;
    BOOL _updatingUI;
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
    [self setWantsLayer:YES];
    self.layer.backgroundColor = [NSColor colorWithCalibratedRed:0.08f green:0.09f blue:0.12f alpha:1.0f].CGColor;

    CGFloat pad = 14.0f;
    CGFloat w = self.bounds.size.width - (pad * 2);
    CGFloat y = 14.0f;

    _titleLabel = [self createLabel:@"PROPRIEDADES DO CONTROLE" frame:NSMakeRect(pad, y, w, 20) bold:YES];
    _titleLabel.textColor = [NSColor cyanColor];
    [self addSubview:_titleLabel];
    y += 28.0f;

    // Label
    [self addSubview:[self createLabel:@"Rótulo / Nome:" frame:NSMakeRect(pad, y, w, 16) bold:NO]];
    y += 18.0f;
    _labelField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad, y, w, 24)];
    _labelField.delegate = self;
    _labelField.target = self;
    _labelField.action = @selector(onFieldChanged:);
    [self addSubview:_labelField];
    y += 32.0f;

    // Control Type
    [self addSubview:[self createLabel:@"Tipo de Controle:" frame:NSMakeRect(pad, y, w, 16) bold:NO]];
    y += 18.0f;
    _typePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(pad, y, w, 26) pullsDown:NO];
    [_typePopup addItemsWithTitles:@[@"Fader Vertical", @"Knob / Potenciômetro", @"Pad / Botão", @"Pad X/Y", @"Rótulo / Label"]];
    _typePopup.target = self;
    _typePopup.action = @selector(onTypeChanged:);
    [self addSubview:_typePopup];
    y += 34.0f;

    // MIDI Channel & Message Type
    CGFloat halfW = (w - 10) / 2.0f;
    [self addSubview:[self createLabel:@"Canal MIDI:" frame:NSMakeRect(pad, y, halfW, 16) bold:NO]];
    [self addSubview:[self createLabel:@"Tipo MIDI:" frame:NSMakeRect(pad + halfW + 10, y, halfW, 16) bold:NO]];
    y += 18.0f;

    _channelPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(pad, y, halfW, 26) pullsDown:NO];
    for (int ch = 1; ch <= 16; ch++) {
        [_channelPopup addItemWithTitle:[NSString stringWithFormat:@"Canal %d", ch]];
    }
    _channelPopup.target = self;
    _channelPopup.action = @selector(onChannelChanged:);
    [self addSubview:_channelPopup];

    _midiTypePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(pad + halfW + 10, y, halfW, 26) pullsDown:NO];
    [_midiTypePopup addItemsWithTitles:@[@"Control Change (CC)", @"Nota (Note On)", @"Pitch Bend"]];
    _midiTypePopup.target = self;
    _midiTypePopup.action = @selector(onMidiTypeChanged:);
    [self addSubview:_midiTypePopup];
    y += 34.0f;

    // MIDI Number & Button Mode
    [self addSubview:[self createLabel:@"Número CC / Nota:" frame:NSMakeRect(pad, y, halfW, 16) bold:NO]];
    [self addSubview:[self createLabel:@"Comportamento:" frame:NSMakeRect(pad + halfW + 10, y, halfW, 16) bold:NO]];
    y += 18.0f;

    _midiNumberField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad, y, halfW, 24)];
    _midiNumberField.target = self;
    _midiNumberField.action = @selector(onFieldChanged:);
    [self addSubview:_midiNumberField];

    _buttonModePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(pad + halfW + 10, y, halfW, 26) pullsDown:NO];
    [_buttonModePopup addItemsWithTitles:@[@"Momentâneo", @"Alternar (Toggle)"]];
    _buttonModePopup.target = self;
    _buttonModePopup.action = @selector(onButtonModeChanged:);
    [self addSubview:_buttonModePopup];
    y += 34.0f;

    // Colors (Native NSColorWell!)
    [self addSubview:[self createLabel:@"Cor Principal:" frame:NSMakeRect(pad, y, halfW, 16) bold:NO]];
    [self addSubview:[self createLabel:@"Cor de Realce/LED:" frame:NSMakeRect(pad + halfW + 10, y, halfW, 16) bold:NO]];
    y += 18.0f;

    _colorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(pad, y, halfW, 28)];
    _colorWell.target = self;
    _colorWell.action = @selector(onColorChanged:);
    [self addSubview:_colorWell];

    _accentColorWell = [[NSColorWell alloc] initWithFrame:NSMakeRect(pad + halfW + 10, y, halfW, 28)];
    _accentColorWell.target = self;
    _accentColorWell.action = @selector(onColorChanged:);
    [self addSubview:_accentColorWell];
    y += 36.0f;

    // Fader Extra Options
    _bottomButtonCheckbox = [NSButton checkboxWithTitle:@"Botão LED no rodapé do Fader" target:self action:@selector(onFaderBtnToggled:)];
    _bottomButtonCheckbox.frame = NSMakeRect(pad, y, w, 20);
    [self addSubview:_bottomButtonCheckbox];
    y += 24.0f;

    [self addSubview:[self createLabel:@"Nota do Botão Inferior:" frame:NSMakeRect(pad, y, halfW, 16) bold:NO]];
    _bottomButtonNoteField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad + halfW + 10, y - 4, halfW, 24)];
    _bottomButtonNoteField.target = self;
    _bottomButtonNoteField.action = @selector(onFieldChanged:);
    [self addSubview:_bottomButtonNoteField];
    y += 32.0f;

    // Coordinates (X, Y, W, H)
    CGFloat qW = (w - 15) / 4.0f;
    [self addSubview:[self createLabel:@"X" frame:NSMakeRect(pad, y, qW, 14) bold:NO]];
    [self addSubview:[self createLabel:@"Y" frame:NSMakeRect(pad + (qW + 5), y, qW, 14) bold:NO]];
    [self addSubview:[self createLabel:@"Larg" frame:NSMakeRect(pad + (qW + 5) * 2, y, qW, 14) bold:NO]];
    [self addSubview:[self createLabel:@"Alt" frame:NSMakeRect(pad + (qW + 5) * 3, y, qW, 14) bold:NO]];
    y += 16.0f;

    _xField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad, y, qW, 22)];
    _xField.target = self; _xField.action = @selector(onFrameFieldChanged:);
    [self addSubview:_xField];

    _yField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad + (qW + 5), y, qW, 22)];
    _yField.target = self; _yField.action = @selector(onFrameFieldChanged:);
    [self addSubview:_yField];

    _wField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad + (qW + 5) * 2, y, qW, 22)];
    _wField.target = self; _wField.action = @selector(onFrameFieldChanged:);
    [self addSubview:_wField];

    _hField = [[NSTextField alloc] initWithFrame:NSMakeRect(pad + (qW + 5) * 3, y, qW, 22)];
    _hField.target = self; _hField.action = @selector(onFrameFieldChanged:);
    [self addSubview:_hField];
    y += 36.0f;

    // Action Buttons
    _btnDuplicate = [[NSButton alloc] initWithFrame:NSMakeRect(pad, y, halfW, 30)];
    _btnDuplicate.title = @"📋 Duplicar";
    _btnDuplicate.bezelStyle = NSBezelStyleRounded;
    _btnDuplicate.target = self;
    _btnDuplicate.action = @selector(onDuplicateClicked:);
    [self addSubview:_btnDuplicate];

    _btnDelete = [[NSButton alloc] initWithFrame:NSMakeRect(pad + halfW + 10, y, halfW, 30)];
    _btnDelete.title = @"🗑️ Excluir";
    _btnDelete.bezelStyle = NSBezelStyleRounded;
    _btnDelete.target = self;
    _btnDelete.action = @selector(onDeleteClicked:);
    [self addSubview:_btnDelete];

    [self setEnabledForAll:NO];
}

- (NSTextField *)createLabel:(NSString *)text frame:(NSRect)frame bold:(BOOL)bold {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text;
    label.editable = NO;
    label.selectable = NO;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.font = bold ? [NSFont boldSystemFontOfSize:11.0f] : [NSFont systemFontOfSize:11.0f];
    label.textColor = [NSColor lightGrayColor];
    return label;
}

- (void)setEnabledForAll:(BOOL)enabled {
    _labelField.enabled = enabled;
    _typePopup.enabled = enabled;
    _channelPopup.enabled = enabled;
    _midiTypePopup.enabled = enabled;
    _midiNumberField.enabled = enabled;
    _buttonModePopup.enabled = enabled;
    _colorWell.enabled = enabled;
    _accentColorWell.enabled = enabled;
    _bottomButtonCheckbox.enabled = enabled;
    _bottomButtonNoteField.enabled = enabled;
    _xField.enabled = enabled;
    _yField.enabled = enabled;
    _wField.enabled = enabled;
    _hField.enabled = enabled;
    _btnDuplicate.enabled = enabled;
    _btnDelete.enabled = enabled;
}

- (void)bindControl:(MidiControlModel *)control {
    _currentControl = control;
    if (!control) {
        _titleLabel.stringValue = @"NENHUM SELECIONADO";
        _titleLabel.textColor = [NSColor grayColor];
        [self setEnabledForAll:NO];
        return;
    }

    _titleLabel.stringValue = [NSString stringWithFormat:@"PROPRIEDADES: %@", control.label.uppercaseString];
    _titleLabel.textColor = [NSColor cyanColor];
    [self setEnabledForAll:YES];
    [self refreshValues];
}

- (void)refreshValues {
    if (!_currentControl) return;
    _updatingUI = YES;

    _labelField.stringValue = _currentControl.label ?: @"";

    if ([_currentControl.type isEqualToString:@"fader"]) [_typePopup selectItemAtIndex:0];
    else if ([_currentControl.type isEqualToString:@"knob"]) [_typePopup selectItemAtIndex:1];
    else if ([_currentControl.type isEqualToString:@"button"]) [_typePopup selectItemAtIndex:2];
    else if ([_currentControl.type isEqualToString:@"xypad"]) [_typePopup selectItemAtIndex:3];
    else if ([_currentControl.type isEqualToString:@"label"]) [_typePopup selectItemAtIndex:4];

    NSInteger chIdx = MAX(0, MIN(15, _currentControl.midiChannel - 1));
    [_channelPopup selectItemAtIndex:chIdx];

    if ([_currentControl.midiType isEqualToString:@"cc"]) [_midiTypePopup selectItemAtIndex:0];
    else if ([_currentControl.midiType isEqualToString:@"note"]) [_midiTypePopup selectItemAtIndex:1];
    else [_midiTypePopup selectItemAtIndex:2];

    _midiNumberField.integerValue = _currentControl.midiNumber;

    if ([_currentControl.mode isEqualToString:@"toggle"]) [_buttonModePopup selectItemAtIndex:1];
    else [_buttonModePopup selectItemAtIndex:0];

    _colorWell.color = _currentControl.color ?: [NSColor cyanColor];
    _accentColorWell.color = _currentControl.accentColor ?: [NSColor whiteColor];

    _bottomButtonCheckbox.state = _currentControl.hasBottomButton ? NSControlStateValueOn : NSControlStateValueOff;
    _bottomButtonNoteField.integerValue = _currentControl.buttonMidiNumber;

    _xField.integerValue = round(_currentControl.frame.origin.x);
    _yField.integerValue = round(_currentControl.frame.origin.y);
    _wField.integerValue = round(_currentControl.frame.size.width);
    _hField.integerValue = round(_currentControl.frame.size.height);

    _updatingUI = NO;
}

- (void)controlTextDidChange:(NSNotification *)obj {
    if (_updatingUI || !_currentControl) return;
    if (obj.object == _labelField) {
        _currentControl.label = _labelField.stringValue;
        [self.delegate inspectorDidUpdateControl:_currentControl];
    }
}

- (void)onFieldChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    _currentControl.label = _labelField.stringValue;
    _currentControl.midiNumber = _midiNumberField.integerValue;
    _currentControl.buttonMidiNumber = _bottomButtonNoteField.integerValue;
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onFrameFieldChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    _currentControl.frame = NSMakeRect(_xField.doubleValue, _yField.doubleValue, _wField.doubleValue, _hField.doubleValue);
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onTypeChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    NSInteger idx = _typePopup.indexOfSelectedItem;
    NSArray *types = @[@"fader", @"knob", @"button", @"xypad", @"label"];
    if (idx >= 0 && idx < types.count) {
        _currentControl.type = types[idx];
        [self.delegate inspectorDidUpdateControl:_currentControl];
    }
}

- (void)onChannelChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    _currentControl.midiChannel = _channelPopup.indexOfSelectedItem + 1;
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onMidiTypeChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    NSInteger idx = _midiTypePopup.indexOfSelectedItem;
    if (idx == 0) _currentControl.midiType = @"cc";
    else if (idx == 1) _currentControl.midiType = @"note";
    else _currentControl.midiType = @"pitchbend";
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onButtonModeChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    _currentControl.mode = _buttonModePopup.indexOfSelectedItem == 1 ? @"toggle" : @"momentary";
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onColorChanged:(id)sender {
    if (_updatingUI || !_currentControl) return;
    _currentControl.color = _colorWell.color;
    _currentControl.accentColor = _accentColorWell.color;
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onFaderBtnToggled:(id)sender {
    if (_updatingUI || !_currentControl) return;
    _currentControl.hasBottomButton = (_bottomButtonCheckbox.state == NSControlStateValueOn);
    [self.delegate inspectorDidUpdateControl:_currentControl];
}

- (void)onDuplicateClicked:(id)sender {
    if (_currentControl) [self.delegate inspectorDidRequestDuplicate:_currentControl];
}

- (void)onDeleteClicked:(id)sender {
    if (_currentControl) [self.delegate inspectorDidRequestDelete:_currentControl];
}

@end
