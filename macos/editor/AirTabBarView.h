#import <Cocoa/Cocoa.h>
#import "LayoutModel.h"

@protocol AirTabBarDelegate <NSObject>
- (void)tabBarDidSelectPageIndex:(NSInteger)index;
- (void)tabBarDidRequestAddPage;
- (void)tabBarDidRequestDeletePageIndex:(NSInteger)index;
- (void)tabBarDidRenamePageIndex:(NSInteger)index toName:(NSString *)newName;
@end

@interface AirTabBarView : NSView
@property (nonatomic, weak) id<AirTabBarDelegate> delegate;
@property (nonatomic, weak) LayoutModel *layout;

- (void)reloadTabs;
@end
