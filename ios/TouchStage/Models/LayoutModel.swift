import UIKit

public class LayoutPageModel {
    public var pageId: String = ""
    public var name: String = "Screen 1"
    public var controls: [MidiControlModel] = []

    public init(name: String = "Screen 1") {
        self.pageId = UUID().uuidString
        self.name = name
    }

    public static func page(withName name: String) -> LayoutPageModel {
        let p = LayoutPageModel(name: name)
        p.pageId = "page_\(name.lowercased().replacingOccurrences(of: " ", with: "_"))"
        return p
    }

    public func copy() -> LayoutPageModel {
        let p = LayoutPageModel(name: self.name)
        p.pageId = self.pageId
        p.controls = self.controls.map { $0.copy() }
        return p
    }
}

public class LayoutModel {
    public var name: String = "TouchStage Layout"
    public var author: String = "User"
    public var version: String = "1.0"
    public var canvasWidth: CGFloat = 920.0
    public var canvasHeight: CGFloat = 460.0
    public var activePageIndex: Int = 0
    public var pages: [LayoutPageModel] = []

    public var currentPage: LayoutPageModel? {
        guard !pages.isEmpty else { return nil }
        if activePageIndex >= 0 && activePageIndex < pages.count {
            return pages[activePageIndex]
        }
        return pages[0]
    }

    public init() {}

    public convenience init?(jsonData: Data) {
        self.init()
        guard let obj = try? JSONSerialization.jsonObject(with: jsonData, options: []),
              let dict = obj as? [String: Any] else {
            return nil
        }
        self.load(from: dict)
    }

    public convenience init?(jsonString: String) {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        self.init(jsonData: data)
    }

    public func load(from dict: [String: Any]) {
        name = (dict["name"] as? String) ?? "TouchStage Layout"
        author = (dict["author"] as? String) ?? "User"
        version = (dict["version"] as? String) ?? "1.0"
        canvasWidth = CGFloat((dict["canvasWidth"] as? NSNumber)?.doubleValue ?? 920.0)
        canvasHeight = CGFloat((dict["canvasHeight"] as? NSNumber)?.doubleValue ?? 460.0)
        activePageIndex = (dict["activePageIndex"] as? NSNumber)?.intValue ?? 0

        pages.removeAll()
        if let rawPages = dict["pages"] as? [[String: Any]] {
            for pDict in rawPages {
                let page = LayoutPageModel(name: (pDict["name"] as? String) ?? "Screen")
                page.pageId = (pDict["id"] as? String) ?? UUID().uuidString
                if let rawCtrls = pDict["controls"] as? [[String: Any]] {
                    for cDict in rawCtrls {
                        page.controls.append(MidiControlModel(dictionary: cDict))
                    }
                }
                pages.append(page)
            }
        }

        if pages.isEmpty {
            pages.append(LayoutPageModel.page(withName: "Main"))
        }
        if activePageIndex >= pages.count {
            activePageIndex = 0
        }
    }

    public func toJsonData() -> Data? {
        var pageDicts: [[String: Any]] = []
        for p in pages {
            var ctrlDicts: [[String: Any]] = []
            for c in p.controls {
                ctrlDicts.append(c.dictionaryRepresentation())
            }
            pageDicts.append([
                "id": p.pageId,
                "name": p.name,
                "controls": ctrlDicts
            ])
        }

        let root: [String: Any] = [
            "name": name,
            "author": author,
            "version": version,
            "canvasWidth": canvasWidth,
            "canvasHeight": canvasHeight,
            "activePageIndex": activePageIndex,
            "pages": pageDicts
        ]

        return try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted])
    }

    // -------------------------------------------------------------
    // Factory Built-in Presets
    // -------------------------------------------------------------

    public static func presetStage8Track() -> LayoutModel {
        let l = LayoutModel()
        l.name = "Stage 8-Track"
        l.author = "TouchStage"
        l.version = "1.0"
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
            let x: CGFloat = CGFloat(60 + i * 100)

            // 1. Vertical Fader
            let f = MidiControlModel()
            f.controlId = "fader_\(ch["id"]!)"
            f.type = "fader"
            f.label = ch["label"]!
            f.frame = CGRect(x: x, y: 20, width: 80, height: 220)
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

            // 2. Toggle Pad Button
            let btn = MidiControlModel()
            btn.controlId = "btn_\(ch["id"]!)"
            btn.type = "button"
            btn.shape = "square"
            btn.label = ""
            btn.frame = CGRect(x: x, y: 260, width: 80, height: 60)
            btn.color = ColorFromHex(ch["color"])
            btn.accentColor = ColorFromHex(ch["accent"])
            btn.midiChannel = 1
            btn.midiType = "note"
            btn.midiNumber = 60 + i
            btn.mode = "toggle"
            btn.value = 127
            page1.controls.append(btn)

            // 3. Rotary Knob with center value readout
            let kn = MidiControlModel()
            kn.controlId = "knob_\(ch["id"]!)"
            kn.type = "knob"
            kn.shape = "circle"
            kn.label = ""
            kn.frame = CGRect(x: x, y: 340, width: 80, height: 80)
            kn.color = ColorFromHex(ch["color"])
            kn.accentColor = ColorFromHex(ch["accent"])
            kn.midiChannel = 1
            kn.midiType = "cc"
            kn.midiNumber = 21 + i
            kn.minValue = 0
            kn.maxValue = 127
            kn.value = knobVals[i]
            kn.valueDisplay = "scale"
            kn.valuePosition = "center"
            kn.valueFontSize = 13.0
            kn.hasLabel = false
            page1.controls.append(kn)
        }

        l.pages.append(page1)
        return l
    }

    public static func presetDrumPads() -> LayoutModel {
        let l = LayoutModel()
        l.name = "16-Pad Matrix"
        l.canvasWidth = 920.0
        l.canvasHeight = 460.0
        l.pages.removeAll()

        let page1 = LayoutPageModel.page(withName: "Drum Pads")
        let padColors = ["#00F0FF", "#38BDF8", "#C084FC", "#FBBF24",
                         "#00E676", "#FF2E93", "#FB7185", "#A3E635",
                         "#00F0FF", "#38BDF8", "#C084FC", "#FBBF24",
                         "#00E676", "#FF2E93", "#FB7185", "#A3E635"]

        for i in 0..<16 {
            let row = i / 4
            let col = i % 4
            let padW: CGFloat = 170.0
            let padH: CGFloat = 85.0
            let padX: CGFloat = 60.0 + CGFloat(col) * 195.0
            let padY: CGFloat = 30.0 + CGFloat(row) * 100.0

            let m = MidiControlModel()
            m.controlId = "pad_\(i + 1)"
            m.type = "button"
            m.shape = "square"
            m.label = "PAD \(i + 1)"
            m.frame = CGRect(x: padX, y: padY, width: padW, height: padH)
            m.accentColor = ColorFromHex(padColors[i])
            m.color = DeriveDarkBaseColor(from: m.accentColor)
            m.midiChannel = 10
            m.midiType = "note"
            m.midiNumber = 36 + i
            m.mode = "momentary"
            page1.controls.append(m)
        }

        l.pages.append(page1)
        return l
    }
}
