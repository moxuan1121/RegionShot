#import <UIKit/UIKit.h>

@interface RSChatController : UIViewController
+ (void)showImage:(UIImage *)image scene:(UIWindowScene *)scene;
+ (void)showText:(NSString *)text scene:(UIWindowScene *)scene sendImmediately:(BOOL)send;
+ (void)showImage:(UIImage *)image scene:(UIWindowScene *)scene persona:(NSDictionary *)persona;
+ (void)showServiceSettings;
- (void)minimize;
@end
