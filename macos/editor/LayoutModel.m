#import "LayoutModel.h"

// Color conversion helpers
static NSColor *ColorFromHex(NSString *hexStr) {
    if (!hexStr || hexStr.length == 0) return [NSColor cyanColor];
    NSString *clean = [hexStr stringByReplacingOccurrencesOfString:@"#" withString:@""];
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&rgb];
    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0f;
    CGFloat g = ((rgb >> 8) & 0xFF) / 255.0f;
    CGFloat b = (rgb & 0xFF) / 255.0f;
    return [NSColor colorWithCalibratedRed:r green:g blue:b alpha:1.0f];
}

static NSString *HexFromColor(NSColor *color) {
    if (!color) return @"#00e5ff";
    NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!rgb) rgb = color;
    int r = (int)(round(rgb.redComponent * 255.0f));
    int g = (int)(round(rgb.greenComponent * 255.0f));
    int b = (int)(round(rgb.blueComponent * 255.0f));
    return [NSString stringWithFormat:@"#%02x%02x%02x", r, g, b];
}

@implementation MidiControlModel

- (id)copyWithZone:(NSZone *)zone {
    MidiControlModel *copy = [[MidiControlModel allocWithZone:zone] init];
    copy.controlId = [self.controlId copy];
    copy.type = [self.type copy];
    copy.label = [self.label copy];
    copy.frame = self.frame;
    copy.color = self.color;
    copy.accentColor = self.accentColor;
    copy.midiChannel = self.midiChannel;
    copy.midiType = [self.midiType copy];
    copy.midiNumber = self.midiNumber;
    copy.minValue = self.minValue;
    copy.maxValue = self.maxValue;
    copy.value = self.value;
    copy.hasLabel = self.hasLabel;
    copy.labelPosition = [self.labelPosition copy];
    copy.orientation = [self.orientation copy];
    copy.knobStyle = [self.knobStyle copy];
    copy.faderStyle = [self.faderStyle copy];
    copy.fontSize = self.fontSize;
    copy.shape = [self.shape copy];
    copy.hasBackground = self.hasBackground;
    copy.hasVuMeter = self.hasVuMeter;
    copy.vuMidiChannel = self.vuMidiChannel;
    copy.vuMidiNumber = self.vuMidiNumber;
    copy.vuLevel = self.vuLevel;
    copy.peakLevel = self.peakLevel;
    copy.hasBottomButton = self.hasBottomButton;
    copy.buttonMidiNumber = self.buttonMidiNumber;
    copy.buttonMode = [self.buttonMode copy];
    copy.buttonValue = self.buttonValue;
    copy.mode = [self.mode copy];
    return copy;
}

