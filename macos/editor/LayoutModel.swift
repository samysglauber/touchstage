import Cocoa

public func ColorFromHex(_ hexStr: String?) -> NSColor {
    guard let hex = hexStr, !hex.isEmpty else { return NSColor.cyan }
    let clean = hex.replacingOccurrences(of: "#", with: "")
    guard let rgb = UInt32(clean, radix: 16) else { return NSColor.cyan }
    let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
    let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
    let b = CGFloat(rgb & 0xFF) / 255.0
    return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
}

public func HexFromColor(_ color: NSColor?) -> String {
    guard let color = color else { return "#00e5ff" }
    let rgb = color.usingColorSpace(.sRGB) ?? color
    let r = Int(round(rgb.redComponent * 255.0))
    let g = Int(round(rgb.greenComponent * 255.0))
    let b = Int(round(rgb.blueComponent * 255.0))
    return String(format: "#%02x%02x%02x", r, g, b)
}

public func DeriveDarkBaseColor(from color: NSColor?) -> NSColor {
    guard let color = color else { return NSColor(calibratedWhite: 0.12, alpha: 1.0) }
    let rgb = color.usingColorSpace(.deviceRGB) ?? color
    var h: CGFloat = 0
    var s: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    
    // For white, silver, or very low saturation grays, use neutral grayscale tones without hue tint
    if s < 0.15 {
        let darkVal = max(0.14, min(0.32, b * 0.28))
        return NSColor(calibratedWhite: darkVal, alpha: 1.0)
    }

    let newS = min(1.0, max(0.65, s * 1.15))
    let newB = max(0.12, min(0.42, b * 0.38))
    return NSColor(hue: h, saturation: newS, brightness: newB, alpha: 1.0)
}

@objc public class MidiControlModel: NSObject, NSCopying {
    public var controlId: String = ""
    public var type: String = "fader" // "fader", "knob", "button", "xypad", "label"
    public var label: String = "CONTROL"
    public var frame: NSRect = NSRect(x: 0, y: 0, width: 80, height: 200)
    public var color: NSColor = NSColor.cyan
    public var accentColor: NSColor = NSColor.cyan
    public var midiChannel: Int = 1 // 1 - 16
    public var midiType: String = "cc" // "cc", "note", "pitchbend"
    public var midiNumber: Int = 7 // 0 - 127
    public var minValue: Int = 0
    public var maxValue: Int = 127
    public var value: Double = 0.0

    // Options
    public var hasLabel: Bool = false
    public var labelPosition: String = "top" // "top", "bottom"
    public var orientation: String = "vertical" // "vertical", "horizontal"
    public var knobStyle: String = "standard" // "standard", "inverted", "centered"
    public var valueDisplay: String = "none" // "none", "scale", "percent"
    public var valuePosition: String = "center" // "center", "bottom"
    public var valueFontSize: CGFloat = 0.0 // 0 = auto
    public var faderStyle: String = "standard" // "standard", "inverted", "centered"
    public var fontSize: CGFloat = 0.0
    public var shape: String = "square" // "square", "circle"
    public var hasBackground: Bool = false
    public var hasVuMeter: Bool = false
    public var vuMidiChannel: Int = 1
    public var vuMidiNumber: Int = 7
    public var vuLevel: CGFloat = 0.0
    public var peakLevel: CGFloat = 0.0
    public var hasBottomButton: Bool = false
    public var buttonMidiNumber: Int = 60
    public var buttonMode: String = "toggle"
    public var buttonValue: Bool = false
    public var mode: String = "momentary" // "momentary", "toggle"

    public override init() {
        super.init()
        self.controlId = String(format: "ctrl_%u", arc4random() % 10000)
    }

    public func copy(with zone: NSZone? = nil) -> Any {
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
        copy.vuLevel = self.vuLevel
        copy.peakLevel = self.peakLevel
        copy.hasBottomButton = self.hasBottomButton
        copy.buttonMidiNumber = self.buttonMidiNumber
        copy.buttonMode = self.buttonMode
        copy.buttonValue = self.buttonValue
        copy.mode = self.mode
        return copy
    }

