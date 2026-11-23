import Foundation
import Network

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

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: nwPort)
        let conn = NWConnection(to: endpoint, using: .tcp)

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isConnected = true
                self?.sendHandshake()
                self?.receiveNextPacket()
            case .failed, .cancelled:
                // Silent fallback
                break
            default:
                break
            }
        }

        conn.start(queue: netQueue)
        self.tcpConnection = conn
    }

    private func sendHandshake() {
        let msg = "{\"client\":\"TouchStage iOS\",\"version\":\"1.0\"}\n"
        if let data = msg.data(using: .utf8) {
            tcpConnection?.send(content: data, completion: .contentProcessed({ _ in }))
        }
    }

    private func receiveNextPacket() {
        tcpConnection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard error == nil, let data = content, !data.isEmpty else {
                if isComplete { self?.setupTcpSync() }
                return
            }

            self?.handleTcpPayload(data)
            self?.receiveNextPacket()
        }
    }

    private func handleTcpPayload(_ data: Data) {
        if let layout = LayoutModel(jsonData: data), !layout.pages.isEmpty {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .touchStageDidReceiveLayout, object: layout)
            }
        }
    }
}
