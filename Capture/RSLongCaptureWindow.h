#import <UIKit/UIKit.h>

@interface RSLongCaptureWindow : UIWindow
- (instancetype)initWithScene:(UIWindowScene *)scene rect:(CGRect)rect displaySize:(CGSize)size
                       capture:(UIImage *(^)(void))capture
                    completion:(void (^)(UIImage *image))completion;
- (void)start;
- (void)cancel;
@end
