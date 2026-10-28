#import <Cocoa/Cocoa.h>
#import "EditorWindowController.h"

@interface EditorAppDelegate : NSObject <NSApplicationDelegate>
@property (strong, nonatomic) EditorWindowController *editorController;
@end

@implementation EditorAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.editorController = [[EditorWindowController alloc] init];
    [self.editorController showEditor];
    [self setupAppMenu];
}

- (void)setupAppMenu {
    NSMenu *mainMenu = [[NSMenu alloc] init];

    // App Menu
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"TouchStage Editor"];
    [appMenu addItemWithTitle:@"About TouchStage Editor" action:nil keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide TouchStage Editor" action:@selector(hide:) keyEquivalent:@"h"];
    [appMenu addItemWithTitle:@"Quit TouchStage Editor" action:@selector(terminate:) keyEquivalent:@"q"];
    appMenuItem.submenu = appMenu;
    [mainMenu addItem:appMenuItem];

    // File Menu
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] init];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"Recent Projects..." action:@selector(showLauncherSheet) keyEquivalent:@"r"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"New Project" action:@selector(onNewLayoutClicked:) keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"Open Layout..." action:@selector(onOpenLayoutClicked:) keyEquivalent:@"o"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Save Layout File..." action:@selector(onSaveLayoutClicked:) keyEquivalent:@"s"];
    [fileMenu addItemWithTitle:@"Save as Preset..." action:@selector(onSavePresetClicked:) keyEquivalent:@"S"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close Window" action:@selector(performClose:) keyEquivalent:@"w"];
    fileMenuItem.submenu = fileMenu;
    [mainMenu addItem:fileMenuItem];

    // Edit Menu (Enables native system-level Cmd+Z, Cmd+Shift+Z, Cmd+C, Cmd+V, Cmd+A)
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Delete" action:@selector(deleteSelected:) keyEquivalent:@"\b"];
    editMenuItem.submenu = editMenu;
    [mainMenu addItem:editMenuItem];

    [NSApp setMainMenu:mainMenu];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        EditorAppDelegate *delegate = [[EditorAppDelegate alloc] init];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
