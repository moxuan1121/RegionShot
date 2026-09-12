#import <UIKit/UIKit.h>

@interface RSChatController : UIViewController
+ (void)showImage:(UIImage *)image scene:(UIWindowScene *)scene;
+ (void)showText:(NSString *)text scene:(UIWindowScene *)scene sendImmediately:(BOOL)send;
+ (void)showText:(NSString *)text scene:(UIWindowScene *)scene persona:(NSDictionary *)persona;
+ (void)showImage:(UIImage *)image scene:(UIWindowScene *)scene persona:(NSDictionary *)persona;
+ (void)showServiceSettings;
+ (void)minimizeForLock;
- (void)minimize;
@end
