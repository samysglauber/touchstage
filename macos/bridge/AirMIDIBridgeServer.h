#import <Cocoa/Cocoa.h>
#import <CoreMIDI/CoreMIDI.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <unistd.h>
#import <fcntl.h>

@interface ConnectedDevice : NSObject
@property (nonatomic, copy) NSString *deviceId;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *ipAddress;
@property (nonatomic, assign) int socketFd;
@property (nonatomic, copy) NSString *currentLayoutJson;
@property (nonatomic, strong) NSDate *connectedAt;
@end

@interface AirMIDIBridgeServer : NSObject <NSNetServiceDelegate>
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, copy) NSString *localIP;
@property (nonatomic, copy) NSString *hostName;
@property (nonatomic, readonly) NSArray<ConnectedDevice *> *connectedDevices;
@property (nonatomic, copy) void (^deviceListChanged)(void);

- (instancetype)initWithPort:(NSInteger)port;
- (BOOL)start;
- (void)stop;
- (void)sendLayoutJson:(NSString *)json toDevice:(ConnectedDevice *)device;
- (void)broadcastLayoutJson:(NSString *)json excludingFd:(int)excludeFd;
- (int)broadcastSyncLayoutJson:(NSString *)json excludingFd:(int)excludeFd;
- (void)sendMidiStatus:(Byte)status data1:(Byte)d1 data2:(Byte)d2;
- (void)sendMackieEnableMeters;
- (void)handleIncomingMidiFromDaw:(const MIDIPacketList *)pktlist;
@end
