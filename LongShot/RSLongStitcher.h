#import <UIKit/UIKit.h>

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
- (nullable UIImage *)finish:(NSError **)error;
- (void)cancel;
@end
