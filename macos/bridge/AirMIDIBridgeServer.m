#import "AirMIDIBridgeServer.h"

@implementation ConnectedDevice
@end

static void DawMidiReadProc(const MIDIPacketList *pktlist, void *readProcRefCon, void *srcConnRefCon) {
    AirMIDIBridgeServer *server = (__bridge AirMIDIBridgeServer *)readProcRefCon;
    [server handleIncomingMidiFromDaw:pktlist];
}

@implementation AirMIDIBridgeServer {
    int _tcpServerFd;
    int _udpServerFd;
    int _beaconSocketFd;
    BOOL _isRunning;
    MIDIClientRef _midiClient;
    MIDIEndpointRef _virtualSource;
    MIDIEndpointRef _virtualDestination;
    NSMutableArray<ConnectedDevice *> *_devices;
    dispatch_queue_t _netQueue;
    dispatch_source_t _beaconTimer;
    NSNetService *_netService;
    NSString *_latestLayoutJson;
    Byte _dawRunningStatus;
}

- (instancetype)initWithPort:(NSInteger)port {
    self = [super init];
    if (self) {
        signal(SIGPIPE, SIG_IGN);
        _port = port;
        _devices = [NSMutableArray array];
        _netQueue = dispatch_queue_create("com.airmidi.bridge.network", DISPATCH_QUEUE_CONCURRENT);
        _localIP = [self getLocalIPAddress] ?: @"127.0.0.1";
        _hostName = [[NSHost currentHost] localizedName] ?: @"Mac";
        _dawRunningStatus = 0;
        [self setupCoreMIDI];
    }
    return self;
}

- (void)setupCoreMIDI {
    OSStatus status = MIDIClientCreate(CFSTR("TouchStage Bridge Client"), NULL, NULL, &_midiClient);
    if (status != noErr) {
        NSLog(@"[TouchStage Bridge] MIDIClientCreate error: %d", (int)status);
        return;
    }

    // 1. Virtual Source: sends MIDI from Phones -> DAW
    status = MIDISourceCreate(_midiClient, CFSTR("TouchStage Controller"), &_virtualSource);
    if (status != noErr) {
        NSLog(@"[TouchStage Bridge] MIDISourceCreate error: %d", (int)status);
    } else {
        NSLog(@"[TouchStage Bridge] Virtual Source 'TouchStage Controller' active (Phone -> DAW)");
    }

    // 2. Virtual Destination: receives MIDI from DAW -> Phones (Bidirectional Feedback!)
    status = MIDIDestinationCreate(_midiClient, CFSTR("TouchStage Controller"), DawMidiReadProc, (__bridge void *)self, &_virtualDestination);
    if (status != noErr) {
        NSLog(@"[TouchStage Bridge] MIDIDestinationCreate error: %d", (int)status);
    } else {
        NSLog(@"[TouchStage Bridge] Virtual Destination 'TouchStage Controller' active (DAW -> Phone)");
    }
}

// Receive MIDI from Phone and send to DAW
- (void)sendMidiStatus:(Byte)status data1:(Byte)d1 data2:(Byte)d2 {
    if (!_virtualSource) return;
    Byte packetBuf[128];
    MIDIPacketList *packetList = (MIDIPacketList *)packetBuf;
    MIDIPacket *cur = MIDIPacketListInit(packetList);
    Byte msg[3] = { status, d1, d2 };
    cur = MIDIPacketListAdd(packetList, sizeof(packetBuf), cur, 0, 3, msg);
    MIDIReceived(_virtualSource, packetList);
}

- (void)sendMackieEnableMeters {
    // Send Note 52 (SID_DISPLAY_NAME_VALUE) to toggle meter mode in Ableton Live's MackieControl
    [self sendMidiStatus:0x90 data1:52 data2:127];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self sendMidiStatus:0x80 data1:52 data2:0];
    });
}

