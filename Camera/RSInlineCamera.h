#import <UIKit/UIKit.h>
@interface RSInlineCamera : UIViewController
@property(nonatomic, copy) void (^completion)(UIImage *image);
- (void)stop;
@end
