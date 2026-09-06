#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, RSFloatingAction) {
    RSFloatingActionCopy,
    RSFloatingActionSave,
    RSFloatingActionShare,
    RSFloatingActionHide,
    RSFloatingActionCloseAll,
};

NS_ASSUME_NONNULL_BEGIN

@class RSFloatingImageView;
@protocol RSFloatingImageViewDelegate <NSObject>
- (void)floatingImageViewDidActivate:(RSFloatingImageView *)snap;
- (void)floatingImageViewDidRequestRemoval:(RSFloatingImageView *)snap;
- (void)floatingImageView:(RSFloatingImageView *)snap didRequestAction:(RSFloatingAction)action;
@end

@interface RSFloatingImageView : UIImageView
@property (nonatomic, weak) id<RSFloatingImageViewDelegate> actionDelegate;
@property (nonatomic, readonly) UIImage *croppedImage;
- (instancetype)initWithCroppedImage:(UIImage *)image;
@end
NS_ASSUME_NONNULL_END
