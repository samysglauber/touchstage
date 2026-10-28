import Cocoa

public class AirFlippedView: NSView {
    public override var isFlipped: Bool { return true }
    public override var mouseDownCanMoveWindow: Bool { return false }
}

@objc public protocol InspectorDelegate: AnyObject {
    @objc optional func inspectorWillChangeControl(_ control: MidiControlModel)
    func inspectorDidUpdateControl(_ control: MidiControlModel)
    func inspectorDidRequestDuplicate(_ control: MidiControlModel)
    func inspectorDidRequestDelete(_ control: MidiControlModel)
}

public class InspectorView: NSView, NSTextFieldDelegate {
    public weak var delegate: InspectorDelegate?
    public var currentControl: MidiControlModel?

    private var visualEffect: NSVisualEffectView!
    private var scrollView: NSScrollView!
    private var contentContainer: AirFlippedView!
    private var emptyStateView: AirFlippedView!

    // Header Badge & Name
    private var badgeRow: NSView!
    private var colorDot: NSView!
    private var badgeLabel: NSTextField!
    private var labelField: NSTextField!

    private var appearanceHeader: NSTextField!
    private var showLabelCheckbox: NSButton!
    private var labelPosLabel: NSTextField!
    private var labelPosSegment: NSSegmentedControl!
    private var fontSizeLabel: NSTextField!
    private var fontSizeSlider: NSSlider!
    private var buttonShapeLabel: NSTextField!
    private var buttonShapeSegment: NSSegmentedControl!
    private var labelBgCheckbox: NSButton!

    // Knob & Fader specific options
    private var knobStyleLabel: NSTextField!
    private var knobStyleSegment: NSSegmentedControl!
    private var knobValueDisplayLabel: NSTextField!
    private var knobValueDisplaySegment: NSSegmentedControl!
    private var knobValuePosLabel: NSTextField!
    private var knobValuePosSegment: NSSegmentedControl!
    private var faderOrientationLabel: NSTextField!
    private var faderOrientationSegment: NSSegmentedControl!
    private var faderStyleLabel: NSTextField!
    private var faderStyleSegment: NSSegmentedControl!

    private var colorLabel: NSTextField!
    private var colorWell: NSColorWell!

    // MIDI Mapping Section
    private var midiHeader: NSTextField!
    private var channelLabel: NSTextField!
    private var midiTypeLabel: NSTextField!
    private var channelPopup: NSPopUpButton!
    private var midiTypePopup: NSPopUpButton!
    private var midiNumLabel: NSTextField!
    private var midiNumberField: NSTextField!
    private var buttonModeLabel: NSTextField!
    private var buttonModeSegment: NSSegmentedControl!

    // MIDI Range
    private var rangeMinLabel: NSTextField!
    private var rangeMaxLabel: NSTextField!
    private var minValField: NSTextField!
    private var maxValField: NSTextField!

    // Position & Size Section
    private var posHeader: NSTextField!
    private var xLabel: NSTextField!
    private var yLabel: NSTextField!
    private var wLabel: NSTextField!
    private var hLabel: NSTextField!
    private var xField: NSTextField!
    private var yField: NSTextField!
    private var wField: NSTextField!
    private var hField: NSTextField!

    // Actions
    private var btnDuplicate: NSButton!
    private var btnDelete: NSButton!

    private var isUpdatingUI: Bool = false

    public override var isFlipped: Bool { return true }
    public override var mouseDownCanMoveWindow: Bool { return false }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        self.wantsLayer = true

        // 1. Frosted Sidebar Material
        visualEffect = NSVisualEffectView(frame: self.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .sidebar
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        self.addSubview(visualEffect)

        // 2. Empty State View
        emptyStateView = AirFlippedView(frame: self.bounds)
        emptyStateView.autoresizingMask = [.width, .height]

        let emptyMidY = self.bounds.size.height / 2.0 - 60.0
        let emptyIcon = NSImageView(frame: NSRect(x: (self.bounds.size.width - 48) / 2.0, y: emptyMidY, width: 48, height: 48))
        emptyIcon.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin, .maxYMargin]
        emptyIcon.image = AirSymbol("slider.vertical.3", 34.0)
        emptyIcon.contentTintColor = NSColor(calibratedWhite: 0.35, alpha: 1.0)
        emptyStateView.addSubview(emptyIcon)

        let emptyTitle = createLabel("No Selection", frame: NSRect(x: 20, y: emptyMidY + 54.0, width: self.bounds.size.width - 40, height: 20), bold: true)
        emptyTitle.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        emptyTitle.alignment = .center
        emptyTitle.font = NSFont.systemFont(ofSize: 13.5, weight: .semibold)
        emptyTitle.textColor = AirColorTextSecondary()
        emptyStateView.addSubview(emptyTitle)

