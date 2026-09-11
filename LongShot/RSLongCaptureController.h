#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RSLongCaptureMode) {
    RSLongCaptureModeRolling = 0,
    RSLongCaptureModeStep = 1,
    RSLongCaptureModeAutomatic = 2,
    RSLongCaptureModeConservativeStep = 3
};

@interface RSLongCaptureController : UIWindow
+ (instancetype)startWithScene:(nullable UIWindowScene *)scene
                          mode:(RSLongCaptureMode)mode
                    completion:(void (^)(UIWindowScene * _Nullable scene))completion
                        cancel:(dispatch_block_t)cancel;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