    public static func control(with dict: [String: Any]) -> MidiControlModel {
        let m = MidiControlModel()
        m.controlId = (dict["id"] as? String) ?? String(format: "ctrl_%u", arc4random() % 10000)
        m.type = (dict["type"] as? String) ?? "fader"
        m.label = (dict["label"] as? String) ?? "CONTROL"

        let x = (dict["x"] as? NSNumber)?.doubleValue ?? 0
        let y = (dict["y"] as? NSNumber)?.doubleValue ?? 0
        let w = (dict["width"] as? NSNumber)?.doubleValue ?? 80
        let h = (dict["height"] as? NSNumber)?.doubleValue ?? 200
        m.frame = NSRect(x: x, y: y, width: w > 10 ? w : 80, height: h > 10 ? h : 200)

        m.color = ColorFromHex(dict["color"] as? String)
        m.accentColor = ColorFromHex(dict["accentColor"] as? String)
        m.midiChannel = (dict["midiChannel"] as? NSNumber)?.intValue ?? 1
        m.midiType = (dict["midiType"] as? String) ?? "cc"
        m.midiNumber = (dict["midiNumber"] as? NSNumber)?.intValue ?? 7
        m.minValue = (dict["minValue"] as? NSNumber)?.intValue ?? 0
        m.maxValue = (dict["maxValue"] as? NSNumber)?.intValue ?? 127
        m.value = (dict["value"] as? NSNumber)?.doubleValue ?? 0.0

        m.hasLabel = (dict["hasLabel"] as? NSNumber)?.boolValue ?? false
        m.labelPosition = (dict["labelPosition"] as? String) ?? (m.type == "knob" ? "bottom" : "top")
        m.orientation = (dict["orientation"] as? String) ?? "vertical"
        m.knobStyle = (dict["knobStyle"] as? String) ?? "standard"
        m.valueDisplay = (dict["valueDisplay"] as? String) ?? "none"
        m.valuePosition = (dict["valuePosition"] as? String) ?? "center"
        var vFontSize = CGFloat((dict["valueFontSize"] as? NSNumber)?.doubleValue ?? 0.0)
        if m.valuePosition == "center" && vFontSize > 20.0 {
            vFontSize = 20.0
        }
        m.valueFontSize = vFontSize
        m.faderStyle = (dict["faderStyle"] as? String) ?? "standard"
        m.fontSize = CGFloat((dict["fontSize"] as? NSNumber)?.doubleValue ?? 0.0)
        m.shape = (dict["shape"] as? String) ?? "square"
        m.hasBackground = (dict["hasBackground"] as? NSNumber)?.boolValue ?? (m.type == "fader" || m.type == "label")
        m.hasVuMeter = (dict["hasVuMeter"] as? NSNumber)?.boolValue ?? false
        m.vuMidiChannel = (dict["vuMidiChannel"] as? NSNumber)?.intValue ?? m.midiChannel
        m.vuMidiNumber = (dict["vuMidiNumber"] as? NSNumber)?.intValue ?? m.midiNumber
        m.hasBottomButton = (dict["hasBottomButton"] as? NSNumber)?.boolValue ?? false
        m.buttonMidiNumber = (dict["buttonMidiNumber"] as? NSNumber)?.intValue ?? 60
        m.buttonMode = (dict["buttonMode"] as? String) ?? "toggle"
        m.buttonValue = (dict["buttonValue"] as? NSNumber)?.boolValue ?? false
        m.mode = (dict["mode"] as? String) ?? "momentary"
        return m
    }

    public func toDictionary() -> [String: Any] {
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
            "faderStyle": faderStyle
        ]

        if fontSize > 0 {
            dict["fontSize"] = fontSize
        }
        if valueFontSize > 0 {
            dict["valueFontSize"] = valueFontSize
        }

        if type == "fader" {
            dict["hasVuMeter"] = hasVuMeter
            if vuMidiNumber > 0 { dict["vuMidiNumber"] = vuMidiNumber }
            if vuMidiChannel > 0 { dict["vuMidiChannel"] = vuMidiChannel }
            dict["hasBackground"] = hasBackground
        } else if type == "button" {
            dict["shape"] = shape
            dict["mode"] = mode
        } else if type == "label" {
            dict["hasBackground"] = hasBackground
        }

        return dict
    }
}

@objc public class LayoutPageModel: NSObject, NSCopying {
    public var pageId: String = ""
    public var name: String = "Screen 1"
    public var controls: [MidiControlModel] = []

    public override init() {
        super.init()
        self.pageId = String(format: "page_%u", arc4random() % 10000)
    }

