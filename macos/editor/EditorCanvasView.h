#import <Cocoa/Cocoa.h>
#import "LayoutModel.h"

@protocol EditorCanvasDelegate <NSObject>
- (void)canvasDidSelectControl:(MidiControlModel *)control;
- (void)canvasDidChangeControl:(MidiControlModel *)control;
- (void)canvasDidDeleteControl:(MidiControlModel *)control;
@end

@interface EditorCanvasView : NSView
@property (nonatomic, strong) LayoutModel *layout;
@property (nonatomic, strong) NSMutableArray<MidiControlModel *> *selectedControls;
@property (nonatomic, strong) MidiControlModel *selectedControl;
@property (nonatomic, assign) BOOL snapToGrid;
@property (nonatomic, weak) id<EditorCanvasDelegate> delegate;

- (void)selectAllControls;
- (void)clearSelection;
- (void)addControlOfType:(NSString *)type atPoint:(NSPoint)point;
- (void)addControlOfTypeAtCenter:(NSString *)type;
- (void)duplicateSelected;
- (void)deleteSelected;
- (void)copySelected;
- (void)pasteCopied;
- (void)undo;
- (void)redo;
- (void)pushUndoSnapshot;
- (void)undo:(id)sender;
- (void)redo:(id)sender;
- (void)copy:(id)sender;
- (void)paste:(id)sender;
- (void)selectAll:(id)sender;
- (void)deleteSelected:(id)sender;
- (void)bringSelectedToFront;
- (void)sendSelectedToBack;
- (void)toggleSnapToGrid:(id)sender;
@end
