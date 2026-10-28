import Cocoa
import Darwin

public class AirPrimaryButton: NSButton {
    private var isPressed: Bool = false

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.isBordered = false
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.wantsLayer = true
        self.isBordered = false
    }

    public override var isFlipped: Bool { return true }

    public override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds

        let bg = isPressed ? NSColor(calibratedRed: 0.03, green: 0.42, blue: 0.85, alpha: 1.0) : AirColorAccent()
        bg.setFill()
        let pill = NSBezierPath(roundedRect: bounds, xRadius: 6.0, yRadius: 6.0)
        pill.fill()

        let img = self.image
        let buttonTitle = self.title

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12.0, weight: .semibold)
        ]
        let textSize = (buttonTitle as NSString).size(withAttributes: attrs)

        let spacing: CGFloat = 6.0
        let imgW: CGFloat = img?.size.width ?? 0
        let imgH: CGFloat = img?.size.height ?? 0
        let totalW = imgW + (img != nil ? spacing : 0) + textSize.width

        var curX = round((bounds.size.width - totalW) / 2.0)

        if let img = img {
            let imgY = round((bounds.size.height - imgH) / 2.0)
            let imgRect = NSRect(x: curX, y: imgY, width: imgW, height: imgH)
            img.draw(in: imgRect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: true, hints: nil)
            curX += imgW + spacing
        }

        let textY = round((bounds.size.height - textSize.height) / 2.0)
        let textRect = NSRect(x: curX, y: textY, width: textSize.width, height: textSize.height)
        (buttonTitle as NSString).draw(in: textRect, withAttributes: attrs)
    }

    public override func mouseDown(with event: NSEvent) {
        isPressed = true
        setNeedsDisplay(bounds)
        super.mouseDown(with: event)
        isPressed = false
        setNeedsDisplay(bounds)
    }
}

public class AirHeaderBarView: NSVisualEffectView {
    public override var isFlipped: Bool { return true }
    public override var mouseDownCanMoveWindow: Bool { return true }

    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        self.window?.performDrag(with: event)
    }
}

public class TouchStageRecentRowButton: NSButton {
    public var projectPath: String = ""
    public var projectName: String = ""
    public var projectOrientation: String = ""
    private var trackingAreaObj: NSTrackingArea?
    private var isHovered: Bool = false

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.isBordered = false
        self.wantsLayer = true
        self.title = ""
        updateTrackingAreas()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.isBordered = false
        self.wantsLayer = true
        self.title = ""
        updateTrackingAreas()
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingAreaObj {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(rect: self.bounds,
                                  options: [.mouseEnteredAndExited, .activeAlways],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingAreaObj = area
    }

    public override func mouseEntered(with event: NSEvent) {
        isHovered = true
        setNeedsDisplay(bounds)
    }

    public override func mouseExited(with event: NSEvent) {
        isHovered = false
        setNeedsDisplay(bounds)
    }

    public override var isFlipped: Bool { return true }

    public override func draw(_ dirtyRect: NSRect) {
        if isHovered {
            NSColor(calibratedWhite: 1.0, alpha: 0.08).setFill()
            let hoverBg = NSBezierPath(roundedRect: self.bounds, xRadius: 6.0, yRadius: 6.0)
            hoverBg.fill()
        }

        let isPortrait = (projectOrientation == "portrait")
        let iconSymbol = isPortrait ? "rectangle.portrait.fill" : "rectangle.fill"
        if let icon = AirSymbol(iconSymbol, 18.0) {
            let tinted = icon.copy() as! NSImage
            tinted.lockFocus()
            AirColorAccent().set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: 14, y: (self.bounds.size.height - 18) / 2.0, width: 18, height: 18),
                        from: .zero, operation: .sourceOver, fraction: isHovered ? 1.0 : 0.85)
        }

        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13.0, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        (projectName as NSString).draw(at: NSPoint(x: 46, y: 8.0), withAttributes: titleAttr)

        var sub = isPortrait ? "Vertical (460 × 920)" : "Horizontal (920 × 460)"
        if projectPath == "builtin_stage8" {
            sub += " • Factory Preset"
        } else if !projectPath.isEmpty {
            let folder = (projectPath as NSString).deletingLastPathComponent
            sub += " • \((folder as NSString).lastPathComponent)"
        }
        let subAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.0, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 0.6, alpha: 1.0)
        ]
        (sub as NSString).draw(at: NSPoint(x: 46, y: 26.0), withAttributes: subAttr)

        if let chevron = AirSymbol("chevron.right", 11.0) {
            let tinted = chevron.copy() as! NSImage
            tinted.lockFocus()
            NSColor(calibratedWhite: 0.75, alpha: 1.0).set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: NSRect(x: self.bounds.size.width - 24, y: (self.bounds.size.height - 11) / 2.0, width: 11, height: 11),
                        from: .zero, operation: .sourceOver, fraction: isHovered ? 1.0 : 0.4)
        }

        NSColor(calibratedWhite: 1.0, alpha: 0.06).setFill()
        NSRect(x: 46, y: self.bounds.size.height - 1.0, width: self.bounds.size.width - 46, height: 1.0).fill()
    }
}

