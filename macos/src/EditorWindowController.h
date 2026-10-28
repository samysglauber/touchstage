#import <Cocoa/Cocoa.h>
#import "EditorCanvasView.h"
#import "InspectorView.h"
#import "LayoutModel.h"

@protocol EditorWindowDelegate <NSObject>
- (void)editorDidUpdateLayout:(LayoutModel *)layout;
- (void)editorDidRequestSendLayoutToPhone:(LayoutModel *)layout;
@end

@interface EditorWindowController : NSWindowController <EditorCanvasDelegate, InspectorDelegate>
@property (nonatomic, weak) id<EditorWindowDelegate> editorDelegate;
@property (nonatomic, strong) LayoutModel *layout;

- (void)showEditor;
@end
