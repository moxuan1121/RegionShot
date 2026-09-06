#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface RSSelectionWindow : UIWindow
@property (nonatomic, readonly) CGRect selectionRect;
@property (nonatomic, readonly) CGSize displaySize;
@property (nonatomic, copy, nullable) void (^longCaptureHandler)(CGRect rect, CGSize size);
- (instancetype)initWithImage:(UIImage *)image
                       confirm:(void (^)(CGRect selectionRect, CGSize displaySize))confirm
                        cancel:(dispatch_block_t)cancel;
- (void)show;
- (void)dismiss;
@end
NS_ASSUME_NONNULL_END