// Receive MIDI from DAW and send to connected Phones (Bidirectional Feedback with Running Status)
- (void)handleIncomingMidiFromDaw:(const MIDIPacketList *)pktlist {
    if (!pktlist || pktlist->numPackets == 0) return;
    const MIDIPacket *packet = &pktlist->packet[0];
    for (int i = 0; i < pktlist->numPackets; i++) {
        int b = 0;
        while (b < packet->length) {
            Byte byte = packet->data[b];

            // 1. System Real-Time messages (0xF8 - 0xFF, single byte)
            // They do not clear or modify running status.
            if (byte >= 0xF8) {
                b++;
                continue;
            }

            // 2. SysEx message (0xF0 ... 0xF7)
            if (byte == 0xF0) {
                _dawRunningStatus = 0; // Clears running status
                while (b < packet->length && packet->data[b] != 0xF7) {
                    b++;
                }
                if (b < packet->length) b++; // Consume 0xF7
                continue;
            }

            // 3. System Common messages (0xF1 - 0xF7)
            if (byte >= 0xF1 && byte <= 0xF7) {
                _dawRunningStatus = 0; // Clears running status
                if (byte == 0xF1 || byte == 0xF3) {
                    b += 2; // Status + 1 data byte
                } else if (byte == 0xF2) {
                    b += 3; // Status + 2 data bytes
                } else {
                    b += 1;
                }
                continue;
            }

            // 4. Channel Voice messages (0x80 - 0xEF) or Running Status data
            Byte status = 0;
            if ((byte & 0x80) != 0) {
                // New status byte
                status = byte;
                _dawRunningStatus = status;
                b++;
            } else {
                // Data byte using active Running Status
                if (_dawRunningStatus == 0) {
                    // No running status active, skip stray byte
                    b++;
                    continue;
                }
                status = _dawRunningStatus;
            }

            Byte msgType = status & 0xF0;
            if (msgType == 0xC0 || msgType == 0xD0) {
                // 1 data byte messages: Program Change (0xC0), Channel Pressure / MCU Meter (0xD0)
                if (b < packet->length) {
                    Byte d1 = packet->data[b++];
                    [self broadcastMidiToPhones:status data1:d1 data2:0];
                } else {
                    break;
                }
            } else {
                // 2 data byte messages: Note Off (0x80), Note On (0x90), Poly Pressure (0xA0), CC (0xB0), Pitch Bend (0xE0)
                if (b + 1 < packet->length) {
                    Byte d1 = packet->data[b++];
                    Byte d2 = packet->data[b++];
                    [self broadcastMidiToPhones:status data1:d1 data2:d2];
                } else {
                    break;
                }
            }
        }
        packet = MIDIPacketNext(packet);
    }
}

- (void)broadcastMidiToPhones:(Byte)status data1:(Byte)d1 data2:(Byte)d2 {
    NSString *msg = [NSString stringWithFormat:@"MIDI:%02X,%d,%d\n", status, d1, d2];
    const char *bytes = msg.UTF8String;
    size_t len = strlen(bytes);

    @synchronized(_devices) {
        for (ConnectedDevice *d in _devices) {
            if (d.socketFd > 0) {
                send(d.socketFd, bytes, len, 0);
            }
        }
    }
}

- (NSString *)getLocalIPAddress {
    NSString *address = nil;
    struct ifaddrs *interfaces = NULL;
    struct ifaddrs *temp_addr = NULL;
    if (getifaddrs(&interfaces) == 0) {
        temp_addr = interfaces;
        while (temp_addr != NULL) {
            if (temp_addr->ifa_addr->sa_family == AF_INET) {
                NSString *name = [NSString stringWithUTF8String:temp_addr->ifa_name];
                if ([name isEqualToString:@"en0"] || [name isEqualToString:@"en1"]) {
                    address = [NSString stringWithUTF8String:inet_ntoa(((struct sockaddr_in *)temp_addr->ifa_addr)->sin_addr)];
                    break;
                }
            }
            temp_addr = temp_addr->ifa_next;
        }
    }
    freeifaddrs(interfaces);
    return address ?: @"127.0.0.1";
}

- (NSArray<ConnectedDevice *> *)connectedDevices {
    @synchronized(_devices) {
        return [_devices copy];
    }
}

