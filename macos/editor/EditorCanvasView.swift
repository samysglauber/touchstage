import Cocoa

@objc public protocol EditorCanvasDelegate: AnyObject {
    func canvasDidSelectControl(_ control: MidiControlModel?)
    func canvasDidChangeControl(_ control: MidiControlModel)
    func canvasDidDeleteControl(_ control: MidiControlModel?)
}

public class EditorCanvasView: NSView {
    public weak var delegate: EditorCanvasDelegate?
    public var layout: LayoutModel = LayoutModel.referencePreset() {
        didSet {
            selectedControls.removeAll()
            undoStack.removeAll()
            redoStack.removeAll()
            setNeedsDisplay(bounds)
        }
    }

    public var selectedControls: [MidiControlModel] = []
    public var selectedControl: MidiControlModel? {
        get { return selectedControls.last }
        set {
            selectedControls.removeAll()
            if let val = newValue {
                selectedControls.append(val)
            }
            setNeedsDisplay(bounds)
        }
    }

    public var snapToGrid: Bool = true
    public var gridSize: CGFloat = 20.0

    private var isDragging: Bool = false
    private var isResizing: Bool = false
    private var resizeCorner: Int = 0 // 1: top-left, 2: top-right, 3: bottom-right, 4: bottom-left
    private var dragStartMouse: NSPoint = .zero
    private var initialControlFrame: NSRect = .zero
    private var initialFramesByControlId: [String: NSRect] = [:]
    private var lastRightClickPoint: NSPoint = .zero

    // Marquee / Rubberband Selection
    private var isMarqueeSelecting: Bool = false
    private var marqueeStartPoint: NSPoint = .zero
    private var marqueeRect: NSRect = .zero
    private var initialSelectionBeforeMarquee: [MidiControlModel]?
    private var clickedControlOnMouseDown: MidiControlModel?
    private var clickedControlWasAlreadySelected: Bool = false

    private var floatingSnapBtn: NSButton!
    private var floatingGridSizePopup: NSPopUpButton!
    private var copiedControls: [MidiControlModel] = []
    private var undoStack: [[MidiControlModel]] = []
    private var redoStack: [[MidiControlModel]] = []
    private var mouseDownSnapshot: [MidiControlModel]?
    private var hasDraggedOrResized: Bool = false

    private static let maxUndoSteps: Int = 500

