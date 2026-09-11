#import <UIKit/UIKit.h>

@interface RSChatCameraController : UIViewController
+ (void)showInScene:(UIWindowScene *)scene completion:(void (^)(UIImage *image))completion;
@end
