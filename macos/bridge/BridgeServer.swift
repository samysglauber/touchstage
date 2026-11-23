import Foundation
import CoreMIDI
import Darwin

class ConnectedDevice: NSObject, Identifiable {
    var deviceId: String
    var name: String
    var ipAddress: String
    var socketFd: Int32
    var currentLayoutJson: String?
    var connectedAt: Date
    
    var id: String {
        return deviceId
    }
    
    init(socketFd: Int32, ipAddress: String) {
        self.socketFd = socketFd
        self.ipAddress = ipAddress
        self.deviceId = "dev_\(arc4random() % 10000)"
        self.name = "Device (\(ipAddress))"
        self.connectedAt = Date()
        super.init()
    }
}

class BridgeServer: NSObject, NetServiceDelegate {
    var port: Int
    var localIP: String
    var hostName: String
    
    private var tcpServerFd: Int32 = -1
    private var udpServerFd: Int32 = -1
    private var beaconSocketFd: Int32 = -1
    private var isRunning: Bool = false
    
    private var midiClient = MIDIClientRef()
    private var virtualSource = MIDIEndpointRef()
    private var virtualDestination = MIDIEndpointRef()
    
    private var _devices: [ConnectedDevice] = []
    private let devicesLock = NSLock()
    
    var connectedDevices: [ConnectedDevice] {
        devicesLock.lock()
        defer { devicesLock.unlock() }
        return _devices
    }
    
    var deviceListChanged: (() -> Void)?
    
    private let netQueue = DispatchQueue(label: "com.touchstage.bridge.network", attributes: .concurrent)
    private var beaconTimer: DispatchSourceTimer?
    private var netService: NetService?
    private var latestLayoutJson: String?
    private var dawRunningStatus: UInt8 = 0
    
    struct CachedMidiMessage {
        let status: UInt8
        let d1: UInt8
        let d2: UInt8
    }
    private var dawMidiCache: [UInt16: CachedMidiMessage] = [:]
    private let dawMidiCacheLock = NSLock()
    
    // MIDI Clock & BPM Synchronization
    private var clockTickCount: Int = 0
    private var clockTimestamps: [UInt64] = []
    private var lastCalculatedBpm: Double = 120.0
    private var lastBpmBroadcastTime: Double = 0
    
    init(port: Int = 9000) {
        signal(SIGPIPE, SIG_IGN)
        self.port = port
        self.localIP = BridgeServer.getLocalIPAddress()
        self.hostName = Host.current().localizedName ?? "Mac"
        super.init()
        setupCoreMIDI()
    }
    
    private func setupCoreMIDI() {
        let status = MIDIClientCreateWithBlock("TouchStage Bridge Client" as CFString, &midiClient) { _ in }
        if status != noErr {
            NSLog("[TouchStage Bridge] MIDIClientCreate error: %d", status)
            return
        }
        
        let srcStatus = MIDISourceCreate(midiClient, "TouchStage Controller" as CFString, &virtualSource)
        if srcStatus == noErr {
            NSLog("[TouchStage Bridge] Virtual Source 'TouchStage Controller' active (Phone -> DAW)")
        }
        
        let dstStatus = MIDIDestinationCreateWithBlock(midiClient, "TouchStage Controller" as CFString, &virtualDestination) { [weak self] pktListPtr, _ in
            self?.handleIncomingMidiFromDaw(pktListPtr)
        }
        if dstStatus == noErr {
            NSLog("[TouchStage Bridge] Virtual Destination 'TouchStage Controller' active (DAW -> Phone)")
        }
    }
    
