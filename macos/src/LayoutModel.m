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

    if ([self.type isEqualToString:@"fader"]) {
        dict[@"hasBottomButton"] = @(self.hasBottomButton);
        dict[@"buttonMidiNumber"] = @(self.buttonMidiNumber);
        dict[@"buttonMode"] = self.buttonMode ?: @"toggle";
        dict[@"buttonValue"] = @(self.buttonValue);
    } else if ([self.type isEqualToString:@"button"]) {
        dict[@"mode"] = self.mode ?: @"momentary";
    }
    return dict;
}

@end

@implementation LayoutModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _name = @"Novo Layout";
        _author = @"AirMIDI Studio";
        _version = @"1.0";
        _canvasWidth = 920.0f;
        _canvasHeight = 460.0f;
        _controls = [NSMutableArray array];
    }
    return self;
}

+ (instancetype)layoutFromJSONData:(NSData *)data error:(NSError **)error {
    NSDictionary *dict = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!dict || ![dict isKindOfClass:[NSDictionary class]]) return nil;

    LayoutModel *model = [[LayoutModel alloc] init];
    model.name = dict[@"name"] ?: @"Sem Nome";
    model.author = dict[@"author"] ?: @"AirMIDI";
    model.version = dict[@"version"] ?: @"1.0";
    if (dict[@"canvasWidth"]) model.canvasWidth = [dict[@"canvasWidth"] doubleValue];
    if (dict[@"canvasHeight"]) model.canvasHeight = [dict[@"canvasHeight"] doubleValue];

    NSArray *ctrls = dict[@"controls"];
    if ([ctrls isKindOfClass:[NSArray class]]) {
        for (NSDictionary *cDict in ctrls) {
            if ([cDict isKindOfClass:[NSDictionary class]]) {
                [model.controls addObject:[MidiControlModel controlWithDictionary:cDict]];
            }
        }
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

    NSMutableArray *ctrlArray = [NSMutableArray array];
    for (MidiControlModel *m in self.controls) {
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

    NSMutableArray *ctrlArray = [NSMutableArray array];
    for (MidiControlModel *m in self.controls) {
        [ctrlArray addObject:[m toDictionary]];
    }
    root[@"controls"] = ctrlArray;

    // Use options: 0 to ensure absolutely no newlines for network packet transmission!
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:nil];
    if (!data) return @"{}";
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

// Preset 1: Reference screenshot (6 faders, bells button, synth filter knob)
+ (instancetype)referencePreset {
    LayoutModel *l = [[LayoutModel alloc] init];
    l.name = @"Live Stage Rig (Foto)";
    l.canvasWidth = 920.0f;
    l.canvasHeight = 460.0f;

    NSArray *faders = @[
        @{@"id":@"fader_piano", @"label":@"PIANO", @"color":@"#005f6b", @"accent":@"#00d2d3", @"x":@10,  @"cc":@11, @"note":@60},
        @{@"id":@"fader_pad",   @"label":@"PAD",   @"color":@"#4b5358", @"accent":@"#8395a7", @"x":@115, @"cc":@12, @"note":@62},
        @{@"id":@"fader_rhodes",@"label":@"RHODES",@"color":@"#280659", @"accent":@"#5f27cd", @"x":@220, @"cc":@13, @"note":@64},
        @{@"id":@"fader_organ", @"label":@"ORGAN", @"color":@"#5e3e06", @"accent":@"#ff9f43", @"x":@325, @"cc":@14, @"note":@65},
        @{@"id":@"fader_synth", @"label":@"SYNTH", @"color":@"#0d4d22", @"accent":@"#10ac84", @"x":@430, @"cc":@15, @"note":@67},
        @{@"id":@"fader_galileu",@"label":@"GALILEU",@"color":@"#40064a", @"accent":@"#ee5253", @"x":@535, @"cc":@16, @"note":@69}
    ];

    for (NSDictionary *info in faders) {
        MidiControlModel *m = [[MidiControlModel alloc] init];
        m.controlId = info[@"id"];
        m.type = @"fader";
        m.label = info[@"label"];
        m.frame = NSMakeRect([info[@"x"] doubleValue], 10, 78, 440);
        m.color = ColorFromHex(info[@"color"]);
        m.accentColor = ColorFromHex(info[@"accent"]);
        m.midiChannel = 1;
        m.midiType = @"cc";
        m.midiNumber = [info[@"cc"] integerValue];
        m.minValue = 0;
        m.maxValue = 127;
        m.value = 40;
        m.hasBottomButton = YES;
        m.buttonMidiNumber = [info[@"note"] integerValue];
        m.buttonMode = @"toggle";
        m.buttonValue = YES;
        [l.controls addObject:m];
    }

    // Bells pad
    MidiControlModel *bells = [[MidiControlModel alloc] init];
    bells.controlId = @"pad_bells";
    bells.type = @"button";
    bells.label = @"BELLS";
    bells.frame = NSMakeRect(675, 25, 145, 145);
    bells.color = ColorFromHex(@"#574802");
    bells.accentColor = ColorFromHex(@"#c4a300");
    bells.midiChannel = 1;
    bells.midiType = @"note";
    bells.midiNumber = 72;
    bells.mode = @"momentary";
    [l.controls addObject:bells];

    // Synth filter knob
    MidiControlModel *knob = [[MidiControlModel alloc] init];
    knob.controlId = @"knob_synth_filter";
    knob.type = @"knob";
    knob.label = @"SYNTH FILTER";
    knob.frame = NSMakeRect(670, 220, 160, 190);
    knob.color = ColorFromHex(@"#00c853");
    knob.accentColor = ColorFromHex(@"#00e676");
    knob.midiChannel = 1;
    knob.midiType = @"cc";
    knob.midiNumber = 74;
    knob.minValue = 0;
    knob.maxValue = 127;
    knob.value = 65;
    [l.controls addObject:knob];

    return l;
}

+ (instancetype)mixer8Preset {
    LayoutModel *l = [[LayoutModel alloc] init];
    l.name = @"Mixer 8 Canais";
    l.canvasWidth = 960.0f;
    l.canvasHeight = 460.0f;
    NSArray *colors = @[@"#005f6b", @"#4b5358", @"#280659", @"#5e3e06", @"#0d4d22", @"#40064a", @"#004085", @"#721c24"];
    NSArray *accents = @[@"#00d2d3", @"#8395a7", @"#5f27cd", @"#ff9f43", @"#10ac84", @"#ee5253", @"#007bff", @"#f8d7da"];
    for (int i = 0; i < 8; i++) {
        MidiControlModel *m = [[MidiControlModel alloc] init];
        m.controlId = [NSString stringWithFormat:@"fader_ch%d", i + 1];
        m.type = @"fader";
        m.label = [NSString stringWithFormat:@"CH %d", i + 1];
        m.frame = NSMakeRect(15 + i * 115, 10, 85, 440);
        m.color = ColorFromHex(colors[i]);
        m.accentColor = ColorFromHex(accents[i]);
        m.midiChannel = 1;
        m.midiType = @"cc";
        m.midiNumber = 20 + i;
        m.minValue = 0;
        m.maxValue = 127;
        m.value = 64;
        m.hasBottomButton = YES;
        m.buttonMidiNumber = 48 + i;
        m.buttonMode = @"toggle";
        [l.controls addObject:m];
    }
    return l;
}

+ (instancetype)drumPadPreset {
    LayoutModel *l = [[LayoutModel alloc] init];
    l.name = @"Matriz 16 Pads";
    l.canvasWidth = 960.0f;
    l.canvasHeight = 460.0f;
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
        [l.controls addObject:m];
    }
    return l;
}

@end
