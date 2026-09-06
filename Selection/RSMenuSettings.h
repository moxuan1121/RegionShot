#import <UIKit/UIKit.h>

NSArray<NSDictionary *> *RSSelectionMenuItems(void);
UIImage *RSSelectionMenuIcon(NSDictionary *item);
CGFloat RSSelectionMenuSize(BOOL icon);
BOOL RSSelectionMenuHideNames(void);

@interface RSMenuSettings : UITableViewController
@property (nonatomic, copy) dispatch_block_t onClose;
@end