    public static func page(withName name: String) -> LayoutPageModel {
        let p = LayoutPageModel()
        p.name = name.isEmpty ? "Screen" : name
        return p
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = LayoutPageModel()
        copy.pageId = self.pageId
        copy.name = self.name
        copy.controls = self.controls.map { ($0.copy() as! MidiControlModel) }
        return copy
    }

    public static func page(with dict: [String: Any]) -> LayoutPageModel {
        let p = LayoutPageModel()
        p.pageId = (dict["id"] as? String) ?? String(format: "page_%u", arc4random() % 10000)
        p.name = (dict["name"] as? String) ?? "Screen"
        if let ctrls = dict["controls"] as? [[String: Any]] {
            for cDict in ctrls {
                p.controls.append(MidiControlModel.control(with: cDict))
            }
        }
        return p
    }

    public func toDictionary() -> [String: Any] {
        return [
            "id": pageId,
            "name": name,
            "controls": controls.map { $0.toDictionary() }
        ]
    }
}

@objc public class LayoutModel: NSObject {
    public var name: String = "Untitled Project"
    public var author: String = "TouchStage Editor"
    public var version: String = "1.0"
    public var canvasWidth: CGFloat = 920.0
    public var canvasHeight: CGFloat = 460.0
    public var orientation: String = "landscape"
    public var pages: [LayoutPageModel] = []
    public var activePageIndex: Int = 0

    public override init() {
        super.init()
        self.pages.append(LayoutPageModel.page(withName: "Screen 1"))
    }

    public var activePage: LayoutPageModel {
        if pages.isEmpty {
            pages.append(LayoutPageModel.page(withName: "Screen 1"))
            activePageIndex = 0
        }
        if activePageIndex < 0 || activePageIndex >= pages.count {
            activePageIndex = 0
        }
        return pages[activePageIndex]
    }

    public var controls: [MidiControlModel] {
        get { return activePage.controls }
        set { activePage.controls = newValue }
    }

    @discardableResult
    public func addPage(withName name: String) -> LayoutPageModel {
        let p = LayoutPageModel.page(withName: name)
        pages.append(p)
        activePageIndex = pages.count - 1
        return p
    }

    public func removePage(at index: Int) {
        if index >= 0 && index < pages.count && pages.count > 1 {
            pages.remove(at: index)
            if activePageIndex >= pages.count {
                activePageIndex = pages.count - 1
            }
        }
    }

