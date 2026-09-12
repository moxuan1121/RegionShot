#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RSLongCaptureMode) {
    RSLongCaptureModeManual = 2,
    RSLongCaptureModeButtonStep = 3
};

@interface RSLongCaptureController : UIWindow
+ (instancetype)startWithScene:(nullable UIWindowScene *)scene
                          mode:(RSLongCaptureMode)mode
                    completion:(void (^)(UIWindowScene * _Nullable scene))completion
                        cancel:(dispatch_block_t)cancel;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
