#import "AirMIDIServer.h"

@implementation AirMIDIServer {
    int _tcpServerFd;
    int _udpServerFd;
    BOOL _isRunning;
    MIDIClientRef _midiClient;
    MIDIEndpointRef _virtualSource;
    NSMutableArray *_clientSockets;
    dispatch_queue_t _netQueue;
}

- (instancetype)initWithPort:(NSInteger)port {
    self = [super init];
    if (self) {
        _port = port;
        _clientSockets = [NSMutableArray array];
        _netQueue = dispatch_queue_create("com.airmidi.network", DISPATCH_QUEUE_CONCURRENT);
        _localIP = [self getLocalIPAddress] ?: @"127.0.0.1";
        _currentLayout = [LayoutModel referencePreset];
        [self setupCoreMIDI];
    }
    return self;
}

- (void)setupCoreMIDI {
    OSStatus status = MIDIClientCreate(CFSTR("AirMIDI Client"), NULL, NULL, &_midiClient);
    if (status != noErr) {
        NSLog(@"[AirMIDI] Erro MIDIClientCreate: %d", (int)status);
        return;
    }
    status = MIDISourceCreate(_midiClient, CFSTR("AirMIDI Controller"), &_virtualSource);
    if (status != noErr) {
        NSLog(@"[AirMIDI] Erro MIDISourceCreate: %d", (int)status);
    } else {
        NSLog(@"[AirMIDI] Porta CoreMIDI 'AirMIDI Controller' criada com sucesso!");
    }
}

- (void)sendMidiStatus:(Byte)status data1:(Byte)d1 data2:(Byte)d2 {
    if (!_virtualSource) return;
    Byte packetBuf[128];
    MIDIPacketList *packetList = (MIDIPacketList *)packetBuf;
    MIDIPacket *cur = MIDIPacketListInit(packetList);
    Byte msg[3] = { status, d1, d2 };
    cur = MIDIPacketListAdd(packetList, sizeof(packetBuf), cur, 0, 3, msg);
    MIDIReceived(_virtualSource, packetList);
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
    return address ?: @"localhost";
}

- (BOOL)start {
    // 1. TCP Server for control and layout synchronization
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
        NSLog(@"[AirMIDI] Falha no bind TCP porta %ld", (long)_port);
        close(_tcpServerFd);
        return NO;
    }

    if (listen(_tcpServerFd, 32) < 0) {
        close(_tcpServerFd);
        return NO;
    }

    // 2. UDP Server for fast low-latency MIDI datagrams
    _udpServerFd = socket(AF_INET, SOCK_DGRAM, 0);
    if (_udpServerFd >= 0) {
        setsockopt(_udpServerFd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
        bind(_udpServerFd, (struct sockaddr *)&addr, sizeof(addr));
    }

    _isRunning = YES;
    NSLog(@"[AirMIDI] Servidor Nativo rodando em %@:%ld (TCP/UDP)", _localIP, (long)_port);

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
            dispatch_async(self->_netQueue, ^{
                [self handleTcpClient:clientFd];
            });
        }
    });

    return YES;
}

- (void)handleTcpClient:(int)fd {
    @synchronized(_clientSockets) {
        [_clientSockets addObject:@(fd)];
        [self notifyClientCount];
    }

    // Immediately send current layout upon connection
    [self sendLayoutToSocket:fd layout:_currentLayout];

    char buffer[4096];
    while (_isRunning) {
        ssize_t n = recv(fd, buffer, sizeof(buffer), 0);
        if (n <= 0) break;

        // Binary MIDI packet: 3 bytes [status, d1, d2]
        if (n == 3) {
            uint8_t *b = (uint8_t *)buffer;
            [self sendMidiStatus:b[0] data1:b[1] data2:b[2]];
            continue;
        }

        // Text command
        buffer[n] = '\0';
        NSString *msg = [NSString stringWithUTF8String:buffer];
        if (!msg) continue;

        if ([msg hasPrefix:@"GET_LAYOUT"]) {
            [self sendLayoutToSocket:fd layout:_currentLayout];
        } else if ([msg hasPrefix:@"MIDI:"]) {
            // Text fallback: MIDI:B0,07,64
            NSArray *parts = [[msg substringFromIndex:5] componentsSeparatedByString:@","];
            if (parts.count >= 3) {
                unsigned int st = 0, d1 = 0, d2 = 0;
                [[NSScanner scannerWithString:parts[0]] scanHexInt:&st];
                d1 = (unsigned int)[parts[1] integerValue];
                d2 = (unsigned int)[parts[2] integerValue];
                [self sendMidiStatus:(Byte)st data1:(Byte)d1 data2:(Byte)d2];
            }
        }
    }

    @synchronized(_clientSockets) {
        [_clientSockets removeObject:@(fd)];
        [self notifyClientCount];
    }
    close(fd);
}

- (void)sendLayoutToSocket:(int)fd layout:(LayoutModel *)layout {
    if (!layout) return;
    NSString *json = [layout toJSONString];
    NSString *payload = [NSString stringWithFormat:@"LAYOUT:%@\n", json];
    const char *bytes = payload.UTF8String;
    size_t total = strlen(bytes);
    size_t sent = 0;
    while (sent < total) {
        ssize_t n = send(fd, bytes + sent, total - sent, 0);
        if (n <= 0) break;
        sent += n;
    }
}

- (void)broadcastLayout:(LayoutModel *)layout {
    _currentLayout = layout;
    @synchronized(_clientSockets) {
        for (NSNumber *fdNum in _clientSockets) {
            [self sendLayoutToSocket:[fdNum intValue] layout:layout];
        }
    }
}

- (void)notifyClientCount {
    NSInteger count = _clientSockets.count;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.clientCountChanged) {
            self.clientCountChanged(count);
        }
    });
}

- (void)stop {
    _isRunning = NO;
    if (_tcpServerFd >= 0) close(_tcpServerFd);
    if (_udpServerFd >= 0) close(_udpServerFd);
    if (_virtualSource) MIDIEndpointDispose(_virtualSource);
    if (_midiClient) MIDIClientDispose(_midiClient);
}

@end