+ (instancetype)controlWithDictionary:(NSDictionary *)dict {
    MidiControlModel *m = [[MidiControlModel alloc] init];
    m.controlId = dict[@"id"] ?: [NSString stringWithFormat:@"ctrl_%u", arc4random() % 10000];
    m.type = dict[@"type"] ?: @"fader";
    m.label = dict[@"label"] ?: @"CONTROL";
    
    CGFloat x = [dict[@"x"] doubleValue];
    CGFloat y = [dict[@"y"] doubleValue];
    CGFloat w = [dict[@"width"] doubleValue];
    CGFloat h = [dict[@"height"] doubleValue];
    m.frame = NSMakeRect(x, y, w > 10 ? w : 80, h > 10 ? h : 200);

    m.color = ColorFromHex(dict[@"color"]);
    m.accentColor = ColorFromHex(dict[@"accentColor"]);
    m.midiChannel = dict[@"midiChannel"] ? [dict[@"midiChannel"] integerValue] : 1;
    m.midiType = dict[@"midiType"] ?: @"cc";
    m.midiNumber = dict[@"midiNumber"] ? [dict[@"midiNumber"] integerValue] : 7;
    m.minValue = dict[@"minValue"] ? [dict[@"minValue"] integerValue] : 0;
    m.maxValue = dict[@"maxValue"] ? [dict[@"maxValue"] integerValue] : 127;
    m.value = dict[@"value"] ? [dict[@"value"] doubleValue] : 0;

    m.hasLabel = dict[@"hasLabel"] ? [dict[@"hasLabel"] boolValue] : NO;
    m.labelPosition = dict[@"labelPosition"] ?: ([m.type isEqualToString:@"knob"] ? @"bottom" : @"top");
    m.orientation = dict[@"orientation"] ?: @"vertical";
    m.knobStyle = dict[@"knobStyle"] ?: @"standard";
    m.faderStyle = dict[@"faderStyle"] ?: @"standard";
    m.fontSize = dict[@"fontSize"] ? [dict[@"fontSize"] doubleValue] : 0;
    m.shape = dict[@"shape"] ?: @"square";
    m.hasBackground = [dict[@"hasBackground"] boolValue];
    m.hasVuMeter = [dict[@"hasVuMeter"] boolValue];
    m.vuMidiChannel = dict[@"vuMidiChannel"] ? [dict[@"vuMidiChannel"] integerValue] : m.midiChannel;
    m.vuMidiNumber = dict[@"vuMidiNumber"] ? [dict[@"vuMidiNumber"] integerValue] : m.midiNumber;
    m.hasBottomButton = [dict[@"hasBottomButton"] boolValue];
    m.buttonMidiNumber = dict[@"buttonMidiNumber"] ? [dict[@"buttonMidiNumber"] integerValue] : 60;
    m.buttonMode = dict[@"buttonMode"] ?: @"toggle";
    m.buttonValue = [dict[@"buttonValue"] boolValue];
    m.mode = dict[@"mode"] ?: @"momentary";
    return m;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"] = self.controlId ?: @"";
    dict[@"type"] = self.type ?: @"fader";
    dict[@"label"] = self.label ?: @"";
    dict[@"x"] = @(self.frame.origin.x);
    dict[@"y"] = @(self.frame.origin.y);
    dict[@"width"] = @(self.frame.size.width);
    dict[@"height"] = @(self.frame.size.height);
    dict[@"color"] = HexFromColor(self.color);
    dict[@"accentColor"] = HexFromColor(self.accentColor);
    dict[@"midiChannel"] = @(self.midiChannel);
    dict[@"midiType"] = self.midiType ?: @"cc";
    dict[@"midiNumber"] = @(self.midiNumber);
    dict[@"minValue"] = @(self.minValue);
    dict[@"maxValue"] = @(self.maxValue);
    dict[@"value"] = @(self.value);

    dict[@"hasLabel"] = @(self.hasLabel);
    dict[@"labelPosition"] = self.labelPosition ?: ([self.type isEqualToString:@"knob"] ? @"bottom" : @"top");
    dict[@"orientation"] = self.orientation ?: @"vertical";
    dict[@"knobStyle"] = self.knobStyle ?: @"standard";
    dict[@"faderStyle"] = self.faderStyle ?: @"standard";
    if (self.fontSize > 0) {
        dict[@"fontSize"] = @(self.fontSize);
    }

    if ([self.type isEqualToString:@"fader"]) {
        dict[@"hasVuMeter"] = @(self.hasVuMeter);
        if (self.vuMidiNumber > 0) dict[@"vuMidiNumber"] = @(self.vuMidiNumber);
        if (self.vuMidiChannel > 0) dict[@"vuMidiChannel"] = @(self.vuMidiChannel);
    } else if ([self.type isEqualToString:@"button"]) {
        dict[@"shape"] = self.shape ?: @"square";
        dict[@"mode"] = self.mode ?: @"momentary";
    } else if ([self.type isEqualToString:@"label"]) {
        dict[@"hasBackground"] = @(self.hasBackground);
    }
    return dict;
}

@end

@implementation LayoutPageModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _pageId = [NSString stringWithFormat:@"page_%u", arc4random() % 10000];
        _name = @"Screen 1";
        _controls = [NSMutableArray array];
    }
    return self;
}

+ (instancetype)pageWithName:(NSString *)name {
    LayoutPageModel *p = [[LayoutPageModel alloc] init];
    p.name = name ?: @"Screen";
    return p;
}

- (id)copyWithZone:(NSZone *)zone {
    LayoutPageModel *copy = [[LayoutPageModel allocWithZone:zone] init];
    copy.pageId = [self.pageId copy];
    copy.name = [self.name copy];
    copy.controls = [NSMutableArray array];
    for (MidiControlModel *m in self.controls) {
        [copy.controls addObject:[m copy]];
    }
    return copy;
}

