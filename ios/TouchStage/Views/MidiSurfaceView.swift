import UIKit

public protocol MidiSurfaceViewDelegate: AnyObject {
    func midiSurfaceDidRequestSettings()
    func midiSurfaceDidRequestPageChange(to index: Int)
}

public class MidiSurfaceView: UIView {
    public var layout: LayoutModel = LayoutModel.presetStage8Track() {
        didSet {
            setNeedsDisplay()
        }
    }

    public weak var delegate: MidiSurfaceViewDelegate?
    public var hapticsEnabled: Bool = true

    // Multi-touch tracking state
    private struct ActiveTouch {
        let control: MidiControlModel
        let initialPoint: CGPoint
        let initialValue: Double
        let isBottomButton: Bool
    }

    private var activeTouches: [UITouch: ActiveTouch] = [:]
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .medium)
    private var displayLink: CADisplayLink?
    private var hasActiveAnimations: Bool = false

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        isMultipleTouchEnabled = true
        backgroundColor = UIColor(red: 0.04, green: 0.045, blue: 0.06, alpha: 1.0)
        hapticFeedback.prepare()

        displayLink = CADisplayLink(target: self, selector: #selector(onDisplayFrame))
        displayLink?.add(to: .main, forMode: .common)
    }

    deinit {
        displayLink?.invalidate()
    }

    @objc private func onDisplayFrame() {
        guard let page = layout.currentPage else { return }
        var needsRedraw = false

        for ctrl in page.controls {
            // Smooth button flash decay
            if ctrl.buttonFlash > 0.01 {
                ctrl.buttonFlash = max(0.0, ctrl.buttonFlash - 0.08)
                needsRedraw = true
            }

            // Smooth button activation glow transition
            let targetActivation: CGFloat = (ctrl.isPressed || ctrl.value > 0) ? 1.0 : 0.0
            if abs(ctrl.buttonActivation - targetActivation) > 0.02 {
                ctrl.buttonActivation += (targetActivation - ctrl.buttonActivation) * 0.35
                needsRedraw = true
            }
        }

        if needsRedraw {
            setNeedsDisplay()
        }
    }

    // -------------------------------------------------------------
    // Canvas Geometry & Scaling
    // -------------------------------------------------------------

    private var canvasTransform: (scale: CGFloat, offsetX: CGFloat, offsetY: CGFloat) {
        let devW = bounds.width
        let devH = bounds.height
        guard devW > 0 && devH > 0 else { return (1.0, 0, 0) }

        let targetW = layout.canvasWidth > 0 ? layout.canvasWidth : 920.0
        let targetH = layout.canvasHeight > 0 ? layout.canvasHeight : 460.0

        let scaleX = devW / targetW
        let scaleY = devH / targetH
        let scale = min(scaleX, scaleY)

        let offsetX = (devW - (targetW * scale)) / 2.0
        let offsetY = (devH - (targetH * scale)) / 2.0
        return (scale, offsetX, offsetY)
    }

    private func toCanvasPoint(_ screenPoint: CGPoint) -> CGPoint {
        let geom = canvasTransform
        return CGPoint(
            x: (screenPoint.x - geom.offsetX) / geom.scale,
            y: (screenPoint.y - geom.offsetY) / geom.scale
        )
    }

    // -------------------------------------------------------------
    // Multi-Touch Event Handling
    // -------------------------------------------------------------

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let page = layout.currentPage else { return }

        for touch in touches {
            let canvasPt = toCanvasPoint(touch.location(in: self))

            // Hit test backwards (topmost control first)
            for ctrl in page.controls.reversed() {
                if ctrl.frame.contains(canvasPt) {
                    let isBottomBtn = ctrl.type == "fader" && ctrl.hasBottomButton && canvasPt.y >= (ctrl.frame.maxY - 56.0)
                    
                    let at = ActiveTouch(
                        control: ctrl,
                        initialPoint: canvasPt,
                        initialValue: ctrl.value,
                        isBottomButton: isBottomBtn
                    )
                    activeTouches[touch] = at
                    ctrl.isPressed = true

                    handleTouchDown(at: at, canvasPoint: canvasPt)
                    break
                }
            }
        }
        setNeedsDisplay()
    }

    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard let at = activeTouches[touch] else { continue }
            let canvasPt = toCanvasPoint(touch.location(in: self))
            handleTouchDrag(at: at, canvasPoint: canvasPt)
        }
        setNeedsDisplay()
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let at = activeTouches[touch] {
                handleTouchUp(at: at)
                at.control.isPressed = false
                activeTouches.removeValue(forKey: touch)
            }
        }
        setNeedsDisplay()
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // -------------------------------------------------------------
    // Control Interaction Logic
    // -------------------------------------------------------------

    private func handleTouchDown(at: ActiveTouch, canvasPoint: CGPoint) {
        let ctrl = at.control

        if hapticsEnabled {
            hapticFeedback.impactOccurred()
        }

        if at.isBottomButton {
            ctrl.buttonValue = !ctrl.buttonValue
            ctrl.buttonFlash = 1.0
            let val = ctrl.buttonValue ? 127 : 0
            NetworkManager.shared.sendCC(channel: ctrl.midiChannel, cc: ctrl.buttonMidiNumber, value: val)
            return
        }

        switch ctrl.type {
        case "fader":
            updateFaderValue(ctrl: ctrl, canvasPoint: canvasPoint)
        case "knob":
            // Touch down records initial anchor for vertical drag or rotary gesture
            break
        case "button":
            ctrl.buttonFlash = 1.0
            if ctrl.mode == "toggle" {
                ctrl.value = (ctrl.value > 0) ? 0.0 : 127.0
            } else {
                ctrl.value = 127.0
            }
            sendButtonMidi(ctrl: ctrl, isDown: true)
        case "xypad":
            updateXYPadValue(ctrl: ctrl, canvasPoint: canvasPoint)
        default:
            break
        }
    }

    private func handleTouchDrag(at: ActiveTouch, canvasPoint: CGPoint) {
        let ctrl = at.control
        guard !at.isBottomButton else { return }

        switch ctrl.type {
        case "fader":
            updateFaderValue(ctrl: ctrl, canvasPoint: canvasPoint)
        case "knob":
            updateKnobValue(ctrl: ctrl, at: at, canvasPoint: canvasPoint)
        case "xypad":
            updateXYPadValue(ctrl: ctrl, canvasPoint: canvasPoint)
        default:
            break
        }
    }

    private func handleTouchUp(at: ActiveTouch) {
        let ctrl = at.control
        if at.isBottomButton { return }

        if ctrl.type == "button" && ctrl.mode == "momentary" {
            ctrl.value = 0.0
            sendButtonMidi(ctrl: ctrl, isDown: false)
        }
    }

    // -------------------------------------------------------------
    // Value Updates & MIDI Dispatch
    // -------------------------------------------------------------

    private func updateFaderValue(ctrl: MidiControlModel, canvasPoint: CGPoint) {
        let isHoriz = (ctrl.orientation == "horizontal")
        let r = ctrl.frame
        let margin: CGFloat = 20.0

        var pct: CGFloat = 0.0
        if isHoriz {
            pct = (canvasPoint.x - (r.origin.x + margin)) / (r.width - (margin * 2))
        } else {
            // Vertical fader: bottom is 0.0, top is 1.0
            pct = ((r.origin.y + r.height - margin) - canvasPoint.y) / (r.height - (margin * 2))
        }
        pct = max(0.0, min(1.0, pct))

        let range = Double(ctrl.maxValue - ctrl.minValue)
        let actualVal = Double(ctrl.minValue) + (Double(pct) * range)
        ctrl.value = actualVal

        sendControlMidi(ctrl: ctrl, val: Int(round(actualVal)))
    }

    private func updateKnobValue(ctrl: MidiControlModel, at: ActiveTouch, canvasPoint: CGPoint) {
        // High-precision vertical drag tracking
        let dy = at.initialPoint.y - canvasPoint.y
        let sensitivity = 0.005
        let range = Double(ctrl.maxValue - ctrl.minValue)
        var newVal = at.initialValue + (Double(dy) * sensitivity * range)
        newVal = max(Double(ctrl.minValue), min(Double(ctrl.maxValue), newVal))
        ctrl.value = newVal

        sendControlMidi(ctrl: ctrl, val: Int(round(newVal)))
    }

    private func updateXYPadValue(ctrl: MidiControlModel, canvasPoint: CGPoint) {
        let r = ctrl.frame
        let normX = max(0.0, min(1.0, (canvasPoint.x - r.origin.x) / r.width))
        let normY = max(0.0, min(1.0, 1.0 - ((canvasPoint.y - r.origin.y) / r.height)))

        ctrl.valueX = normX * 127.0
        ctrl.valueY = normY * 127.0

        NetworkManager.shared.sendCC(channel: ctrl.midiChannel, cc: ctrl.midiNumber, value: Int(round(ctrl.valueX)))
        NetworkManager.shared.sendCC(channel: ctrl.midiChannel, cc: ctrl.midiNumber + 1, value: Int(round(ctrl.valueY)))
    }

    private func sendControlMidi(ctrl: MidiControlModel, val: Int) {
        let clamped = max(0, min(127, val))
        if ctrl.midiType == "note" {
            NetworkManager.shared.sendNoteOn(channel: ctrl.midiChannel, note: ctrl.midiNumber, velocity: clamped)
        } else if ctrl.midiType == "pitchbend" {
            NetworkManager.shared.sendPitchBend(channel: ctrl.midiChannel, value: clamped * 128)
        } else {
            NetworkManager.shared.sendCC(channel: ctrl.midiChannel, cc: ctrl.midiNumber, value: clamped)
        }
    }

    private func sendButtonMidi(ctrl: MidiControlModel, isDown: Bool) {
        let val = isDown ? 127 : 0
        if ctrl.midiType == "note" {
            if isDown {
                NetworkManager.shared.sendNoteOn(channel: ctrl.midiChannel, note: ctrl.midiNumber, velocity: 127)
            } else {
                NetworkManager.shared.sendNoteOff(channel: ctrl.midiChannel, note: ctrl.midiNumber)
            }
        } else {
            NetworkManager.shared.sendCC(channel: ctrl.midiChannel, cc: ctrl.midiNumber, value: val)
        }
    }

    // -------------------------------------------------------------
    // CoreGraphics Rendering (120 FPS ProMotion Pipeline)
    // -------------------------------------------------------------

    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let page = layout.currentPage else { return }

        let geom = canvasTransform
        ctx.saveGState()
        ctx.translateBy(x: geom.offsetX, y: geom.offsetY)
        ctx.scaleBy(x: geom.scale, y: geom.scale)

        for ctrl in page.controls {
            switch ctrl.type {
            case "fader":
                drawFader(ctx: ctx, ctrl: ctrl)
            case "knob":
                drawKnob(ctx: ctx, ctrl: ctrl)
            case "button":
                drawButton(ctx: ctx, ctrl: ctrl)
            case "xypad":
                drawXYPad(ctx: ctx, ctrl: ctrl)
            case "label":
                drawLabel(ctx: ctx, ctrl: ctrl)
            default:
                break
            }
        }

        ctx.restoreGState()
    }

    // -------------------------------------------------------------
    // Fader Drawing
    // -------------------------------------------------------------

    private func drawFader(ctx: CGContext, ctrl: MidiControlModel) {
        let frame = ctrl.frame
        let isHoriz = (ctrl.orientation == "horizontal")
        let pillHeight: CGFloat = 26.0
        let hasLabel = ctrl.hasLabel
        let isBottom = (ctrl.labelPosition == "bottom")

        var trackRect = frame
        var pillRect = CGRect.zero

        if isHoriz {
            if hasLabel {
                if isBottom {
                    pillRect = CGRect(x: frame.origin.x, y: frame.maxY - pillHeight, width: frame.width, height: pillHeight)
                    trackRect = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height - pillHeight - 4.0)
                } else {
                    pillRect = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: pillHeight)
                    trackRect = CGRect(x: frame.origin.x, y: frame.origin.y + pillHeight + 4.0, width: frame.width, height: frame.height - pillHeight - 4.0)
                }
            }
        } else {
            if hasLabel {
                if isBottom {
                    pillRect = CGRect(x: frame.origin.x, y: frame.maxY - pillHeight, width: frame.width, height: pillHeight)
                    trackRect = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height - pillHeight - 6.0)
                } else {
                    pillRect = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: pillHeight)
                    trackRect = CGRect(x: frame.origin.x, y: frame.origin.y + pillHeight + 6.0, width: frame.width, height: frame.height - pillHeight - 6.0)
                }
            }
        }

        // 1. Draw Label Pill
        if hasLabel {
            if ctrl.hasBackground {
                let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: 8.0)
                UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1.0).setFill()
                pillPath.fill()
                UIColor(white: 0.18, alpha: 1.0).setStroke()
                pillPath.lineWidth = 1.0
                pillPath.stroke()
            }

            let fSize: CGFloat = (ctrl.fontSize > 0) ? ctrl.fontSize : 11.5
            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: fSize, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: pStyle,
                .kern: 1.2
            ]
            let textRect = CGRect(x: pillRect.origin.x, y: pillRect.midY - (fSize / 2.0) - 1.0, width: pillRect.width, height: fSize + 4.0)
            (ctrl.label as NSString).draw(in: textRect, withAttributes: attrs)
        }

        // 2. Track & Slot
        let range = (ctrl.maxValue > ctrl.minValue) ? CGFloat(ctrl.maxValue - ctrl.minValue) : 127.0
        var pct = CGFloat(ctrl.value - Double(ctrl.minValue)) / range
        pct = max(0.0, min(1.0, pct))

        if isHoriz {
            // Horizontal Track
            let slotH: CGFloat = 14.0
            let slotY = trackRect.midY - (slotH / 2.0)
            let slotRect = CGRect(x: trackRect.origin.x + 4.0, y: slotY, width: trackRect.width - 8.0, height: slotH)

            let slotPath = UIBezierPath(roundedRect: slotRect, cornerRadius: 6.0)
            UIColor(red: 0.04, green: 0.045, blue: 0.06, alpha: 1.0).setFill()
            slotPath.fill()
            UIColor(white: 0.14, alpha: 1.0).setStroke()
            slotPath.lineWidth = 1.0
            slotPath.stroke()

            let travelW = slotRect.width - 12.0
            let thumbW: CGFloat = 28.0
            let thumbH = min(frame.height + 4.0, 56.0)
            let thumbX = (slotRect.origin.x + 6.0) + pct * travelW - (thumbW / 2.0)
            let thumbRect = CGRect(x: max(slotRect.origin.x - 2.0, min(slotRect.maxX - thumbW + 2.0, thumbX)),
                                   y: trackRect.midY - (thumbH / 2.0),
                                   width: thumbW, height: thumbH)

            // Draw glowing neon beam
            let beamY = slotRect.midY
            let beamLeft = slotRect.origin.x + 6.0
            let beamRight = beamLeft + (pct * travelW)
            if abs(beamRight - beamLeft) > 2.0 {
                let beam = UIBezierPath()
                beam.move(to: CGPoint(x: beamLeft, y: beamY))
                beam.addLine(to: CGPoint(x: beamRight, y: beamY))
                beam.lineCapStyle = .round

                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 10.0, color: ctrl.accentColor.cgColor)
                ctrl.accentColor.setStroke()
                beam.lineWidth = 3.5
                beam.stroke()
                ctx.restoreGState()

                UIColor.white.setStroke()
                beam.lineWidth = 1.2
                beam.stroke()
            }

            drawThumb(ctx: ctx, rect: thumbRect, accentColor: ctrl.accentColor, isHoriz: true)
        } else {
            // Vertical Track
            let slotW: CGFloat = 14.0
            let slotX = trackRect.midX - (slotW / 2.0)
            let slotRect = CGRect(x: slotX, y: trackRect.origin.y + 4.0, width: slotW, height: trackRect.height - 8.0)

            // Subtle graduation tick marks
            let numTicks = 9
            let tickStep = slotRect.height / CGFloat(numTicks - 1)
            UIColor(white: 0.25, alpha: 0.7).setStroke()
            for i in 0..<numTicks {
                let ty = slotRect.origin.y + CGFloat(i) * tickStep
                let tickL = UIBezierPath()
                tickL.move(to: CGPoint(x: slotX - 8.0, y: ty))
                tickL.addLine(to: CGPoint(x: slotX - 2.0, y: ty))
                tickL.lineWidth = 1.0
                tickL.stroke()

                let tickR = UIBezierPath()
                tickR.move(to: CGPoint(x: slotRect.maxX + 2.0, y: ty))
                tickR.addLine(to: CGPoint(x: slotRect.maxX + 8.0, y: ty))
                tickR.lineWidth = 1.0
                tickR.stroke()
            }

            let slotPath = UIBezierPath(roundedRect: slotRect, cornerRadius: 6.0)
            UIColor(red: 0.04, green: 0.045, blue: 0.06, alpha: 1.0).setFill()
            slotPath.fill()
            UIColor(white: 0.14, alpha: 1.0).setStroke()
            slotPath.lineWidth = 1.0
            slotPath.stroke()

            let travelH = slotRect.height - 12.0
            let thumbW = min(frame.width + 4.0, 56.0)
            let thumbH: CGFloat = 28.0
            let thumbX = trackRect.midX - (thumbW / 2.0)
            let thumbY = (slotRect.maxY - 6.0) - (pct * travelH) - (thumbH / 2.0)
            let thumbRect = CGRect(x: thumbX,
                                   y: max(slotRect.origin.y - 2.0, min(slotRect.maxY - thumbH + 2.0, thumbY)),
                                   width: thumbW, height: thumbH)

            // Neon glowing fill beam
            let beamX = slotRect.midX
            let beamBottom = slotRect.maxY - 6.0
            let beamTop = beamBottom - (pct * travelH)
            if abs(beamBottom - beamTop) > 2.0 {
                let beam = UIBezierPath()
                beam.move(to: CGPoint(x: beamX, y: beamBottom))
                beam.addLine(to: CGPoint(x: beamX, y: beamTop))
                beam.lineCapStyle = .round

                ctx.saveGState()
                ctx.setShadow(offset: .zero, blur: 10.0, color: ctrl.accentColor.cgColor)
                ctrl.accentColor.setStroke()
                beam.lineWidth = 3.5
                beam.stroke()
                ctx.restoreGState()

                UIColor.white.setStroke()
                beam.lineWidth = 1.2
                beam.stroke()
            }

            drawThumb(ctx: ctx, rect: thumbRect, accentColor: ctrl.accentColor, isHoriz: false)
        }
    }

    private func drawThumb(ctx: CGContext, rect: CGRect, accentColor: UIColor, isHoriz: Bool) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3.0), blur: 8.0, color: UIColor(white: 0.0, alpha: 0.75).cgColor)
        let thumbPath = UIBezierPath(roundedRect: rect, cornerRadius: 4.5)

        // Brushed metallic gradient
        let colors = [
            UIColor(red: 0.28, green: 0.30, blue: 0.36, alpha: 1.0).cgColor,
            UIColor(red: 0.18, green: 0.19, blue: 0.23, alpha: 1.0).cgColor,
            UIColor(red: 0.13, green: 0.14, blue: 0.17, alpha: 1.0).cgColor,
            UIColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1.0).cgColor
        ]
        let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0.0, 0.2, 0.5, 1.0])!
        ctx.addPath(thumbPath.cgPath)
        ctx.clip()
        ctx.drawLinearGradient(grad, start: CGPoint(x: rect.minX, y: rect.minY), end: CGPoint(x: rect.minX, y: rect.maxY), options: [])
        ctx.restoreGState()

        UIColor(white: 0.35, alpha: 0.7).setStroke()
        thumbPath.lineWidth = 1.0
        thumbPath.stroke()

        // Core neon indicator slit
        let slitW: CGFloat = isHoriz ? 3.0 : 16.0
        let slitH: CGFloat = isHoriz ? 16.0 : 3.0
        let slitRect = CGRect(x: rect.midX - (slitW / 2.0), y: rect.midY - (slitH / 2.0), width: slitW, height: slitH)
        let slitPath = UIBezierPath(roundedRect: slitRect, cornerRadius: 1.5)

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 8.0, color: accentColor.cgColor)
        accentColor.setFill()
        slitPath.fill()
        ctx.restoreGState()

        let slitCore = slitRect.insetBy(dx: 0.5, dy: 0.5)
        UIColor.white.setFill()
        UIBezierPath(roundedRect: slitCore, cornerRadius: 1.0).fill()
    }

    // -------------------------------------------------------------
    // Rotary Knob Drawing
    // -------------------------------------------------------------

    private func drawKnob(ctx: CGContext, ctrl: MidiControlModel) {
        let frame = ctrl.frame
        let pillHeight: CGFloat = 26.0
        let hasLabel = ctrl.hasLabel
        let isTop = (ctrl.labelPosition == "top")

        var dialArea = frame
        var pillRect = CGRect.zero

        if hasLabel {
            if isTop {
                pillRect = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: pillHeight)
                dialArea = CGRect(x: frame.origin.x, y: frame.origin.y + pillHeight + 6.0, width: frame.width, height: frame.height - pillHeight - 6.0)
            } else {
                pillRect = CGRect(x: frame.origin.x, y: frame.maxY - pillHeight, width: frame.width, height: pillHeight)
                dialArea = CGRect(x: frame.origin.x, y: frame.origin.y, width: frame.width, height: frame.height - pillHeight - 6.0)
            }
        }

        let dialSize = min(dialArea.width, dialArea.height)
        let cx = dialArea.midX
        let cy = dialArea.midY
        let radius = dialSize * 0.44

        // 1. Recessed Well
        let well = UIBezierPath(ovalIn: CGRect(x: cx - radius, y: cy - radius, width: radius * 2.0, height: radius * 2.0))
        UIColor(red: 0.05, green: 0.06, blue: 0.08, alpha: 1.0).setFill()
        well.fill()
        UIColor(white: 0.15, alpha: 1.0).setStroke()
        well.lineWidth = 1.0
        well.stroke()

        // 2. Halo Arc Ring
        let haloRadius = radius * 0.90
        let range = (ctrl.maxValue > ctrl.minValue) ? CGFloat(ctrl.maxValue - ctrl.minValue) : 127.0
        var pct = CGFloat(ctrl.value - Double(ctrl.minValue)) / range
        pct = max(0.0, min(1.0, pct))

        let startAngle: CGFloat = 135.0 * .pi / 180.0
        let totalSweep: CGFloat = 270.0 * .pi / 180.0
        let trackEndAngle: CGFloat = startAngle + totalSweep

        // Unlit track
        let trackArc = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: haloRadius, startAngle: startAngle, endAngle: trackEndAngle, clockwise: true)
        UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0).setStroke()
        trackArc.lineWidth = 4.0
        trackArc.lineCapStyle = .round
        trackArc.stroke()

        // Active glowing neon arc
        let activeEndAngle = startAngle + (pct * totalSweep)
        if pct > 0.01 {
            let activeArc = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: haloRadius, startAngle: startAngle, endAngle: activeEndAngle, clockwise: true)
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 8.0, color: ctrl.accentColor.cgColor)
            ctrl.accentColor.setStroke()
            activeArc.lineWidth = 4.0
            activeArc.lineCapStyle = .round
            activeArc.stroke()
            ctx.restoreGState()
        }

        // 3. Dial Face
        let faceRadius = radius * 0.74
        let faceRect = CGRect(x: cx - faceRadius, y: cy - faceRadius, width: faceRadius * 2.0, height: faceRadius * 2.0)
        let face = UIBezierPath(ovalIn: faceRect)
        UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1.0).setFill()
        face.fill()
        UIColor(white: 0.22, alpha: 0.9).setStroke()
        face.lineWidth = 1.0
        face.stroke()

        // 4. Value Display (Center Cap vs Bottom Badge)
        let isCenterVal = (ctrl.valuePosition == "center" && ctrl.valueDisplay != "none")
        let needleAngle = activeEndAngle
        let needleStartR = isCenterVal ? (faceRadius * 0.55) : (faceRadius * 0.20)
        let needleEndR = faceRadius * 0.88

        let pStartX = cx + cos(needleAngle) * needleStartR
        let pStartY = cy + sin(needleAngle) * needleStartR
        let pEndX = cx + cos(needleAngle) * needleEndR
        let pEndY = cy + sin(needleAngle) * needleEndR

        let needle = UIBezierPath()
        needle.move(to: CGPoint(x: pStartX, y: pStartY))
        needle.addLine(to: CGPoint(x: pEndX, y: pEndY))
        needle.lineCapStyle = .round

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 8.0, color: ctrl.accentColor.cgColor)
        ctrl.accentColor.setStroke()
        needle.lineWidth = 3.5
        needle.stroke()
        ctx.restoreGState()

        UIColor.white.setStroke()
        needle.lineWidth = 1.2
        needle.stroke()

        // Numeric Readout formatting
        if ctrl.valueDisplay != "none" {
            let valString: String
            if ctrl.valueDisplay == "percent" {
                valString = "\(Int(round(pct * 100.0)))%"
            } else {
                let actualVal = Int(round(Double(ctrl.minValue) + (Double(pct) * range)))
                valString = "\(actualVal)"
            }

            let pStyle = NSMutableParagraphStyle()
            pStyle.alignment = .center

            if isCenterVal {
                // Center circular cap
                let centerR = faceRadius * 0.50
                let centerCap = UIBezierPath(ovalIn: CGRect(x: cx - centerR, y: cy - centerR, width: centerR * 2.0, height: centerR * 2.0))
                UIColor(red: 0.12, green: 0.14, blue: 0.18, alpha: 1.0).setFill()
                centerCap.fill()
                UIColor(white: 0.28, alpha: 0.9).setStroke()
                centerCap.lineWidth = 1.0
                centerCap.stroke()

                let autoFontSize = max(9.0, min(14.0, centerR * 0.74))
                let rawFontSize = (ctrl.valueFontSize > 0) ? ctrl.valueFontSize : autoFontSize
                let fontSize = min(20.0, rawFontSize) // Capped at 20pt strictly

                let valAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: pStyle
                ]
                let textSize = (valString as NSString).size(withAttributes: valAttrs)
                let textRect = CGRect(x: cx - centerR, y: cy - (textSize.height / 2.0), width: centerR * 2.0, height: textSize.height)
                (valString as NSString).draw(in: textRect, withAttributes: valAttrs)
            } else {
                // Bottom badge pill
                let autoFontSize: CGFloat = 10.0
                let fontSize = (ctrl.valueFontSize > 0) ? ctrl.valueFontSize : autoFontSize
                let badgeW: CGFloat = max(42.0, CGFloat(valString.count) * (fontSize * 0.85) + 14.0)
                let badgeH: CGFloat = max(16.0, fontSize + 6.0)
                let badgeY = (hasLabel && !isTop) ? (pillRect.origin.y - badgeH - 3.0) : (cy + radius + 3.0)
                let badgeRect = CGRect(x: cx - (badgeW / 2.0), y: badgeY, width: badgeW, height: badgeH)

                let badgePath = UIBezierPath(roundedRect: badgeRect, cornerRadius: 4.0)
                UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.95).setFill()
                badgePath.fill()
                UIColor(white: 0.22, alpha: 0.8).setStroke()
                badgePath.lineWidth = 1.0
                badgePath.stroke()

                let valAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold),
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: pStyle
                ]
                let textRect = CGRect(x: badgeRect.origin.x, y: badgeRect.midY - (fontSize / 2.0) - 1.0, width: badgeRect.width, height: fontSize + 2.0)
                (valString as NSString).draw(in: textRect, withAttributes: valAttrs)
            }
        }
    }

    // -------------------------------------------------------------
    // Illuminated Pad & Button Drawing
    // -------------------------------------------------------------

    private func drawButton(ctx: CGContext, ctrl: MidiControlModel) {
        let r = ctrl.frame
        let isCircle = (ctrl.shape == "circle")
        let isLit = (ctrl.value > 0 || ctrl.isPressed)

        let baseColor = (HexFromColor(ctrl.color) == HexFromColor(ctrl.accentColor)) ? DeriveDarkBaseColor(from: ctrl.accentColor) : ctrl.color

        if isCircle {
            let size = min(r.width, r.height)
            let circleRect = CGRect(x: r.midX - size / 2.0, y: r.midY - size / 2.0, width: size, height: size)

            ctx.saveGState()
            let glowRadius: CGFloat = isLit ? 14.0 : 6.0
            ctx.setShadow(offset: .zero, blur: glowRadius, color: ctrl.accentColor.withAlphaComponent(isLit ? 0.95 : 0.45).cgColor)
            ctrl.accentColor.setStroke()
            let ring = UIBezierPath(ovalIn: circleRect.insetBy(dx: 4.0, dy: 4.0))
            ring.lineWidth = 3.0
            ring.stroke()
            ctx.restoreGState()

            let faceRect = circleRect.insetBy(dx: 8.0, dy: 8.0)
            let face = UIBezierPath(ovalIn: faceRect)
            if isLit {
                baseColor.setFill()
                face.fill()
            } else {
                UIColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1.0).setFill()
                face.fill()
            }
            UIColor(white: 0.28, alpha: 0.8).setStroke()
            face.lineWidth = 1.0
            face.stroke()
        } else {
            let cornerR: CGFloat = 12.0
            let padRect = r

            ctx.saveGState()
            let glowRadius: CGFloat = isLit ? 16.0 : 8.0
            let glowAlpha: CGFloat = isLit ? 0.85 : 0.35
            ctx.setShadow(offset: .zero, blur: glowRadius, color: ctrl.accentColor.withAlphaComponent(glowAlpha).cgColor)

            let padPath = UIBezierPath(roundedRect: padRect, cornerRadius: cornerR)
            if isLit {
                baseColor.setFill()
                padPath.fill()
            } else {
                UIColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1.0).setFill()
                padPath.fill()
            }

            ctrl.accentColor.setStroke()
            padPath.lineWidth = 2.5
            padPath.stroke()
            ctx.restoreGState()

            let innerHighlight = UIBezierPath(roundedRect: padRect.insetBy(dx: 2.0, dy: 2.0), cornerRadius: cornerR - 2.0)
            UIColor(white: 1.0, alpha: isLit ? 0.35 : 0.08).setStroke()
            innerHighlight.lineWidth = 1.0
            innerHighlight.stroke()

            // Specular Flash Burst animation
            if ctrl.buttonFlash > 0.01 {
                let flashPath = UIBezierPath(roundedRect: padRect, cornerRadius: cornerR)
                UIColor(white: 1.0, alpha: ctrl.buttonFlash * 0.45).setFill()
                flashPath.fill()
            }

            if !ctrl.label.isEmpty {
                let fSize: CGFloat = (ctrl.fontSize > 0) ? ctrl.fontSize : 13.0
                let pStyle = NSMutableParagraphStyle()
                pStyle.alignment = .center
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: fSize, weight: .bold),
                    .foregroundColor: isLit ? UIColor.white : ctrl.accentColor.withAlphaComponent(0.9),
                    .paragraphStyle: pStyle,
                    .kern: 1.0
                ]
                let textRect = CGRect(x: padRect.origin.x + 4.0, y: padRect.midY - (fSize / 2.0) - 1.0, width: padRect.width - 8.0, height: fSize + 4.0)
                (ctrl.label as NSString).draw(in: textRect, withAttributes: attrs)
            }
        }
    }

    // -------------------------------------------------------------
    // XY Pad & Text Label Drawing
    // -------------------------------------------------------------

    private func drawXYPad(ctx: CGContext, ctrl: MidiControlModel) {
        let r = ctrl.frame
        let cornerR: CGFloat = 10.0
        let bgPath = UIBezierPath(roundedRect: r, cornerRadius: cornerR)
        UIColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1.0).setFill()
        bgPath.fill()
        UIColor(white: 0.20, alpha: 1.0).setStroke()
        bgPath.lineWidth = 1.0
        bgPath.stroke()

        // Crosshairs
        UIColor(white: 0.18, alpha: 0.6).setStroke()
        let chH = UIBezierPath()
        chH.move(to: CGPoint(x: r.minX + 8.0, y: r.midY))
        chH.addLine(to: CGPoint(x: r.maxX - 8.0, y: r.midY))
        chH.stroke()

        let chV = UIBezierPath()
        chV.move(to: CGPoint(x: r.midX, y: r.minY + 8.0))
        chV.addLine(to: CGPoint(x: r.midX, y: r.maxY - 8.0))
        chV.stroke()

        // Puck position
        let normX = CGFloat(ctrl.valueX / 127.0)
        let normY = CGFloat(1.0 - (ctrl.valueY / 127.0))
        let puckX = r.origin.x + (normX * r.width)
        let puckY = r.origin.y + (normY * r.height)
        let puckRadius: CGFloat = 12.0

        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 12.0, color: ctrl.accentColor.cgColor)
        ctrl.accentColor.setFill()
        UIBezierPath(ovalIn: CGRect(x: puckX - puckRadius, y: puckY - puckRadius, width: puckRadius * 2.0, height: puckRadius * 2.0)).fill()
        ctx.restoreGState()

        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: puckX - 4.0, y: puckY - 4.0, width: 8.0, height: 8.0)).fill()
    }

    private func drawLabel(ctx: CGContext, ctrl: MidiControlModel) {
        let r = ctrl.frame
        if ctrl.hasBackground {
            let bg = UIBezierPath(roundedRect: r, cornerRadius: 6.0)
            UIColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 0.9).setFill()
            bg.fill()
            UIColor(white: 0.20, alpha: 0.8).setStroke()
            bg.lineWidth = 1.0
            bg.stroke()
        }

        let fSize: CGFloat = (ctrl.fontSize > 0) ? ctrl.fontSize : 12.0
        let pStyle = NSMutableParagraphStyle()
        pStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fSize, weight: .bold),
            .foregroundColor: ctrl.accentColor,
            .paragraphStyle: pStyle,
            .kern: 1.0
        ]
        let textRect = CGRect(x: r.origin.x, y: r.midY - (fSize / 2.0) - 1.0, width: r.width, height: fSize + 4.0)
        (ctrl.label as NSString).draw(in: textRect, withAttributes: attrs)
    }
}
