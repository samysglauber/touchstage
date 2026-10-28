#import <Cocoa/Cocoa.h>
#import "LayoutModel.h"

@protocol InspectorDelegate <NSObject>
@optional
- (void)inspectorWillChangeControl:(MidiControlModel *)control;
@required
- (void)inspectorDidUpdateControl:(MidiControlModel *)control;
- (void)inspectorDidRequestDuplicate:(MidiControlModel *)control;
- (void)inspectorDidRequestDelete:(MidiControlModel *)control;
@end

@interface InspectorView : NSView
@property (nonatomic, weak) id<InspectorDelegate> delegate;
@property (nonatomic, strong) MidiControlModel *currentControl;

- (void)bindControl:(MidiControlModel *)control;
- (void)refreshValues;
@end
