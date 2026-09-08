// Adapted from KeyboardAI-RootHide 23c761e, GPL-3.0; see THIRD_PARTY.md.
// Adapted from Kayoko, GPL-3.0; see THIRD_PARTY.md.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RSInputAnchoredMenuView : UIControl

@property(nonatomic, copy, nullable) dispatch_block_t onDismiss;
@property(nonatomic, assign) CGFloat menuWidth;
@property(nonatomic, assign) BOOL centersTitles;
@property(nonatomic, assign) BOOL presentsBelowSource;
@property(nonatomic, assign) BOOL animatesDismissal;

- (void)addItemWithTitle:(NSString *)title
                   image:(nullable UIImage *)image
             destructive:(BOOL)destructive
                 handler:(dispatch_block_t)handler;
- (void)presentFromView:(UIView *)sourceView inView:(UIView *)hostView;
- (void)trackGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer;
- (void)dismiss;

@end

NS_ASSUME_NONNULL_END
