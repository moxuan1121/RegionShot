#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface RSScreenCapture : NSObject
+ (BOOL)isCaptureAvailable;
+ (nullable UIImage *)captureScreen;
+ (nullable UIImage *)cropImage:(UIImage *)image toRect:(CGRect)rect displaySize:(CGSize)displaySize;
@end
NS_ASSUME_NONNULL_END
