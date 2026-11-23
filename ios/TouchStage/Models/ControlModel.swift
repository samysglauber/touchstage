import UIKit

public func ColorFromHex(_ hexStr: String?) -> UIColor {
    guard let hex = hexStr, !hex.isEmpty else { return UIColor.cyan }
    let clean = hex.replacingOccurrences(of: "#", with: "")
    guard let rgb = UInt32(clean, radix: 16) else { return UIColor.cyan }
    let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
    let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
    let b = CGFloat(rgb & 0xFF) / 255.0
    return UIColor(red: r, green: g, blue: b, alpha: 1.0)
}

public func HexFromColor(_ color: UIColor?) -> String {
    guard let color = color else { return "#00e5ff" }
    var r: CGFloat = 0
    var g: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    let ri = Int(round(r * 255.0))
    let gi = Int(round(g * 255.0))
    let bi = Int(round(b * 255.0))
    return String(format: "#%02x%02x%02x", ri, gi, bi)
}

public func DeriveDarkBaseColor(from color: UIColor?) -> UIColor {
    guard let color = color else { return UIColor(white: 0.12, alpha: 1.0) }
    var h: CGFloat = 0
    var s: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    color.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    
    // For white, silver, or very low saturation grays, use neutral grayscale tones without hue tint
    if s < 0.15 {
        let darkVal = max(0.14, min(0.32, b * 0.28))
        return UIColor(white: darkVal, alpha: 1.0)
    }

    let newS = min(1.0, max(0.65, s * 1.15))
    let newB = max(0.12, min(0.42, b * 0.38))
    return UIColor(hue: h, saturation: newS, brightness: newB, alpha: 1.0)
}

public class MidiControlModel {
    public var controlId: String = ""
    public var type: String = "fader" // "fader", "knob", "button", "xypad", "label", "vu"
    public var label: String = "CONTROL"
    public var frame: CGRect = CGRect(x: 0, y: 0, width: 80, height: 200)
    public var color: UIColor = UIColor.cyan
    public var accentColor: UIColor = UIColor.cyan
    public var midiChannel: Int = 1 // 1 - 16
    public var midiType: String = "cc" // "cc", "note", "pitchbend"
    public var midiNumber: Int = 7 // 0 - 127
    public var minValue: Int = 0
    public var maxValue: Int = 127
    public var value: Double = 0.0

    // Options
    public var hasLabel: Bool = true
    public var labelPosition: String = "top" // "top", "bottom"
    public var orientation: String = "vertical" // "vertical", "horizontal"
    public var knobStyle: String = "standard" // "standard", "inverted", "centered"
    public var valueDisplay: String = "none" // "none", "scale", "percent"
    public var valuePosition: String = "center" // "center", "bottom"
    public var valueFontSize: CGFloat = 0.0 // 0 = auto, max 20pt for center
    public var faderStyle: String = "standard" // "standard", "inverted", "centered"
    public var fontSize: CGFloat = 0.0
    public var shape: String = "square" // "square", "circle"
    public var hasBackground: Bool = true
    public var hasVuMeter: Bool = false
    public var vuMidiChannel: Int = 1
    public var vuMidiNumber: Int = 0
    public var vuLevel: Double = 0.0
    public var hasBottomButton: Bool = false
    public var buttonMidiNumber: Int = 60
    public var buttonMode: String = "toggle"
    public var buttonValue: Bool = false
    public var isMuted: Bool = false
    public var mode: String = "momentary" // "momentary", "toggle"
    public var valueX: Double = 64.0
    public var valueY: Double = 64.0

    // Runtime Interactive State (Zero-allocation animation & touch tracking)
    public var isPressed: Bool = false
    public var buttonActivation: CGFloat = 0.0
    public var buttonFlash: CGFloat = 0.0
    public var initialTouchPoint: CGPoint = .zero
    public var initialValue: Double = 0.0
    public var initialAngle: CGFloat = 0.0

    public init() {}

