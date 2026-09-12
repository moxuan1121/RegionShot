#import <UIKit/UIKit.h>

@interface RSChatCameraController : UIViewController
+ (BOOL)isVisible;
+ (void)showInScene:(UIWindowScene *)scene completion:(void (^)(UIImage *image))completion;
@end
