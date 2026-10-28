#import <Cocoa/Cocoa.h>
#import "LayoutModel.h"

@protocol EditorCanvasDelegate <NSObject>
- (void)canvasDidSelectControl:(MidiControlModel *)control;
- (void)canvasDidChangeControl:(MidiControlModel *)control;
- (void)canvasDidDeleteControl:(MidiControlModel *)control;
@end

@interface EditorCanvasView : NSView
@property (nonatomic, strong) LayoutModel *layout;
@property (nonatomic, strong) MidiControlModel *selectedControl;
@property (nonatomic, weak) id<EditorCanvasDelegate> delegate;

- (void)addControlOfType:(NSString *)type atPoint:(NSPoint)point;
- (void)duplicateSelected;
- (void)deleteSelected;
@end
