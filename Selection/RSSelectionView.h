#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface RSSelectionView : UIView
@property (nonatomic, readonly) CGRect selectionRect;
@property (nonatomic, readonly) BOOL hasValidSelection;
@property (nonatomic, copy, nullable) dispatch_block_t doubleTapHandler;
@property (nonatomic, copy, nullable) dispatch_block_t cancelHandler;
@property (nonatomic, copy, nullable) void (^selectionChanged)(BOOL dragging);
- (void)selectAll;
@end
NS_ASSUME_NONNULL_END
