#import <UIKit/UIKit.h>
@interface RSHistoryController : UITableViewController
+ (void)recordImage:(UIImage *)image completion:(void (^)(NSError *))completion;
+ (void)showWithRestore:(void (^)(UIImage *, UIWindowScene *))restore;
@end