    public static func layout(fromJSONData data: Data) throws -> LayoutModel {
        guard let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw NSError(domain: "TouchStage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }

        let model = LayoutModel()
        model.name = (dict["name"] as? String) ?? "Untitled Layout"
        model.author = (dict["author"] as? String) ?? "AirMIDI"
        model.version = (dict["version"] as? String) ?? "1.0"
        if let cw = dict["canvasWidth"] as? NSNumber { model.canvasWidth = CGFloat(cw.doubleValue) }
        if let ch = dict["canvasHeight"] as? NSNumber { model.canvasHeight = CGFloat(ch.doubleValue) }
        if let ori = dict["orientation"] as? String {
            model.orientation = ori
        } else {
            model.orientation = (model.canvasHeight > model.canvasWidth) ? "portrait" : "landscape"
        }

        model.pages.removeAll()

        if let pagesArr = dict["pages"] as? [[String: Any]], !pagesArr.isEmpty {
            for pDict in pagesArr {
                model.pages.append(LayoutPageModel.page(with: pDict))
            }
        } else {
            // Fallback for single-page legacy layouts
            let defaultPage = LayoutPageModel.page(withName: "Screen 1")
            if let ctrls = dict["controls"] as? [[String: Any]] {
                for cDict in ctrls {
                    defaultPage.controls.append(MidiControlModel.control(with: cDict))
                }
            }
            model.pages.append(defaultPage)
        }

        if let activeIdx = dict["activePageIndex"] as? NSNumber {
            model.activePageIndex = activeIdx.intValue
        } else {
            model.activePageIndex = 0
        }

        return model
    }

    public func toJSONData() throws -> Data {
        let root: [String: Any] = [
            "name": name,
            "author": author,
            "version": version,
            "canvasWidth": canvasWidth,
            "canvasHeight": canvasHeight,
            "orientation": orientation,
            "activePageIndex": activePageIndex,
            "pages": pages.map { $0.toDictionary() },
            "controls": controls.map { $0.toDictionary() }
        ]
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
    }

    public func toJSONString() -> String {
        let root: [String: Any] = [
            "name": name,
            "author": author,
            "version": version,
            "canvasWidth": canvasWidth,
            "canvasHeight": canvasHeight,
            "orientation": orientation,
            "activePageIndex": activePageIndex,
            "pages": pages.map { $0.toDictionary() },
            "controls": controls.map { $0.toDictionary() }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: []) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    // Blank Project (Clean Empty Canvas)
    public static func blankLayout(name: String = "Untitled Project", orientation: String = "landscape") -> LayoutModel {
        let l = LayoutModel()
        l.name = name
        let isPortrait = (orientation == "portrait")
        l.canvasWidth = isPortrait ? 460.0 : 920.0
        l.canvasHeight = isPortrait ? 920.0 : 460.0
        l.orientation = orientation
        l.pages.removeAll()
        let page = LayoutPageModel.page(withName: "Screen 1")
        l.pages.append(page)
        l.activePageIndex = 0
        l.controls = page.controls
        return l
    }

    // Reference Factory Preset: Stage 8-Track (8 Faders, 8 Buttons, 8 Knobs locked to 20px Grid)
    public static func referencePreset() -> LayoutModel {
        let l = LayoutModel()
        l.name = "Stage 8-Track"
        l.canvasWidth = 920.0
        l.canvasHeight = 460.0
        l.pages.removeAll()

        let page1 = LayoutPageModel.page(withName: "Mixer 8-Track")

        let channels: [[String: String]] = [
            ["id": "ch1", "label": "CH 1", "color": "#005f73", "accent": "#00F0FF"],
            ["id": "ch2", "label": "CH 2", "color": "#0369a1", "accent": "#38BDF8"],
            ["id": "ch3", "label": "CH 3", "color": "#4c1d95", "accent": "#C084FC"],
            ["id": "ch4", "label": "CH 4", "color": "#78350f", "accent": "#FBBF24"],
            ["id": "ch5", "label": "CH 5", "color": "#064e3b", "accent": "#00E676"],
            ["id": "ch6", "label": "CH 6", "color": "#831843", "accent": "#FF2E93"],
            ["id": "ch7", "label": "CH 7", "color": "#881337", "accent": "#FB7185"],
            ["id": "ch8", "label": "CH 8", "color": "#3f6212", "accent": "#A3E635"]
        ]

        let faderVals: [Double] = [80.0, 85.0, 82.0, 80.0, 84.0, 76.0, 88.0, 72.0]
        let knobVals: [Double] = [64.0, 50.0, 64.0, 50.0, 64.0, 50.0, 64.0, 50.0]

        for i in 0..<8 {
            let ch = channels[i]
            let x: CGFloat = CGFloat(60 + i * 100) // 20px grid aligned: 60, 160, 260, 360, 460, 560, 660, 760

            // 1. Vertical Fader (80 x 220 at y=20 -> ends at y=240)
            let f = MidiControlModel()
            f.controlId = "fader_\(ch["id"]!)"
            f.type = "fader"
            f.label = ch["label"]!
            f.frame = NSRect(x: x, y: 20, width: 80, height: 220)
            f.color = ColorFromHex(ch["color"])
            f.accentColor = ColorFromHex(ch["accent"])
            f.midiChannel = 1
            f.midiType = "cc"
            f.midiNumber = 11 + i
            f.minValue = 0
            f.maxValue = 127
            f.value = faderVals[i]
            f.hasLabel = true
            f.labelPosition = "top"
            f.hasBackground = true
            page1.controls.append(f)

            // 2. Toggle Illuminated Pad Button (80 x 60 at y=260 -> ends at y=320)
            let btn = MidiControlModel()
            btn.controlId = "btn_\(ch["id"]!)"
            btn.type = "button"
            btn.shape = "square"
            btn.label = ""
            btn.frame = NSRect(x: x, y: 260, width: 80, height: 60)
            btn.color = ColorFromHex(ch["color"])
            btn.accentColor = ColorFromHex(ch["accent"])
            btn.midiChannel = 1
            btn.midiType = "note"
            btn.midiNumber = 60 + i
            btn.mode = "toggle"
            btn.value = 127
            page1.controls.append(btn)

            // 3. Rotary Knob with Value Readout (80 x 80 at y=340 -> ends at y=420)
            let kn = MidiControlModel()
            kn.controlId = "knob_\(ch["id"]!)"
            kn.type = "knob"
            kn.shape = "circle"
            kn.label = ""
            kn.frame = NSRect(x: x, y: 340, width: 80, height: 80)
            kn.color = ColorFromHex(ch["color"])
            kn.accentColor = ColorFromHex(ch["accent"])
            kn.midiChannel = 1
            kn.midiType = "cc"
            kn.midiNumber = 21 + i
            kn.minValue = 0
            kn.maxValue = 127
            kn.value = knobVals[i]
            kn.hasLabel = false
            kn.valueDisplay = "scale"
            kn.valuePosition = "center"
            page1.controls.append(kn)
        }

        l.pages.append(page1)
        l.activePageIndex = 0
        l.controls = page1.controls
        return l
    }

    public static func mixer8Preset() -> LayoutModel {
        let l = LayoutModel()
        l.name = "Mixer 8 Canais"
        l.canvasWidth = 960.0
        l.canvasHeight = 460.0
        l.pages.removeAll()

        let page1 = LayoutPageModel.page(withName: "Canais 1-8")
        let colors = ["#005f6b", "#4b5358", "#280659", "#5e3e06", "#0d4d22", "#40064a", "#004085", "#721c24"]
        let accents = ["#00d2d3", "#8395a7", "#5f27cd", "#ff9f43", "#10ac84", "#ee5253", "#007bff", "#f8d7da"]
        for i in 0..<8 {
            let m = MidiControlModel()
            m.controlId = "fader_ch\(i + 1)"
            m.type = "fader"
            m.label = "CH \(i + 1)"
            m.frame = NSRect(x: 15 + i * 115, y: 10, width: 85, height: 360)
            m.color = ColorFromHex(colors[i])
            m.accentColor = ColorFromHex(accents[i])
            m.midiChannel = 1
            m.midiType = "cc"
            m.midiNumber = 20 + i
            m.minValue = 0
            m.maxValue = 127
            m.value = 64
            m.hasLabel = true
            m.labelPosition = "top"
            page1.controls.append(m)

            let btn = MidiControlModel()
            btn.controlId = "btn_ch\(i + 1)"
            btn.type = "button"
            btn.shape = "circle"
            btn.label = ""
            btn.frame = NSRect(x: 30 + i * 115, y: 385, width: 56, height: 56)
            btn.color = ColorFromHex(colors[i])
            btn.accentColor = ColorFromHex(accents[i])
            btn.midiChannel = 1
            btn.midiType = "note"
            btn.midiNumber = 48 + i
            btn.mode = "toggle"
            btn.value = 127
            page1.controls.append(btn)
        }
        l.pages.append(page1)

        let page2 = LayoutPageModel.page(withName: "Master & Aux")
        let master = MidiControlModel()
        master.controlId = "fader_master"
        master.type = "fader"
        master.label = "MASTER"
        master.frame = NSRect(x: 800, y: 20, width: 100, height: 410)
        master.color = ColorFromHex("#c0392b")
        master.accentColor = ColorFromHex("#e74c3c")
        master.midiChannel = 1
        master.midiType = "cc"
        master.midiNumber = 7
        master.hasLabel = true
        master.labelPosition = "top"
        page2.controls.append(master)
        l.pages.append(page2)

        l.activePageIndex = 0
        return l
    }

    public static func drumPadPreset() -> LayoutModel {
        let l = LayoutModel()
        l.name = "Matriz 16 Pads"
        l.canvasWidth = 960.0
        l.canvasHeight = 460.0
        l.pages.removeAll()

        let page1 = LayoutPageModel.page(withName: "16 Pads")
        for i in 0..<16 {
            let row = i / 4
            let col = i % 4
            let m = MidiControlModel()
            m.controlId = "pad_\(i + 1)"
            m.type = "button"
            m.label = "PAD \(i + 1)"
            m.frame = NSRect(x: 20 + col * 120, y: 20 + (3 - row) * 105, width: 105, height: 90)
            m.color = ColorFromHex("#182030")
            m.accentColor = ColorFromHex("#00e5ff")
            m.midiChannel = 10
            m.midiType = "note"
            m.midiNumber = 36 + i
            m.mode = "momentary"
            page1.controls.append(m)
        }
        l.pages.append(page1)
        l.activePageIndex = 0
        return l
    }
}
