import Foundation
import Combine
import AppKit

class BridgeState: ObservableObject {
    @Published var localIP: String = "127.0.0.1"
    @Published var port: Int = 9000
    @Published var devices: [ConnectedDevice] = []
    @Published var isCopied: Bool = false

    var onStateChanged: (() -> Void)?

    let server: BridgeServer

    var expectedHeight: CGFloat {
        let devH: CGFloat
        if devices.isEmpty {
            devH = 54.0
        } else if devices.count == 1 {
            devH = 45.0
        } else {
            devH = 82.0
        }
        // 16 top + 70 serverCard + 12 gap + 14 header + 6 gap + devH + 12 gap + 1 sep + 10 gap + 26 footer + 14 bottom
        return 16 + 70 + 12 + 14 + 6 + devH + 12 + 1 + 10 + 26 + 14
    }

    init(port: Int = 9000) {
        self.server = BridgeServer(port: port)
        self.localIP = server.localIP
        self.port = server.port
        self.devices = server.connectedDevices

        server.deviceListChanged = { [weak self] in
            DispatchQueue.main.async {
                self?.refresh()
            }
        }
        _ = server.start()
    }

    func refresh() {
        self.localIP = server.localIP
        self.port = server.port
        self.devices = server.connectedDevices
        self.onStateChanged?()
    }

    func copyIP() {
        let ipString = "\(localIP):\(port)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ipString, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.isCopied = false
        }
    }

    func openEditor(closePopover: () -> Void) {
        closePopover()
        let bundleDir = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
        var editorPath = (bundleDir as NSString).appendingPathComponent("TouchStage Editor.app")
        if !FileManager.default.fileExists(atPath: editorPath) {
            editorPath = "/Applications/TouchStage Editor.app"
        }
        if FileManager.default.fileExists(atPath: editorPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: editorPath))
        } else if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.touchstage.editor") {
            NSWorkspace.shared.openApplication(at: appUrl, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    func quit() {
        server.stop()
        NSApp.terminate(nil)
    }
}