+ (instancetype)pageWithDictionary:(NSDictionary *)dict {
    LayoutPageModel *p = [[LayoutPageModel alloc] init];
    p.pageId = dict[@"id"] ?: [NSString stringWithFormat:@"page_%u", arc4random() % 10000];
    p.name = dict[@"name"] ?: @"Screen";
    p.controls = [NSMutableArray array];
    NSArray *ctrls = dict[@"controls"];
    if ([ctrls isKindOfClass:[NSArray class]]) {
        for (NSDictionary *cDict in ctrls) {
            if ([cDict isKindOfClass:[NSDictionary class]]) {
                [p.controls addObject:[MidiControlModel controlWithDictionary:cDict]];
            }
        }
    }
    return p;
}

- (NSDictionary *)toDictionary {
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    dict[@"id"] = self.pageId ?: @"";
    dict[@"name"] = self.name ?: @"Screen";
    NSMutableArray *ctrlArray = [NSMutableArray array];
    for (MidiControlModel *m in self.controls) {
        [ctrlArray addObject:[m toDictionary]];
    }
    dict[@"controls"] = ctrlArray;
    return dict;
}

@end

@implementation LayoutModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"Untitled Project";
        _author = @"TouchStage Editor";
        _version = @"1.0";
        _canvasWidth = 920.0f;
        _canvasHeight = 460.0f;
        _orientation = @"landscape";
        _pages = [NSMutableArray array];
        _activePageIndex = 0;
        [_pages addObject:[LayoutPageModel pageWithName:@"Screen 1"]];
    }
    return self;
}

- (LayoutPageModel *)activePage {
    if (!_pages || _pages.count == 0) {
        if (!_pages) _pages = [NSMutableArray array];
        [_pages addObject:[LayoutPageModel pageWithName:@"Screen 1"]];
        _activePageIndex = 0;
    }
    if (_activePageIndex < 0 || _activePageIndex >= _pages.count) {
        _activePageIndex = 0;
    }
    return _pages[_activePageIndex];
}

- (NSMutableArray<MidiControlModel *> *)controls {
    return [self activePage].controls;
}

- (LayoutPageModel *)addPageWithName:(NSString *)name {
    LayoutPageModel *p = [LayoutPageModel pageWithName:name];
    [_pages addObject:p];
    _activePageIndex = _pages.count - 1;
    return p;
}

- (void)removePageAtIndex:(NSInteger)index {
    if (index >= 0 && index < _pages.count && _pages.count > 1) {
        [_pages removeObjectAtIndex:index];
        if (_activePageIndex >= _pages.count) {
            _activePageIndex = _pages.count - 1;
        }
    }
}

+ (instancetype)layoutFromJSONData:(NSData *)data error:(NSError **)error {
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return nil;

    LayoutModel *model = [[LayoutModel alloc] init];
    model.name = dict[@"name"] ?: @"Untitled Layout";
    model.author = dict[@"author"] ?: @"AirMIDI";
    model.version = dict[@"version"] ?: @"1.0";
    if (dict[@"canvasWidth"]) model.canvasWidth = [dict[@"canvasWidth"] doubleValue];
    if (dict[@"canvasHeight"]) model.canvasHeight = [dict[@"canvasHeight"] doubleValue];
    if (dict[@"orientation"]) model.orientation = dict[@"orientation"];
    else model.orientation = (model.canvasHeight > model.canvasWidth) ? @"portrait" : @"landscape";

    [model.pages removeAllObjects];

    NSArray *pagesArr = dict[@"pages"];
    if ([pagesArr isKindOfClass:[NSArray class]] && pagesArr.count > 0) {
        for (NSDictionary *pDict in pagesArr) {
            if ([pDict isKindOfClass:[NSDictionary class]]) {
                [model.pages addObject:[LayoutPageModel pageWithDictionary:pDict]];
            }
        }
    } else {
        // Fallback for single-page legacy layouts
        LayoutPageModel *defaultPage = [LayoutPageModel pageWithName:@"Screen 1"];
        NSArray *ctrls = dict[@"controls"];
        if ([ctrls isKindOfClass:[NSArray class]]) {
            for (NSDictionary *cDict in ctrls) {
                if ([cDict isKindOfClass:[NSDictionary class]]) {
                    [defaultPage.controls addObject:[MidiControlModel controlWithDictionary:cDict]];
                }
            }
        }
        [model.pages addObject:defaultPage];
    }

    if (dict[@"activePageIndex"]) {
        model.activePageIndex = [dict[@"activePageIndex"] integerValue];
    } else {
        model.activePageIndex = 0;
    }
    return model;
}

