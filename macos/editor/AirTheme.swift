import Cocoa

public func AirSymbol(_ symbolName: String, _ pointSize: CGFloat = 0) -> NSImage? {
    if #available(macOS 11.0, *) {
        guard let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
        if pointSize > 0 {
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
            return img.withSymbolConfiguration(config)
        }
        return img
    }
    return nil
}

public func AirColorWindowBg() -> NSColor {
    return NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0)
}

public func AirColorCanvasDeviceBg() -> NSColor {
    return NSColor(calibratedRed: 0.04, green: 0.045, blue: 0.06, alpha: 1.0)
}

public func AirColorPanelBg() -> NSColor {
    return NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1.0)
}

public func AirColorCardBg() -> NSColor {
    return NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.19, alpha: 1.0)
}

public func AirColorBorder() -> NSColor {
    return NSColor(calibratedWhite: 0.18, alpha: 1.0)
}

public func AirColorAccent() -> NSColor {
    return NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 1.0)
}

public func AirColorTextPrimary() -> NSColor {
    return NSColor(calibratedWhite: 0.95, alpha: 1.0)
}

public func AirColorTextSecondary() -> NSColor {
    return NSColor(calibratedWhite: 0.60, alpha: 1.0)
}

public func AirColorTextMuted() -> NSColor {
    return NSColor(calibratedWhite: 0.38, alpha: 1.0)
}

public func AirColorDanger() -> NSColor {
    return NSColor(calibratedRed: 1.0, green: 0.27, blue: 0.23, alpha: 1.0)
}

public func AirColorSuccess() -> NSColor {
    return NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1.0)
}
