#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface RSSelectionToolbar : UIView
@property (nonatomic) BOOL selectionActive;
@property (nonatomic, copy, nullable) dispatch_block_t captureHandler;
@property (nonatomic, copy, nullable) dispatch_block_t cancelHandler;
@property (nonatomic, copy, nullable) dispatch_block_t recognitionHandler;
@property (nonatomic, copy, nullable) dispatch_block_t editHandler;
@property (nonatomic, copy, nullable) dispatch_block_t aiHandler;
@property (nonatomic, copy, nullable) dispatch_block_t copyHandler;
@property (nonatomic, copy, nullable) dispatch_block_t saveHandler;
@property (nonatomic, copy, nullable) dispatch_block_t fullscreenHandler;
@property (nonatomic, copy, nullable) dispatch_block_t historyHandler;
- (void)reloadButtons;
@property (nonatomic, copy, nullable) void (^personaHandler)(NSDictionary *persona);
@end
NS_ASSUME_NONNULL_END
