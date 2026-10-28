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

// Fader extra options
@property (nonatomic, assign) BOOL hasBottomButton;
@property (nonatomic, assign) NSInteger buttonMidiNumber;
@property (nonatomic, copy) NSString *buttonMode; // "toggle", "momentary"
@property (nonatomic, assign) BOOL buttonValue;

// Button mode
@property (nonatomic, copy) NSString *mode; // "momentary", "toggle"

+ (instancetype)controlWithDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;
@end

@interface LayoutModel : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *author;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, assign) CGFloat canvasWidth;
@property (nonatomic, assign) CGFloat canvasHeight;
@property (nonatomic, strong) NSMutableArray<MidiControlModel *> *controls;

+ (instancetype)layoutFromJSONData:(NSData *)data error:(NSError **)error;
+ (instancetype)referencePreset;
+ (instancetype)mixer8Preset;
+ (instancetype)drumPadPreset;

- (NSData *)toJSONDataWithError:(NSError **)error;
- (NSString *)toJSONString;
@end
