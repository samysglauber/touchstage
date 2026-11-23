import Foundation

public struct DiscoveredServer: Identifiable, Hashable {
    public var id: String { "\(ip):\(port)" }
    public let name: String
    public let ip: String
    public let port: Int
    public let lastSeen: Date
}

public protocol NetworkDiscoveryDelegate: AnyObject {
    func networkDiscoveryDidUpdateServers(_ servers: [DiscoveredServer])
}

public class NetworkDiscovery {
    public static let shared = NetworkDiscovery()
    public weak var delegate: NetworkDiscoveryDelegate?

    private var socketFD: Int32 = -1
    private var isListening = false
    private let queue = DispatchQueue(label: "com.touchstage.discovery", qos: .utility)
    private var servers: [String: DiscoveredServer] = [:]
    private var purgeTimer: Timer?

    private let beaconPort: UInt16 = 9002

    private init() {}

    public func start() {
        guard !isListening else { return }
        isListening = true

        queue.async { [weak self] in
            self?.setupSocket()
            self?.listenLoop()
        }

        DispatchQueue.main.async { [weak self] in
            self?.purgeTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                self?.purgeStaleServers()
            }
        }
    }

    public func stop() {
        isListening = false
        purgeTimer?.invalidate()
        purgeTimer = nil
        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
    }

    private func setupSocket() {
        socketFD = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketFD >= 0 else { return }

        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = __uint8_t(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = beaconPort.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY.bigEndian

        let bindRes = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        if bindRes < 0 {
            close(socketFD)
            socketFD = -1
        }
    }

    private func listenLoop() {
        var buffer = [UInt8](repeating: 0, count: 2048)
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        while isListening && socketFD >= 0 {
            let bytesRead = withUnsafeMutablePointer(to: &clientAddr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(socketFD, &buffer, buffer.count, 0, $0, &addrLen)
                }
            }

            guard bytesRead > 0 else { continue }
            let data = Data(bytes: buffer, count: bytesRead)

            if let json = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any],
               let service = json["service"] as? String, service == "touchstage" {
                
                let name = (json["name"] as? String) ?? "TouchStage Bridge"
                let port = (json["port"] as? NSNumber)?.intValue ?? 9000
                
                // Get sender IP from sockaddr_in
                var ipStr = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                var sinAddr = clientAddr.sin_addr
                inet_ntop(AF_INET, &sinAddr, &ipStr, socklen_t(INET_ADDRSTRLEN))
                let senderIp = String(cString: ipStr)
                let resolvedIp = (json["host"] as? String) ?? (json["ip"] as? String) ?? senderIp

                let server = DiscoveredServer(name: name, ip: resolvedIp, port: port, lastSeen: Date())
                DispatchQueue.main.async { [weak self] in
                    self?.handleDiscoveredServer(server)
                }
            }
        }
    }

    private func handleDiscoveredServer(_ server: DiscoveredServer) {
        servers[server.id] = server
        notifyDelegate()

        // Auto-connect if not currently connected
        if !NetworkManager.shared.isConnected {
            NSLog("[TouchStage iOS] Auto-connecting to discovered Bridge: %@ (%@:%d)", server.name, server.ip, server.port)
            NetworkManager.shared.connect(to: server.ip, port: server.port, name: server.name)
        }
    }

    private func purgeStaleServers() {
        let now = Date()
        let initialCount = servers.count
        servers = servers.filter { now.timeIntervalSince($0.value.lastSeen) < 6.0 }
        if servers.count != initialCount {
            notifyDelegate()
        }
    }

    private func notifyDelegate() {
        let list = Array(servers.values).sorted { $0.lastSeen > $1.lastSeen }
        delegate?.networkDiscoveryDidUpdateServers(list)
    }

    public var availableServers: [DiscoveredServer] {
        return Array(servers.values).sorted { $0.lastSeen > $1.lastSeen }
    }
}
