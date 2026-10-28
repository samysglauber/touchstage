#import <Cocoa/Cocoa.h>
#import "EditorCanvasView.h"
#import "InspectorView.h"
#import "AirTabBarView.h"
#import "LayoutModel.h"

@interface EditorWindowController : NSWindowController <EditorCanvasDelegate, InspectorDelegate, AirTabBarDelegate>
@property (nonatomic, strong) LayoutModel *layout;

- (void)showEditor;
- (void)showLauncherSheet;
- (IBAction)onNewLayoutClicked:(id)sender;
- (IBAction)onOpenLayoutClicked:(id)sender;
- (IBAction)onSaveLayoutClicked:(id)sender;
- (IBAction)onSavePresetClicked:(id)sender;
@end