public class EditorWindowController: NSWindowController, EditorCanvasDelegate, InspectorDelegate, AirTabBarDelegate {
    public var layout: LayoutModel = LayoutModel.blankLayout()

    private var canvasView: EditorCanvasView!
    private var inspectorView: InspectorView!
    private var tabBarView: AirTabBarView!
    private var presetsPopup: NSPopUpButton!
    private var orientationSegment: NSSegmentedControl!
    private var launcherSheetWindow: NSWindow?

    public init() {
        let frame = NSRect(x: 100, y: 100, width: 1260, height: 750)
        let window = NSWindow(contentRect: frame,
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = "TouchStage Editor"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = AirColorWindowBg()
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 1020, height: 600)

        super.init(window: window)
        setupViews()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        guard let contentView = self.window?.contentView else { return }
        let bounds = contentView.bounds

        let topBarH: CGFloat = 52.0
        let tabBarH: CGFloat = 38.0
        let inspectorW: CGFloat = 315.0
        let canvasW = bounds.size.width - inspectorW
        let bodyH = bounds.size.height - topBarH - tabBarH

        // 1. Frosted Glass Top Header Bar
        let topBar = AirHeaderBarView(frame: NSRect(x: 0, y: bounds.size.height - topBarH, width: bounds.size.width, height: topBarH))
        topBar.autoresizingMask = [.width, .minYMargin]
        topBar.material = .headerView
        topBar.blendingMode = .withinWindow
        topBar.state = .active

        let hairline = NSView(frame: NSRect(x: 0, y: topBarH - 1.0, width: bounds.size.width, height: 1.0))
        hairline.autoresizingMask = [.width, .minYMargin]
        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = AirColorBorder().cgColor
        topBar.addSubview(hairline)

        // --- LEFT GROUP: Preset Capsule & Save Preset (offset x=84 for traffic lights) ---
        presetsPopup = NSPopUpButton(frame: NSRect(x: 84, y: 12, width: 160, height: 28), pullsDown: false)
        presetsPopup.bezelStyle = .texturedRounded
        presetsPopup.font = NSFont.systemFont(ofSize: 12.0, weight: .medium)
        presetsPopup.target = self
        presetsPopup.action = #selector(onPresetSelected(_:))
        reloadPresetsMenu()
        topBar.addSubview(presetsPopup)

        let btnSavePreset = createToolbarButton(title: "Save Preset",
                                                symbol: "bookmark",
                                                tooltip: "Save current layout into preset library",
                                                frame: NSRect(x: 252, y: 12, width: 104, height: 28),
                                                action: #selector(onSavePresetClicked(_:)))
        btnSavePreset.autoresizingMask = [.maxXMargin]
        topBar.addSubview(btnSavePreset)

        let btnDeletePreset = createToolbarButton(title: "Delete",
                                                  symbol: "trash",
                                                  tooltip: "Delete selected user preset from library",
                                                  frame: NSRect(x: 362, y: 12, width: 80, height: 28),
                                                  action: #selector(onDeletePresetClicked(_:)))
        btnDeletePreset.autoresizingMask = [.maxXMargin]
        topBar.addSubview(btnDeletePreset)

        // --- RIGHT GROUP: File Open/Save & Primary Sync Action ---
        let btnSync = AirPrimaryButton(frame: NSRect(x: bounds.size.width - 170, y: 11, width: 154, height: 30))
        btnSync.autoresizingMask = [.minXMargin]
        btnSync.title = "Sync to Devices"
        btnSync.image = AirSymbol("antenna.radiowaves.left.and.right", 12.0)
        btnSync.toolTip = "Send layout directly to TouchStage Bridge and connected mobile devices"
        btnSync.target = self
        btnSync.action = #selector(onSendToBridgeClicked(_:))
        topBar.addSubview(btnSync)

        let rightDivider = NSView(frame: NSRect(x: bounds.size.width - 182, y: 15, width: 1.0, height: 22.0))
        rightDivider.autoresizingMask = [.minXMargin]
        rightDivider.wantsLayer = true
        rightDivider.layer?.backgroundColor = AirColorBorder().cgColor
        topBar.addSubview(rightDivider)

        let btnExport = createToolbarButton(title: "Save File",
                                            symbol: "square.and.arrow.up",
                                            tooltip: "Save Layout to JSON File (⌘S)",
                                            frame: NSRect(x: bounds.size.width - 290, y: 12, width: 96, height: 28),
                                            action: #selector(onSaveLayoutClicked(_:)))
        btnExport.autoresizingMask = [.minXMargin]
        topBar.addSubview(btnExport)

        let btnImport = createToolbarButton(title: "Open",
                                            symbol: "folder",
                                            tooltip: "Open Layout from JSON File (⌘O)",
                                            frame: NSRect(x: bounds.size.width - 378, y: 12, width: 80, height: 28),
                                            action: #selector(onOpenLayoutClicked(_:)))
        btnImport.autoresizingMask = [.minXMargin]
        topBar.addSubview(btnImport)

        let btnNew = createToolbarButton(title: "New Project",
                                         symbol: "plus",
                                         tooltip: "Create a new blank layout (⌘N)",
                                         frame: NSRect(x: bounds.size.width - 496, y: 12, width: 110, height: 28),
                                         action: #selector(onNewLayoutClicked(_:)))
        btnNew.autoresizingMask = [.minXMargin]
        topBar.addSubview(btnNew)

        orientationSegment = NSSegmentedControl(labels: ["Landscape", "Portrait"], trackingMode: .selectOne, target: self, action: #selector(onOrientationChanged(_:)))
        orientationSegment.frame = NSRect(x: bounds.size.width - 660, y: 12, width: 154, height: 28)
        orientationSegment.segmentStyle = .texturedRounded
        orientationSegment.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        orientationSegment.selectedSegment = (layout.canvasHeight > layout.canvasWidth) ? 1 : 0
        orientationSegment.autoresizingMask = [.minXMargin]
        topBar.addSubview(orientationSegment)

        // 2. Hardware-grade Canvas View
        canvasView = EditorCanvasView(frame: NSRect(x: 0, y: 0, width: canvasW, height: bodyH))
        canvasView.autoresizingMask = [.width, .height]
        canvasView.layout = layout
        canvasView.delegate = self
        contentView.addSubview(canvasView)

        // 3. Pro Sidebar Inspector View
        inspectorView = InspectorView(frame: NSRect(x: bounds.size.width - inspectorW, y: 0, width: inspectorW, height: bounds.size.height - topBarH))
        inspectorView.autoresizingMask = [.minXMargin, .height]
        inspectorView.delegate = self
        contentView.addSubview(inspectorView)

        // 4. Multi-Screen Tab Bar
        tabBarView = AirTabBarView(frame: NSRect(x: 0, y: bounds.size.height - topBarH - tabBarH, width: canvasW, height: tabBarH))
        tabBarView.autoresizingMask = [.width, .minYMargin]
        tabBarView.layout = layout
        tabBarView.delegate = self
        tabBarView.reloadTabs()
        contentView.addSubview(tabBarView)

        // 5. Add Header Bar on top of everything
        contentView.addSubview(topBar, positioned: .above, relativeTo: nil)
    }

    private func createToolbarButton(title: String, symbol: String, tooltip: String, frame: NSRect, action: Selector) -> NSButton {
        let btn = NSButton(frame: frame)
        btn.bezelStyle = .texturedRounded
        btn.title = title
        btn.image = AirSymbol(symbol, 12.0)
        btn.imagePosition = .imageLeading
        btn.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        btn.toolTip = tooltip
        btn.target = self
        btn.action = action
        return btn
    }

    public func showEditor() {
        self.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async { [weak self] in
            self?.showLauncherSheet()
        }
    }

    // MARK: - EditorCanvasDelegate

    public func canvasDidSelectControl(_ control: MidiControlModel?) {
        inspectorView.bindControl(control)
    }

    public func canvasDidChangeControl(_ control: MidiControlModel) {
        inspectorView.refreshValues()
    }

    public func canvasDidDeleteControl(_ control: MidiControlModel?) {
        inspectorView.bindControl(nil)
    }

    // MARK: - InspectorDelegate

    public func inspectorWillChangeControl(_ control: MidiControlModel) {
        canvasView.pushUndoSnapshot()
    }

    public func inspectorDidUpdateControl(_ control: MidiControlModel) {
        canvasView.setNeedsDisplay(canvasView.bounds)
    }

    public func inspectorDidRequestDuplicate(_ control: MidiControlModel) {
        canvasView.duplicateSelected()
    }

    public func inspectorDidRequestDelete(_ control: MidiControlModel) {
        canvasView.deleteSelected()
    }

    // MARK: - AirTabBarDelegate

    public func tabBarDidSelectPageIndex(_ index: Int) {
        if index >= 0 && index < layout.pages.count {
            layout.activePageIndex = index
            canvasView.selectedControl = nil
            inspectorView.bindControl(nil)
            tabBarView.reloadTabs()
            canvasView.setNeedsDisplay(canvasView.bounds)
        }
    }

    public func tabBarDidRequestAddPage() {
        let pageName = "Screen \(layout.pages.count + 1)"
        layout.addPage(withName: pageName)
        canvasView.selectedControl = nil
        inspectorView.bindControl(nil)
        tabBarView.reloadTabs()
        canvasView.setNeedsDisplay(canvasView.bounds)
    }

    public func tabBarDidRequestDeletePageIndex(_ index: Int) {
        if layout.pages.count <= 1 { return }
        layout.removePage(at: index)
        canvasView.selectedControl = nil
        inspectorView.bindControl(nil)
        tabBarView.reloadTabs()
        canvasView.setNeedsDisplay(canvasView.bounds)
    }

    public func tabBarDidRenamePageIndex(_ index: Int, toName newName: String) {
        if index >= 0 && index < layout.pages.count && !newName.isEmpty {
            layout.pages[index].name = newName
            tabBarView.reloadTabs()
        }
    }

    // MARK: - Presets & Storage

    private func presetsDirectoryPath() -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        let appSupport = paths.first ?? (NSHomeDirectory() + "/Library/Application Support")
        let dir = appSupport + "/TouchStage Editor/Presets"
        let studioDir = appSupport + "/TouchStage Studio/Presets"
        let legacyDir = appSupport + "/AirMIDI Studio/Presets"
        let fm = FileManager.default
        if fm.fileExists(atPath: studioDir) && !fm.fileExists(atPath: dir) {
            try? fm.copyItem(atPath: studioDir, toPath: dir)
        } else if fm.fileExists(atPath: legacyDir) && !fm.fileExists(atPath: dir) {
            try? fm.copyItem(atPath: legacyDir, toPath: dir)
        }
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
        return dir
    }

    public func reloadPresetsMenu() {
        presetsPopup.removeAllItems()

        let item1 = NSMenuItem(title: "Stage 8-Track", action: nil, keyEquivalent: "")
        item1.representedObject = "builtin_stage8"
        item1.image = AirSymbol("slider.vertical.3", 12.0)
        presetsPopup.menu?.addItem(item1)

        let dir = presetsDirectoryPath()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        var presetFiles: [String] = []
        for file in files {
            if (file as NSString).pathExtension.lowercased() == "json" {
                presetFiles.append(file)
            }
        }

        if !presetFiles.isEmpty {
            presetsPopup.menu?.addItem(NSMenuItem.separator())
            for file in presetFiles {
                let title = (file as NSString).deletingPathExtension
                let fullPath = (dir as NSString).appendingPathComponent(file)
                let uItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                uItem.representedObject = fullPath
                uItem.image = AirSymbol("doc.text", 12.0)
                presetsPopup.menu?.addItem(uItem)
            }
        }

        if presetsPopup.item(withTitle: layout.name) == nil && !layout.name.isEmpty {
            let curItem = NSMenuItem(title: layout.name, action: nil, keyEquivalent: "")
            curItem.representedObject = "current_unsaved"
            curItem.image = AirSymbol("doc.badge.plus", 12.0)
            presetsPopup.menu?.insertItem(curItem, at: 0)
        }

        if !layout.name.isEmpty {
            presetsPopup.selectItem(withTitle: layout.name)
        }
    }

    @IBAction public func onSavePresetClicked(_ sender: Any?) {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "Save as Editor Preset"
        alert.informativeText = "Enter a name for this layout to save it into your TouchStage Editor preset library:"
        alert.icon = AirSymbol("bookmark.circle.fill", 36.0)
        alert.addButton(withTitle: "Save Preset")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = layout.name.isEmpty ? "Custom Rig" : layout.name
        alert.accessoryView = input

        alert.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self = self else { return }
            if returnCode == .alertFirstButtonReturn {
                var name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { name = "Custom Rig" }
                self.layout.name = name

                let fileName = "\(name).json"
                let filePath = (self.presetsDirectoryPath() as NSString).appendingPathComponent(fileName)
                if let data = try? self.layout.toJSONData() {
                    try? data.write(to: URL(fileURLWithPath: filePath))
                    self.reloadPresetsMenu()
                    self.presetsPopup.selectItem(withTitle: name)
                    self.recordRecentProject(named: name, path: filePath, orientation: self.layout.orientation)
                }
            }
        }
    }

    @objc private func onOrientationChanged(_ sender: Any?) {
        let sel = orientationSegment.selectedSegment
        if sel == 1 { // Portrait
            layout.orientation = "portrait"
            layout.canvasWidth = 460.0
            layout.canvasHeight = 920.0
        } else { // Landscape
            layout.orientation = "landscape"
            layout.canvasWidth = 920.0
            layout.canvasHeight = 460.0
        }
        canvasView.setNeedsDisplay(canvasView.bounds)
    }

    @objc private func onPresetSelected(_ sender: Any?) {
        guard let item = presetsPopup.selectedItem else { return }

        if let rep = item.representedObject as? String {
            if rep == "current_unsaved" {
                return
            } else if rep == "builtin_stage8" {
                layout = LayoutModel.referencePreset()
                recordRecentProject(named: "Stage 8-Track", path: "builtin_stage8", orientation: "landscape")
            } else {
                if let data = try? Data(contentsOf: URL(fileURLWithPath: rep)),
                   let loaded = try? LayoutModel.layout(fromJSONData: data) {
                    layout = loaded
                    recordRecentProject(named: loaded.name, path: rep, orientation: loaded.orientation)
                }
            }
        }

        orientationSegment.selectedSegment = (layout.canvasHeight > layout.canvasWidth) ? 1 : 0
        canvasView.layout = layout
        tabBarView.layout = layout
        tabBarView.reloadTabs()
        inspectorView.bindControl(nil)
        reloadPresetsMenu()
    }

    @objc private func onDeletePresetClicked(_ sender: Any?) {
        guard let item = presetsPopup.selectedItem, let window = self.window else { return }

        if let rep = item.representedObject as? String, rep.hasPrefix("builtin_") || rep == "current_unsaved" {
            let alert = NSAlert()
            alert.messageText = "Cannot Delete Preset"
            alert.informativeText = "\"\(item.title)\" cannot be removed from presets."
            alert.icon = AirSymbol("lock.shield", 36.0)
            alert.addButton(withTitle: "OK")
            alert.beginSheetModal(for: window, completionHandler: nil)
            return
        }

        guard let filePath = item.representedObject as? String, FileManager.default.fileExists(atPath: filePath) else {
            return
        }

        let presetName = item.title
        let confirm = NSAlert()
        confirm.messageText = "Delete Preset \"\(presetName)\"?"
        confirm.informativeText = "Are you sure you want to permanently remove this preset from your library?"
        confirm.alertStyle = .critical
        confirm.icon = AirSymbol("trash.circle.fill", 36.0)
        confirm.addButton(withTitle: "Delete")
        confirm.addButton(withTitle: "Cancel")

        confirm.beginSheetModal(for: window) { [weak self] returnCode in
            guard let self = self else { return }
            if returnCode == .alertFirstButtonReturn {
                try? FileManager.default.removeItem(atPath: filePath)

                self.layout = LayoutModel.referencePreset()
                self.orientationSegment.selectedSegment = (self.layout.canvasHeight > self.layout.canvasWidth) ? 1 : 0
                self.canvasView.layout = self.layout
                self.tabBarView.layout = self.layout
                self.tabBarView.reloadTabs()
                self.inspectorView.bindControl(nil)

                self.reloadPresetsMenu()
                self.presetsPopup.selectItem(at: 0)
            }
        }
    }

    @IBAction public func onNewLayoutClicked(_ sender: Any?) {
        guard let window = self.window else { return }
        let alert = NSAlert()
        alert.messageText = "New Project"
        alert.informativeText = "Enter a name and screen orientation for your TouchStage project:"
        alert.icon = AirSymbol("doc.badge.plus", 36.0)
        alert.addButton(withTitle: "Create Project")
        alert.addButton(withTitle: "Cancel")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 75))

        let labelName = NSTextField(frame: NSRect(x: 0, y: 52, width: 280, height: 16))
        labelName.stringValue = "Project Name:"
        labelName.font = NSFont.systemFont(ofSize: 11.0, weight: .medium)
        labelName.textColor = .secondaryLabelColor
        labelName.isBezeled = false
        labelName.drawsBackground = false
        labelName.isEditable = false
        container.addSubview(labelName)

        let input = NSTextField(frame: NSRect(x: 0, y: 26, width: 280, height: 22))
        input.stringValue = "Untitled Project"
        container.addSubview(input)

        let orientChoice = NSSegmentedControl(labels: ["Horizontal (Landscape)", "Vertical (Portrait)"], trackingMode: .selectOne, target: nil, action: nil)
        orientChoice.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        orientChoice.segmentStyle = .texturedRounded
        orientChoice.font = NSFont.systemFont(ofSize: 11.0)
        orientChoice.selectedSegment = (orientationSegment.selectedSegment == 1) ? 1 : 0
        container.addSubview(orientChoice)

        alert.accessoryView = container

        alert.beginSheetModal(for: window) { [weak self] returnCode in
            if returnCode == .alertFirstButtonReturn {
                var name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if name.isEmpty { name = "Untitled Project" }
                let isPortrait = (orientChoice.selectedSegment == 1)
                self?.startNewProject(named: name, isPortrait: isPortrait)
            }
        }
    }

    public func startNewProject(named name: String, isPortrait: Bool) {
        let newLayout = LayoutModel()
        newLayout.name = name.isEmpty ? "Untitled Project" : name
        if isPortrait {
            newLayout.orientation = "portrait"
            newLayout.canvasWidth = 460.0
            newLayout.canvasHeight = 920.0
        } else {
            newLayout.orientation = "landscape"
            newLayout.canvasWidth = 920.0
            newLayout.canvasHeight = 460.0
        }
        layout = newLayout
        orientationSegment.selectedSegment = isPortrait ? 1 : 0
        canvasView.layout = newLayout
        tabBarView.layout = newLayout
        tabBarView.reloadTabs()
        inspectorView.bindControl(nil)
        presetsPopup.selectItem(at: -1)
        recordRecentProject(named: newLayout.name, path: "", orientation: newLayout.orientation)
    }

    @IBAction public func onSaveLayoutClicked(_ sender: Any?) {
        guard let window = self.window else { return }
        let savePanel = NSSavePanel()
        savePanel.title = "Export TouchStage Layout File"
        savePanel.nameFieldStringValue = "\(layout.name.lowercased().replacingOccurrences(of: " ", with: "_")).json"

        savePanel.beginSheetModal(for: window) { [weak self] result in
            guard let self = self else { return }
            if result == .OK, let url = savePanel.url {
                if let data = try? self.layout.toJSONData() {
                    try? data.write(to: url)
                    self.recordRecentProject(named: self.layout.name, path: url.path, orientation: self.layout.orientation)
                }
            }
        }
    }

    @IBAction public func onOpenLayoutClicked(_ sender: Any?) {
        guard let window = self.window else { return }
        let openPanel = NSOpenPanel()
        openPanel.title = "Open TouchStage Layout File"

        openPanel.beginSheetModal(for: window) { [weak self] result in
            guard let self = self else { return }
            if result == .OK, let url = openPanel.url {
                if let data = try? Data(contentsOf: url),
                   let loaded = try? LayoutModel.layout(fromJSONData: data) {
                    self.layout = loaded
                    self.orientationSegment.selectedSegment = (loaded.canvasHeight > loaded.canvasWidth) ? 1 : 0
                    self.canvasView.layout = loaded
                    self.tabBarView.layout = loaded
                    self.tabBarView.reloadTabs()
                    self.inspectorView.bindControl(nil)
                    self.presetsPopup.selectItem(withTitle: loaded.name)
                    self.recordRecentProject(named: loaded.name, path: url.path, orientation: loaded.orientation)
                }
            }
        }
    }

    @IBAction public func onSendToBridgeClicked(_ sender: Any?) {
        let syncedCount = pushLayoutToLocalBridgeSilently()
        let alert = NSAlert()

        if syncedCount < 0 {
            alert.icon = AirSymbol("exclamationmark.triangle.fill", 36.0)
            alert.messageText = "TouchStage Bridge Not Found"
            alert.informativeText = "TouchStage Bridge is not currently running.\n\nPlease launch TouchStage Bridge from your Applications to connect devices."
            alert.addButton(withTitle: "OK")
        } else if syncedCount == 0 {
            alert.icon = AirSymbol("wifi.slash", 36.0)
            alert.messageText = "No Mobile Devices Connected"
            alert.informativeText = "TouchStage Bridge is active, but no mobile device is currently connected to it.\n\nPlease open TouchStage on your mobile device (Android) and connect to this Mac first, then click Sync to Devices."
            alert.addButton(withTitle: "OK")
        } else {
            alert.icon = AirSymbol("checkmark.circle.fill", 36.0)
            alert.messageText = "Layout Synchronized"
            alert.informativeText = "Layout \"\(layout.name)\" was successfully transmitted to \(syncedCount) connected mobile device(s).\n\nTap 'Update Layout' on your mobile screen to load it."
            alert.addButton(withTitle: "Done")
        }

        if let window = self.window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        }
    }

    private func pushLayoutToLocalBridgeSilently() -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        if sock < 0 { return -1 }

        var tv = timeval(tv_sec: 1, tv_usec: 500000)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(9000).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let connectRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if connectRes != 0 {
            Darwin.close(sock)
            return -1
        }

        var json = layout.toJSONString()
        json = json.replacingOccurrences(of: "\r", with: "")
        json = json.replacingOccurrences(of: "\n", with: " ")

        let payload = "SYNC_LAYOUT:\(json)\n"
        guard let data = payload.data(using: .utf8) else {
            Darwin.close(sock)
            return 0
        }

        data.withUnsafeBytes { rawBuf in
            guard let ptr = rawBuf.baseAddress else { return }
            var sent = 0
            let total = data.count
            while sent < total {
                let n = send(sock, ptr.advanced(by: sent), total - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }

        var ackBuf = [CChar](repeating: 0, count: 64)
        let ackLen = recv(sock, &ackBuf, ackBuf.count - 1, 0)
        Darwin.close(sock)

        if ackLen > 0 {
            let ackStr = String(cString: ackBuf)
            if ackStr.hasPrefix("OK:SYNC:") {
                let countStr = String(ackStr.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
                return Int(countStr) ?? 1
            }
            if ackStr.hasPrefix("OK:SYNC") {
                return 1
            }
        }

        return 0
    }

    // MARK: - Responder Chain Actions

    @objc public func undo(_ sender: Any?) {
        canvasView.undo()
    }

    @objc public func redo(_ sender: Any?) {
        canvasView.redo()
    }

    @objc public override func selectAll(_ sender: Any?) {
        canvasView.selectAllControls()
    }

    @objc public func deleteSelected(_ sender: Any?) {
        canvasView.deleteSelected()
    }

    // MARK: - Recents & Launcher Sheet

    private func recordRecentProject(named name: String, path: String, orientation: String) {
        if name.isEmpty { return }
        var recents = (UserDefaults.standard.array(forKey: "TouchStageRecentProjects") as? [[String: Any]]) ?? []

        recents.removeAll { dict in
            let dictPath = dict["path"] as? String ?? ""
            let dictName = dict["name"] as? String ?? ""
            return (!path.isEmpty && dictPath == path) || dictName == name
        }

        recents.insert([
            "name": name,
            "path": path,
            "orientation": orientation,
            "date": Date()
        ], at: 0)

        while recents.count > 15 {
            recents.removeLast()
        }

        UserDefaults.standard.set(recents, forKey: "TouchStageRecentProjects")
    }

    private func loadRecentProjects() -> [[String: Any]] {
        var results: [[String: Any]] = []

        // 1. Built-in
        results.append([
            "name": "Stage 8-Track",
            "path": "builtin_stage8",
            "orientation": "landscape"
        ])

        // 2. Presets Directory
        let dir = presetsDirectoryPath()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        for file in files {
            if (file as NSString).pathExtension.lowercased() == "json" {
                let title = (file as NSString).deletingPathExtension
                let fullPath = (dir as NSString).appendingPathComponent(file)
                var orient = "landscape"
                if let d = try? Data(contentsOf: URL(fileURLWithPath: fullPath)),
                   let dict = try? JSONSerialization.jsonObject(with: d, options: []) as? [String: Any] {
                    if let o = dict["orientation"] as? String {
                        orient = o
                    } else if let ch = dict["canvasHeight"] as? NSNumber, let cw = dict["canvasWidth"] as? NSNumber, ch.doubleValue > cw.doubleValue {
                        orient = "portrait"
                    }
                }
                results.append([
                    "name": title,
                    "path": fullPath,
                    "orientation": orient
                ])
            }
        }

        // 3. Saved Recents
        if let savedRecents = UserDefaults.standard.array(forKey: "TouchStageRecentProjects") as? [[String: Any]] {
            for item in savedRecents {
                let p = item["path"] as? String ?? ""
                let name = item["name"] as? String ?? ""
                if !p.lowercased().contains("builtin_stage8") && !p.lowercased().contains("builtin_stage6") {
                    let alreadyAdded = results.contains {
                        ($0["path"] as? String == p) || ($0["name"] as? String == name)
                    }
                    if !alreadyAdded && (p.isEmpty || FileManager.default.fileExists(atPath: p)) {
                        results.append(item)
                    }
                }
            }
        }

        return results
    }

    @objc public func showLauncherSheet() {
        if launcherSheetWindow != nil { return }
        guard let window = self.window else { return }

        let sheetFrame = NSRect(x: 0, y: 0, width: 650, height: 420)
        let sheet = NSWindow(contentRect: sheetFrame,
                             styleMask: [.titled, .fullSizeContentView],
                             backing: .buffered,
                             defer: false)
        sheet.titlebarAppearsTransparent = true
        sheet.titleVisibility = .hidden
        sheet.isMovableByWindowBackground = true

        let vibrant = NSVisualEffectView(frame: sheetFrame)
        vibrant.autoresizingMask = [.width, .height]
        vibrant.material = .underWindowBackground
        vibrant.blendingMode = .behindWindow
        vibrant.state = .active
        sheet.contentView = vibrant

        // Left Column
        let leftCol = NSView(frame: NSRect(x: 0, y: 0, width: 225, height: 420))
        leftCol.wantsLayer = true
        leftCol.layer?.backgroundColor = NSColor(calibratedWhite: 0.06, alpha: 0.75).cgColor
        vibrant.addSubview(leftCol)

        let leftDivider = NSView(frame: NSRect(x: 224, y: 0, width: 1, height: 420))
        leftDivider.wantsLayer = true
        leftDivider.layer?.backgroundColor = AirColorBorder().cgColor
        leftCol.addSubview(leftDivider)

        let iconView = NSImageView(frame: NSRect(x: 24, y: 326, width: 56, height: 56))
        var appIcon = NSImage(named: NSImage.applicationIconName)
        if appIcon == nil, let iconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns") {
            appIcon = NSImage(contentsOfFile: iconPath)
        }
        iconView.image = appIcon ?? AirSymbol("slider.vertical.3", 44.0)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        leftCol.addSubview(iconView)

        let titleLbl = NSTextField(frame: NSRect(x: 24, y: 290, width: 180, height: 26))
        titleLbl.stringValue = "TouchStage"
        titleLbl.font = NSFont.systemFont(ofSize: 18.0, weight: .bold)
        titleLbl.textColor = .white
        titleLbl.isBezeled = false
        titleLbl.drawsBackground = false
        titleLbl.isEditable = false
        leftCol.addSubview(titleLbl)

        let subLbl = NSTextField(frame: NSRect(x: 24, y: 270, width: 180, height: 18))
        subLbl.stringValue = "MIDI Layout Editor"
        subLbl.font = NSFont.systemFont(ofSize: 11.0, weight: .medium)
        subLbl.textColor = .secondaryLabelColor
        subLbl.isBezeled = false
        subLbl.drawsBackground = false
        subLbl.isEditable = false
        leftCol.addSubview(subLbl)

        let brandHairline = NSView(frame: NSRect(x: 24, y: 256, width: 177, height: 1))
        brandHairline.wantsLayer = true
        brandHairline.layer?.backgroundColor = AirColorBorder().cgColor
        leftCol.addSubview(brandHairline)

        let btnNew = NSButton(frame: NSRect(x: 24, y: 198, width: 177, height: 38))
        btnNew.bezelStyle = .texturedRounded
        btnNew.title = "  New Project"
        btnNew.image = AirSymbol("plus.circle.fill", 15.0)
        btnNew.imagePosition = .imageLeading
        btnNew.font = NSFont.systemFont(ofSize: 12.5, weight: .bold)
        btnNew.target = self
        btnNew.action = #selector(onLauncherNewProject(_:))
        leftCol.addSubview(btnNew)

        let btnOpen = NSButton(frame: NSRect(x: 24, y: 152, width: 177, height: 34))
        btnOpen.bezelStyle = .texturedRounded
        btnOpen.title = "  Open Project..."
        btnOpen.image = AirSymbol("folder.fill", 13.0)
        btnOpen.imagePosition = .imageLeading
        btnOpen.font = NSFont.systemFont(ofSize: 12.0, weight: .medium)
        btnOpen.target = self
        btnOpen.action = #selector(onLauncherOpenFile(_:))
        leftCol.addSubview(btnOpen)

        // Right Column
        let rightCol = NSView(frame: NSRect(x: 225, y: 0, width: 425, height: 420))
        vibrant.addSubview(rightCol)

        let recentHeader = NSTextField(frame: NSRect(x: 24, y: 372, width: 220, height: 22))
        recentHeader.stringValue = "RECENT PROJECTS"
        recentHeader.font = NSFont.systemFont(ofSize: 11.5, weight: .bold)
        recentHeader.textColor = .secondaryLabelColor
        recentHeader.isBezeled = false
        recentHeader.drawsBackground = false
        recentHeader.isEditable = false
        rightCol.addSubview(recentHeader)

        let btnClose = NSButton(frame: NSRect(x: 425 - 34, y: 368, width: 22, height: 22))
        btnClose.bezelStyle = .circular
        btnClose.image = AirSymbol("xmark", 10.0)
        btnClose.imagePosition = .imageOnly
        btnClose.isBordered = false
        btnClose.wantsLayer = true
        btnClose.toolTip = "Close (Esc)"
        btnClose.keyEquivalent = "\u{1b}"
        btnClose.target = self
        btnClose.action = #selector(onCloseLauncherSheet(_:))
        rightCol.addSubview(btnClose)

        let rightDivider = NSView(frame: NSRect(x: 24, y: 358, width: 380, height: 1))
        rightDivider.wantsLayer = true
        rightDivider.layer?.backgroundColor = AirColorBorder().cgColor
        rightCol.addSubview(rightDivider)

        let recents = loadRecentProjects()
        let rowH: CGFloat = 50.0
        let listContentH = max(330.0, CGFloat(recents.count) * rowH + 10.0)

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 16, width: 388, height: 334))
        scrollView.hasVerticalScroller = (CGFloat(recents.count) * rowH > 330.0)
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        let listDocView = NSView(frame: NSRect(x: 0, y: 0, width: 388, height: listContentH))
        scrollView.documentView = listDocView
        rightCol.addSubview(scrollView)

        var curY = listContentH - rowH - 6.0
        for item in recents {
            let rowBtn = TouchStageRecentRowButton(frame: NSRect(x: 4, y: curY, width: 380, height: rowH))
            rowBtn.projectName = (item["name"] as? String) ?? "Untitled Project"
            rowBtn.projectPath = (item["path"] as? String) ?? ""
            rowBtn.projectOrientation = (item["orientation"] as? String) ?? "landscape"
            rowBtn.target = self
            rowBtn.action = #selector(onRecentRowClicked(_:))
            listDocView.addSubview(rowBtn)
            curY -= rowH
        }

        launcherSheetWindow = sheet
        window.beginSheet(sheet, completionHandler: nil)
    }

