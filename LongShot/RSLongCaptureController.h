#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, RSLongCaptureMode) {
    RSLongCaptureModeRolling = 0,
    RSLongCaptureModeStep = 1,
    RSLongCaptureModeAutomatic = 2
};

@interface RSLongCaptureController : UIWindow
+ (instancetype)startWithScene:(nullable UIWindowScene *)scene
                          mode:(RSLongCaptureMode)mode
                    completion:(void (^)(UIImage *image, UIWindowScene * _Nullable scene))completion
                        cancel:(dispatch_block_t)cancel;
- (void)stop;
@end