- (NSData *)toJSONDataWithError:(NSError **)error {
    NSMutableDictionary *root = [NSMutableDictionary dictionary];
    root[@"name"] = self.name ?: @"Layout";
    root[@"author"] = self.author ?: @"AirMIDI";
    root[@"version"] = self.version ?: @"1.0";
    root[@"canvasWidth"] = @(self.canvasWidth);
    root[@"canvasHeight"] = @(self.canvasHeight);
    root[@"orientation"] = self.orientation ?: ((self.canvasHeight > self.canvasWidth) ? @"portrait" : @"landscape");
    root[@"activePageIndex"] = @(self.activePageIndex);

    NSMutableArray *pageList = [NSMutableArray array];
    for (LayoutPageModel *p in self.pages) {
        [pageList addObject:[p toDictionary]];
    }
    root[@"pages"] = pageList;

    // Top-level "controls" for backward compatibility
    NSMutableArray *ctrlArray = [NSMutableArray array];
    for (MidiControlModel *m in [self controls]) {
        [ctrlArray addObject:[m toDictionary]];
    }
    root[@"controls"] = ctrlArray;

    return [NSJSONSerialization dataWithJSONObject:root options:NSJSONWritingPrettyPrinted error:error];
}

- (NSString *)toJSONString {
    NSMutableDictionary *root = [NSMutableDictionary dictionary];
    root[@"name"] = self.name ?: @"Layout";
    root[@"author"] = self.author ?: @"AirMIDI";
    root[@"version"] = self.version ?: @"1.0";
    root[@"canvasWidth"] = @(self.canvasWidth);
    root[@"canvasHeight"] = @(self.canvasHeight);
    root[@"orientation"] = self.orientation ?: ((self.canvasHeight > self.canvasWidth) ? @"portrait" : @"landscape");
    root[@"activePageIndex"] = @(self.activePageIndex);

    NSMutableArray *pageList = [NSMutableArray array];
    for (LayoutPageModel *p in self.pages) {
        [pageList addObject:[p toDictionary]];
    }
    root[@"pages"] = pageList;

    // Top-level "controls" for backward compatibility
    NSMutableArray *ctrlArray = [NSMutableArray array];
    for (MidiControlModel *m in [self controls]) {
        [ctrlArray addObject:[m toDictionary]];
    }
    root[@"controls"] = ctrlArray;

    // Use options: 0 to ensure absolutely no newlines for network packet transmission!
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
    if (!data) return @"{}";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

// Preset 1: Reference screenshot (Screen 1: Mixer Rig, Screen 2: Lead & FX)
+ (instancetype)referencePreset {
    LayoutModel *l = [[LayoutModel alloc] init];
    l.name = @"Live Stage Rig";
    l.canvasWidth = 920.0f;
    l.canvasHeight = 460.0f;
    [l.pages removeAllObjects];

    // Page 1: Main Mixer Rig
    LayoutPageModel *page1 = [LayoutPageModel pageWithName:@"Mixer Rig"];

    NSArray *channels = @[
        @{@"id":@"piano",   @"label":@"PIANO",   @"color":@"#005f73", @"accent":@"#00F0FF", @"x":@12,  @"cc":@11, @"note":@60, @"val":@78},
        @{@"id":@"pad",     @"label":@"PAD",     @"color":@"#475569", @"accent":@"#E0F7FF", @"x":@120, @"cc":@12, @"note":@62, @"val":@85},
        @{@"id":@"rhodes",  @"label":@"RHODES",  @"color":@"#4c1d95", @"accent":@"#C084FC", @"x":@228, @"cc":@13, @"note":@64, @"val":@82},
        @{@"id":@"organ",   @"label":@"ORGAN",   @"color":@"#78350f", @"accent":@"#FBBF24", @"x":@336, @"cc":@14, @"note":@65, @"val":@80},
        @{@"id":@"synth",   @"label":@"SYNTH",   @"color":@"#064e3b", @"accent":@"#00E676", @"x":@444, @"cc":@15, @"note":@67, @"val":@84},
        @{@"id":@"galileu", @"label":@"GALILEU", @"color":@"#831843", @"accent":@"#FF2E93", @"x":@552, @"cc":@16, @"note":@69, @"val":@76}
    ];

    NSInteger trackIdx = 1;
    for (NSDictionary *info in channels) {
        CGFloat x = [info[@"x"] doubleValue];

        // 1. Vertical Fader
        MidiControlModel *m = [[MidiControlModel alloc] init];
        m.controlId = [NSString stringWithFormat:@"fader_%@", info[@"id"]];
        m.type = @"fader";
        m.label = info[@"label"];
        m.frame = NSMakeRect(x, 12, 92, 235);
        m.color = ColorFromHex(info[@"color"]);
        m.accentColor = ColorFromHex(info[@"accent"]);
        m.midiChannel = 1;
        m.midiType = @"cc";
        m.midiNumber = [info[@"cc"] integerValue];
        m.minValue = 0;
        m.maxValue = 127;
        m.value = [info[@"val"] doubleValue];
        m.hasLabel = YES;
        m.labelPosition = @"top";
        [page1.controls addObject:m];

        // 2. Square Illuminated Pad Button
        MidiControlModel *btn = [[MidiControlModel alloc] init];
        btn.controlId = [NSString stringWithFormat:@"btn_%@", info[@"id"]];
        btn.type = @"button";
        btn.shape = @"square";
        btn.label = @"";
        btn.frame = NSMakeRect(x + 11, 258, 70, 68);
        btn.color = ColorFromHex(info[@"color"]);
        btn.accentColor = ColorFromHex(info[@"accent"]);
        btn.midiChannel = 1;
        btn.midiType = @"note";
        btn.midiNumber = [info[@"note"] integerValue];
        btn.mode = @"toggle";
        btn.value = 127; // Lit by default
        [page1.controls addObject:btn];

        // 3. Bottom Rotary Knob
        MidiControlModel *kn = [[MidiControlModel alloc] init];
        kn.controlId = [NSString stringWithFormat:@"knob_%@", info[@"id"]];
        kn.type = @"knob";
        kn.shape = @"circle";
        kn.label = @"";
        kn.frame = NSMakeRect(x + 13, 338, 66, 76);
        kn.color = ColorFromHex(info[@"color"]);
        kn.accentColor = ColorFromHex(info[@"accent"]);
        kn.midiChannel = 1;
        kn.midiType = @"cc";
        kn.midiNumber = 20 + [info[@"cc"] integerValue];
        kn.minValue = 0;
        kn.maxValue = 127;
        kn.value = 64;
        kn.hasLabel = NO;
        [page1.controls addObject:kn];
    }

    // Right Column: BELLS Pad
    MidiControlModel *bells = [[MidiControlModel alloc] init];
    bells.controlId = @"pad_bells";
    bells.type = @"button";
    bells.shape = @"square";
    bells.label = @"BELLS";
    bells.frame = NSMakeRect(666, 12, 150, 140);
    bells.color = ColorFromHex(@"#78350f");
    bells.accentColor = ColorFromHex(@"#FBBF24");
    bells.midiChannel = 1;
    bells.midiType = @"note";
    bells.midiNumber = 72;
    bells.mode = @"momentary";
    bells.value = 127;
    [page1.controls addObject:bells];

    // Right Column: SYNTH FILTER Big Knob
    MidiControlModel *knob = [[MidiControlModel alloc] init];
    knob.controlId = @"knob_synth_filter";
    knob.type = @"knob";
    knob.label = @"";
    knob.frame = NSMakeRect(666, 168, 150, 190);
    knob.color = ColorFromHex(@"#064e3b");
    knob.accentColor = ColorFromHex(@"#00E676");
    knob.midiChannel = 1;
    knob.midiType = @"cc";
    knob.midiNumber = 74;
    knob.minValue = 0;
    knob.maxValue = 127;
    knob.value = 64;
    knob.hasLabel = NO;
    [page1.controls addObject:knob];

    // Right Column: SYNTH FILTER Capsule Label
    MidiControlModel *lblFilter = [[MidiControlModel alloc] init];
    lblFilter.controlId = @"lbl_synth_filter";
    lblFilter.type = @"label";
    lblFilter.label = @"SYNTH FILTER";
    lblFilter.frame = NSMakeRect(666, 375, 150, 34);
    lblFilter.hasBackground = YES;
    lblFilter.accentColor = ColorFromHex(@"#00E676");
    [page1.controls addObject:lblFilter];

    [l.pages addObject:page1];

    // Page 2: Lead & Synth FX
    LayoutPageModel *page2 = [LayoutPageModel pageWithName:@"Lead & FX"];

    MidiControlModel *xy = [[MidiControlModel alloc] init];
    xy.controlId = @"xy_filter_resonance";
    xy.type = @"xypad";
    xy.label = @"XY MORPH / FILTER";
    xy.frame = NSMakeRect(40, 40, 360, 360);
    xy.color = ColorFromHex(@"#1a2332");
    xy.accentColor = ColorFromHex(@"#00e5ff");
    xy.midiChannel = 1;
    xy.midiType = @"cc";
    xy.midiNumber = 1;
    [page2.controls addObject:xy];

    MidiControlModel *k1 = [[MidiControlModel alloc] init];
    k1.controlId = @"knob_reverb";
    k1.type = @"knob";
    k1.label = @"REVERB";
    k1.frame = NSMakeRect(460, 40, 120, 150);
    k1.color = ColorFromHex(@"#280659");
    k1.accentColor = ColorFromHex(@"#5f27cd");
    k1.midiChannel = 1;
    k1.midiType = @"cc";
    k1.midiNumber = 91;
    k1.hasLabel = YES;
    k1.labelPosition = @"bottom";
    [page2.controls addObject:k1];

    MidiControlModel *k2 = [[MidiControlModel alloc] init];
    k2.controlId = @"knob_delay";
    k2.type = @"knob";
    k2.label = @"DELAY";
    k2.frame = NSMakeRect(610, 40, 120, 150);
    k2.color = ColorFromHex(@"#005f6b");
    k2.accentColor = ColorFromHex(@"#00d2d3");
    k2.midiChannel = 1;
    k2.midiType = @"cc";
    k2.midiNumber = 92;
    k2.hasLabel = YES;
    k2.labelPosition = @"bottom";
    [page2.controls addObject:k2];

    MidiControlModel *k3 = [[MidiControlModel alloc] init];
    k3.controlId = @"knob_chorus";
    k3.type = @"knob";
    k3.label = @"CHORUS";
    k3.frame = NSMakeRect(760, 40, 120, 150);
    k3.color = ColorFromHex(@"#40064a");
    k3.accentColor = ColorFromHex(@"#ee5253");
    k3.midiChannel = 1;
    k3.midiType = @"cc";
    k3.midiNumber = 93;
    k3.hasLabel = YES;
    k3.labelPosition = @"bottom";
    [page2.controls addObject:k3];

    // Trigger buttons
    NSArray *padTitles = @[@"DROP", @"SWEEP", @"CRUSH", @"STOP"];
    for (int i = 0; i < 4; i++) {
        MidiControlModel *btn = [[MidiControlModel alloc] init];
        btn.controlId = [NSString stringWithFormat:@"fx_btn_%d", i + 1];
        btn.type = @"button";
        btn.shape = @"square";
        btn.label = padTitles[i];
        btn.frame = NSMakeRect(460 + i * 105, 230, 95, 95);
        btn.color = ColorFromHex(@"#1e222d");
        btn.accentColor = ColorFromHex(@"#ff9f43");
        btn.midiChannel = 1;
        btn.midiType = @"note";
        btn.midiNumber = 80 + i;
        btn.mode = @"momentary";
        [page2.controls addObject:btn];
    }

    [l.pages addObject:page2];
    l.activePageIndex = 0;

    return l;
}

+ (instancetype)mixer8Preset {
    LayoutModel *l = [[LayoutModel alloc] init];
    l.name = @"Mixer 8 Canais";
    l.canvasWidth = 960.0f;
    l.canvasHeight = 460.0f;
    [l.pages removeAllObjects];

    LayoutPageModel *page1 = [LayoutPageModel pageWithName:@"Canais 1-8"];
    NSArray *colors = @[@"#005f6b", @"#4b5358", @"#280659", @"#5e3e06", @"#0d4d22", @"#40064a", @"#004085", @"#721c24"];
    NSArray *accents = @[@"#00d2d3", @"#8395a7", @"#5f27cd", @"#ff9f43", @"#10ac84", @"#ee5253", @"#007bff", @"#f8d7da"];
    for (int i = 0; i < 8; i++) {
        MidiControlModel *m = [[MidiControlModel alloc] init];
        m.controlId = [NSString stringWithFormat:@"fader_ch%d", i + 1];
        m.type = @"fader";
        m.label = [NSString stringWithFormat:@"CH %d", i + 1];
        m.frame = NSMakeRect(15 + i * 115, 10, 85, 360);
        m.color = ColorFromHex(colors[i]);
        m.accentColor = ColorFromHex(accents[i]);
        m.midiChannel = 1;
        m.midiType = @"cc";
        m.midiNumber = 20 + i;
        m.minValue = 0;
        m.maxValue = 127;
        m.value = 64;
        m.hasLabel = YES;
        m.labelPosition = @"top";
        [page1.controls addObject:m];

        // Mute / Solo modular circular button
        MidiControlModel *btn = [[MidiControlModel alloc] init];
        btn.controlId = [NSString stringWithFormat:@"btn_ch%d", i + 1];
        btn.type = @"button";
        btn.shape = @"circle";
        btn.label = @"";
        btn.frame = NSMakeRect(30 + i * 115, 385, 56, 56);
        btn.color = ColorFromHex(colors[i]);
        btn.accentColor = ColorFromHex(accents[i]);
        btn.midiChannel = 1;
        btn.midiType = @"note";
        btn.midiNumber = 48 + i;
        btn.mode = @"toggle";
        btn.value = 127;
        [page1.controls addObject:btn];
    }
    [l.pages addObject:page1];

    LayoutPageModel *page2 = [LayoutPageModel pageWithName:@"Master & Aux"];
    MidiControlModel *master = [[MidiControlModel alloc] init];
    master.controlId = @"fader_master";
    master.type = @"fader";
    master.label = @"MASTER";
    master.frame = NSMakeRect(800, 20, 100, 410);
    master.color = ColorFromHex(@"#c0392b");
    master.accentColor = ColorFromHex(@"#e74c3c");
    master.midiChannel = 1;
    master.midiType = @"cc";
    master.midiNumber = 7;
    master.hasLabel = YES;
    master.labelPosition = @"top";
    [page2.controls addObject:master];
    [l.pages addObject:page2];

    l.activePageIndex = 0;
    return l;
}

+ (instancetype)drumPadPreset {
    LayoutModel *l = [[LayoutModel alloc] init];
    l.name = @"Matriz 16 Pads";
    l.canvasWidth = 960.0f;
    l.canvasHeight = 460.0f;
    [l.pages removeAllObjects];

    LayoutPageModel *page1 = [LayoutPageModel pageWithName:@"16 Pads"];
    for (int i = 0; i < 16; i++) {
        int row = i / 4;
        int col = i % 4;
        MidiControlModel *m = [[MidiControlModel alloc] init];
        m.controlId = [NSString stringWithFormat:@"pad_%d", i + 1];
        m.type = @"button";
        m.label = [NSString stringWithFormat:@"PAD %d", i + 1];
        m.frame = NSMakeRect(20 + col * 120, 20 + (3 - row) * 105, 105, 90);
        m.color = ColorFromHex(@"#182030");
        m.accentColor = ColorFromHex(@"#00e5ff");
        m.midiChannel = 10;
        m.midiType = @"note";
        m.midiNumber = 36 + i;
        m.mode = @"momentary";
        [page1.controls addObject:m];
    }
    [l.pages addObject:page1];
    l.activePageIndex = 0;
    return l;
}

@end