    public override var isFlipped: Bool { return true }
    public override var mouseDownCanMoveWindow: Bool { return false }
    public override var acceptsFirstResponder: Bool { return true }
    public override func becomeFirstResponder() -> Bool { return true }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupCanvas()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCanvas()
    }

    private func setupCanvas() {
        self.wantsLayer = true
        self.layer?.backgroundColor = AirColorWindowBg().cgColor

        if let savedSize = UserDefaults.standard.object(forKey: "TouchStageGridSize") as? Double, savedSize > 0 {
            gridSize = CGFloat(savedSize)
        } else {
            gridSize = 20.0
        }
        if UserDefaults.standard.object(forKey: "TouchStageSnapToGrid") != nil {
            snapToGrid = UserDefaults.standard.bool(forKey: "TouchStageSnapToGrid")
        } else {
            snapToGrid = true
        }

        floatingSnapBtn = NSButton(frame: NSRect(x: 20, y: self.bounds.size.height - 48, width: 125, height: 30))
        floatingSnapBtn.autoresizingMask = [.maxXMargin, .minYMargin]
        floatingSnapBtn.bezelStyle = .texturedRounded
        floatingSnapBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        floatingSnapBtn.image = AirSymbol("grid", 13.0)
        floatingSnapBtn.imagePosition = .imageLeading
        floatingSnapBtn.target = self
        floatingSnapBtn.action = #selector(toggleSnapToGrid(_:))
        floatingSnapBtn.toolTip = "Toggle Grid Snapping on Canvas (Click to toggle ON/OFF)"
        self.addSubview(floatingSnapBtn)

        floatingGridSizePopup = NSPopUpButton(frame: NSRect(x: 152, y: self.bounds.size.height - 48, width: 84, height: 30), pullsDown: false)
        floatingGridSizePopup.autoresizingMask = [.maxXMargin, .minYMargin]
        floatingGridSizePopup.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        let sizes: [CGFloat] = [5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 40.0, 50.0]
        for s in sizes {
            floatingGridSizePopup.addItem(withTitle: "\(Int(s)) px")
            floatingGridSizePopup.lastItem?.representedObject = s
        }
        floatingGridSizePopup.target = self
        floatingGridSizePopup.action = #selector(onGridSizeChanged(_:))
        floatingGridSizePopup.toolTip = "Select Grid Snap Size"
        self.addSubview(floatingGridSizePopup)

        updateSnapButtonAppearance()
    }

    private func updateSnapButtonAppearance() {
        floatingSnapBtn.state = snapToGrid ? .on : .off
        floatingSnapBtn.title = snapToGrid ? "Snap: ON (\(Int(gridSize))px)" : "Snap: OFF"
        selectGridSizePopup(gridSize)
    }

    private func selectGridSizePopup(_ size: CGFloat) {
        guard let popup = floatingGridSizePopup else { return }
        for item in popup.itemArray {
            if let s = item.representedObject as? CGFloat, abs(s - size) < 0.1 {
                popup.select(item)
                break
            }
        }
    }

    @objc public func toggleSnapToGrid(_ sender: Any?) {
        snapToGrid = !snapToGrid
        UserDefaults.standard.set(snapToGrid, forKey: "TouchStageSnapToGrid")
        updateSnapButtonAppearance()
        setNeedsDisplay(bounds)
    }

    @objc private func onGridSizeChanged(_ sender: Any?) {
        if let s = floatingGridSizePopup.selectedItem?.representedObject as? CGFloat {
            gridSize = s
            snapToGrid = true
            UserDefaults.standard.set(Double(s), forKey: "TouchStageGridSize")
            UserDefaults.standard.set(snapToGrid, forKey: "TouchStageSnapToGrid")
            updateSnapButtonAppearance()
            setNeedsDisplay(bounds)
        }
    }

    @objc private func onSelectGridSizeFromMenu(_ sender: NSMenuItem) {
        if let s = sender.representedObject as? CGFloat {
            gridSize = s
            snapToGrid = true
            UserDefaults.standard.set(Double(s), forKey: "TouchStageGridSize")
            UserDefaults.standard.set(snapToGrid, forKey: "TouchStageSnapToGrid")
            updateSnapButtonAppearance()
            setNeedsDisplay(bounds)
        }
    }

    public func selectAllControls() {
        selectedControls.removeAll()
        selectedControls.append(contentsOf: layout.controls)
        delegate?.canvasDidSelectControl(selectedControl)
        setNeedsDisplay(bounds)
    }

    public func clearSelection() {
        selectedControls.removeAll()
        delegate?.canvasDidSelectControl(nil)
        setNeedsDisplay(bounds)
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let bounds = self.bounds

        // 1. Studio Dark Backdrop
        AirColorWindowBg().setFill()
        bounds.fill()

        // 2. Hardware Device Worksurface
        let devW = layout.canvasWidth > 0 ? layout.canvasWidth : 920.0
        let devH = layout.canvasHeight > 0 ? layout.canvasHeight : 460.0

        let availW = max(100.0, bounds.size.width - 60.0)
        let availH = max(100.0, bounds.size.height - 70.0)
        let zoom = min(1.0, min(availW / devW, availH / devH))

        let renderedDevW = devW * zoom
        let renderedDevH = devH * zoom

        let devX = (bounds.size.width - renderedDevW) / 2.0
        var devY = (bounds.size.height - 30.0 - renderedDevH) / 2.0
        if devY < 18.0 { devY = 18.0 }
        let devRect = NSRect(x: devX, y: devY, width: renderedDevW, height: renderedDevH)

        // Drop Shadow under device
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.6)
        shadow.shadowBlurRadius = 24.0
        shadow.shadowOffset = NSSize(width: 0, height: -6.0)
        shadow.set()

        // Device Bezel (Outer)
        let bezelPad = 12.0 * zoom
        let bezelRect = devRect.insetBy(dx: -bezelPad, dy: -bezelPad)
        let bezelPath = NSBezierPath(roundedRect: bezelRect, xRadius: 18.0 * zoom, yRadius: 18.0 * zoom)
        NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.16, alpha: 1.0).setFill()
        bezelPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        // Bezel Border
        NSColor(calibratedWhite: 0.25, alpha: 1.0).setStroke()
        bezelPath.lineWidth = 1.5
        bezelPath.stroke()

        // Device Screen / Surface (Inner)
        let screenPath = NSBezierPath(roundedRect: devRect, xRadius: 10.0 * zoom, yRadius: 10.0 * zoom)
        AirColorCanvasDeviceBg().setFill()
        screenPath.fill()
        NSColor(calibratedWhite: 0.18, alpha: 1.0).setStroke()
        screenPath.lineWidth = 1.0
        screenPath.stroke()

        // 3. Render Controls
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        screenPath.addClip()

        ctx.translateBy(x: devX, y: devY)
        ctx.scaleBy(x: zoom, y: zoom)

        // Dynamic Grid Dots
        let gridAlpha: CGFloat = snapToGrid ? 0.20 : 0.08
        NSColor(calibratedWhite: 1.0, alpha: gridAlpha).setFill()
        var gx: CGFloat = gridSize
        while gx < devW {
            var gy: CGFloat = gridSize
            while gy < devH {
                NSRect(x: gx - 1.0, y: gy - 1.0, width: 2.0, height: 2.0).fill()
                gy += gridSize
            }
            gx += gridSize
        }

        for ctrl in layout.controls {
            if ctrl.type == "fader" {
                drawFader(ctrl)
            } else if ctrl.type == "knob" {
                drawKnob(ctrl)
            } else if ctrl.type == "button" {
                drawButton(ctrl)
            } else if ctrl.type == "xypad" {
                drawXYPad(ctrl)
            } else if ctrl.type == "label" {
                drawLabel(ctrl)
            } else if ctrl.type == "display" {
                drawDisplay(ctrl)
            }
        }

        // 4. Selection Highlight
        if !selectedControls.isEmpty {
            for ctrl in selectedControls {
                let isPrimary = (ctrl === selectedControl)
                drawSelection(for: ctrl, isPrimary: isPrimary)
            }
        }

        // 5. Marquee Box
        if isMarqueeSelecting && !marqueeRect.isEmpty {
            let marqueePath = NSBezierPath(roundedRect: marqueeRect, xRadius: 4.0, yRadius: 4.0)
            AirColorAccent().withAlphaComponent(0.18).setFill()
            marqueePath.fill()
            AirColorAccent().withAlphaComponent(0.85).setStroke()
            marqueePath.lineWidth = 1.5 / zoom
            let dash: [CGFloat] = [4.0 / zoom, 3.0 / zoom]
            marqueePath.setLineDash(dash, count: 2, phase: 0.0)
            marqueePath.stroke()
        }

        ctx.restoreGState()

        // 6. Minimalist Aspect Badge
        let badgeText: String
        if zoom < 0.98 {
            badgeText = String(format: "%d × %d  •  %@ Canvas (%d%%)", Int(devW), Int(devH), (devH > devW) ? "Portrait" : "Landscape", Int(round(zoom * 100.0)))
        } else {
            badgeText = String(format: "%d × %d  •  %@ Canvas", Int(devW), Int(devH), (devH > devW) ? "Portrait" : "Landscape")
        }
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        let badgeAttr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.0, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1.0),
            .paragraphStyle: pStyle
        ]
        let badgeRect = NSRect(x: devX, y: devRect.maxY + 12.0, width: renderedDevW, height: 18.0)
        (badgeText as NSString).draw(in: badgeRect, withAttributes: badgeAttr)
    }

    // MARK: - Control Renderers

    private func drawFader(_ ctrl: MidiControlModel) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let frame = ctrl.frame
        let isHorizontal = (ctrl.orientation == "horizontal")
        let pillHeight: CGFloat = 26.0
        let hasLabel = ctrl.hasLabel
        let isLabelBottom = (ctrl.labelPosition == "bottom")

        var trackRect = frame
        var pillRect = NSRect.zero

        if isHorizontal {
            if hasLabel {
                if isLabelBottom {
                    pillRect = NSRect(x: frame.origin.x, y: frame.maxY - pillHeight, width: frame.size.width, height: pillHeight)
                    trackRect = NSRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: frame.size.height - pillHeight - 4.0)
                } else {
                    pillRect = NSRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: pillHeight)
                    trackRect = NSRect(x: frame.origin.x, y: frame.origin.y + pillHeight + 4.0, width: frame.size.width, height: frame.size.height - pillHeight - 4.0)
                }
            }
        } else {
            if hasLabel {
                if isLabelBottom {
                    pillRect = NSRect(x: frame.origin.x, y: frame.maxY - pillHeight, width: frame.size.width, height: pillHeight)
                    trackRect = NSRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: frame.size.height - pillHeight - 8.0)
                } else {
                    pillRect = NSRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: pillHeight)
                    trackRect = NSRect(x: frame.origin.x, y: frame.origin.y + pillHeight + 8.0, width: frame.size.width, height: frame.size.height - pillHeight - 8.0)
                }
            }
        }

        if trackRect.size.height < 24.0 { trackRect.size.height = 24.0 }
        if trackRect.size.width < 24.0 { trackRect.size.width = 24.0 }

        // 1. Draw Label Pill
        if hasLabel {
            if ctrl.hasBackground {
                let pill = NSBezierPath(roundedRect: pillRect, xRadius: 8.0, yRadius: 8.0)
                NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1.0).setFill()
                pill.fill()
                NSColor(calibratedWhite: 0.18, alpha: 1.0).setStroke()
                pill.lineWidth = 1.0
                pill.stroke()
            }

            let fSize: CGFloat = (ctrl.fontSize > 0) ? ctrl.fontSize : 11.0
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fSize, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: style,
                .kern: 1.2
            ]
            let textRect = NSRect(x: pillRect.origin.x, y: pillRect.origin.y + (pillRect.size.height - fSize) / 2.0 - 1.0, width: pillRect.size.width, height: fSize + 4.0)
            (ctrl.label as NSString).draw(in: textRect, withAttributes: attr)

            if !ctrl.targetPageId.isEmpty {
                let linkAttr: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                    .foregroundColor: ctrl.accentColor.withAlphaComponent(0.85)
                ]
                let linkRect = NSRect(x: pillRect.maxX - 14.0, y: pillRect.origin.y + 2.0, width: 12.0, height: 12.0)
                ("↗" as NSString).draw(in: linkRect, withAttributes: linkAttr)
            }
        }

        let range = (ctrl.maxValue > ctrl.minValue) ? CGFloat(ctrl.maxValue - ctrl.minValue) : 127.0
        var pct = CGFloat(ctrl.value - Double(ctrl.minValue)) / range
        pct = max(0.0, min(1.0, pct))
        let fStyle = ctrl.faderStyle.lowercased()

        if isHorizontal {
            let slotH: CGFloat = 16.0
            let slotY = trackRect.midY - (slotH / 2.0)
            let slotRect = NSRect(x: trackRect.origin.x + 4.0, y: slotY, width: trackRect.size.width - 8.0, height: slotH)

            let numTicks = 9
            let tickStep = slotRect.size.width / CGFloat(numTicks - 1)
            NSColor(calibratedWhite: 0.25, alpha: 0.7).setStroke()
            for i in 0..<numTicks {
                let tx = slotRect.origin.x + CGFloat(i) * tickStep
                let topTick = NSBezierPath()
                topTick.move(to: NSPoint(x: tx, y: slotY - 8.0))
                topTick.line(to: NSPoint(x: tx, y: slotY - 2.0))
                topTick.lineWidth = 1.0
                topTick.stroke()

                let botTick = NSBezierPath()
                botTick.move(to: NSPoint(x: tx, y: slotRect.maxY + 2.0))
                botTick.line(to: NSPoint(x: tx, y: slotRect.maxY + 8.0))
                botTick.lineWidth = 1.0
                botTick.stroke()
            }

            let slotPath = NSBezierPath(roundedRect: slotRect, xRadius: 6.0, yRadius: 6.0)
            NSColor(calibratedRed: 0.04, green: 0.045, blue: 0.06, alpha: 1.0).setFill()
            slotPath.fill()
            NSColor(calibratedWhite: 0.14, alpha: 1.0).setStroke()
            slotPath.lineWidth = 1.0
            slotPath.stroke()

            let travelW = slotRect.size.width - 12.0
            var beamLeft: CGFloat = 0, beamRight: CGFloat = 0
            let thumbW: CGFloat = 28.0
            let thumbH = min(frame.size.height + 4.0, 60.0)
            var thumbX: CGFloat = 0

            if fStyle == "inverted" {
                let fillW = travelW * pct
                beamRight = slotRect.maxX - 6.0
                beamLeft = beamRight - fillW
                thumbX = (slotRect.maxX - 6.0) - fillW - (thumbW / 2.0)
            } else if fStyle == "centered" {
                let cTick = NSBezierPath()
                cTick.move(to: NSPoint(x: slotRect.midX, y: slotY - 6.0))
                cTick.line(to: NSPoint(x: slotRect.midX, y: slotRect.maxY + 6.0))
                NSColor(calibratedWhite: 0.35, alpha: 1.0).setStroke()
                cTick.lineWidth = 1.5
                cTick.stroke()

                if pct >= 0.5 {
                    beamLeft = slotRect.midX
                    beamRight = beamLeft + (pct - 0.5) * travelW
                } else {
                    beamRight = slotRect.midX
                    beamLeft = beamRight - (0.5 - pct) * travelW
                }
                thumbX = (slotRect.origin.x + 6.0) + pct * travelW - (thumbW / 2.0)
            } else {
                let fillW = travelW * pct
                beamLeft = slotRect.origin.x + 6.0
                beamRight = beamLeft + fillW
                thumbX = (slotRect.origin.x + 6.0) + fillW - (thumbW / 2.0)
            }

            if abs(beamRight - beamLeft) > 2.0 {
                let beamY = slotRect.midY
                let beam = NSBezierPath()
                beam.move(to: NSPoint(x: beamLeft, y: beamY))
                beam.line(to: NSPoint(x: beamRight, y: beamY))
                beam.lineCapStyle = .round

                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 12.0, color: ctrl.accentColor.cgColor)
                ctrl.accentColor.setStroke()
                beam.lineWidth = 3.5
                beam.stroke()
                ctx.restoreGState()

                NSColor.white.setStroke()
                beam.lineWidth = 1.5
                beam.stroke()
            }

            thumbX = max(slotRect.origin.x - 2.0, min(slotRect.maxX - thumbW + 2.0, thumbX))
            let thumbY = trackRect.midY - (thumbH / 2.0)
            let thumbRect = NSRect(x: thumbX, y: thumbY, width: thumbW, height: thumbH)

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -3.0), blur: 8.0, color: NSColor(calibratedWhite: 0.0, alpha: 0.75).cgColor)
            let thumbPath = NSBezierPath(roundedRect: thumbRect, xRadius: 4.5, yRadius: 4.5)

            let metalGrad = NSGradient(colorsAndLocations:
                (NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.36, alpha: 1.0), 0.0),
                (NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.23, alpha: 1.0), 0.20),
                (NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1.0), 0.50),
                (NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1.0), 1.0))
            metalGrad?.draw(in: thumbPath, angle: 0.0)
            ctx.restoreGState()

            NSColor(calibratedWhite: 0.35, alpha: 0.7).setStroke()
            thumbPath.lineWidth = 1.0
            thumbPath.stroke()

            let slitW: CGFloat = 3.0
            let slitH: CGFloat = 16.0
            let slitRect = NSRect(x: thumbRect.midX - slitW / 2.0, y: thumbRect.midY - slitH / 2.0, width: slitW, height: slitH)
            let slitPath = NSBezierPath(roundedRect: slitRect, xRadius: 1.5, yRadius: 1.5)

            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 10.0, color: ctrl.accentColor.cgColor)
            ctrl.accentColor.setFill()
            slitPath.fill()
            ctx.restoreGState()

            let slitCoreRect = slitRect.insetBy(dx: 0.5, dy: 2.0)
            let slitCorePath = NSBezierPath(roundedRect: slitCoreRect, xRadius: 1.0, yRadius: 1.0)
            NSColor.white.setFill()
            slitCorePath.fill()
        } else {
            // Vertical Fader
            let slotW: CGFloat = max(14.0, min(26.0, trackRect.size.width * 0.22))
            let slotX = trackRect.midX - (slotW / 2.0)
            let slotRect = NSRect(x: slotX, y: trackRect.origin.y + 4.0, width: slotW, height: trackRect.size.height - 8.0)

            let numTicks = 9
            let tickStep = slotRect.size.height / CGFloat(numTicks - 1)
            NSColor(calibratedWhite: 0.25, alpha: 0.7).setStroke()
            for i in 0..<numTicks {
                let ty = slotRect.origin.y + CGFloat(i) * tickStep
                let leftTick = NSBezierPath()
                leftTick.move(to: NSPoint(x: slotX - 10.0, y: ty))
                leftTick.line(to: NSPoint(x: slotX - 3.0, y: ty))
                leftTick.lineWidth = 1.0
                leftTick.stroke()

                let rightTick = NSBezierPath()
                rightTick.move(to: NSPoint(x: slotRect.maxX + 3.0, y: ty))
                rightTick.line(to: NSPoint(x: slotRect.maxX + 10.0, y: ty))
                rightTick.lineWidth = 1.0
                rightTick.stroke()
            }

            let slotPath = NSBezierPath(roundedRect: slotRect, xRadius: slotW / 2.5, yRadius: slotW / 2.5)
            NSColor(calibratedRed: 0.04, green: 0.045, blue: 0.06, alpha: 1.0).setFill()
            slotPath.fill()
            NSColor(calibratedWhite: 0.14, alpha: 1.0).setStroke()
            slotPath.lineWidth = 1.0
            slotPath.stroke()

            let travelH = slotRect.size.height - 12.0
            var beamBottom: CGFloat = 0, beamTop: CGFloat = 0
            let thumbW = max(36.0, trackRect.size.width - 16.0)
            let thumbH: CGFloat = 28.0
            let thumbX = trackRect.midX - (thumbW / 2.0)
            var thumbY: CGFloat = 0

            if fStyle == "inverted" {
                let fillH = travelH * pct
                beamTop = slotRect.origin.y + 6.0
                beamBottom = beamTop + fillH
                thumbY = (slotRect.origin.y + 6.0) + fillH - (thumbH / 2.0)
            } else if fStyle == "centered" {
                let cTick = NSBezierPath()
                cTick.move(to: NSPoint(x: slotX - 6.0, y: slotRect.midY))
                cTick.line(to: NSPoint(x: slotRect.maxX + 6.0, y: slotRect.midY))
                NSColor(calibratedWhite: 0.35, alpha: 1.0).setStroke()
                cTick.lineWidth = 1.5
                cTick.stroke()

                if pct >= 0.5 {
                    beamBottom = slotRect.midY
                    beamTop = beamBottom - (pct - 0.5) * travelH
                } else {
                    beamTop = slotRect.midY
                    beamBottom = beamTop + (0.5 - pct) * travelH
                }
                thumbY = (slotRect.maxY - 6.0) - pct * travelH - (thumbH / 2.0)
            } else {
                let fillH = travelH * pct
                beamBottom = slotRect.maxY - 6.0
                beamTop = beamBottom - fillH
                thumbY = (slotRect.maxY - 6.0) - fillH - (thumbH / 2.0)
            }

            if abs(beamBottom - beamTop) > 2.0 {
                let beamX = slotRect.midX
                let beam = NSBezierPath()
                beam.move(to: NSPoint(x: beamX, y: beamBottom))
                beam.line(to: NSPoint(x: beamX, y: beamTop))
                beam.lineCapStyle = .round

                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 12.0, color: ctrl.accentColor.cgColor)
                ctrl.accentColor.setStroke()
                beam.lineWidth = 3.5
                beam.stroke()
                ctx.restoreGState()

                NSColor.white.setStroke()
                beam.lineWidth = 1.5
                beam.stroke()
            }

            thumbY = max(slotRect.origin.y - 2.0, min(slotRect.maxY - thumbH + 2.0, thumbY))
            let thumbRect = NSRect(x: thumbX, y: thumbY, width: thumbW, height: thumbH)

            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -3.0), blur: 8.0, color: NSColor(calibratedWhite: 0.0, alpha: 0.75).cgColor)
            let thumbPath = NSBezierPath(roundedRect: thumbRect, xRadius: 4.5, yRadius: 4.5)

            let metalGrad = NSGradient(colorsAndLocations:
                (NSColor(calibratedRed: 0.28, green: 0.30, blue: 0.36, alpha: 1.0), 0.0),
                (NSColor(calibratedRed: 0.18, green: 0.19, blue: 0.23, alpha: 1.0), 0.20),
                (NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1.0), 0.50),
                (NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1.0), 1.0))
            metalGrad?.draw(in: thumbPath, angle: 90.0)
            ctx.restoreGState()

            NSColor(calibratedWhite: 0.35, alpha: 0.7).setStroke()
            thumbPath.lineWidth = 1.0
            thumbPath.stroke()

            let brushLine = NSBezierPath()
            brushLine.move(to: NSPoint(x: thumbX + 4.0, y: thumbRect.midY))
            brushLine.line(to: NSPoint(x: thumbX + thumbW - 4.0, y: thumbRect.midY))
            NSColor(calibratedWhite: 1.0, alpha: 0.06).setStroke()
            brushLine.lineWidth = 1.0
            brushLine.stroke()

            let slitW: CGFloat = 16.0
            let slitH: CGFloat = 3.0
            let slitRect = NSRect(x: thumbRect.midX - slitW / 2.0, y: thumbRect.midY - slitH / 2.0, width: slitW, height: slitH)
            let slitPath = NSBezierPath(roundedRect: slitRect, xRadius: 1.5, yRadius: 1.5)

            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 10.0, color: ctrl.accentColor.cgColor)
            ctrl.accentColor.setFill()
            slitPath.fill()
            ctx.restoreGState()

            let slitCoreRect = slitRect.insetBy(dx: 2.0, dy: 0.5)
            let slitCorePath = NSBezierPath(roundedRect: slitCoreRect, xRadius: 1.0, yRadius: 1.0)
            NSColor.white.setFill()
            slitCorePath.fill()
        }
    }

    private func drawKnob(_ ctrl: MidiControlModel) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let frame = ctrl.frame
        let pillHeight: CGFloat = 26.0
        let hasLabel = ctrl.hasLabel
        let isLabelTop = (ctrl.labelPosition == "top")

        var dialArea = frame
        var pillRect = NSRect.zero

        if hasLabel {
            if isLabelTop {
                pillRect = NSRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: pillHeight)
                dialArea = NSRect(x: frame.origin.x, y: frame.origin.y + pillHeight + 6.0, width: frame.size.width, height: frame.size.height - pillHeight - 6.0)
            } else {
                pillRect = NSRect(x: frame.origin.x, y: frame.maxY - pillHeight, width: frame.size.width, height: pillHeight)
                dialArea = NSRect(x: frame.origin.x, y: frame.origin.y, width: frame.size.width, height: frame.size.height - pillHeight - 6.0)
            }
        }

        let dialSize = min(dialArea.size.width, dialArea.size.height)
        let cx = dialArea.midX
        let cy = dialArea.midY
        let radius = dialSize * 0.44

        // 1. Recessed Well
        let well = NSBezierPath(ovalIn: NSRect(x: cx - radius, y: cy - radius, width: radius * 2.0, height: radius * 2.0))
        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.08, alpha: 1.0).setFill()
        well.fill()
        NSColor(calibratedWhite: 0.15, alpha: 1.0).setStroke()
        well.lineWidth = 1.0
        well.stroke()

        // 2. Halo Arc Ring
        let haloRadius = radius * 0.90
        let range = (ctrl.maxValue > ctrl.minValue) ? CGFloat(ctrl.maxValue - ctrl.minValue) : 127.0
        var pct = CGFloat(ctrl.value - Double(ctrl.minValue)) / range
        pct = max(0.0, min(1.0, pct))

        let trackArc = NSBezierPath()
        trackArc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: haloRadius, startAngle: 135.0, endAngle: 45.0, clockwise: false)
        NSColor(calibratedRed: 0.12, green: 0.14, blue: 0.18, alpha: 1.0).setStroke()
        trackArc.lineWidth = 4.0
        trackArc.lineCapStyle = .round
        trackArc.stroke()

        let style = ctrl.knobStyle.lowercased()
        let activeArc = NSBezierPath()
        var needleAngle: CGFloat = 135.0 + (pct * 270.0)

        if style == "inverted" {
            if pct > 0.01 {
                activeArc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: haloRadius, startAngle: 405.0, endAngle: 405.0 - pct * 270.0, clockwise: true)
            }
            needleAngle = 405.0 - (pct * 270.0)
        } else if style == "centered" {
            let centerTick = NSBezierPath()
            centerTick.move(to: NSPoint(x: cx, y: cy - haloRadius - 3.0))
            centerTick.line(to: NSPoint(x: cx, y: cy - haloRadius + 4.0))
            NSColor(calibratedWhite: 0.35, alpha: 1.0).setStroke()
            centerTick.lineWidth = 1.5
            centerTick.stroke()

            if pct >= 0.5 {
                let sweep = (pct - 0.5) * 270.0
                if sweep > 1.0 {
                    activeArc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: haloRadius, startAngle: 270.0, endAngle: 270.0 + sweep, clockwise: false)
                }
            } else {
                let sweep = (0.5 - pct) * 270.0
                if sweep > 1.0 {
                    activeArc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: haloRadius, startAngle: 270.0, endAngle: 270.0 - sweep, clockwise: true)
                }
            }
            needleAngle = 135.0 + (pct * 270.0)
        } else {
            if pct > 0.01 {
                activeArc.appendArc(withCenter: NSPoint(x: cx, y: cy), radius: haloRadius, startAngle: 135.0, endAngle: 135.0 + pct * 270.0, clockwise: false)
            }
            needleAngle = 135.0 + (pct * 270.0)
        }

        if activeArc.elementCount > 0 {
            activeArc.lineCapStyle = .round

            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 12.0, color: ctrl.accentColor.cgColor)
            ctrl.accentColor.setStroke()
            activeArc.lineWidth = 4.0
            activeArc.stroke()
            ctx.restoreGState()

            NSColor.white.setStroke()
            activeArc.lineWidth = 1.5
            activeArc.stroke()
        }

        // 3. Turned Metal Dial Face
        let dialFaceR = radius * 0.72
        let faceRect = NSRect(x: cx - dialFaceR, y: cy - dialFaceR, width: dialFaceR * 2.0, height: dialFaceR * 2.0)
        let face = NSBezierPath(ovalIn: faceRect)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2.0), blur: 6.0, color: NSColor(calibratedWhite: 0.0, alpha: 0.7).cgColor)

        let dialGrad = NSGradient(colorsAndLocations:
            (NSColor(calibratedRed: 0.25, green: 0.27, blue: 0.33, alpha: 1.0), 0.0),
            (NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 1.0), 0.35),
            (NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1.0), 0.70),
            (NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1.0), 1.0))
        dialGrad?.draw(in: face, angle: 90.0)
        ctx.restoreGState()

        NSColor(calibratedWhite: 0.35, alpha: 0.8).setStroke()
        face.lineWidth = 1.0
        face.stroke()

        let innerGroove = faceRect.insetBy(dx: dialFaceR * 0.35, dy: dialFaceR * 0.35)
        let groovePath = NSBezierPath(ovalIn: innerGroove)
        NSColor(calibratedWhite: 1.0, alpha: 0.04).setStroke()
        groovePath.lineWidth = 1.0
        groovePath.stroke()

        // 4. Indicator Needle
        let showValue = (ctrl.valueDisplay != "none")
        var valueString = ""
        if ctrl.valueDisplay == "percent" {
            valueString = "\(Int(round(pct * 100.0)))%"
        } else if ctrl.valueDisplay == "scale" {
            valueString = "\(Int(round(ctrl.value)))"
        }
        let isCenterVal = (showValue && ctrl.valuePosition == "center")

        let needleStartR = isCenterVal ? (dialFaceR * 0.50) : (dialFaceR * 0.20)
        let rad = needleAngle * .pi / 180.0
        let pStartX = cx + cos(rad) * needleStartR
        let pStartY = cy + sin(rad) * needleStartR
        let pEndX = cx + cos(rad) * (dialFaceR * 0.85)
        let pEndY = cy + sin(rad) * (dialFaceR * 0.85)

        let needle = NSBezierPath()
        needle.move(to: NSPoint(x: pStartX, y: pStartY))
        needle.line(to: NSPoint(x: pEndX, y: pEndY))
        needle.lineCapStyle = .round

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 10.0, color: ctrl.accentColor.cgColor)
        ctrl.accentColor.setStroke()
        needle.lineWidth = 3.5
        needle.stroke()
        ctx.restoreGState()

        NSColor.white.setStroke()
        needle.lineWidth = 1.5
        needle.stroke()

        // 4b. Value Readout (Center Cap or Bottom Badge)
        if showValue && !valueString.isEmpty {
            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .center

            if isCenterVal {
                let centerR = dialFaceR * 0.46
                let centerRect = NSRect(x: cx - centerR, y: cy - centerR, width: centerR * 2.0, height: centerR * 2.0)
                let centerCap = NSBezierPath(ovalIn: centerRect)
                NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 0.96).setFill()
                centerCap.fill()
                NSColor(calibratedWhite: 0.28, alpha: 0.9).setStroke()
                centerCap.lineWidth = 1.0
                centerCap.stroke()

                let autoFontSize = max(9.0, min(14.0, centerR * 0.74))
                let rawFontSize = (ctrl.valueFontSize > 0) ? ctrl.valueFontSize : autoFontSize
                let fontSize = min(20.0, rawFontSize)
                let valAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: NSColor.white,
                    .paragraphStyle: pStyle
                ]
                let textSize = (valueString as NSString).size(withAttributes: valAttrs)
                let textRect = NSRect(x: cx - centerR, y: cy - (textSize.height / 2.0), width: centerR * 2.0, height: textSize.height)
                (valueString as NSString).draw(in: textRect, withAttributes: valAttrs)
            } else {
                let autoFontSize: CGFloat = 10.0
                let fontSize = (ctrl.valueFontSize > 0) ? ctrl.valueFontSize : autoFontSize
                let badgeW: CGFloat = max(42.0, CGFloat(valueString.count) * (fontSize * 0.85) + 14.0)
                let badgeH: CGFloat = max(16.0, fontSize + 6.0)
                let badgeY: CGFloat
                if hasLabel && !isLabelTop {
                    badgeY = pillRect.origin.y - badgeH - 3.0
                } else {
                    badgeY = cy + radius + 3.0
                }
                let badgeRect = NSRect(x: cx - badgeW / 2.0, y: badgeY, width: badgeW, height: badgeH)
                let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4.0, yRadius: 4.0)
                NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 0.92).setFill()
                badgePath.fill()
                NSColor(calibratedWhite: 0.24, alpha: 0.8).setStroke()
                badgePath.lineWidth = 0.8
                badgePath.stroke()

                let valAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .semibold),
                    .foregroundColor: ctrl.accentColor,
                    .paragraphStyle: pStyle
                ]
                let textSize = (valueString as NSString).size(withAttributes: valAttrs)
                let textRect = NSRect(x: badgeRect.origin.x, y: badgeRect.midY - (textSize.height / 2.0), width: badgeW, height: textSize.height)
                (valueString as NSString).draw(in: textRect, withAttributes: valAttrs)
            }
        }

        // 5. Draw Pill Label
        if hasLabel {
            if ctrl.hasBackground {
                let pill = NSBezierPath(roundedRect: pillRect, xRadius: 8.0, yRadius: 8.0)
                NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1.0).setFill()
                pill.fill()
                NSColor(calibratedWhite: 0.18, alpha: 1.0).setStroke()
                pill.lineWidth = 1.0
                pill.stroke()
            }

            let fSize: CGFloat = (ctrl.fontSize > 0) ? ctrl.fontSize : 11.0
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fSize, weight: .bold),
                .foregroundColor: NSColor.white,
                .paragraphStyle: style,
                .kern: 1.2
            ]
            let textRect = NSRect(x: pillRect.origin.x, y: pillRect.origin.y + (pillRect.size.height - fSize) / 2.0 - 1.0, width: pillRect.size.width, height: fSize + 4.0)
            (ctrl.label as NSString).draw(in: textRect, withAttributes: attr)

            if !ctrl.targetPageId.isEmpty {
                let linkAttr: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                    .foregroundColor: ctrl.accentColor.withAlphaComponent(0.85)
                ]
                let linkRect = NSRect(x: pillRect.maxX - 14.0, y: pillRect.origin.y + 2.0, width: 12.0, height: 12.0)
                ("↗" as NSString).draw(in: linkRect, withAttributes: linkAttr)
            }
        }
    }

    private func drawButton(_ ctrl: MidiControlModel) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = ctrl.frame
        let isCircle = (ctrl.shape == "circle")
        let isLit = (ctrl.value > 0)

        if isCircle {
            let size = min(r.size.width, r.size.height)
            let x = r.midX - size / 2.0
            let y = r.midY - size / 2.0
            let outerRect = NSRect(x: x, y: y, width: size, height: size)

            let ringRect = outerRect.insetBy(dx: 1.5, dy: 1.5)
            let ring = NSBezierPath(ovalIn: ringRect)

            ctx.saveGState()
            let glowRadius: CGFloat = isLit ? 16.0 : 8.0
            let glowAlpha: CGFloat = isLit ? 0.85 : 0.35
            ctx.setShadow(offset: .zero, blur: glowRadius, color: ctrl.accentColor.withAlphaComponent(glowAlpha).cgColor)

            let faceRect = ringRect.insetBy(dx: 2.0, dy: 2.0)
            let face = NSBezierPath(ovalIn: faceRect)
            let baseColor = (HexFromColor(ctrl.color) == HexFromColor(ctrl.accentColor)) ? DeriveDarkBaseColor(from: ctrl.accentColor) : ctrl.color
            if isLit {
                let glassGrad = NSGradient(starting: ctrl.accentColor.withAlphaComponent(0.85),
                                           ending: baseColor.withAlphaComponent(0.95))
                glassGrad?.draw(in: face, relativeCenterPosition: NSPoint(x: 0.0, y: 0.1))
            } else {
                let darkGrad = NSGradient(colorsAndLocations:
                    (NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 1.0), 0.0),
                    (NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1.0), 0.6),
                    (NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0), 1.0))
                darkGrad?.draw(in: face, angle: -90.0)
            }

            ctrl.accentColor.setStroke()
            ring.lineWidth = 3.0
            ring.stroke()
            ctx.restoreGState()

            let innerHighlightRect = ringRect.insetBy(dx: 2.0, dy: 2.0)
            let innerHighlight = NSBezierPath(ovalIn: innerHighlightRect)
            NSColor(calibratedWhite: 1.0, alpha: isLit ? 0.35 : 0.08).setStroke()
            innerHighlight.lineWidth = 1.0
            innerHighlight.stroke()

            if !ctrl.label.isEmpty {
                let fSize: CGFloat = (ctrl.fontSize > 0) ? ctrl.fontSize : 13.0
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                let attr: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fSize, weight: .bold),
                    .foregroundColor: isLit ? NSColor.white : ctrl.accentColor.withAlphaComponent(0.9),
                    .paragraphStyle: style,
                    .kern: 1.2
                ]
                let textRect = NSRect(x: faceRect.origin.x + 2.0, y: faceRect.midY - (fSize + 4.0) / 2.0, width: faceRect.size.width - 4.0, height: fSize + 6.0)
                (ctrl.label as NSString).draw(in: textRect, withAttributes: attr)
            }
        } else {
            let cornerR: CGFloat = 12.0
            let padRect = r

            ctx.saveGState()
            let glowRadius: CGFloat = isLit ? 16.0 : 8.0
            let glowAlpha: CGFloat = isLit ? 0.85 : 0.35
            ctx.setShadow(offset: .zero, blur: glowRadius, color: ctrl.accentColor.withAlphaComponent(glowAlpha).cgColor)

            let padPath = NSBezierPath(roundedRect: padRect, xRadius: cornerR, yRadius: cornerR)
            let baseColor = (HexFromColor(ctrl.color) == HexFromColor(ctrl.accentColor)) ? DeriveDarkBaseColor(from: ctrl.accentColor) : ctrl.color

            if isLit {
                let glassGrad = NSGradient(starting: ctrl.accentColor.withAlphaComponent(0.85),
                                           ending: baseColor.withAlphaComponent(0.95))
                glassGrad?.draw(in: padPath, relativeCenterPosition: NSPoint(x: 0.0, y: 0.1))
            } else {
                let darkGrad = NSGradient(colorsAndLocations:
                    (NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.21, alpha: 1.0), 0.0),
                    (NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1.0), 0.6),
                    (NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1.0), 1.0))
                darkGrad?.draw(in: padPath, angle: -90.0)
            }

            ctrl.accentColor.setStroke()
            padPath.lineWidth = 3.0
            padPath.stroke()
            ctx.restoreGState()

            let innerHighlightRect = padRect.insetBy(dx: 2.0, dy: 2.0)
            let innerHighlight = NSBezierPath(roundedRect: innerHighlightRect, xRadius: cornerR - 2.0, yRadius: cornerR - 2.0)
            NSColor(calibratedWhite: 1.0, alpha: isLit ? 0.35 : 0.08).setStroke()
            innerHighlight.lineWidth = 1.0
            innerHighlight.stroke()

            if !ctrl.label.isEmpty {
                let fSize: CGFloat = (ctrl.fontSize > 0) ? ctrl.fontSize : 13.0
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                let attr: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: fSize, weight: .bold),
                    .foregroundColor: isLit ? NSColor.white : ctrl.accentColor.withAlphaComponent(0.9),
                    .paragraphStyle: style,
                    .kern: 1.2
                ]
                let textRect = NSRect(x: r.origin.x + 4.0, y: r.midY - (fSize + 4.0) / 2.0, width: r.size.width - 8.0, height: fSize + 6.0)
                (ctrl.label as NSString).draw(in: textRect, withAttributes: attr)
            }
        }

        if !ctrl.targetPageId.isEmpty {
            let linkAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.0, weight: .bold),
                .foregroundColor: isLit ? NSColor.white.withAlphaComponent(0.9) : ctrl.accentColor.withAlphaComponent(0.85)
            ]
            let linkRect = NSRect(x: r.maxX - 16.0, y: r.origin.y + 4.0, width: 14.0, height: 12.0)
            ("↗" as NSString).draw(in: linkRect, withAttributes: linkAttr)
        }
    }

    private func drawXYPad(_ ctrl: MidiControlModel) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = ctrl.frame
        let p = NSBezierPath(roundedRect: r, xRadius: 14.0, yRadius: 14.0)
        NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.08, alpha: 1.0).setFill()
        p.fill()

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 8.0, color: ctrl.accentColor.withAlphaComponent(0.4).cgColor)
        NSColor(calibratedWhite: 0.20, alpha: 1.0).setStroke()
        p.lineWidth = 1.5
        p.stroke()
        ctx.restoreGState()

        let puckX = r.origin.x + CGFloat(ctrl.value / 127.0) * r.size.width
        let puckY = r.origin.y + (1.0 - CGFloat(ctrl.value / 127.0)) * r.size.height

        NSColor(calibratedWhite: 0.18, alpha: 0.8).setStroke()
        let cross = NSBezierPath()
        cross.move(to: NSPoint(x: puckX, y: r.origin.y + 4.0))
        cross.line(to: NSPoint(x: puckX, y: r.maxY - 4.0))
        cross.move(to: NSPoint(x: r.origin.x + 4.0, y: puckY))
        cross.line(to: NSPoint(x: r.maxX - 4.0, y: puckY))
        cross.lineWidth = 1.0
        cross.stroke()

        let puckRect = NSRect(x: puckX - 11.0, y: puckY - 11.0, width: 22.0, height: 22.0)
        let puck = NSBezierPath(ovalIn: puckRect)

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 14.0, color: ctrl.accentColor.cgColor)
        ctrl.accentColor.setFill()
        puck.fill()
        ctx.restoreGState()

        NSColor.white.setFill()
        let corePuck = puckRect.insetBy(dx: 4.0, dy: 4.0)
        let corePuckPath = NSBezierPath(ovalIn: corePuck)
        corePuckPath.fill()

        let style = NSMutableParagraphStyle()
        style.alignment = .left
        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.0, weight: .bold),
            .foregroundColor: NSColor(calibratedWhite: 0.65, alpha: 1.0),
            .paragraphStyle: style,
            .kern: 1.2
        ]
        (ctrl.label as NSString).draw(in: NSRect(x: r.origin.x + 10.0, y: r.origin.y + 8.0, width: r.size.width - 20.0, height: 16.0), withAttributes: attr)
    }

    private func drawLabel(_ ctrl: MidiControlModel) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = ctrl.frame
        let isFilled = (ctrl.backgroundStyle == "filled")
        let isVertical = (ctrl.orientation == "vertical")

        if ctrl.hasBackground {
            let pillRadius = min(13.0, min(r.size.width, r.size.height) / 2.0)
            let pill = NSBezierPath(roundedRect: r, xRadius: pillRadius, yRadius: pillRadius)

            if isFilled {
                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 10.0, color: ctrl.accentColor.withAlphaComponent(0.5).cgColor)
                ctrl.accentColor.setFill()
                pill.fill()
                ctx.restoreGState()
            } else {
                NSColor(calibratedRed: 0.06, green: 0.07, blue: 0.09, alpha: 1.0).setFill()
                pill.fill()

                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 8.0, color: ctrl.accentColor.withAlphaComponent(0.6).cgColor)
                ctrl.accentColor.setStroke()
                pill.lineWidth = 1.2
                pill.stroke()
                ctx.restoreGState()
            }
        }

        let fSize: CGFloat = (ctrl.fontSize > 0) ? ctrl.fontSize : 12.0
        let style = NSMutableParagraphStyle()
        style.alignment = .center

        var textColor = NSColor.white
        if ctrl.hasBackground && isFilled {
            if let rgb = ctrl.accentColor.usingColorSpace(.sRGB) {
                let lum = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
                textColor = (lum > 0.6) ? NSColor(calibratedWhite: 0.06, alpha: 1.0) : NSColor.white
            }
        }

        let attr: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fSize, weight: .bold),
            .foregroundColor: textColor,
            .paragraphStyle: style,
            .kern: 1.4
        ]

        if isVertical {
            ctx.saveGState()
            let cx = r.midX
            let cy = r.midY
            ctx.translateBy(x: cx, y: cy)
            ctx.rotate(by: -.pi / 2.0)
            let textRect = NSRect(x: -r.height / 2.0 + 4.0, y: -(fSize + 4.0) / 2.0, width: r.height - 8.0, height: fSize + 6.0)
            (ctrl.label as NSString).draw(in: textRect, withAttributes: attr)
            ctx.restoreGState()
        } else {
            let textRect = NSRect(x: r.origin.x, y: r.midY - (fSize + 4.0) / 2.0, width: r.size.width, height: fSize + 6.0)
            (ctrl.label as NSString).draw(in: textRect, withAttributes: attr)
        }

        if !ctrl.targetPageId.isEmpty {
            let linkAttr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.0, weight: .bold),
                .foregroundColor: (ctrl.hasBackground && isFilled) ? textColor.withAlphaComponent(0.8) : ctrl.accentColor.withAlphaComponent(0.85)
            ]
            let linkRect = isVertical ?
                NSRect(x: r.midX - 5.0, y: r.origin.y + 4.0, width: 12.0, height: 12.0) :
                NSRect(x: r.maxX - 16.0, y: r.origin.y + 3.0, width: 14.0, height: 12.0)
            ("↗" as NSString).draw(in: linkRect, withAttributes: linkAttr)
        }
    }

    private func drawDisplay(_ ctrl: MidiControlModel) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let r = ctrl.frame

        // 1. Sleek Card Background
        if ctrl.hasBackground {
            let card = NSBezierPath(roundedRect: r, xRadius: 10.0, yRadius: 10.0)
            NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 0.95).setFill()
            card.fill()

            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 8.0, color: ctrl.accentColor.withAlphaComponent(0.4).cgColor)
            ctrl.accentColor.withAlphaComponent(0.6).setStroke()
            card.lineWidth = 1.2
            card.stroke()
            ctx.restoreGState()
        }

        // 2. Beat Indicator LED (Top-Right)
        let ledR: CGFloat = 4.5
        let ledX = r.maxX - ledR - 10.0
        let ledY = r.origin.y + 12.0
        let ledRect = NSRect(x: ledX - ledR, y: ledY - ledR, width: ledR * 2.0, height: ledR * 2.0)
        let ledPath = NSBezierPath(ovalIn: ledRect)
        ctrl.accentColor.setFill()
        ledPath.fill()

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 6.0, color: ctrl.accentColor.cgColor)
        ctrl.accentColor.setFill()
        ledPath.fill()
        ctx.restoreGState()

        // 3. Label (Top or Bottom)
        let isBottom = (ctrl.labelPosition == "bottom")
        if ctrl.hasLabel && !ctrl.label.isEmpty {
            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .left
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.0, weight: .bold),
                .foregroundColor: NSColor(calibratedWhite: 0.65, alpha: 1.0),
                .paragraphStyle: pStyle,
                .kern: 1.0
            ]
            let lblStr = ctrl.label.uppercased() as NSString
            let labelY = isBottom ? (r.maxY - 18.0) : (r.origin.y + 8.0)
            lblStr.draw(at: NSPoint(x: r.origin.x + 10.0, y: labelY), withAttributes: labelAttrs)
        }

        // 4. Large Digital Readout
        let valStr: String
        if ctrl.displayMode == "cc" {
            let range = Double(max(1, ctrl.maxValue - ctrl.minValue))
            let calculatedVal = Double(ctrl.minValue) + (ctrl.value / 127.0) * range
            valStr = "\(Int(round(calculatedVal)))"
        } else {
            valStr = "120.0"
        }

        let fSize: CGFloat = (ctrl.fontSize > 0) ? ctrl.fontSize : 24.0
        let valStyle = NSMutableParagraphStyle()
        valStyle.alignment = .center
        let valAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fSize, weight: .black),
            .foregroundColor: NSColor.white,
            .paragraphStyle: valStyle
        ]
        let textSize = (valStr as NSString).size(withAttributes: valAttrs)
        let yShift: CGFloat = ctrl.hasLabel ? (isBottom ? -7.0 : 7.0) : 0.0
        let valTextRect = NSRect(x: r.origin.x + 6.0, y: r.midY - (textSize.height / 2.0) + yShift, width: r.size.width - 12.0, height: textSize.height)
        (valStr as NSString).draw(in: valTextRect, withAttributes: valAttrs)
    }

    private func drawSelection(for ctrl: MidiControlModel, isPrimary: Bool) {
        let r = ctrl.frame

        let outline = NSBezierPath(roundedRect: r.insetBy(dx: -3.0, dy: -3.0), xRadius: 6.0, yRadius: 6.0)
        AirColorAccent().setStroke()
        outline.lineWidth = 2.0
        outline.stroke()

        if selectedControls.count == 1 || isPrimary {
            let hSize: CGFloat = 8.0
            let corners: [NSPoint] = [
                NSPoint(x: r.minX - 3.0, y: r.minY - 3.0),
                NSPoint(x: r.maxX + 3.0, y: r.minY - 3.0),
                NSPoint(x: r.maxX + 3.0, y: r.maxY + 3.0),
                NSPoint(x: r.minX - 3.0, y: r.maxY + 3.0)
            ]

            for pt in corners {
                let hRect = NSRect(x: pt.x - hSize / 2.0, y: pt.y - hSize / 2.0, width: hSize, height: hSize)
                let hPath = NSBezierPath(ovalIn: hRect)
                NSColor.white.setFill()
                hPath.fill()
                AirColorAccent().setStroke()
                hPath.lineWidth = 1.5
                hPath.stroke()
            }
        }

        if isPrimary {
            let tag: String
            if selectedControls.count > 1 {
                tag = String(format: "%lu Selected  •  %d × %d", selectedControls.count, Int(r.size.width), Int(r.size.height))
            } else {
                tag = String(format: "%d × %d  •  Ch %ld #%ld", Int(r.size.width), Int(r.size.height), ctrl.midiChannel, ctrl.midiNumber)
            }

            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.0, weight: .medium),
                .foregroundColor: NSColor.white,
                .paragraphStyle: style
            ]
            let tagSize = (tag as NSString).size(withAttributes: attr)
            let tagRect = NSRect(x: r.midX - (tagSize.width + 16.0) / 2.0, y: r.origin.y - 22.0, width: tagSize.width + 16.0, height: 18.0)

            let tagBg = NSBezierPath(roundedRect: tagRect, xRadius: 4.0, yRadius: 4.0)
            NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.0, alpha: 0.95).setFill()
            tagBg.fill()

            (tag as NSString).draw(in: NSRect(x: tagRect.origin.x, y: tagRect.origin.y + 2.0, width: tagRect.size.width, height: 14.0), withAttributes: attr)
        }
    }

    // MARK: - Coordinates & Event Handling

    private func canvasPoint(from event: NSEvent) -> NSPoint {
        let p = self.convert(event.locationInWindow, from: nil)
        let devW = layout.canvasWidth > 0 ? layout.canvasWidth : 920.0
        let devH = layout.canvasHeight > 0 ? layout.canvasHeight : 460.0
        let availW = max(100.0, self.bounds.size.width - 60.0)
        let availH = max(100.0, self.bounds.size.height - 70.0)
        let zoom = min(1.0, min(availW / devW, availH / devH))

        let renderedDevW = devW * zoom
        let renderedDevH = devH * zoom
        let devX = (self.bounds.size.width - renderedDevW) / 2.0
        var devY = (self.bounds.size.height - 30.0 - renderedDevH) / 2.0
        if devY < 18.0 { devY = 18.0 }

        return NSPoint(x: (p.x - devX) / zoom, y: (p.y - devY) / zoom)
    }

    public override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers, !chars.isEmpty else {
            super.keyDown(with: event)
            return
        }

        let c = chars.utf16.first!

        // 1. Delete
        if c == NSDeleteCharacter || c == 0x7F || c == NSDeleteFunctionKey {
            if !selectedControls.isEmpty {
                deleteSelected()
                return
            }
        }

        // 2. Arrow Keys Movement
        if c == NSUpArrowFunctionKey || c == NSDownArrowFunctionKey ||
           c == NSLeftArrowFunctionKey || c == NSRightArrowFunctionKey {
            if !selectedControls.isEmpty {
                pushUndoSnapshot()

                var step: CGFloat = gridSize
                if event.modifierFlags.contains(.option) {
                    step = 1.0
                } else if !snapToGrid {
                    step = event.modifierFlags.contains(.shift) ? 10.0 : 5.0
                } else if event.modifierFlags.contains(.shift) {
                    step = gridSize * 2.0
                }

                var dx: CGFloat = 0.0
                var dy: CGFloat = 0.0
                if c == NSUpArrowFunctionKey { dy = -step }
                else if c == NSDownArrowFunctionKey { dy = step }
                else if c == NSLeftArrowFunctionKey { dx = -step }
                else if c == NSRightArrowFunctionKey { dx = step }

                for ctrl in selectedControls {
                    var r = ctrl.frame
                    r.origin.x += dx
                    r.origin.y += dy
                    if snapToGrid && !event.modifierFlags.contains(.option) {
                        r.origin.x = round(r.origin.x / gridSize) * gridSize
                        r.origin.y = round(r.origin.y / gridSize) * gridSize
                    }
                    ctrl.frame = r
                    delegate?.canvasDidChangeControl(ctrl)
                }
                setNeedsDisplay(bounds)
                return
            }
        }

        // 3. Command Shortcuts
        if event.modifierFlags.contains(.command) {
            let lower = chars.lowercased()
            if lower == "a" {
                selectAllControls()
                return
            } else if lower == "c" {
                copySelected()
                return
            } else if lower == "v" {
                pasteCopied()
                return
            } else if lower == "d" {
                duplicateSelected()
                return
            } else if lower == "z" {
                if event.modifierFlags.contains(.shift) {
                    redo()
                } else {
                    undo()
                }
                return
            } else if lower == "y" {
                redo()
                return
            }
        }

        super.keyDown(with: event)
    }

    public override func mouseDown(with event: NSEvent) {
        CloseColorPanelIfOpen()
        self.window?.makeFirstResponder(self)
        let mousePos = canvasPoint(from: event)
        let flags = event.modifierFlags
        let isMultiSelect = flags.contains(.command) || flags.contains(.shift)

        // Check resize handles if controls are selected
        if !selectedControls.isEmpty, let selCtrl = selectedControl {
            let devW = layout.canvasWidth > 0 ? layout.canvasWidth : 920.0
            let devH = layout.canvasHeight > 0 ? layout.canvasHeight : 460.0
            let availW = max(100.0, self.bounds.size.width - 60.0)
            let availH = max(100.0, self.bounds.size.height - 70.0)
            let zoom = min(1.0, min(availW / devW, availH / devH))

            let r = selCtrl.frame
            let hArea = 18.0 / zoom
            let tlHandle = NSRect(x: r.minX - hArea / 2.0, y: r.minY - hArea / 2.0, width: hArea, height: hArea)
            let trHandle = NSRect(x: r.maxX - hArea / 2.0, y: r.minY - hArea / 2.0, width: hArea, height: hArea)
            let brHandle = NSRect(x: r.maxX - hArea / 2.0, y: r.maxY - hArea / 2.0, width: hArea, height: hArea)
            let blHandle = NSRect(x: r.minX - hArea / 2.0, y: r.maxY - hArea / 2.0, width: hArea, height: hArea)

            var corner = 0
            if tlHandle.contains(mousePos) { corner = 1 }
            else if trHandle.contains(mousePos) { corner = 2 }
            else if brHandle.contains(mousePos) { corner = 3 }
            else if blHandle.contains(mousePos) { corner = 4 }

            if corner > 0 {
                isResizing = true
                resizeCorner = corner
                dragStartMouse = mousePos
                initialControlFrame = r
                initialFramesByControlId.removeAll()
                for c in selectedControls {
                    initialFramesByControlId[c.controlId] = c.frame
                }
                mouseDownSnapshot = currentControlsSnapshot()
                hasDraggedOrResized = false
                return
            }
        }

        // Hit test controls (front to back)
        var hit: MidiControlModel? = nil
        for ctrl in layout.controls.reversed() {
            if ctrl.frame.contains(mousePos) {
                hit = ctrl
                break
            }
        }

        clickedControlOnMouseDown = hit
        clickedControlWasAlreadySelected = false

        if let hit = hit {
            if isMultiSelect {
                if let idx = selectedControls.firstIndex(where: { $0 === hit }) {
                    selectedControls.remove(at: idx)
                    delegate?.canvasDidSelectControl(selectedControl)
                } else {
                    selectedControls.append(hit)
                    delegate?.canvasDidSelectControl(hit)
                }
            } else {
                if !selectedControls.contains(where: { $0 === hit }) {
                    selectedControls.removeAll()
                    selectedControls.append(hit)
                    delegate?.canvasDidSelectControl(hit)
                } else {
                    clickedControlWasAlreadySelected = true
                    delegate?.canvasDidSelectControl(hit)
                }
            }

            isDragging = true
            dragStartMouse = mousePos
            mouseDownSnapshot = currentControlsSnapshot()
            hasDraggedOrResized = false
            initialFramesByControlId.removeAll()
            for ctrl in selectedControls {
                initialFramesByControlId[ctrl.controlId] = ctrl.frame
            }
        } else {
            if !isMultiSelect {
                selectedControls.removeAll()
                delegate?.canvasDidSelectControl(nil)
            }
            isMarqueeSelecting = true
            marqueeStartPoint = mousePos
            marqueeRect = NSRect(x: mousePos.x, y: mousePos.y, width: 0, height: 0)
            initialSelectionBeforeMarquee = selectedControls
        }

        setNeedsDisplay(bounds)
    }

    public override func mouseDragged(with event: NSEvent) {
        let mousePos = canvasPoint(from: event)

        if isResizing, let selCtrl = selectedControl {
            if !hasDraggedOrResized {
                hasDraggedOrResized = true
                if let snap = mouseDownSnapshot { pushSnapshot(snap) }
            }

            let dx = mousePos.x - dragStartMouse.x
            let dy = mousePos.y - dragStartMouse.y
            let initF = initialControlFrame
            let minW: CGFloat = 40.0
            let minH: CGFloat = 30.0

            var newX = initF.origin.x
            var newY = initF.origin.y
            var newW = initF.size.width
            var newH = initF.size.height

            if resizeCorner == 1 { // Top-Left
                newX = min(initF.origin.x + dx, initF.maxX - minW)
                newY = min(initF.origin.y + dy, initF.maxY - minH)
                if snapToGrid && !event.modifierFlags.contains(.option) {
                    newX = round(newX / gridSize) * gridSize
                    newY = round(newY / gridSize) * gridSize
                }
                newW = initF.maxX - newX
                newH = initF.maxY - newY
            } else if resizeCorner == 2 { // Top-Right
                newY = min(initF.origin.y + dy, initF.maxY - minH)
                if snapToGrid && !event.modifierFlags.contains(.option) {
                    newY = round(newY / gridSize) * gridSize
                }
                newH = initF.maxY - newY
                newW = max(minW, initF.size.width + dx)
                if snapToGrid && !event.modifierFlags.contains(.option) {
                    newW = round(newW / gridSize) * gridSize
                }
            } else if resizeCorner == 3 { // Bottom-Right
                newW = max(minW, initF.size.width + dx)
                newH = max(minH, initF.size.height + dy)
                if snapToGrid && !event.modifierFlags.contains(.option) {
                    newW = round(newW / gridSize) * gridSize
                    newH = round(newH / gridSize) * gridSize
                }
            } else if resizeCorner == 4 { // Bottom-Left
                newX = min(initF.origin.x + dx, initF.maxX - minW)
                if snapToGrid && !event.modifierFlags.contains(.option) {
                    newX = round(newX / gridSize) * gridSize
                }
                newW = initF.maxX - newX
                newH = max(minH, initF.size.height + dy)
                if snapToGrid && !event.modifierFlags.contains(.option) {
                    newH = round(newH / gridSize) * gridSize
                }
            }

            let deltaW = newW - initF.size.width
            let deltaH = newH - initF.size.height

            if selectedControls.count > 1 {
                for c in selectedControls {
                    if let orig = initialFramesByControlId[c.controlId] {
                        let finalW = max(minW, orig.size.width + deltaW)
                        let finalH = max(minH, orig.size.height + deltaH)
                        var finalX = orig.origin.x
                        var finalY = orig.origin.y
                        if resizeCorner == 1 || resizeCorner == 4 {
                            finalX = orig.origin.x - deltaW
                        }
                        if resizeCorner == 1 || resizeCorner == 2 {
                            finalY = orig.origin.y - deltaH
                        }
                        c.frame = NSRect(x: finalX, y: finalY, width: finalW, height: finalH)
                        delegate?.canvasDidChangeControl(c)
                    }
                }
            } else {
                selCtrl.frame = NSRect(x: newX, y: newY, width: newW, height: newH)
                delegate?.canvasDidChangeControl(selCtrl)
            }
            setNeedsDisplay(bounds)
        } else if isDragging && !selectedControls.isEmpty {
            if !hasDraggedOrResized {
                hasDraggedOrResized = true
                if let snap = mouseDownSnapshot { pushSnapshot(snap) }
            }

            var deltaX = mousePos.x - dragStartMouse.x
            var deltaY = mousePos.y - dragStartMouse.y

            if snapToGrid && !event.modifierFlags.contains(.option) {
                deltaX = round(deltaX / gridSize) * gridSize
                deltaY = round(deltaY / gridSize) * gridSize
            }

            for ctrl in selectedControls {
                if let origRect = initialFramesByControlId[ctrl.controlId] {
                    ctrl.frame = NSRect(x: origRect.origin.x + deltaX, y: origRect.origin.y + deltaY, width: origRect.size.width, height: origRect.size.height)
                    delegate?.canvasDidChangeControl(ctrl)
                }
            }
            setNeedsDisplay(bounds)
        } else if isMarqueeSelecting {
            let minX = min(marqueeStartPoint.x, mousePos.x)
            let minY = min(marqueeStartPoint.y, mousePos.y)
            let width = abs(mousePos.x - marqueeStartPoint.x)
            let height = abs(mousePos.y - marqueeStartPoint.y)
            marqueeRect = NSRect(x: minX, y: minY, width: width, height: height)

            let isMultiSelect = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
            if isMultiSelect, let initial = initialSelectionBeforeMarquee {
                selectedControls = initial
            } else {
                selectedControls.removeAll()
            }

            for ctrl in layout.controls {
                if marqueeRect.intersects(ctrl.frame) {
                    if !selectedControls.contains(where: { $0 === ctrl }) {
                        selectedControls.append(ctrl)
                    }
                }
            }

            delegate?.canvasDidSelectControl(selectedControl)
            setNeedsDisplay(bounds)
        }
    }

    public override func mouseUp(with event: NSEvent) {
        let isMultiSelect = event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift)
        if !hasDraggedOrResized && clickedControlWasAlreadySelected && clickedControlOnMouseDown != nil && !isMultiSelect {
            selectedControls.removeAll()
            if let clicked = clickedControlOnMouseDown {
                selectedControls.append(clicked)
                delegate?.canvasDidSelectControl(clicked)
            }
        }

        isDragging = false
        isResizing = false
        isMarqueeSelecting = false
        clickedControlOnMouseDown = nil
        clickedControlWasAlreadySelected = false
        marqueeRect = .zero
        initialSelectionBeforeMarquee = nil
        delegate?.canvasDidSelectControl(selectedControl)
        setNeedsDisplay(bounds)
    }

    // MARK: - Context Menu

    public override func menu(for event: NSEvent) -> NSMenu? {
        CloseColorPanelIfOpen()
        let mousePos = canvasPoint(from: event)
        lastRightClickPoint = mousePos

        var hit: MidiControlModel? = nil
        for ctrl in layout.controls.reversed() {
            if ctrl.frame.contains(mousePos) {
                hit = ctrl
                break
            }
        }

        if let hit = hit {
            if !selectedControls.contains(where: { $0 === hit }) {
                selectedControls.removeAll()
                selectedControls.append(hit)
                delegate?.canvasDidSelectControl(hit)
            }
            setNeedsDisplay(bounds)
        }

        let menu = NSMenu(title: "Canvas Context")

        let itemFader = NSMenuItem(title: "Add Vertical Fader", action: #selector(onAddFader(_:)), keyEquivalent: "")
        itemFader.image = AirSymbol("slider.vertical.3", 13.0)
        itemFader.target = self
        menu.addItem(itemFader)

        let itemHorizFader = NSMenuItem(title: "Add Horizontal Fader", action: #selector(onAddHorizontalFader(_:)), keyEquivalent: "")
        itemHorizFader.image = AirSymbol("slider.horizontal.3", 13.0)
        itemHorizFader.target = self
        menu.addItem(itemHorizFader)

        let itemKnob = NSMenuItem(title: "Add Rotary Knob", action: #selector(onAddKnob(_:)), keyEquivalent: "")
        itemKnob.image = AirSymbol("dial.medium", 13.0)
        itemKnob.target = self
        menu.addItem(itemKnob)

        let itemBtn = NSMenuItem(title: "Add Button / Pad", action: #selector(onAddButton(_:)), keyEquivalent: "")
        itemBtn.image = AirSymbol("square.grid.2x2", 13.0)
        itemBtn.target = self
        menu.addItem(itemBtn)

        let itemXY = NSMenuItem(title: "Add XY Pad", action: #selector(onAddXYPad(_:)), keyEquivalent: "")
        itemXY.image = AirSymbol("dot.squareshape.split.2x2", 13.0)
        itemXY.target = self
        menu.addItem(itemXY)

        let itemLbl = NSMenuItem(title: "Add Text Label", action: #selector(onAddLabel(_:)), keyEquivalent: "")
        itemLbl.image = AirSymbol("textformat", 13.0)
        itemLbl.target = self
        menu.addItem(itemLbl)

        let itemDisplay = NSMenuItem(title: "Add BPM / Value Display", action: #selector(onAddDisplay(_:)), keyEquivalent: "")
        itemDisplay.image = AirSymbol("metronome", 13.0)
        itemDisplay.target = self
        menu.addItem(itemDisplay)

        menu.addItem(NSMenuItem.separator())

        let itemSnap = NSMenuItem(title: "Snap to Grid (\(Int(gridSize))px)", action: #selector(toggleSnapToGrid(_:)), keyEquivalent: "")
        itemSnap.state = snapToGrid ? .on : .off
        itemSnap.image = AirSymbol("grid", 13.0)
        itemSnap.target = self
        menu.addItem(itemSnap)

        let gridSubmenu = NSMenu(title: "Grid Size")
        let sizes: [CGFloat] = [5.0, 10.0, 15.0, 20.0, 25.0, 30.0, 40.0, 50.0]
        for s in sizes {
            let item = NSMenuItem(title: "\(Int(s)) px", action: #selector(onSelectGridSizeFromMenu(_:)), keyEquivalent: "")
            item.representedObject = s
            item.state = (abs(gridSize - s) < 0.1) ? .on : .off
            item.target = self
            gridSubmenu.addItem(item)
        }
        let gridMenuItem = NSMenuItem(title: "Grid Size", action: nil, keyEquivalent: "")
        gridMenuItem.submenu = gridSubmenu
        gridMenuItem.image = AirSymbol("ruler", 13.0)
        menu.addItem(gridMenuItem)

        if !selectedControls.isEmpty {
            menu.addItem(NSMenuItem.separator())

            let itemCopy = NSMenuItem(title: "Copy", action: #selector(copySelected), keyEquivalent: "c")
            itemCopy.image = AirSymbol("doc.on.doc", 13.0)
            itemCopy.target = self
            menu.addItem(itemCopy)

            if !copiedControls.isEmpty {
                let itemPaste = NSMenuItem(title: "Paste", action: #selector(pasteCopied), keyEquivalent: "v")
                itemPaste.image = AirSymbol("doc.on.clipboard", 13.0)
                itemPaste.target = self
                menu.addItem(itemPaste)
            }

            let itemDup = NSMenuItem(title: "Duplicate", action: #selector(duplicateSelected), keyEquivalent: "d")
            itemDup.image = AirSymbol("plus.square.on.square", 13.0)
            itemDup.target = self
            menu.addItem(itemDup)

            menu.addItem(NSMenuItem.separator())

            let itemUndo = NSMenuItem(title: "Undo", action: #selector(undo), keyEquivalent: "z")
            itemUndo.image = AirSymbol("arrow.uturn.backward", 13.0)
            itemUndo.target = self
            menu.addItem(itemUndo)

            let itemRedo = NSMenuItem(title: "Redo", action: #selector(redo), keyEquivalent: "Z")
            itemRedo.image = AirSymbol("arrow.uturn.forward", 13.0)
            itemRedo.target = self
            menu.addItem(itemRedo)

            menu.addItem(NSMenuItem.separator())

            let itemFront = NSMenuItem(title: "Bring to Front", action: #selector(bringSelectedToFront), keyEquivalent: "")
            itemFront.image = AirSymbol("arrow.up.to.line", 13.0)
            itemFront.target = self
            menu.addItem(itemFront)

            let itemBack = NSMenuItem(title: "Send to Back", action: #selector(sendSelectedToBack), keyEquivalent: "")
            itemBack.image = AirSymbol("arrow.down.to.line", 13.0)
            itemBack.target = self
            menu.addItem(itemBack)

            menu.addItem(NSMenuItem.separator())

            let itemDel = NSMenuItem(title: "Delete", action: #selector(deleteSelected), keyEquivalent: "\u{8}")
            itemDel.image = AirSymbol("trash", 13.0)
            itemDel.target = self
            menu.addItem(itemDel)
        } else if !copiedControls.isEmpty {
            menu.addItem(NSMenuItem.separator())
            let itemPaste = NSMenuItem(title: "Paste", action: #selector(pasteCopied), keyEquivalent: "v")
            itemPaste.image = AirSymbol("doc.on.clipboard", 13.0)
            itemPaste.target = self
            menu.addItem(itemPaste)
        }

        return menu
    }

    @objc private func onAddFader(_ sender: Any?) { addControl(ofType: "fader", orientation: "vertical", at: lastRightClickPoint) }
    @objc private func onAddHorizontalFader(_ sender: Any?) { addControl(ofType: "fader", orientation: "horizontal", at: lastRightClickPoint) }
    @objc private func onAddKnob(_ sender: Any?) { addControl(ofType: "knob", orientation: "vertical", at: lastRightClickPoint) }
    @objc private func onAddButton(_ sender: Any?) { addControl(ofType: "button", orientation: "vertical", at: lastRightClickPoint) }
    @objc private func onAddXYPad(_ sender: Any?) { addControl(ofType: "xypad", orientation: "vertical", at: lastRightClickPoint) }
    @objc private func onAddLabel(_ sender: Any?) { addControl(ofType: "label", orientation: "horizontal", at: lastRightClickPoint) }
    @objc private func onAddDisplay(_ sender: Any?) { addControl(ofType: "display", orientation: "vertical", at: lastRightClickPoint) }

    // MARK: - Undo & Redo

    public func currentControlsSnapshot() -> [MidiControlModel] {
        return layout.controls.map { ($0.copy() as! MidiControlModel) }
    }

    private func pushSnapshot(_ snapshot: [MidiControlModel]) {
        undoStack.append(snapshot)
        while undoStack.count > Self.maxUndoSteps {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    public func pushUndoSnapshot() {
        pushSnapshot(currentControlsSnapshot())
    }

    @objc public func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentControlsSnapshot())
        while redoStack.count > Self.maxUndoSteps {
            redoStack.removeFirst()
        }
        restoreControls(from: previous)
    }

    @objc public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentControlsSnapshot())
        while undoStack.count > Self.maxUndoSteps {
            undoStack.removeFirst()
        }
        restoreControls(from: next)
    }

    private func restoreControls(from snapshot: [MidiControlModel]) {
        let prevSelectedIds = Set(selectedControls.map { $0.controlId })
        layout.controls.removeAll()

        var newSelectedList: [MidiControlModel] = []
        for m in snapshot {
            let copy = m.copy() as! MidiControlModel
            layout.controls.append(copy)
            if prevSelectedIds.contains(copy.controlId) {
                newSelectedList.append(copy)
            }
        }
        selectedControls = newSelectedList
        delegate?.canvasDidSelectControl(selectedControl)
        setNeedsDisplay(bounds)
    }

    // MARK: - Clipboard & Actions

    @objc public func copySelected() {
        guard !selectedControls.isEmpty else { return }
        copiedControls = selectedControls.map { ($0.copy() as! MidiControlModel) }
    }

    private func nextAvailableMidiNumber(forMidiType type: String, channel: Int) -> Int {
        var used = Set<Int>()
        for c in layout.controls {
            if c.midiChannel == channel && c.midiType == type {
                used.insert(c.midiNumber)
            }
        }
        let start = (type == "note") ? 60 : 11
        var candidate = start
        while used.contains(candidate) && candidate < 127 {
            candidate += 1
        }
        return candidate
    }

    @objc public func pasteCopied() {
        guard !copiedControls.isEmpty else { return }
        pushUndoSnapshot()

        let offset: CGFloat = snapToGrid ? gridSize : 15.0
        var newSelection: [MidiControlModel] = []
        for orig in copiedControls {
            let copy = orig.copy() as! MidiControlModel
            copy.controlId = String(format: "%@_%u", copy.type, arc4random() % 10000)
            copy.label = "\(copy.label) Copy"
            copy.frame = copy.frame.offsetBy(dx: offset, dy: offset)
            copy.midiNumber = nextAvailableMidiNumber(forMidiType: copy.midiType, channel: copy.midiChannel)
            layout.controls.append(copy)
            newSelection.append(copy)
        }
        selectedControls = newSelection
        delegate?.canvasDidSelectControl(selectedControl)
        setNeedsDisplay(bounds)
    }

    public func addControlOfTypeAtCenter(_ type: String) {
        var t = type
        if t == "xy" { t = "xypad" }
        let devW = layout.canvasWidth > 0 ? layout.canvasWidth : 920.0
        let devH = layout.canvasHeight > 0 ? layout.canvasHeight : 460.0

        let w: CGFloat = (t == "fader") ? 80 : (t == "knob") ? 80 : (t == "button") ? 80 : (t == "display") ? 140 : (t == "xypad") ? 180 : 120
        let h: CGFloat = (t == "fader") ? 220 : (t == "knob") ? 80 : (t == "button") ? 60 : (t == "display") ? 70 : (t == "xypad") ? 180 : 36

        let cx = (devW - w) / 2.0 + CGFloat(layout.controls.count % 5) * gridSize
        let cy = (devH - h) / 2.0 + CGFloat(layout.controls.count % 4) * gridSize

        let defOrient = (t == "label") ? "horizontal" : "vertical"
        addControl(ofType: t, orientation: defOrient, at: NSPoint(x: cx, y: cy))
    }

    public func addControl(ofType type: String, orientation: String = "vertical", at pt: NSPoint) {
        pushUndoSnapshot()

        var t = type
        if t == "xy" { t = "xypad" }
        let m = MidiControlModel()
        m.controlId = String(format: "%@_%u", t, arc4random() % 10000)
        m.type = t
        m.orientation = orientation
        m.knobStyle = "standard"
        m.label = "\(t.uppercased()) \(layout.controls.count + 1)"

        let isHoriz = (m.orientation == "horizontal")
        let w: CGFloat = (t == "fader") ? (isHoriz ? 240 : 80) : (t == "knob") ? 80 : (t == "button") ? 80 : (t == "display") ? 140 : (t == "xypad") ? 180 : (isHoriz ? 120 : 36)
        let h: CGFloat = (t == "fader") ? (isHoriz ? 70 : 220) : (t == "knob") ? 80 : (t == "button") ? 60 : (t == "display") ? 70 : (t == "xypad") ? 180 : (isHoriz ? 36 : 120)

        let devW = layout.canvasWidth > 0 ? layout.canvasWidth : 920.0
        let devH = layout.canvasHeight > 0 ? layout.canvasHeight : 460.0
        var posX = snapToGrid ? (round((pt.x - w / 2.0) / gridSize) * gridSize) : (pt.x - w / 2.0)
        var posY = snapToGrid ? (round((pt.y - h / 2.0) / gridSize) * gridSize) : (pt.y - h / 2.0)
        posX = max(10.0, min(devW - w - 10.0, posX))
        posY = max(10.0, min(devH - h - 10.0, posY))
        m.frame = NSRect(x: posX, y: posY, width: w, height: h)

        m.color = NSColor(calibratedRed: 0.0, green: 0.45, blue: 0.5, alpha: 1.0)
        m.accentColor = NSColor(calibratedRed: 0.0, green: 0.8, blue: 1.0, alpha: 1.0)
        m.midiChannel = 1
        m.midiType = (t == "button") ? "note" : "cc"
        m.midiNumber = nextAvailableMidiNumber(forMidiType: m.midiType, channel: m.midiChannel)
        m.minValue = 0
        m.maxValue = 127
        m.mode = (t == "button") ? "toggle" : "momentary"
        m.value = (t == "button") ? 127 : ((t == "fader" || t == "knob") ? 64 : ((t == "display") ? 120 : 0))

        if t == "fader" {
            m.hasLabel = true
            m.labelPosition = "top"
            m.hasBackground = true
        } else if t == "knob" {
            m.hasLabel = true
            m.labelPosition = "bottom"
            m.hasBackground = true
        } else if t == "button" {
            m.shape = "square"
            m.mode = "toggle" // Default to Toggle so buttons stay activated in DAW!
        } else if t == "display" {
            m.label = "BPM"
            m.hasLabel = true
            m.labelPosition = "top"
            m.displayMode = "bpm"
            m.hasBackground = true
            m.midiType = "note"
            m.midiChannel = 1
            m.midiNumber = nextAvailableMidiNumber(forMidiType: "note", channel: 1)
            m.mode = "momentary"
            m.minValue = 0
            m.maxValue = 127
            m.fontSize = 28.0
        }

        layout.controls.append(m)
        selectedControl = m
        delegate?.canvasDidSelectControl(m)
        setNeedsDisplay(bounds)
    }

    @objc public func duplicateSelected() {
        guard !selectedControls.isEmpty else { return }
        pushUndoSnapshot()

        let offset: CGFloat = snapToGrid ? gridSize : 15.0
        var newSelection: [MidiControlModel] = []

        for orig in selectedControls {
            let copy = orig.copy() as! MidiControlModel
            copy.controlId = String(format: "%@_%u", copy.type, arc4random() % 10000)
            copy.label = "\(copy.label) Copy"
            copy.frame = copy.frame.offsetBy(dx: offset, dy: offset)
            copy.midiNumber = nextAvailableMidiNumber(forMidiType: copy.midiType, channel: copy.midiChannel)

            layout.controls.append(copy)
            newSelection.append(copy)
        }

        selectedControls = newSelection
        delegate?.canvasDidSelectControl(selectedControl)
        setNeedsDisplay(bounds)
    }

    @objc public func deleteSelected(_ sender: Any? = nil) {
        guard !selectedControls.isEmpty else { return }
        pushUndoSnapshot()

        let toDelete = selectedControls
        selectedControls.removeAll()
        for target in toDelete {
            layout.controls.removeAll(where: { $0 === target })
        }
        delegate?.canvasDidDeleteControl(nil)
        setNeedsDisplay(bounds)
    }

    @objc public func bringSelectedToFront() {
        guard !selectedControls.isEmpty else { return }
        pushUndoSnapshot()

        let selected = selectedControls
        for m in selected {
            layout.controls.removeAll(where: { $0 === m })
            layout.controls.append(m)
        }
        setNeedsDisplay(bounds)
    }

    @objc public func sendSelectedToBack() {
        guard !selectedControls.isEmpty else { return }
        pushUndoSnapshot()

        let selected = selectedControls
        for m in selected.reversed() {
            layout.controls.removeAll(where: { $0 === m })
            layout.controls.insert(m, at: 0)
        }
        setNeedsDisplay(bounds)
    }
}
