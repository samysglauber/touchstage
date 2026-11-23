import Cocoa
import Foundation

public class EditorSyncServer: NSObject {
    public static let shared = EditorSyncServer()

    private var latestLayoutJson: String?

    public override init() {
        super.init()
    }

    public func startIfNeeded(with layout: LayoutModel? = nil) {
        if let l = layout {
            updateLayoutCache(l)
        }
    }

    public func updateLayoutCache(_ layout: LayoutModel) {
        var json = layout.toJSONString()
        json = json.replacingOccurrences(of: "\r", with: "")
        json = json.replacingOccurrences(of: "\n", with: " ")
        self.latestLayoutJson = json
    }

    public func isBridgeActive() -> Bool {
        let testSock = socket(AF_INET, SOCK_STREAM, 0)
        guard testSock >= 0 else { return false }
        defer { Darwin.close(testSock) }

        var tv = timeval(tv_sec: 0, tv_usec: 200000) // 200ms
        setsockopt(testSock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(testSock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(9000).bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)

        let res = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(testSock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return (res == 0)
    }

    public func ensureBridgeIsRunning() -> Bool {
        if isBridgeActive() { return true }

        let possibleUrls = [
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("TouchStage Bridge.app"),
            URL(fileURLWithPath: "/Users/samysglauber/Documents/MIDI Controller/TouchStage Bridge.app"),
            URL(fileURLWithPath: "/Applications/TouchStage Bridge.app")
        ]

        for appUrl in possibleUrls {
            if FileManager.default.fileExists(atPath: appUrl.path) {
                NSLog("[TouchStage Editor] Launching TouchStage Bridge automatically from %@", appUrl.path)
                let conf = NSWorkspace.OpenConfiguration()
                conf.activates = false // Keep in background
                let sema = DispatchSemaphore(value: 0)
                NSWorkspace.shared.openApplication(at: appUrl, configuration: conf) { _, _ in
                    sema.signal()
                }
                _ = sema.wait(timeout: .now() + 1.5)

                for _ in 0..<25 {
                    usleep(100_000) // 100ms
                    if isBridgeActive() {
                        NSLog("[TouchStage Editor] TouchStage Bridge is ready on port 9000.")
                        return true
                    }
                }
                break
            }
        }
        return isBridgeActive()
    }

    public func pushLayout(_ layout: LayoutModel) -> Int {
        updateLayoutCache(layout)

        // Automatically launch Bridge in background if closed!
        if !isBridgeActive() {
            _ = ensureBridgeIsRunning()
        }

        return pushToBridge(layout)
    }

    private func pushToBridge(_ layout: LayoutModel) -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return -1 }
        defer { Darwin.close(sock) }

        var tv = timeval(tv_sec: 2, tv_usec: 0)
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

        guard connectRes == 0 else { return -1 }

        guard let json = latestLayoutJson, let data = "SYNC_LAYOUT:\(json)\n".data(using: .utf8) else {
            return 0
        }

        data.withUnsafeBytes { raw in
            guard let ptr = raw.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = Darwin.send(sock, ptr.advanced(by: sent), data.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }

        var ackBuf = [CChar](repeating: 0, count: 64)
        let ackLen = recv(sock, &ackBuf, ackBuf.count - 1, 0)
        if ackLen > 0 {
            let ackStr = String(cString: ackBuf)
            if ackStr.hasPrefix("OK:SYNC:") {
                let countStr = String(ackStr.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
                return Int(countStr) ?? 1
            }
            if ackStr.hasPrefix("OK:SYNC") { return 1 }
        }
        return 0
    }

    public func stop() {
        // No server ports or timers to stop
    }
}