- (BOOL)start {
    _tcpServerFd = socket(AF_INET, SOCK_STREAM, 0);
    if (_tcpServerFd < 0) return NO;

    int opt = 1;
    setsockopt(_tcpServerFd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons((uint16_t)_port);

    if (bind(_tcpServerFd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(_tcpServerFd);
        return NO;
    }
    if (listen(_tcpServerFd, 32) < 0) {
        close(_tcpServerFd);
        return NO;
    }

    _udpServerFd = socket(AF_INET, SOCK_DGRAM, 0);
    if (_udpServerFd >= 0) {
        setsockopt(_udpServerFd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        bind(_udpServerFd, (struct sockaddr *)&addr, sizeof(addr));
    }

    [self startDiscoveryBeacon];
    [self startBonjourService];

    _isRunning = YES;
    NSLog(@"[AirMIDI Bridge] Ready on %@:%ld", _localIP, (long)_port);

    // UDP Receive Loop
    if (_udpServerFd >= 0) {
        dispatch_async(_netQueue, ^{
            uint8_t udpBuf[64];
            while (self->_isRunning) {
                struct sockaddr_in clientAddr;
                socklen_t clientLen = sizeof(clientAddr);
                ssize_t n = recvfrom(self->_udpServerFd, udpBuf, sizeof(udpBuf), 0, (struct sockaddr *)&clientAddr, &clientLen);
                if (n >= 3) {
                    [self sendMidiStatus:udpBuf[0] data1:udpBuf[1] data2:udpBuf[2]];
                }
            }
        });
    }

    // TCP Accept Loop
    dispatch_async(_netQueue, ^{
        while (self->_isRunning) {
            struct sockaddr_in clientAddr;
            socklen_t clientLen = sizeof(clientAddr);
            int clientFd = accept(self->_tcpServerFd, (struct sockaddr *)&clientAddr, &clientLen);
            if (clientFd < 0) {
                if (!self->_isRunning) break;
                continue;
            }
            char ipStr[INET_ADDRSTRLEN];
            inet_ntop(AF_INET, &(clientAddr.sin_addr), ipStr, INET_ADDRSTRLEN);
            NSString *clientIp = [NSString stringWithUTF8String:ipStr];

            dispatch_async(self->_netQueue, ^{
                [self handleTcpClient:clientFd ipAddress:clientIp];
            });
        }
    });

    return YES;
}

- (void)startDiscoveryBeacon {
    _beaconSocketFd = socket(AF_INET, SOCK_DGRAM, 0);
    if (_beaconSocketFd < 0) return;

    int broadcastEnable = 1;
    setsockopt(_beaconSocketFd, SOL_SOCKET, SO_BROADCAST, &broadcastEnable, sizeof(broadcastEnable));

    _beaconTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, _netQueue);
    dispatch_source_set_timer(_beaconTimer, dispatch_time(DISPATCH_TIME_NOW, 0), 2.0 * NSEC_PER_SEC, 0.2 * NSEC_PER_SEC);

    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(_beaconTimer, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_isRunning) return;

        NSString *jsonBeacon = [NSString stringWithFormat:
            @"{\"service\":\"touchstage\",\"name\":\"%@\",\"host\":\"%@\",\"port\":%ld}\n",
            strongSelf.hostName, strongSelf.localIP, (long)strongSelf.port];
        const char *bytes = jsonBeacon.UTF8String;

        struct sockaddr_in bcastAddr;
        memset(&bcastAddr, 0, sizeof(bcastAddr));
        bcastAddr.sin_family = AF_INET;
        bcastAddr.sin_port = htons(9002);
        bcastAddr.sin_addr.s_addr = inet_addr("255.255.255.255");

        sendto(strongSelf->_beaconSocketFd, bytes, strlen(bytes), 0, (struct sockaddr *)&bcastAddr, sizeof(bcastAddr));
    });

    dispatch_resume(_beaconTimer);
}

- (void)startBonjourService {
    _netService = [[NSNetService alloc] initWithDomain:@"local."
                                                  type:@"_touchstage._tcp."
                                                  name:_hostName
                                                  port:(int)_port];
    _netService.delegate = self;
    [_netService publish];
}

