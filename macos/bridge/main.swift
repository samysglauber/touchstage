import Cocoa
import SwiftUI

class BridgeAppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var bridgeState: BridgeState!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. Initialize State and CoreMIDI / Wi-Fi Server
        bridgeState = BridgeState(port: 9000)
        
        // 2. Setup Popover with SwiftUI
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        
        let bridgeView = BridgeView(state: bridgeState, closePopover: { [weak self] in
            self?.popover.performClose(nil)
        })
        let hostingController = NSHostingController(rootView: bridgeView)
        popover.contentViewController = hostingController
        
        // 3. Status Bar Item (Minimalist Slider Icon)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14.5, weight: .medium)
            if let icon = NSImage(systemSymbolName: "slider.vertical.3", accessibilityDescription: "TouchStage Bridge")?.withSymbolConfiguration(config) {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = createFallbackIcon()
            }
            button.toolTip = "TouchStage Bridge"
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
    }
    
    private func createFallbackIcon() -> NSImage {
        let size = NSMakeSize(18, 18)
        let img = NSImage(size: size, flipped: false) { dstRect in
            NSColor.black.setStroke()
            for i in 0..<3 {
                let x = 4.0 + (Double(i) * 5.0)
                let track = NSBezierPath()
                track.move(to: NSPoint(x: x, y: 2))
                track.line(to: NSPoint(x: x, y: 16))
                track.lineWidth = 1.5
                track.stroke()
                
                let thumbY = (i == 0 ? 8.0 : (i == 1 ? 4.0 : 11.0))
                let thumb = NSRect(x: x - 2, y: thumbY, width: 4, height: 3)
                NSColor.black.setFill()
                thumb.fill()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
    
    @objc func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            bridgeState.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = BridgeAppDelegate()
app.delegate = delegate
app.run()