    func sendMidiStatus(status: UInt8, data1: UInt8, data2: UInt8) {
        guard virtualSource != 0 else { return }
        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        var msg = [status, data1, data2]
        packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, 3, &msg)
        MIDIReceived(virtualSource, &packetList)
    }
    
    func sendMackieEnableMeters() {
        sendMidiStatus(status: 0x90, data1: 52, data2: 127)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            self?.sendMidiStatus(status: 0x80, data1: 52, data2: 0)
        }
    }
    
    func sendMidiSysEx(_ bytes: [UInt8]) {
        guard virtualSource != 0, !bytes.isEmpty else { return }
        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        var msg = bytes
        packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, msg.count, &msg)
        MIDIReceived(virtualSource, &packetList)
    }
    
    func requestDawStateSync() {
        sendMackieEnableMeters()
        // SysEx Device Inquiry: requests identification and refresh from Ableton Mackie Control script
        sendMidiSysEx([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7])
        // Mackie Host Query
        sendMidiSysEx([0xF0, 0x00, 0x00, 0x66, 0x14, 0x00, 0xF7])
    }
    
    private func recordInDawCache(status: UInt8, d1: UInt8, d2: UInt8) {
        let msgType = status & 0xF0
        let ch = status & 0x0F
        let key: UInt16
        if msgType == 0xB0 { // Control Change
            key = 0xB000 | (UInt16(ch) << 8) | UInt16(d1)
        } else if msgType == 0x90 || msgType == 0x80 { // Note On / Note Off
            key = 0x9000 | (UInt16(ch) << 8) | UInt16(d1)
        } else if msgType == 0xE0 { // Pitch Bend
            key = 0xE000 | (UInt16(ch) << 8)
        } else {
            return
        }
        dawMidiCacheLock.lock()
        dawMidiCache[key] = CachedMidiMessage(status: status, d1: d1, d2: d2)
        dawMidiCacheLock.unlock()
    }
    
    func dumpMidiCache(to device: ConnectedDevice) {
        guard device.socketFd > 0 else { return }
        dawMidiCacheLock.lock()
        let msgs = Array(dawMidiCache.values)
        dawMidiCacheLock.unlock()
        
        guard !msgs.isEmpty else { return }
        
        var packet = ""
        for m in msgs {
            packet += String(format: "MIDI:%02X,%d,%d\n", m.status, m.d1, m.d2)
        }
        
        if let data = packet.data(using: .utf8) {
            data.withUnsafeBytes { rawBuffer in
                guard let ptr = rawBuffer.baseAddress else { return }
                _ = Darwin.send(device.socketFd, ptr, data.count, 0)
            }
            NSLog("[TouchStage Bridge] Sent %ld cached DAW states to %@", msgs.count, device.name)
        }
    }
    
    func handleIncomingMidiFromDaw(_ pktlist: UnsafePointer<MIDIPacketList>) {
        var packet = pktlist.pointee.packet
        for _ in 0..<pktlist.pointee.numPackets {
            let length = Int(packet.length)
            let mirror = Mirror(reflecting: packet.data)
            var bytes: [UInt8] = []
            for child in mirror.children {
                if bytes.count < length, let val = child.value as? UInt8 {
                    bytes.append(val)
                }
            }
            
            var b = 0
            while b < bytes.count {
                let byte = bytes[b]
                if byte >= 0xF8 {
                    if byte == 0xF8 { // MIDI Timing Clock (24 PPQN)
                        clockTickCount += 1
                        let now = mach_absolute_time()
                        clockTimestamps.append(now)
                        if clockTimestamps.count > 49 { // 48 clock intervals = 2 full beats
                            clockTimestamps.removeFirst()
                        }
                        if clockTimestamps.count >= 48 {
                            let elapsedTicks = clockTimestamps.last! - clockTimestamps.first!
                            var timebase = mach_timebase_info()
                            mach_timebase_info(&timebase)
                            let elapsedNanos = Double(elapsedTicks) * Double(timebase.numer) / Double(timebase.denom)
                            let elapsedSeconds = elapsedNanos / 1_000_000_000.0
                            if elapsedSeconds > 0.1 && elapsedSeconds < 6.0 {
                                let instantaneousBpm = 120.0 / elapsedSeconds
                                if lastCalculatedBpm <= 0 {
                                    lastCalculatedBpm = instantaneousBpm
                                } else {
                                    lastCalculatedBpm = (lastCalculatedBpm * 0.85) + (instantaneousBpm * 0.15)
                                }
                            }
                        }
                        if clockTickCount % 24 == 0 {
                            let beatNum = ((clockTickCount / 24) % 4) + 1
                            broadcastStringToPhones("BEAT:\(beatNum)\n")
                            
                            let curTime = Date().timeIntervalSince1970
                            if curTime - lastBpmBroadcastTime >= 0.35 {
                                lastBpmBroadcastTime = curTime
                                
                                // Smart snap to eliminate CoreMIDI delivery jitter:
                                var bpmToBroadcast = lastCalculatedBpm
                                let nearestInt = round(lastCalculatedBpm)
                                let nearestHalf = round(lastCalculatedBpm * 2.0) / 2.0
                                if abs(lastCalculatedBpm - nearestInt) < 0.22 {
                                    bpmToBroadcast = nearestInt
                                } else if abs(lastCalculatedBpm - nearestHalf) < 0.12 {
                                    bpmToBroadcast = nearestHalf
                                } else {
                                    bpmToBroadcast = round(lastCalculatedBpm * 10.0) / 10.0
                                }
                                
                                let bpmStr = String(format: "%.1f", bpmToBroadcast)
                                broadcastStringToPhones("BPM:\(bpmStr)\n")
                            }
                        }
                    } else if byte == 0xFA { // Start
                        clockTickCount = 0
                        broadcastStringToPhones("TRANSPORT:START\n")
                    } else if byte == 0xFC { // Stop
                        broadcastStringToPhones("TRANSPORT:STOP\n")
                    }
                    b += 1
                    continue
                }
                if byte == 0xF0 {
                    dawRunningStatus = 0
                    while b < bytes.count && bytes[b] != 0xF7 {
                        b += 1
                    }
                    if b < bytes.count { b += 1 }
                    continue
                }
                if byte >= 0xF1 && byte <= 0xF7 {
                    dawRunningStatus = 0
                    if byte == 0xF1 || byte == 0xF3 {
                        b += 2
                    } else if byte == 0xF2 {
                        b += 3
                    } else {
                        b += 1
                    }
                    continue
                }
                
                var status: UInt8 = 0
                if (byte & 0x80) != 0 {
                    status = byte
                    dawRunningStatus = status
                    b += 1
                } else {
                    if dawRunningStatus == 0 {
                        b += 1
                        continue
                    }
                    status = dawRunningStatus
                }
                
                let msgType = status & 0xF0
                if msgType == 0xC0 || msgType == 0xD0 {
                    if b < bytes.count {
                        let d1 = bytes[b]
                        b += 1
                        broadcastMidiToPhones(status: status, d1: d1, d2: 0)
                    } else {
                        break
                    }
                } else {
                    if b + 1 < bytes.count {
                        let d1 = bytes[b]
                        let d2 = bytes[b + 1]
                        b += 2
                        recordInDawCache(status: status, d1: d1, d2: d2)
                        broadcastMidiToPhones(status: status, d1: d1, d2: d2)
                    } else {
                        break
                    }
                }
            }
            
            packet = MIDIPacketNext(&packet).pointee
        }
    }
    
    private func broadcastMidiToPhones(status: UInt8, d1: UInt8, d2: UInt8) {
        let msg = String(format: "MIDI:%02X,%d,%d\n", status, d1, d2)
        guard let data = msg.data(using: .utf8) else { return }
        
        devicesLock.lock()
        let devs = _devices
        devicesLock.unlock()
        
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            for dev in devs {
                if dev.socketFd > 0 {
                    _ = send(dev.socketFd, ptr, data.count, 0)
                }
            }
        }
    }
    
    public func broadcastStringToPhones(_ msg: String) {
        guard let data = msg.data(using: .utf8) else { return }
        devicesLock.lock()
        let devs = _devices
        devicesLock.unlock()
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            for dev in devs {
                if dev.socketFd > 0 {
                    _ = Darwin.send(dev.socketFd, ptr, data.count, 0)
                }
            }
        }
    }
    
    static func getLocalIPAddress() -> String {
        var address = "127.0.0.1"
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return address }
        defer { freeifaddrs(ifaddr) }
        
        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                                &hostname, socklen_t(hostname.count),
                                nil, socklen_t(0), NI_NUMERICHOST)
                    address = String(cString: hostname)
                    break
                }
            }
        }
        return address
    }
    
    func start() -> Bool {
        tcpServerFd = socket(AF_INET, SOCK_STREAM, 0)
        if tcpServerFd < 0 { return false }
        
        var opt: Int32 = 1
        setsockopt(tcpServerFd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
        
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        
        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(tcpServerFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if bindResult < 0 {
            close(tcpServerFd)
            return false
        }
        
        if Darwin.listen(tcpServerFd, 32) < 0 {
            close(tcpServerFd)
            return false
        }
        
        udpServerFd = socket(AF_INET, SOCK_DGRAM, 0)
        if udpServerFd >= 0 {
            setsockopt(udpServerFd, SOL_SOCKET, SO_REUSEADDR, &opt, socklen_t(MemoryLayout<Int32>.size))
            _ = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.bind(udpServerFd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        
        startDiscoveryBeacon()
        startBonjourService()
        
        isRunning = true
        NSLog("[TouchStage Bridge] Ready on %@:%ld", localIP, port)
        
        // UDP Receive loop (sub-millisecond binary MIDI)
        if udpServerFd >= 0 {
            netQueue.async { [weak self] in
                guard let self = self else { return }
                var udpBuf = [UInt8](repeating: 0, count: 64)
                while self.isRunning {
                    var clientAddr = sockaddr_in()
                    var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                    let n = withUnsafeMutablePointer(to: &clientAddr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            recvfrom(self.udpServerFd, &udpBuf, udpBuf.count, 0, $0, &clientLen)
                        }
                    }
                    if n >= 3 {
                        self.sendMidiStatus(status: udpBuf[0], data1: udpBuf[1], data2: udpBuf[2])
                    }
                }
            }
        }
        
        // TCP Accept Loop
        netQueue.async { [weak self] in
            guard let self = self else { return }
            while self.isRunning {
                var clientAddr = sockaddr_in()
                var clientLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        accept(self.tcpServerFd, $0, &clientLen)
                    }
                }
                if clientFd < 0 {
                    if !self.isRunning { break }
                    continue
                }
                
                var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &clientAddr.sin_addr, &ipBuffer, socklen_t(INET_ADDRSTRLEN))
                let clientIp = String(cString: ipBuffer)
                
                self.netQueue.async {
                    self.handleTcpClient(fd: clientFd, ip: clientIp)
                }
            }
        }
        
        return true
    }
    
    private func startDiscoveryBeacon() {
        beaconSocketFd = socket(AF_INET, SOCK_DGRAM, 0)
        guard beaconSocketFd >= 0 else { return }
        
        var broadcastEnable: Int32 = 1
        setsockopt(beaconSocketFd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, socklen_t(MemoryLayout<Int32>.size))
        
        let timer = DispatchSource.makeTimerSource(queue: netQueue)
        timer.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self = self, self.isRunning else { return }
            let jsonBeacon = "{\"service\":\"touchstage\",\"name\":\"\(self.hostName)\",\"host\":\"\(self.localIP)\",\"port\":\(self.port)}\n"
            guard let bytes = jsonBeacon.data(using: .utf8) else { return }
            
            var bcastAddr = sockaddr_in()
            bcastAddr.sin_family = sa_family_t(AF_INET)
            bcastAddr.sin_port = in_port_t(UInt16(9002).bigEndian)
            bcastAddr.sin_addr.s_addr = inet_addr("255.255.255.255")
            
            bytes.withUnsafeBytes { rawBuffer in
                guard let ptr = rawBuffer.baseAddress else { return }
                _ = withUnsafePointer(to: &bcastAddr) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(self.beaconSocketFd, ptr, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
        timer.resume()
        self.beaconTimer = timer
    }
    
    private func startBonjourService() {
        netService = NetService(domain: "local.", type: "_touchstage._tcp.", name: hostName, port: Int32(port))
        netService?.delegate = self
        netService?.publish()
    }
    
    private func handleTcpClient(fd: Int32, ip: String) {
        var nosig: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosig, socklen_t(MemoryLayout<Int32>.size))
        
        let dev = ConnectedDevice(socketFd: fd, ipAddress: ip)
        
        devicesLock.lock()
        _devices.append(dev)
        devicesLock.unlock()
        notifyDeviceListChanged()
        
        // Immediately dump cached DAW MIDI values to this newly connected device
        dumpMidiCache(to: dev)
        
        if let layout = latestLayoutJson {
            sendLayoutJson(json: layout, to: dev)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.requestDawStateSync()
        }
        
        var recvBuffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        
        while isRunning {
            let n = recv(fd, &chunk, chunk.count, 0)
            if n <= 0 { break }
            
            // Binary MIDI: 3 bytes
            if n == 3 {
                sendMidiStatus(status: chunk[0], data1: chunk[1], data2: chunk[2])
                continue
            }
            
            recvBuffer.append(chunk, count: n)
            
            while let newlineIndex = recvBuffer.firstIndex(of: UInt8(ascii: "\n")) {
                let lineData = recvBuffer.subdata(in: 0..<newlineIndex)
                recvBuffer.removeSubrange(0...newlineIndex)
                
                guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
                
                if line.hasPrefix("SYNC_LAYOUT:") {
                    let json = String(line.dropFirst(12))
                    latestLayoutJson = json
                    NSLog("[TouchStage Bridge] Manual sync triggered from Editor (%ld bytes). Broadcasting to phones...", json.count)
                    let count = broadcastSyncLayoutJson(json: json, excludingFd: fd)
                    let ack = "OK:SYNC:\(count)\n"
                    if let ackData = ack.data(using: .utf8) {
                        ackData.withUnsafeBytes { ptr in
                            _ = send(fd, ptr.baseAddress, ackData.count, 0)
                        }
                    }
                } else if line.hasPrefix("LAYOUT:") {
                    let json = String(line.dropFirst(7))
                    latestLayoutJson = json
                    _ = broadcastSyncLayoutJson(json: json, excludingFd: fd)
                    let ack = "OK:LAYOUT\n"
                    if let ackData = ack.data(using: .utf8) {
                        ackData.withUnsafeBytes { ptr in
                            _ = send(fd, ptr.baseAddress, ackData.count, 0)
                        }
                    }
                } else if line.hasPrefix("DEVICE:") {
                    let customName = String(line.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !customName.isEmpty {
                        dev.name = customName
                        NSLog("[TouchStage Bridge] Mobile device registered custom name: '%@'", customName)
                        notifyDeviceListChanged()
                    }
                } else if line.hasPrefix("GET_LAYOUT") {
                    if let layout = latestLayoutJson {
                        sendLayoutJson(json: layout, to: dev)
                    }
                } else if line.hasPrefix("MIDI:") {
                    let parts = String(line.dropFirst(5)).components(separatedBy: ",")
                    if parts.count >= 3 {
                        let st = UInt32(parts[0], radix: 16) ?? 0
                        let d1 = UInt8(Int(parts[1]) ?? 0)
                        let d2 = UInt8(Int(parts[2]) ?? 0)
                        sendMidiStatus(status: UInt8(st), data1: d1, data2: d2)
                    }
                } else if line.hasPrefix("SYNC_DAW") || line.hasPrefix("GET_STATE") {
                    dumpMidiCache(to: dev)
                    requestDawStateSync()
                    let ack = "OK:SYNC_DAW\n"
                    if let ackData = ack.data(using: .utf8) {
                        ackData.withUnsafeBytes { ptr in
                            _ = Darwin.send(fd, ptr.baseAddress, ackData.count, 0)
                        }
                    }
                }
            }
        }
        
        devicesLock.lock()
        _devices.removeAll { $0.socketFd == fd }
        devicesLock.unlock()
        notifyDeviceListChanged()
        close(fd)
    }
    
    private func notifyDeviceListChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.deviceListChanged?()
        }
    }
    
    func sendLayoutJson(json: String, to device: ConnectedDevice) {
        guard device.socketFd > 0 else { return }
        let payload = "LAYOUT:\(json)\n"
        guard let data = payload.data(using: .utf8) else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let n = send(device.socketFd, ptr.advanced(by: sent), data.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
        device.currentLayoutJson = json
    }
    
    func broadcastSyncLayoutJson(json: String, excludingFd: Int32) -> Int {
        latestLayoutJson = json
        let payload = "SYNC_LAYOUT:\(json)\n"
        guard let data = payload.data(using: .utf8) else { return 0 }
        
        devicesLock.lock()
        let devs = _devices
        devicesLock.unlock()
        
        var count = 0
        data.withUnsafeBytes { rawBuffer in
            guard let ptr = rawBuffer.baseAddress else { return }
            for dev in devs {
                if dev.socketFd != excludingFd && dev.socketFd > 0 {
                    var sent = 0
                    while sent < data.count {
                        let n = send(dev.socketFd, ptr.advanced(by: sent), data.count - sent, 0)
                        if n <= 0 { break }
                        sent += n
                    }
                    dev.currentLayoutJson = json
                    count += 1
                }
            }
        }
        return count
    }
    
    func stop() {
        isRunning = false
        beaconTimer?.cancel()
        beaconTimer = nil
        netService?.stop()
        netService = nil
        if tcpServerFd >= 0 { close(tcpServerFd); tcpServerFd = -1 }
        if udpServerFd >= 0 { close(udpServerFd); udpServerFd = -1 }
        if beaconSocketFd >= 0 { close(beaconSocketFd); beaconSocketFd = -1 }
        if virtualSource != 0 { MIDIEndpointDispose(virtualSource); virtualSource = 0 }
        if virtualDestination != 0 { MIDIEndpointDispose(virtualDestination); virtualDestination = 0 }
        if midiClient != 0 { MIDIClientDispose(midiClient); midiClient = 0 }
    }
}