    @objc private func onLauncherNewProject(_ sender: Any?) {
        closeLauncherSheet { [weak self] in
            self?.onNewLayoutClicked(nil)
        }
    }

    @objc private func onLauncherOpenFile(_ sender: Any?) {
        closeLauncherSheet { [weak self] in
            self?.onOpenLayoutClicked(nil)
        }
    }

    @objc private func onRecentRowClicked(_ sender: TouchStageRecentRowButton) {
        let path = sender.projectPath
        let name = sender.projectName
        closeLauncherSheet { [weak self] in
            self?.openRecentProject(path: path, name: name)
        }
    }

    @objc private func onCloseLauncherSheet(_ sender: Any?) {
        closeLauncherSheet(completion: nil)
    }

    private func closeLauncherSheet(completion: (() -> Void)?) {
        guard let sheet = launcherSheetWindow, let window = self.window else {
            completion?()
            return
        }
        launcherSheetWindow = nil
        window.endSheet(sheet)
        sheet.orderOut(nil)
        if let completion = completion {
            DispatchQueue.main.async(execute: completion)
        }
    }

    private func openRecentProject(path: String, name: String) {
        if path == "builtin_stage8" || path == "builtin_stage6" {
            layout = LayoutModel.referencePreset()
        } else if !path.isEmpty && FileManager.default.fileExists(atPath: path) {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
               let loaded = try? LayoutModel.layout(fromJSONData: data) {
                layout = loaded
            } else {
                layout = LayoutModel.referencePreset()
            }
        } else {
            layout = LayoutModel.referencePreset()
        }

        orientationSegment.selectedSegment = (layout.canvasHeight > layout.canvasWidth) ? 1 : 0
        canvasView.layout = layout
        tabBarView.layout = layout
        tabBarView.reloadTabs()
        inspectorView.bindControl(nil)
        reloadPresetsMenu()
        if !layout.name.isEmpty {
            presetsPopup.selectItem(withTitle: layout.name)
        }
        recordRecentProject(named: layout.name, path: path, orientation: layout.orientation)
    }
}
