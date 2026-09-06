#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
@interface RSSelectionView : UIView
@property (nonatomic, readonly) CGRect selectionRect;
@property (nonatomic, readonly) BOOL hasValidSelection;
@end
NS_ASSUME_NONNULL_END
