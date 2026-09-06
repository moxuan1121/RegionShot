#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface RSSelectionToolbar : UIView
@property (nonatomic, copy, nullable) dispatch_block_t captureHandler;
@property (nonatomic, copy, nullable) dispatch_block_t cancelHandler;
@end
NS_ASSUME_NONNULL_END