    public init(dictionary dict: [String: Any]) {
        controlId = (dict["id"] as? String) ?? (dict["controlId"] as? String) ?? UUID().uuidString
        type = (dict["type"] as? String) ?? "fader"
        label = (dict["label"] as? String) ?? ""

        let x = CGFloat((dict["x"] as? NSNumber)?.doubleValue ?? 0.0)
        let y = CGFloat((dict["y"] as? NSNumber)?.doubleValue ?? 0.0)
        let w = CGFloat((dict["width"] as? NSNumber)?.doubleValue ?? 80.0)
        let h = CGFloat((dict["height"] as? NSNumber)?.doubleValue ?? 200.0)
        frame = CGRect(x: x, y: y, width: max(10, w), height: max(10, h))

        color = ColorFromHex(dict["color"] as? String)
        accentColor = ColorFromHex(dict["accentColor"] as? String)
        midiChannel = (dict["midiChannel"] as? NSNumber)?.intValue ?? 1
        midiType = (dict["midiType"] as? String) ?? "cc"
        midiNumber = (dict["midiNumber"] as? NSNumber)?.intValue ?? 7
        minValue = (dict["minValue"] as? NSNumber)?.intValue ?? 0
        maxValue = (dict["maxValue"] as? NSNumber)?.intValue ?? 127
        value = (dict["value"] as? NSNumber)?.doubleValue ?? 0.0

        hasLabel = (dict["hasLabel"] as? NSNumber)?.boolValue ?? false
        labelPosition = (dict["labelPosition"] as? String) ?? (type == "knob" ? "bottom" : "top")
        orientation = (dict["orientation"] as? String) ?? "vertical"
        knobStyle = (dict["knobStyle"] as? String) ?? "standard"
        valueDisplay = (dict["valueDisplay"] as? String) ?? "none"
        valuePosition = (dict["valuePosition"] as? String) ?? "center"
        var vFontSize = CGFloat((dict["valueFontSize"] as? NSNumber)?.doubleValue ?? 0.0)
        if valuePosition == "center" && vFontSize > 20.0 {
            vFontSize = 20.0
        }
        valueFontSize = vFontSize

        faderStyle = (dict["faderStyle"] as? String) ?? "standard"
        fontSize = CGFloat((dict["fontSize"] as? NSNumber)?.doubleValue ?? 0.0)
        shape = (dict["shape"] as? String) ?? "square"
        hasBackground = (dict["hasBackground"] as? NSNumber)?.boolValue ?? (type == "fader" || type == "label")
        hasVuMeter = (dict["hasVuMeter"] as? NSNumber)?.boolValue ?? false
        vuMidiChannel = (dict["vuMidiChannel"] as? NSNumber)?.intValue ?? midiChannel
        vuMidiNumber = (dict["vuMidiNumber"] as? NSNumber)?.intValue ?? midiNumber
        hasBottomButton = (dict["hasBottomButton"] as? NSNumber)?.boolValue ?? false
        buttonMidiNumber = (dict["buttonMidiNumber"] as? NSNumber)?.intValue ?? 60
        buttonMode = (dict["buttonMode"] as? String) ?? "toggle"
        buttonValue = (dict["buttonValue"] as? NSNumber)?.boolValue ?? false
        isMuted = (dict["isMuted"] as? NSNumber)?.boolValue ?? false
        mode = (dict["mode"] as? String) ?? "momentary"
        valueX = (dict["valueX"] as? NSNumber)?.doubleValue ?? 64.0
        valueY = (dict["valueY"] as? NSNumber)?.doubleValue ?? 64.0
    }

    public func dictionaryRepresentation() -> [String: Any] {
        var dict: [String: Any] = [
            "id": controlId,
            "type": type,
            "label": label,
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.size.width,
            "height": frame.size.height,
            "color": HexFromColor(color),
            "accentColor": HexFromColor(accentColor),
            "midiChannel": midiChannel,
            "midiType": midiType,
            "midiNumber": midiNumber,
            "minValue": minValue,
            "maxValue": maxValue,
            "value": value,
            "hasLabel": hasLabel,
            "labelPosition": labelPosition,
            "orientation": orientation,
            "knobStyle": knobStyle,
            "valueDisplay": valueDisplay,
            "valuePosition": valuePosition,
            "faderStyle": faderStyle,
            "hasBackground": hasBackground
        ]

        if fontSize > 0 { dict["fontSize"] = fontSize }
        if valueFontSize > 0 { dict["valueFontSize"] = valueFontSize }

        if type == "fader" {
            dict["hasVuMeter"] = hasVuMeter
            if vuMidiNumber > 0 { dict["vuMidiNumber"] = vuMidiNumber }
            if vuMidiChannel > 0 { dict["vuMidiChannel"] = vuMidiChannel }
            dict["hasBottomButton"] = hasBottomButton
            dict["buttonMidiNumber"] = buttonMidiNumber
            dict["buttonMode"] = buttonMode
            dict["buttonValue"] = buttonValue
        } else if type == "button" {
            dict["shape"] = shape
            dict["mode"] = mode
        } else if type == "xypad" {
            dict["valueX"] = valueX
            dict["valueY"] = valueY
        }
        return dict
    }

    public func copy() -> MidiControlModel {
        let copy = MidiControlModel()
        copy.controlId = self.controlId
        copy.type = self.type
        copy.label = self.label
        copy.frame = self.frame
        copy.color = self.color
        copy.accentColor = self.accentColor
        copy.midiChannel = self.midiChannel
        copy.midiType = self.midiType
        copy.midiNumber = self.midiNumber
        copy.minValue = self.minValue
        copy.maxValue = self.maxValue
        copy.value = self.value
        copy.hasLabel = self.hasLabel
        copy.labelPosition = self.labelPosition
        copy.orientation = self.orientation
        copy.knobStyle = self.knobStyle
        copy.valueDisplay = self.valueDisplay
        copy.valuePosition = self.valuePosition
        copy.valueFontSize = self.valueFontSize
        copy.faderStyle = self.faderStyle
        copy.fontSize = self.fontSize
        copy.shape = self.shape
        copy.hasBackground = self.hasBackground
        copy.hasVuMeter = self.hasVuMeter
        copy.vuMidiChannel = self.vuMidiChannel
        copy.vuMidiNumber = self.vuMidiNumber
        copy.hasBottomButton = self.hasBottomButton
        copy.buttonMidiNumber = self.buttonMidiNumber
        copy.buttonMode = self.buttonMode
        copy.buttonValue = self.buttonValue
        copy.isMuted = self.isMuted
        copy.mode = self.mode
        copy.valueX = self.valueX
        copy.valueY = self.valueY
        return copy
    }
}
