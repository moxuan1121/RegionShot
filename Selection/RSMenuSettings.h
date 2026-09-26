#import <UIKit/UIKit.h>

NSArray<NSDictionary *> *RSSelectionMenuItems(void);
NSArray<NSDictionary *> *RSFloatingMenuItems(void);
NSArray<NSDictionary *> *RSFrozenMenuItems(void);
UIImage *RSSelectionMenuIcon(NSDictionary *item);
CGFloat RSSelectionMenuSize(BOOL icon);
BOOL RSSelectionMenuHideNames(void);

@interface RSMenuSettings : UITableViewController
@property (nonatomic) BOOL floatingMenu;
@property (nonatomic) BOOL frozenMenu;
@property (nonatomic, copy) dispatch_block_t onClose;
@end
