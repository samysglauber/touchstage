#import <Cocoa/Cocoa.h>

static inline NSImage *AirSymbol(NSString *symbolName, CGFloat pointSize) {
    if (@available(macOS 11.0, *)) {
        NSImage *img = [NSImage imageWithSystemSymbolName:symbolName accessibilityDescription:nil];
        if (img) {
            if (pointSize > 0) {
                NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:pointSize weight:NSFontWeightMedium];
                return [img imageWithSymbolConfiguration:config];
            }
            return img;
        }
    }
    return nil;
}

static inline NSColor *AirColorWindowBg(void) {
    return [NSColor colorWithCalibratedRed:0.07f green:0.08f blue:0.10f alpha:1.0f];
}

static inline NSColor *AirColorCanvasDeviceBg(void) {
    return [NSColor colorWithCalibratedRed:0.04f green:0.045f blue:0.06f alpha:1.0f];
}

static inline NSColor *AirColorPanelBg(void) {
    return [NSColor colorWithCalibratedRed:0.10f green:0.11f blue:0.14f alpha:1.0f];
}

static inline NSColor *AirColorCardBg(void) {
    return [NSColor colorWithCalibratedRed:0.14f green:0.15f blue:0.19f alpha:1.0f];
}

static inline NSColor *AirColorBorder(void) {
    return [NSColor colorWithCalibratedWhite:0.18f alpha:1.0f];
}

static inline NSColor *AirColorAccent(void) {
    return [NSColor colorWithCalibratedRed:0.04f green:0.52f blue:1.0f alpha:1.0f]; // #0A84FF
}

static inline NSColor *AirColorTextPrimary(void) {
    return [NSColor colorWithCalibratedWhite:0.95f alpha:1.0f];
}

static inline NSColor *AirColorTextSecondary(void) {
    return [NSColor colorWithCalibratedWhite:0.60f alpha:1.0f];
}

static inline NSColor *AirColorTextMuted(void) {
    return [NSColor colorWithCalibratedWhite:0.38f alpha:1.0f];
}

static inline NSColor *AirColorDanger(void) {
    return [NSColor colorWithCalibratedRed:1.0f green:0.27f blue:0.23f alpha:1.0f]; // #FF453A
}

static inline NSColor *AirColorSuccess(void) {
    return [NSColor colorWithCalibratedRed:0.19f green:0.82f blue:0.35f alpha:1.0f]; // #30D158
}
