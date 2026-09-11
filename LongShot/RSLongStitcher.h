#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, RSLongAppendResult) {
    RSLongAppendResultAdded,
    RSLongAppendResultUnchanged,
    RSLongAppendResultUncertain,
    RSLongAppendResultLimit
};

@interface RSLongStitcher : NSObject
@property (nonatomic, readonly) NSUInteger frameCount;
@property (nonatomic, readonly) CGFloat estimatedHeight;
- (instancetype)initWithTopInset:(CGFloat)topInset;
- (RSLongAppendResult)appendImage:(UIImage *)image;
- (nullable NSURL *)finishToURL:(NSError * _Nullable * _Nullable)error;
- (nullable UIImage *)finish:(NSError * _Nullable * _Nullable)error;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
