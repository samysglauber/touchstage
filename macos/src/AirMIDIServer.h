#import <Cocoa/Cocoa.h>
#import <CoreMIDI/CoreMIDI.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <ifaddrs.h>
#import <unistd.h>
#import <fcntl.h>
#import "LayoutModel.h"

@interface AirMIDIServer : NSObject
@property (nonatomic, assign) NSInteger port;
@property (nonatomic, readonly) NSInteger connectedClients;
@property (nonatomic, copy) NSString *localIP;
@property (nonatomic, strong) LayoutModel *currentLayout;
@property (nonatomic, copy) void (^clientCountChanged)(NSInteger count);

- (instancetype)initWithPort:(NSInteger)port;
- (BOOL)start;
- (void)stop;
- (void)broadcastLayout:(LayoutModel *)layout;
- (void)sendMidiStatus:(Byte)status data1:(Byte)d1 data2:(Byte)d2;
@end
