#import <Cocoa/Cocoa.h>
#import "AirMIDIServer.h"
#import "EditorWindowController.h"

@interface AppDelegate : NSObject <NSApplicationDelegate, EditorWindowDelegate>
@property (strong, nonatomic) NSStatusItem *statusItem;
@property (strong, nonatomic) NSMenu *statusMenu;
@property (strong, nonatomic) AirMIDIServer *midiServer;
@property (strong, nonatomic) EditorWindowController *editorController;
@property (strong, nonatomic) NSMenuItem *clientsItem;
@property (strong, nonatomic) NSMenuItem *ipItem;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    // 1. Start Native Socket Server & CoreMIDI Virtual Device on port 9000
    NSInteger port = 9000;
    self.midiServer = [[AirMIDIServer alloc] initWithPort:port];
    if (![self.midiServer start]) {
        self.midiServer = [[AirMIDIServer alloc] initWithPort:9001];
        [self.midiServer start];
        port = 9001;
    }

    // 2. Initialize Editor Window Controller
    self.editorController = [[EditorWindowController alloc] init];
    self.editorController.editorDelegate = self;
    self.midiServer.currentLayout = self.editorController.layout;

    // 3. Setup macOS Menu Bar Status Item
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.button.title = @"🎛️ AirMIDI Studio";
    self.statusItem.button.toolTip = @"AirMIDI Studio - Controlador MIDI Nativo & Editor";

    self.statusMenu = [[NSMenu alloc] initWithTitle:@"AirMIDI"];

    NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:@"● AirMIDI: Conexão Pronta" action:nil keyEquivalent:@""];
    titleItem.enabled = NO;
    [self.statusMenu addItem:titleItem];

    NSMenuItem *portItem = [[NSMenuItem alloc] initWithTitle:@"🎹 CoreMIDI: 'AirMIDI Controller'" action:nil keyEquivalent:@""];
    portItem.enabled = NO;
    [self.statusMenu addItem:portItem];

    NSString *ipText = [NSString stringWithFormat:@"🌐 Wi-Fi: %@:%ld", self.midiServer.localIP, (long)port];
    self.ipItem = [[NSMenuItem alloc] initWithTitle:ipText action:@selector(copyServerUrl) keyEquivalent:@""];
    self.ipItem.target = self;
    self.ipItem.toolTip = @"Clique para copiar o IP do Mac";
    [self.statusMenu addItem:self.ipItem];

    self.clientsItem = [[NSMenuItem alloc] initWithTitle:@"📱 Dispositivos conectados: 0" action:nil keyEquivalent:@""];
    self.clientsItem.enabled = NO;
    [self.statusMenu addItem:self.clientsItem];

    [self.statusMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *editorItem = [[NSMenuItem alloc] initWithTitle:@"✏️ Abrir Editor de Layouts no Mac..." action:@selector(openLayoutEditor) keyEquivalent:@"e"];
    editorItem.target = self;
    [self.statusMenu addItem:editorItem];

    NSMenuItem *syncItem = [[NSMenuItem alloc] initWithTitle:@"📶 Sincronizar com Celular via Wi-Fi" action:@selector(syncLayoutWithPhone) keyEquivalent:@"s"];
    syncItem.target = self;
    [self.statusMenu addItem:syncItem];

    [self.statusMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *dawItem = [[NSMenuItem alloc] initWithTitle:@"ℹ️ Configuração na DAW (Ableton / Logic)..." action:@selector(showDawHelp) keyEquivalent:@""];
    dawItem.target = self;
    [self.statusMenu addItem:dawItem];

    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"🚪 Encerrar AirMIDI Studio" action:@selector(quitApp) keyEquivalent:@"q"];
    quitItem.target = self;
    [self.statusMenu addItem:quitItem];

    self.statusItem.menu = self.statusMenu;

    // Listen to client connect/disconnect events
    __weak typeof(self) weakSelf = self;
    self.midiServer.clientCountChanged = ^(NSInteger count) {
        weakSelf.clientsItem.title = [NSString stringWithFormat:@"📱 Dispositivos conectados: %ld", (long)count];
        if (count > 0) {
            weakSelf.statusItem.button.title = [NSString stringWithFormat:@"🎛️ AirMIDI (%ld)", (long)count];
        } else {
            weakSelf.statusItem.button.title = @"🎛️ AirMIDI Studio";
        }
    };

    // Open the native Editor window on launch
    [self.editorController showEditor];
}

- (void)copyServerUrl {
    NSString *ipStr = [NSString stringWithFormat:@"%@:%ld", self.midiServer.localIP, (long)self.midiServer.port];
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:ipStr forType:NSPasteboardTypeString];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Endereço IP copiado!";
    alert.informativeText = [NSString stringWithFormat:@"O IP e porta foram copiados para a área de transferência:\n\n%@\n\nBasta digitar no aplicativo Android.", ipStr];
    [alert runModal];
}

- (void)openLayoutEditor {
    [self.editorController showEditor];
}

- (void)syncLayoutWithPhone {
    [self.midiServer broadcastLayout:self.editorController.layout];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Layout Sincronizado!";
    alert.informativeText = @"O layout atual foi enviado para todos os celulares conectados.";
    [alert runModal];
}

- (void)showDawHelp {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"Configuração na DAW";
    alert.informativeText = 
        @"1. No Ableton Live: vá em Preferences > Link / MIDI.\n"
        @"Localize a porta de entrada 'AirMIDI Controller' e ative 'Track' e 'Remote'.\n\n"
        @"2. No Logic Pro / MainStage: a porta é detectada automaticamente no CoreMIDI nativo.\n\n"
        @"3. No Reaper / Cubase / FL Studio: ative 'AirMIDI Controller' nas entradas MIDI.\n\n"
        @"Ao tocar no celular, os comandos MIDI são injetados diretamente na sua DAW com latência mínima!";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (void)quitApp {
    [self.midiServer stop];
    [NSApp terminate:nil];
}

// -------------------------------------------------------------
// EditorWindowDelegate
// -------------------------------------------------------------
- (void)editorDidUpdateLayout:(LayoutModel *)layout {
    self.midiServer.currentLayout = layout;
    [self.midiServer broadcastLayout:layout];
}

- (void)editorDidRequestSendLayoutToPhone:(LayoutModel *)layout {
    [self.midiServer broadcastLayout:layout];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
