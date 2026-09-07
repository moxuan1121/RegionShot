#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface RSSelectionToolbar : UIView
@property (nonatomic, copy, nullable) dispatch_block_t captureHandler;
@property (nonatomic, copy, nullable) dispatch_block_t cancelHandler;
@property (nonatomic, copy, nullable) dispatch_block_t longCaptureHandler;
@property (nonatomic, copy, nullable) dispatch_block_t recognitionHandler;
@property (nonatomic, copy, nullable) dispatch_block_t editHandler;
@property (nonatomic, copy, nullable) dispatch_block_t aiHandler;
@property (nonatomic, copy, nullable) dispatch_block_t ocrHandler;
@property (nonatomic, copy, nullable) dispatch_block_t fullscreenHandler;
- (void)reloadButtons;
@end
NS_ASSUME_NONNULL_END
