import Foundation
import Network
import UIKit

public extension Notification.Name {
    static let touchStageConnectionChanged = Notification.Name("touchStageConnectionChanged")
    static let touchStageDidReceiveLayout = Notification.Name("touchStageDidReceiveLayout")
}

public class NetworkManager {
    public static let shared = NetworkManager()

    public private(set) var host: String = ""
    public private(set) var port: Int = 9000
    public private(set) var isConnected: Bool = false
    public private(set) var serverName: String = "Offline"
    public private(set) var latencyMs: Double = 0.0

    private var udpSocketFD: Int32 = -1
    private var targetAddr = sockaddr_in()
    private var tcpConnection: NWConnection?
    private var tcpBuffer = Data()
    private let netQueue = DispatchQueue(label: "com.touchstage.network", qos: .userInteractive)

    private var pingTimer: Timer?
    private var pingStartTime: Date?

    private init() {
        // Load last saved connection
        let savedIp = UserDefaults.standard.string(forKey: "TouchStage_BridgeIP") ?? ""
        let savedPort = UserDefaults.standard.integer(forKey: "TouchStage_BridgePort")
        if !savedIp.isEmpty {
            connect(to: savedIp, port: savedPort > 0 ? savedPort : 9000, name: "Saved Bridge")
        }
    }

    public func connect(to host: String, port: Int = 9000, name: String = "TouchStage Bridge") {
        guard !host.isEmpty else { return }
        self.host = host
        self.port = port
        self.serverName = name

        UserDefaults.standard.set(host, forKey: "TouchStage_BridgeIP")
        UserDefaults.standard.set(port, forKey: "TouchStage_BridgePort")

        setupUdpSocket()
        setupTcpSync()

        isConnected = true
        NotificationCenter.default.post(name: .touchStageConnectionChanged, object: nil)
    }

    public func disconnect() {
        isConnected = false
        serverName = "Offline"
        if udpSocketFD >= 0 {
            close(udpSocketFD)
            udpSocketFD = -1
        }
        tcpConnection?.cancel()
        tcpConnection = nil
        pingTimer?.invalidate()
        pingTimer = nil
        NotificationCenter.default.post(name: .touchStageConnectionChanged, object: nil)
    }

    // -------------------------------------------------------------
    // UDP MIDI Output (3-Byte Raw Binary Datagrams)
    // -------------------------------------------------------------

    private func setupUdpSocket() {
        if udpSocketFD >= 0 {
            close(udpSocketFD)
        }

        udpSocketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard udpSocketFD >= 0 else { return }

        var addr = sockaddr_in()
        addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        inet_pton(AF_INET, host, &addr.sin_addr)
        targetAddr = addr
    }

    public func sendMidi(status: UInt8, data1: UInt8, data2: UInt8) {
        guard isConnected && udpSocketFD >= 0 else { return }
        var bytes: [UInt8] = [status, data1, data2]
        withUnsafePointer(to: &targetAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                _ = sendto(udpSocketFD, &bytes, 3, 0, saPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    public func sendCC(channel: Int, cc: Int, value: Int) {
        let ch = UInt8(max(0, min(15, channel - 1)))
        let status = UInt8(0xB0 | ch)
        let c = UInt8(max(0, min(127, cc)))
        let v = UInt8(max(0, min(127, value)))
        sendMidi(status: status, data1: c, data2: v)
    }

    public func sendNoteOn(channel: Int, note: Int, velocity: Int = 127) {
        let ch = UInt8(max(0, min(15, channel - 1)))
        let status = UInt8(0x90 | ch)
        let n = UInt8(max(0, min(127, note)))
        let v = UInt8(max(0, min(127, velocity)))
        sendMidi(status: status, data1: n, data2: v)
    }

    public func sendNoteOff(channel: Int, note: Int) {
        let ch = UInt8(max(0, min(15, channel - 1)))
        let status = UInt8(0x80 | ch)
        let n = UInt8(max(0, min(127, note)))
        sendMidi(status: status, data1: n, data2: 0)
    }

    public func sendPitchBend(channel: Int, value: Int) {
        let ch = UInt8(max(0, min(15, channel - 1)))
        let status = UInt8(0xE0 | ch)
        let clamped = max(0, min(16383, value))
        let lsb = UInt8(clamped & 0x7F)
        let msb = UInt8((clamped >> 7) & 0x7F)
        sendMidi(status: status, data1: lsb, data2: msb)
    }

    // -------------------------------------------------------------
    // TCP Layout Sync & Control Link
    // -------------------------------------------------------------

    private func setupTcpSync() {
        tcpConnection?.cancel()
        tcpBuffer.removeAll()

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let conn = NWConnection(to: endpoint, using: .tcp)

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    NSLog("[TouchStage iOS] TCP Connected to %@:%d", self?.host ?? "", self?.port ?? 0)
                    self?.isConnected = true
                    NotificationCenter.default.post(name: .touchStageConnectionChanged, object: nil)
                    self?.sendHandshake()
                    self?.receiveNextPacket()
                case .failed(let error):
                    NSLog("[TouchStage iOS] TCP failed: %@", error.localizedDescription)
                    self?.isConnected = false
                    NotificationCenter.default.post(name: .touchStageConnectionChanged, object: nil)
                case .cancelled:
                    self?.isConnected = false
                    NotificationCenter.default.post(name: .touchStageConnectionChanged, object: nil)
                default:
                    break
                }
            }
        }

        conn.start(queue: netQueue)
        self.tcpConnection = conn
    }

    private func sendHandshake() {
        let devName = UIDevice.current.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let handshake = "DEVICE:\(devName)\nGET_LAYOUT\n"
        if let data = handshake.data(using: .utf8) {
            tcpConnection?.send(content: data, completion: .contentProcessed({ error in
                if let error = error {
                    NSLog("[TouchStage iOS] Handshake send error: %@", error.localizedDescription)
                } else {
                    NSLog("[TouchStage iOS] Sent DEVICE handshake: '%@'", devName)
                }
            }))
        }
    }

    private func receiveNextPacket() {
        tcpConnection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard error == nil, let data = content, !data.isEmpty else {
                if isComplete {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                        self?.setupTcpSync()
                    }
                }
                return
            }

            self?.handleIncomingTcpData(data)
            self?.receiveNextPacket()
        }
    }

    private func handleIncomingTcpData(_ data: Data) {
        tcpBuffer.append(data)

        while let newlineIndex = tcpBuffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = tcpBuffer.subdata(in: 0..<newlineIndex)
            tcpBuffer.removeSubrange(0...newlineIndex)

            guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }

            if line.hasPrefix("SYNC_LAYOUT:") || line.hasPrefix("LAYOUT:") {
                let json = line.hasPrefix("SYNC_LAYOUT:") ? String(line.dropFirst(12)) : String(line.dropFirst(7))
                if let jsonData = json.data(using: .utf8), let layout = LayoutModel(jsonData: jsonData) {
                    NSLog("[TouchStage iOS] Received synced layout from Bridge (%ld bytes)", json.count)
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: .touchStageDidReceiveLayout, object: layout)
                    }
                }
            } else if line.hasPrefix("OK:") {
                NSLog("[TouchStage iOS] Bridge ACK: %@", line)
            }
        }
    }
}
