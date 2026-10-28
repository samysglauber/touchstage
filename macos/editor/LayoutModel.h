#import <Cocoa/Cocoa.h>

@interface MidiControlModel : NSObject <NSCopying>
@property (nonatomic, copy) NSString *controlId;
@property (nonatomic, copy) NSString *type; // "fader", "knob", "button", "xypad", "label"
@property (nonatomic, copy) NSString *label;
@property (nonatomic, assign) NSRect frame;
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, strong) NSColor *accentColor;
@property (nonatomic, assign) NSInteger midiChannel; // 1 - 16
@property (nonatomic, copy) NSString *midiType; // "cc", "note", "pitchbend"
@property (nonatomic, assign) NSInteger midiNumber; // 0 - 127
@property (nonatomic, assign) NSInteger minValue;
@property (nonatomic, assign) NSInteger maxValue;
@property (nonatomic, assign) CGFloat value;

// Options
@property (nonatomic, assign) BOOL hasLabel;
@property (nonatomic, copy) NSString *labelPosition; // @"top", @"bottom"
@property (nonatomic, copy) NSString *orientation; // @"vertical", @"horizontal" (for faders)
@property (nonatomic, copy) NSString *knobStyle; // @"standard", @"inverted", @"centered" (for knobs)
@property (nonatomic, copy) NSString *faderStyle; // @"standard", @"inverted", @"centered" (for faders)
@property (nonatomic, assign) CGFloat fontSize; // font size for label (0 = default)
@property (nonatomic, copy) NSString *shape; // @"square", @"circle"
@property (nonatomic, assign) BOOL hasBackground; // for label controls
@property (nonatomic, assign) BOOL hasVuMeter; // integrated VU meter on fader
@property (nonatomic, assign) NSInteger vuMidiChannel; // 1-16 (0 = default to control midiChannel)
@property (nonatomic, assign) NSInteger vuMidiNumber;  // CC number for VU meter (0 = default to midiNumber)
@property (nonatomic, assign) CGFloat vuLevel; // live VU level 0.0 - 1.0
@property (nonatomic, assign) CGFloat peakLevel; // live peak hold level 0.0 - 1.0
@property (nonatomic, assign) BOOL hasBottomButton;
@property (nonatomic, assign) NSInteger buttonMidiNumber;
@property (nonatomic, copy) NSString *buttonMode; // "toggle", "momentary"
@property (nonatomic, assign) BOOL buttonValue;

// Button mode
@property (nonatomic, copy) NSString *mode; // "momentary", "toggle"

+ (instancetype)controlWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;
@end

@interface LayoutPageModel : NSObject <NSCopying>
@property (nonatomic, copy) NSString *pageId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, strong) NSMutableArray<MidiControlModel *> *controls;

+ (instancetype)pageWithName:(NSString *)name;
+ (instancetype)pageWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;
@end

@interface LayoutModel : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, assign) CGFloat canvasWidth;
@property (nonatomic, assign) CGFloat canvasHeight;
@property (nonatomic, copy) NSString *orientation; // @"landscape", @"portrait"
@property (nonatomic, strong) NSMutableArray<LayoutPageModel *> *pages;
@property (nonatomic, assign) NSInteger activePageIndex;

// Convenience access to active page controls
- (NSMutableArray<MidiControlModel *> *)controls;
- (LayoutPageModel *)activePage;
- (LayoutPageModel *)addPageWithName:(NSString *)name;
- (void)removePageAtIndex:(NSInteger)index;

+ (instancetype)layoutFromJSONData:(NSData *)data error:(NSError **)error;
+ (instancetype)referencePreset;
+ (instancetype)mixer8Preset;
+ (instancetype)drumPadPreset;

- (NSData *)toJSONDataWithError:(NSError **)error;
- (NSString *)toJSONString;
@end