        let emptySub = createLabel("Select a control on canvas to inspect MIDI mapping and properties, or right-click canvas to add.",
                                   frame: NSRect(x: 28, y: emptyMidY + 78.0, width: self.bounds.size.width - 56, height: 50), bold: false)
        emptySub.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        emptySub.alignment = .center
        emptySub.font = NSFont.systemFont(ofSize: 11.0)
        emptySub.textColor = AirColorTextMuted()
        emptyStateView.addSubview(emptySub)

        self.addSubview(emptyStateView)

        // 3. ScrollView for Inspector fields
        scrollView = NSScrollView(frame: self.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.isHidden = true

        contentContainer = AirFlippedView(frame: NSRect(x: 0, y: 0, width: self.bounds.size.width, height: 600.0))
        contentContainer.autoresizingMask = [.width]
        scrollView.documentView = contentContainer
        self.addSubview(scrollView)

        // Build Subviews inside contentContainer
        let pad: CGFloat = 16.0
        let w = self.bounds.size.width - (pad * 2)
        let halfW = (w - 10.0) / 2.0

        // Header: Type Badge & Colored Dot
        badgeRow = NSView(frame: NSRect(x: pad, y: 16, width: w, height: 24))
        colorDot = NSView(frame: NSRect(x: 2, y: 6, width: 10, height: 10))
        colorDot.wantsLayer = true
        colorDot.layer?.cornerRadius = 5.0
        colorDot.layer?.backgroundColor = AirColorAccent().cgColor
        badgeRow.addSubview(colorDot)

        badgeLabel = createLabel("CONTROL PROPERTIES", frame: NSRect(x: 18, y: 2, width: w - 20, height: 18), bold: true)
        badgeLabel.font = NSFont.systemFont(ofSize: 11.0, weight: .bold)
        badgeLabel.textColor = AirColorAccent()
        badgeRow.addSubview(badgeLabel)
        contentContainer.addSubview(badgeRow)

        // Label Name Field
        labelField = NSTextField(frame: NSRect(x: pad, y: 44, width: w, height: 28))
        labelField.delegate = self
        labelField.target = self
        labelField.action = #selector(onFieldChanged(_:))
        labelField.font = NSFont.systemFont(ofSize: 13.0, weight: .medium)
        labelField.focusRingType = .none
        contentContainer.addSubview(labelField)

        // Appearance Section Header
        appearanceHeader = createSectionHeader("APPEARANCE & STYLE", frame: NSRect(x: pad, y: 80, width: w, height: 16))
        contentContainer.addSubview(appearanceHeader)

        // Show Label Checkbox
        showLabelCheckbox = NSButton(checkboxWithTitle: "Show Label Header", target: self, action: #selector(onShowLabelToggled(_:)))
        showLabelCheckbox.frame = NSRect(x: pad, y: 104, width: w, height: 18)
        contentContainer.addSubview(showLabelCheckbox)

        // Label Position Segment
        labelPosLabel = createLabel("Label Position", frame: NSRect(x: pad, y: 128, width: halfW, height: 14), bold: false)
        contentContainer.addSubview(labelPosLabel)
        labelPosSegment = NSSegmentedControl(labels: ["Top", "Bottom"], trackingMode: .selectOne, target: self, action: #selector(onLabelPosChanged(_:)))
        labelPosSegment.frame = NSRect(x: pad + halfW + 10, y: 124, width: halfW, height: 24)
        labelPosSegment.segmentStyle = .texturedRounded
        labelPosSegment.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        contentContainer.addSubview(labelPosSegment)

        // Font Size Slider
        fontSizeLabel = createLabel("Font Size: Auto", frame: NSRect(x: pad, y: 154, width: halfW, height: 14), bold: false)
        contentContainer.addSubview(fontSizeLabel)
        fontSizeSlider = NSSlider(frame: NSRect(x: pad + halfW + 10, y: 150, width: halfW, height: 20))
        fontSizeSlider.minValue = 0
        fontSizeSlider.maxValue = 32
        fontSizeSlider.target = self
        fontSizeSlider.action = #selector(onFontSizeChanged(_:))
        contentContainer.addSubview(fontSizeSlider)

        // Button Shape Segment
        buttonShapeLabel = createLabel("Button Shape", frame: NSRect(x: pad, y: 104, width: w, height: 14), bold: false)
        contentContainer.addSubview(buttonShapeLabel)
        buttonShapeSegment = NSSegmentedControl(labels: ["Square", "Circle (LED)"], trackingMode: .selectOne, target: self, action: #selector(onButtonShapeChanged(_:)))
        buttonShapeSegment.frame = NSRect(x: pad, y: 122, width: w, height: 24)
        buttonShapeSegment.segmentStyle = .texturedRounded
        buttonShapeSegment.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        contentContainer.addSubview(buttonShapeSegment)

        // Label Capsule Background
        labelBgCheckbox = NSButton(checkboxWithTitle: "Capsule Background", target: self, action: #selector(onLabelBgToggled(_:)))
        labelBgCheckbox.frame = NSRect(x: pad, y: 104, width: w, height: 18)
        contentContainer.addSubview(labelBgCheckbox)

        // Fader Orientation Segment
        faderOrientationLabel = createLabel("Orientation", frame: NSRect(x: pad, y: 104, width: w, height: 14), bold: false)
        contentContainer.addSubview(faderOrientationLabel)
        faderOrientationSegment = NSSegmentedControl(labels: ["Vertical", "Horizontal"], trackingMode: .selectOne, target: self, action: #selector(onFaderOrientationChanged(_:)))
        faderOrientationSegment.frame = NSRect(x: pad, y: 122, width: w, height: 24)
        faderOrientationSegment.segmentStyle = .texturedRounded
        faderOrientationSegment.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        contentContainer.addSubview(faderOrientationSegment)

        // Fader Style Segment
        faderStyleLabel = createLabel("Fader Behavior", frame: NSRect(x: pad, y: 104, width: w, height: 14), bold: false)
        contentContainer.addSubview(faderStyleLabel)
        faderStyleSegment = NSSegmentedControl(labels: ["Standard", "Inverted", "Centered"], trackingMode: .selectOne, target: self, action: #selector(onFaderStyleChanged(_:)))
        faderStyleSegment.frame = NSRect(x: pad, y: 122, width: w, height: 24)
        faderStyleSegment.segmentStyle = .texturedRounded
        faderStyleSegment.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        contentContainer.addSubview(faderStyleSegment)

        // Knob Style Segment
        knobStyleLabel = createLabel("Knob Behavior", frame: NSRect(x: pad, y: 104, width: w, height: 14), bold: false)
        contentContainer.addSubview(knobStyleLabel)
        knobStyleSegment = NSSegmentedControl(labels: ["Standard", "Inverted", "Centered"], trackingMode: .selectOne, target: self, action: #selector(onKnobStyleChanged(_:)))
        knobStyleSegment.frame = NSRect(x: pad, y: 122, width: w, height: 24)
        knobStyleSegment.segmentStyle = .texturedRounded
        knobStyleSegment.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        contentContainer.addSubview(knobStyleSegment)

        // Knob Value Display Segment
        knobValueDisplayLabel = createLabel("Value Display", frame: NSRect(x: pad, y: 146, width: w, height: 14), bold: false)
        contentContainer.addSubview(knobValueDisplayLabel)
        knobValueDisplaySegment = NSSegmentedControl(labels: ["Off", "0-127", "%"], trackingMode: .selectOne, target: self, action: #selector(onKnobValueDisplayChanged(_:)))
        knobValueDisplaySegment.frame = NSRect(x: pad, y: 164, width: w, height: 24)
        knobValueDisplaySegment.segmentStyle = .texturedRounded
        knobValueDisplaySegment.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        contentContainer.addSubview(knobValueDisplaySegment)

        // Knob Value Position Segment
        knobValuePosLabel = createLabel("Display Position", frame: NSRect(x: pad, y: 188, width: w, height: 14), bold: false)
        contentContainer.addSubview(knobValuePosLabel)
        knobValuePosSegment = NSSegmentedControl(labels: ["Center", "Bottom"], trackingMode: .selectOne, target: self, action: #selector(onKnobValuePosChanged(_:)))
        knobValuePosSegment.frame = NSRect(x: pad, y: 206, width: w, height: 24)
        knobValuePosSegment.segmentStyle = .texturedRounded
        knobValuePosSegment.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        contentContainer.addSubview(knobValuePosSegment)

        // Single Color Picker
        colorLabel = createLabel("Control Color", frame: NSRect(x: pad, y: 178, width: w, height: 14), bold: false)
        contentContainer.addSubview(colorLabel)

        colorWell = NSColorWell(frame: NSRect(x: pad, y: 196, width: w, height: 28))
        colorWell.target = self
        colorWell.action = #selector(onColorChanged(_:))
        contentContainer.addSubview(colorWell)

        // MIDI Mapping Section Header
        midiHeader = createSectionHeader("MIDI MAPPING", frame: NSRect(x: pad, y: 214, width: w, height: 16))
        contentContainer.addSubview(midiHeader)

        channelLabel = createLabel("Channel", frame: NSRect(x: pad, y: 234, width: halfW, height: 14), bold: false)
        contentContainer.addSubview(channelLabel)
        midiTypeLabel = createLabel("Message Type", frame: NSRect(x: pad + halfW + 10, y: 234, width: halfW, height: 14), bold: false)
        contentContainer.addSubview(midiTypeLabel)

        channelPopup = NSPopUpButton(frame: NSRect(x: pad, y: 252, width: halfW, height: 26), pullsDown: false)
        for ch in 1...16 {
            channelPopup.addItem(withTitle: "Ch \(ch)")
        }
        channelPopup.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        channelPopup.target = self
        channelPopup.action = #selector(onChannelChanged(_:))
        contentContainer.addSubview(channelPopup)

        midiTypePopup = NSPopUpButton(frame: NSRect(x: pad + halfW + 10, y: 252, width: halfW, height: 26), pullsDown: false)
        midiTypePopup.addItems(withTitles: ["Control (CC)", "Note", "Pitch Bend"])
        midiTypePopup.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        midiTypePopup.target = self
        midiTypePopup.action = #selector(onMidiTypeChanged(_:))
        contentContainer.addSubview(midiTypePopup)

        midiNumLabel = createLabel("CC / Note Number", frame: NSRect(x: pad, y: 286, width: halfW, height: 14), bold: false)
        contentContainer.addSubview(midiNumLabel)
        midiNumberField = NSTextField(frame: NSRect(x: pad, y: 304, width: halfW, height: 24))
        midiNumberField.target = self
        midiNumberField.action = #selector(onFieldChanged(_:))
        contentContainer.addSubview(midiNumberField)

        buttonModeLabel = createLabel("Trigger Mode", frame: NSRect(x: pad, y: 336, width: w, height: 14), bold: false)
        contentContainer.addSubview(buttonModeLabel)
        buttonModeSegment = NSSegmentedControl(labels: ["Momentary", "Toggle"], trackingMode: .selectOne, target: self, action: #selector(onButtonModeChanged(_:)))
        buttonModeSegment.frame = NSRect(x: pad, y: 354, width: w, height: 24)
        buttonModeSegment.segmentStyle = .texturedRounded
        buttonModeSegment.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        contentContainer.addSubview(buttonModeSegment)

        // MIDI Range (0 - 127)
        rangeMinLabel = createLabel("Min Value (0-127)", frame: NSRect(x: pad, y: 384, width: halfW, height: 14), bold: false)
        contentContainer.addSubview(rangeMinLabel)
        rangeMaxLabel = createLabel("Max Value (0-127)", frame: NSRect(x: pad + halfW + 10, y: 384, width: halfW, height: 14), bold: false)
        contentContainer.addSubview(rangeMaxLabel)

        minValField = NSTextField(frame: NSRect(x: pad, y: 402, width: halfW, height: 24))
        minValField.target = self
        minValField.action = #selector(onRangeChanged(_:))
        contentContainer.addSubview(minValField)

        maxValField = NSTextField(frame: NSRect(x: pad + halfW + 10, y: 402, width: halfW, height: 24))
        maxValField.target = self
        maxValField.action = #selector(onRangeChanged(_:))
        contentContainer.addSubview(maxValField)

        // Position & Size Section Header
        posHeader = createSectionHeader("POSITION & SIZE", frame: NSRect(x: pad, y: 342, width: w, height: 16))
        contentContainer.addSubview(posHeader)

        let qW = (w - 15.0) / 4.0
        xLabel = createLabel("X", frame: NSRect(x: pad, y: 362, width: qW, height: 12), bold: false)
        yLabel = createLabel("Y", frame: NSRect(x: pad + (qW + 5), y: 362, width: qW, height: 12), bold: false)
        wLabel = createLabel("Width", frame: NSRect(x: pad + (qW + 5) * 2, y: 362, width: qW, height: 12), bold: false)
        hLabel = createLabel("Height", frame: NSRect(x: pad + (qW + 5) * 3, y: 362, width: qW, height: 12), bold: false)
        contentContainer.addSubview(xLabel)
        contentContainer.addSubview(yLabel)
        contentContainer.addSubview(wLabel)
        contentContainer.addSubview(hLabel)

        xField = NSTextField(frame: NSRect(x: pad, y: 378, width: qW, height: 22))
        xField.target = self; xField.action = #selector(onFrameFieldChanged(_:))
        contentContainer.addSubview(xField)

        yField = NSTextField(frame: NSRect(x: pad + (qW + 5), y: 378, width: qW, height: 22))
        yField.target = self; yField.action = #selector(onFrameFieldChanged(_:))
        contentContainer.addSubview(yField)

        wField = NSTextField(frame: NSRect(x: pad + (qW + 5) * 2, y: 378, width: qW, height: 22))
        wField.target = self; wField.action = #selector(onFrameFieldChanged(_:))
        contentContainer.addSubview(wField)

        hField = NSTextField(frame: NSRect(x: pad + (qW + 5) * 3, y: 378, width: qW, height: 22))
        hField.target = self; hField.action = #selector(onFrameFieldChanged(_:))
        contentContainer.addSubview(hField)

        // Action Buttons
        btnDuplicate = NSButton(frame: NSRect(x: pad, y: 416, width: halfW, height: 30))
        btnDuplicate.title = "Duplicate"
        btnDuplicate.image = AirSymbol("plus.square.on.square", 12.0)
        btnDuplicate.imagePosition = .imageLeading
        btnDuplicate.bezelStyle = .rounded
        btnDuplicate.target = self
        btnDuplicate.action = #selector(onDuplicateClicked(_:))
        contentContainer.addSubview(btnDuplicate)

        btnDelete = NSButton(frame: NSRect(x: pad + halfW + 10, y: 416, width: halfW, height: 30))
        btnDelete.title = "Delete"
        btnDelete.image = AirSymbol("trash", 12.0)
        btnDelete.imagePosition = .imageLeading
        btnDelete.bezelStyle = .rounded
        btnDelete.target = self
        btnDelete.action = #selector(onDeleteClicked(_:))
        contentContainer.addSubview(btnDelete)
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Left Hairline Divider
        AirColorBorder().setStroke()
        let divider = NSBezierPath()
        divider.move(to: NSPoint(x: 0, y: 0))
        divider.line(to: NSPoint(x: 0, y: self.bounds.size.height))
        divider.lineWidth = 1.0
        divider.stroke()
    }

    private func createLabel(_ text: String, frame: NSRect, bold: Bool) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = text
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.font = bold ? NSFont.systemFont(ofSize: 11.0, weight: .bold) : NSFont.systemFont(ofSize: 11.0)
        label.textColor = AirColorTextSecondary()
        return label
    }

    private func createSectionHeader(_ title: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(frame: frame)
        label.stringValue = title
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.font = NSFont.systemFont(ofSize: 10.0, weight: .bold)
        label.textColor = AirColorTextMuted()
        return label
    }

    public func bindControl(_ control: MidiControlModel?) {
        currentControl = control
        guard control != nil else {
            emptyStateView.isHidden = false
            scrollView.isHidden = true
            return
        }

        emptyStateView.isHidden = true
        scrollView.isHidden = false
        scrollView.contentView.scroll(to: .zero)

        refreshValues()
    }

    public func refreshValues() {
        guard let currentControl = currentControl else { return }
        isUpdatingUI = true

        let typeDesc = currentControl.type.uppercased()
        badgeLabel.stringValue = "\(typeDesc) • \(currentControl.label)"
        colorDot.layer?.backgroundColor = currentControl.color.cgColor

        labelField.stringValue = currentControl.label

        let chIdx = max(0, min(15, currentControl.midiChannel - 1))
        channelPopup.selectItem(at: chIdx)

        if currentControl.midiType == "cc" {
            midiTypePopup.selectItem(at: 0)
        } else if currentControl.midiType == "note" {
            midiTypePopup.selectItem(at: 1)
        } else {
            midiTypePopup.selectItem(at: 2)
        }

        midiNumberField.integerValue = currentControl.midiNumber
        buttonModeSegment.selectedSegment = (currentControl.mode == "toggle") ? 1 : 0
        colorWell.color = currentControl.color

        xField.integerValue = Int(round(currentControl.frame.origin.x))
        yField.integerValue = Int(round(currentControl.frame.origin.y))
        wField.integerValue = Int(round(currentControl.frame.size.width))
        hField.integerValue = Int(round(currentControl.frame.size.height))

        // Appearance values
        showLabelCheckbox.state = currentControl.hasLabel ? .on : .off
        labelPosSegment.selectedSegment = (currentControl.labelPosition == "bottom") ? 1 : 0
        fontSizeSlider.doubleValue = Double(currentControl.fontSize)
        fontSizeLabel.stringValue = (currentControl.fontSize > 0) ? "Font Size: \(Int(currentControl.fontSize)) pt" : "Font Size: Auto"
        buttonShapeSegment.selectedSegment = (currentControl.shape == "circle") ? 1 : 0
        labelBgCheckbox.state = currentControl.hasBackground ? .on : .off

        // Fader & Knob behaviors
        faderOrientationSegment.selectedSegment = (currentControl.orientation == "horizontal") ? 1 : 0
        if currentControl.faderStyle == "inverted" {
            faderStyleSegment.selectedSegment = 1
        } else if currentControl.faderStyle == "centered" {
            faderStyleSegment.selectedSegment = 2
        } else {
            faderStyleSegment.selectedSegment = 0
        }

        if currentControl.knobStyle == "inverted" {
            knobStyleSegment.selectedSegment = 1
        } else if currentControl.knobStyle == "centered" {
            knobStyleSegment.selectedSegment = 2
        } else {
            knobStyleSegment.selectedSegment = 0
        }

        if currentControl.valueDisplay == "scale" {
            knobValueDisplaySegment.selectedSegment = 1
        } else if currentControl.valueDisplay == "percent" {
            knobValueDisplaySegment.selectedSegment = 2
        } else {
            knobValueDisplaySegment.selectedSegment = 0
        }

        if currentControl.valuePosition == "bottom" {
            knobValuePosSegment.selectedSegment = 1
        } else {
            knobValuePosSegment.selectedSegment = 0
        }

        // MIDI Range
        minValField.integerValue = currentControl.minValue
        maxValField.integerValue = currentControl.maxValue

        // Relayout fields dynamically
        layoutFieldsForControl(currentControl)

        isUpdatingUI = false
    }

    private func layoutFieldsForControl(_ ctrl: MidiControlModel) {
        let pad: CGFloat = 16.0
        let w = self.bounds.size.width - (pad * 2)
        let halfW = (w - 10.0) / 2.0
        var y: CGFloat = 80.0

        appearanceHeader.frame = NSRect(x: pad, y: y, width: w, height: 16)
        y += 22.0

        let isFader = (ctrl.type == "fader")
        let isKnob = (ctrl.type == "knob")
        let isButton = (ctrl.type == "button")
        let isLabel = (ctrl.type == "label")

        // 1. Controls specific to Fader / Knob
        if isFader || isKnob {
            showLabelCheckbox.isHidden = false
            showLabelCheckbox.title = isFader ? "Show Label Header" : "Show Label"
            showLabelCheckbox.frame = NSRect(x: pad, y: y, width: w, height: 18)
            y += 24.0

            if ctrl.hasLabel {
                labelPosLabel.isHidden = false
                labelPosSegment.isHidden = false
                labelPosLabel.frame = NSRect(x: pad, y: y + 4, width: halfW, height: 14)
                labelPosSegment.frame = NSRect(x: pad + halfW + 10, y: y, width: halfW, height: 24)
                y += 30.0
            } else {
                labelPosLabel.isHidden = true
                labelPosSegment.isHidden = true
            }
        } else {
            showLabelCheckbox.isHidden = true
            labelPosLabel.isHidden = true
            labelPosSegment.isHidden = true
        }

        // Font Size Slider
        if isLabel || ctrl.hasLabel || isButton {
            fontSizeLabel.isHidden = false
            fontSizeSlider.isHidden = false
            fontSizeLabel.frame = NSRect(x: pad, y: y + 4, width: halfW, height: 14)
            fontSizeSlider.frame = NSRect(x: pad + halfW + 10, y: y, width: halfW, height: 20)
            y += 28.0
        } else {
            fontSizeLabel.isHidden = true
            fontSizeSlider.isHidden = true
        }

        // 2. Controls specific to Button
        if isButton {
            buttonShapeLabel.isHidden = false
            buttonShapeSegment.isHidden = false
            buttonShapeLabel.frame = NSRect(x: pad, y: y, width: w, height: 14)
            y += 18.0
            buttonShapeSegment.frame = NSRect(x: pad, y: y, width: w, height: 24)
            y += 32.0
        } else {
            buttonShapeLabel.isHidden = true
            buttonShapeSegment.isHidden = true
        }

        // Controls specific to Fader (Orientation & Style)
        if isFader {
            faderOrientationLabel.isHidden = false
            faderOrientationSegment.isHidden = false
            faderOrientationLabel.frame = NSRect(x: pad, y: y, width: w, height: 14)
            y += 18.0
            faderOrientationSegment.frame = NSRect(x: pad, y: y, width: w, height: 24)
            y += 30.0

            faderStyleLabel.isHidden = false
            faderStyleSegment.isHidden = false
            faderStyleLabel.frame = NSRect(x: pad, y: y, width: w, height: 14)
            y += 18.0
            faderStyleSegment.frame = NSRect(x: pad, y: y, width: w, height: 24)
            y += 32.0
        } else {
            faderOrientationLabel.isHidden = true
            faderOrientationSegment.isHidden = true
            faderStyleLabel.isHidden = true
            faderStyleSegment.isHidden = true
        }

        // Controls specific to Knob
        if isKnob {
            knobStyleLabel.isHidden = false
            knobStyleSegment.isHidden = false
            knobStyleLabel.frame = NSRect(x: pad, y: y, width: w, height: 14)
            y += 18.0
            knobStyleSegment.frame = NSRect(x: pad, y: y, width: w, height: 24)
            y += 30.0

            knobValueDisplayLabel.isHidden = false
            knobValueDisplaySegment.isHidden = false
            knobValueDisplayLabel.frame = NSRect(x: pad, y: y, width: w, height: 14)
            y += 18.0
            knobValueDisplaySegment.frame = NSRect(x: pad, y: y, width: w, height: 24)
            y += 30.0

            let showPos = (ctrl.valueDisplay != "none")
            knobValuePosLabel.isHidden = !showPos
            knobValuePosSegment.isHidden = !showPos
            if showPos {
                knobValuePosLabel.frame = NSRect(x: pad, y: y, width: w, height: 14)
                y += 18.0
                knobValuePosSegment.frame = NSRect(x: pad, y: y, width: w, height: 24)
                y += 30.0
            }
        } else {
            knobStyleLabel.isHidden = true
            knobStyleSegment.isHidden = true
            knobValueDisplayLabel.isHidden = true
            knobValueDisplaySegment.isHidden = true
            knobValuePosLabel.isHidden = true
            knobValuePosSegment.isHidden = true
        }

        // 3. Controls specific to Label
        if isLabel {
            labelBgCheckbox.isHidden = false
            labelBgCheckbox.frame = NSRect(x: pad, y: y, width: w, height: 18)
            y += 24.0
        } else {
            labelBgCheckbox.isHidden = true
        }

        // Color Picker
        colorLabel.frame = NSRect(x: pad, y: y, width: w, height: 14)
        y += 18.0
        colorWell.frame = NSRect(x: pad, y: y, width: w, height: 28)
        y += 36.0

        // MIDI Section
        let hasMidi = !isLabel
        midiHeader.isHidden = !hasMidi
        channelLabel.isHidden = !hasMidi
        midiTypeLabel.isHidden = !hasMidi
        channelPopup.isHidden = !hasMidi
        midiTypePopup.isHidden = !hasMidi
        midiNumLabel.isHidden = !hasMidi
        midiNumberField.isHidden = !hasMidi
        buttonModeLabel.isHidden = !isButton
        buttonModeSegment.isHidden = !isButton
        rangeMinLabel.isHidden = !hasMidi
        rangeMaxLabel.isHidden = !hasMidi
        minValField.isHidden = !hasMidi
        maxValField.isHidden = !hasMidi

        if hasMidi {
            midiHeader.frame = NSRect(x: pad, y: y, width: w, height: 16)
            y += 20.0

            channelLabel.frame = NSRect(x: pad, y: y, width: halfW, height: 14)
            midiTypeLabel.frame = NSRect(x: pad + halfW + 10, y: y, width: halfW, height: 14)
            y += 18.0

            channelPopup.frame = NSRect(x: pad, y: y, width: halfW, height: 26)
            midiTypePopup.frame = NSRect(x: pad + halfW + 10, y: y, width: halfW, height: 26)
            y += 34.0

            if isButton {
                midiNumLabel.stringValue = "Note Number"
                midiNumLabel.frame = NSRect(x: pad, y: y, width: halfW, height: 14)
                y += 18.0
                midiNumberField.frame = NSRect(x: pad, y: y, width: halfW, height: 24)
                y += 32.0

                buttonModeLabel.frame = NSRect(x: pad, y: y, width: w, height: 14)
                y += 18.0
                buttonModeSegment.frame = NSRect(x: pad, y: y, width: w, height: 24)
                y += 34.0
            } else {
                midiNumLabel.stringValue = "CC Number"
                midiNumLabel.frame = NSRect(x: pad, y: y, width: halfW, height: 14)
                y += 18.0
                midiNumberField.frame = NSRect(x: pad, y: y, width: halfW, height: 24)
                y += 34.0
            }

            // MIDI Range (0 - 127)
            rangeMinLabel.frame = NSRect(x: pad, y: y, width: halfW, height: 14)
            rangeMaxLabel.frame = NSRect(x: pad + halfW + 10, y: y, width: halfW, height: 14)
            y += 18.0

            minValField.frame = NSRect(x: pad, y: y, width: halfW, height: 24)
            maxValField.frame = NSRect(x: pad + halfW + 10, y: y, width: halfW, height: 24)
            y += 34.0
        }

        // Position & Size Section
        posHeader.frame = NSRect(x: pad, y: y, width: w, height: 16)
        y += 20.0

        let qW = (w - 15.0) / 4.0
        xLabel.frame = NSRect(x: pad, y: y, width: qW, height: 12)
        yLabel.frame = NSRect(x: pad + (qW + 5), y: y, width: qW, height: 12)
        wLabel.frame = NSRect(x: pad + (qW + 5) * 2, y: y, width: qW, height: 12)
        hLabel.frame = NSRect(x: pad + (qW + 5) * 3, y: y, width: qW, height: 12)
        y += 16.0

        xField.frame = NSRect(x: pad, y: y, width: qW, height: 22)
        yField.frame = NSRect(x: pad + (qW + 5), y: y, width: qW, height: 22)
        wField.frame = NSRect(x: pad + (qW + 5) * 2, y: y, width: qW, height: 22)
        hField.frame = NSRect(x: pad + (qW + 5) * 3, y: y, width: qW, height: 22)
        y += 38.0

        // Actions
        btnDuplicate.frame = NSRect(x: pad, y: y, width: halfW, height: 30)
        btnDelete.frame = NSRect(x: pad + halfW + 10, y: y, width: halfW, height: 30)
        y += 44.0

        contentContainer.frame = NSRect(x: 0, y: 0, width: self.bounds.size.width, height: max(y, self.bounds.size.height))
    }

    private func notifyWillChange() {
        if isUpdatingUI || currentControl == nil { return }
        if let ctrl = currentControl {
            delegate?.inspectorWillChangeControl?(ctrl)
        }
    }

    public func controlTextDidBeginEditing(_ obj: Notification) {
        notifyWillChange()
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        if (obj.object as? NSTextField) === labelField {
            ctrl.label = labelField.stringValue
            badgeLabel.stringValue = "\(ctrl.type.uppercased()) • \(ctrl.label)"
            delegate?.inspectorDidUpdateControl(ctrl)
        }
    }

    @objc private func onShowLabelToggled(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        ctrl.hasLabel = (showLabelCheckbox.state == .on)
        layoutFieldsForControl(ctrl)
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onLabelPosChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        ctrl.labelPosition = (labelPosSegment.selectedSegment == 1) ? "bottom" : "top"
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onButtonShapeChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        ctrl.shape = (buttonShapeSegment.selectedSegment == 1) ? "circle" : "square"
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onLabelBgToggled(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        ctrl.hasBackground = (labelBgCheckbox.state == .on)
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onFieldChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        ctrl.label = labelField.stringValue
        ctrl.midiNumber = midiNumberField.integerValue
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onFrameFieldChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        ctrl.frame = NSRect(x: xField.doubleValue, y: yField.doubleValue, width: wField.doubleValue, height: hField.doubleValue)
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onChannelChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        ctrl.midiChannel = channelPopup.indexOfSelectedItem + 1
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onMidiTypeChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        let idx = midiTypePopup.indexOfSelectedItem
        if idx == 0 { ctrl.midiType = "cc" }
        else if idx == 1 { ctrl.midiType = "note" }
        else { ctrl.midiType = "pitchbend" }
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onButtonModeChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        ctrl.mode = (buttonModeSegment.selectedSegment == 1) ? "toggle" : "momentary"
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onKnobStyleChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        let idx = knobStyleSegment.selectedSegment
        if idx == 1 { ctrl.knobStyle = "inverted" }
        else if idx == 2 { ctrl.knobStyle = "centered" }
        else { ctrl.knobStyle = "standard" }
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onKnobValueDisplayChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        let idx = knobValueDisplaySegment.selectedSegment
        if idx == 1 { ctrl.valueDisplay = "scale" }
        else if idx == 2 { ctrl.valueDisplay = "percent" }
        else { ctrl.valueDisplay = "none" }
        layoutFieldsForControl(ctrl)
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onKnobValuePosChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        ctrl.valuePosition = (knobValuePosSegment.selectedSegment == 1) ? "bottom" : "center"
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onFaderStyleChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        let idx = faderStyleSegment.selectedSegment
        if idx == 1 { ctrl.faderStyle = "inverted" }
        else if idx == 2 { ctrl.faderStyle = "centered" }
        else { ctrl.faderStyle = "standard" }
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onFaderOrientationChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        let makeHorizontal = (faderOrientationSegment.selectedSegment == 1)
        let newOrient = makeHorizontal ? "horizontal" : "vertical"
        if ctrl.orientation != newOrient {
            ctrl.orientation = newOrient
            let f = ctrl.frame
            if makeHorizontal && f.size.height > f.size.width {
                ctrl.frame = NSRect(x: f.origin.x, y: f.origin.y, width: f.size.height, height: f.size.width)
            } else if !makeHorizontal && f.size.width > f.size.height {
                ctrl.frame = NSRect(x: f.origin.x, y: f.origin.y, width: f.size.height, height: f.size.width)
            }
            wField.integerValue = Int(round(ctrl.frame.size.width))
            hField.integerValue = Int(round(ctrl.frame.size.height))
        }
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onRangeChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        var minV = max(0, min(127, minValField.integerValue))
        var maxV = max(0, min(127, maxValField.integerValue))
        if minV > maxV {
            if (sender as? NSTextField) === minValField { maxV = minV }
            else { minV = maxV }
        }
        ctrl.minValue = minV
        ctrl.maxValue = maxV
        minValField.integerValue = minV
        maxValField.integerValue = maxV
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onFontSizeChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        ctrl.fontSize = round(CGFloat(fontSizeSlider.doubleValue))
        fontSizeLabel.stringValue = (ctrl.fontSize > 0) ? "Font Size: \(Int(ctrl.fontSize)) pt" : "Font Size: Auto"
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onColorChanged(_ sender: Any?) {
        guard !isUpdatingUI, let ctrl = currentControl else { return }
        notifyWillChange()
        ctrl.color = colorWell.color
        ctrl.accentColor = colorWell.color
        colorDot.layer?.backgroundColor = colorWell.color.cgColor
        delegate?.inspectorDidUpdateControl(ctrl)
    }

    @objc private func onDuplicateClicked(_ sender: Any?) {
        if let ctrl = currentControl {
            delegate?.inspectorDidRequestDuplicate(ctrl)
        }
    }

    @objc private func onDeleteClicked(_ sender: Any?) {
        if let ctrl = currentControl {
            delegate?.inspectorDidRequestDelete(ctrl)
        }
    }
}