- (void)handleTcpClient:(int)fd ipAddress:(NSString *)ip {
    int nosig = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, (void *)&nosig, sizeof(nosig));

    ConnectedDevice *dev = [[ConnectedDevice alloc] init];
    dev.socketFd = fd;
    dev.ipAddress = ip;
    dev.deviceId = [NSString stringWithFormat:@"dev_%u", arc4random() % 10000];
    dev.name = [NSString stringWithFormat:@"Device (%@)", ip];
    dev.connectedAt = [NSDate date];

    @synchronized(_devices) {
        [_devices addObject:dev];
        [self notifyDeviceListChanged];
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
        [self sendMackieEnableMeters];
    });

    NSMutableData *recvBuffer = [NSMutableData data];
    char chunk[4096];

    while (_isRunning) {
        ssize_t n = recv(fd, chunk, sizeof(chunk), 0);
        if (n <= 0) break;

        // Binary MIDI: 3 bytes
        if (n == 3) {
            uint8_t *b = (uint8_t *)chunk;
            [self sendMidiStatus:b[0] data1:b[1] data2:b[2]];
            continue;
        }

        [recvBuffer appendBytes:chunk length:n];

        // Process line-by-line commands separated by \n
        while (YES) {
            const char *bytes = (const char *)recvBuffer.bytes;
            NSUInteger len = recvBuffer.length;
            const char *newlinePos = memchr(bytes, '\n', len);
            if (!newlinePos) break;

            NSUInteger lineLen = newlinePos - bytes;
            NSString *line = [[NSString alloc] initWithBytes:bytes length:lineLen encoding:NSUTF8StringEncoding];
            [recvBuffer replaceBytesInRange:NSMakeRange(0, lineLen + 1) withBytes:NULL length:0];

            if (!line) continue;
            line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

            if ([line hasPrefix:@"SYNC_LAYOUT:"]) {
                NSString *json = [line substringFromIndex:12];
                _latestLayoutJson = json;
                NSLog(@"[AirMIDI Bridge] Manual sync triggered from Editor (%lu bytes). Broadcasting to phones...", (unsigned long)json.length);
                int syncedCount = [self broadcastSyncLayoutJson:json excludingFd:fd];
                NSString *ack = [NSString stringWithFormat:@"OK:SYNC:%d\n", syncedCount];
                send(fd, ack.UTF8String, ack.length, 0);
            } else if ([line hasPrefix:@"LAYOUT:"]) {
                NSString *json = [line substringFromIndex:7];
                _latestLayoutJson = json;
                [self broadcastSyncLayoutJson:json excludingFd:fd];
                const char *ack = "OK:LAYOUT\n";
                send(fd, ack, strlen(ack), 0);
            } else if ([line hasPrefix:@"DEVICE:"]) {
                NSString *customName = [[line substringFromIndex:7] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (customName.length > 0) {
                    dev.name = customName;
                    NSLog(@"[TouchStage Bridge] Mobile device registered custom name: '%@'", customName);
                    [self notifyDeviceListChanged];
                }
            } else if ([line hasPrefix:@"GET_LAYOUT"]) {
                if (_latestLayoutJson) {
                    [self sendLayoutJson:_latestLayoutJson toDevice:dev];
                }
            } else if ([line hasPrefix:@"MIDI:"]) {
                NSArray *parts = [[line substringFromIndex:5] componentsSeparatedByString:@","];
                if (parts.count >= 3) {
                    unsigned int st = 0, d1 = 0, d2 = 0;
                    [[NSScanner scannerWithString:parts[0]] scanHexInt:&st];
                    d1 = (unsigned int)[parts[1] integerValue];
                    d2 = (unsigned int)[parts[2] integerValue];
                    [self sendMidiStatus:(Byte)st data1:(Byte)d1 data2:(Byte)d2];
                }
            }
        }
    }

    @synchronized(_devices) {
        [_devices removeObject:dev];
        [self notifyDeviceListChanged];
    }
    close(fd);
}

- (void)notifyDeviceListChanged {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.deviceListChanged) {
            self.deviceListChanged();
        }
    });
}

- (void)sendLayoutJson:(NSString *)json toDevice:(ConnectedDevice *)device {
    if (!device || device.socketFd <= 0 || !json) return;
    NSString *payload = [NSString stringWithFormat:@"LAYOUT:%@\n", json];
    const char *bytes = payload.UTF8String;
    size_t total = strlen(bytes);
    size_t sent = 0;
    while (sent < total) {
        ssize_t n = send(device.socketFd, bytes + sent, total - sent, 0);
        if (n <= 0) break;
        sent += n;
    }
    device.currentLayoutJson = json;
}

- (void)broadcastLayoutJson:(NSString *)json excludingFd:(int)excludeFd {
    _latestLayoutJson = json;
    @synchronized(_devices) {
        for (ConnectedDevice *dev in _devices) {
            if (dev.socketFd != excludeFd) {
                [self sendLayoutJson:json toDevice:dev];
            }
        }
    }
}

- (int)broadcastSyncLayoutJson:(NSString *)json excludingFd:(int)excludeFd {
    _latestLayoutJson = json;
    NSString *payload = [NSString stringWithFormat:@"SYNC_LAYOUT:%@\n", json];
    const char *bytes = payload.UTF8String;
    size_t total = strlen(bytes);
    int count = 0;

    @synchronized(_devices) {
        for (ConnectedDevice *dev in _devices) {
            if (dev.socketFd != excludeFd && dev.socketFd > 0) {
                size_t sent = 0;
                while (sent < total) {
                    ssize_t n = send(dev.socketFd, bytes + sent, total - sent, 0);
                    if (n <= 0) break;
                    sent += n;
                }
                dev.currentLayoutJson = json;
                count++;
            }
        }
    }
    return count;
}

- (void)stop {
    _isRunning = NO;
    if (_beaconTimer) {
        dispatch_source_cancel(_beaconTimer);
        _beaconTimer = nil;
    }
    if (_netService) {
        [_netService stop];
        _netService = nil;
    }
    if (_tcpServerFd >= 0) close(_tcpServerFd);
    if (_udpServerFd >= 0) close(_udpServerFd);
    if (_beaconSocketFd >= 0) close(_beaconSocketFd);
    if (_virtualSource) MIDIEndpointDispose(_virtualSource);
    if (_virtualDestination) MIDIEndpointDispose(_virtualDestination);
    if (_midiClient) MIDIClientDispose(_midiClient);
}

@end
