#import <Foundation/Foundation.h>

@class RSFloatingImageView, UIImage, UIWindowScene;

NS_ASSUME_NONNULL_BEGIN

@interface RSRegionShotManager : NSObject

@property (nonatomic, readonly, getter=isCapturing) BOOL capturing;
@property (nonatomic, readonly, getter=isInternalCapture) BOOL internalCapture;
@property (nonatomic, readonly) NSArray<RSFloatingImageView *> *activeSnaps;

+ (instancetype)sharedManager;
- (BOOL)beginCapture;
- (void)cancelCapture;
- (void)bringSnapToFront:(RSFloatingImageView *)snap;
- (void)removeSnap:(RSFloatingImageView *)snap;
- (void)closeAllSnaps;
- (void)showHistory;
- (void)saveImage:(UIImage *)image;
- (void)saveScreenshot:(UIImage *)image scene:(nullable UIWindowScene *)scene;
- (BOOL)isFrozenSelectionVisible;

@end

NS_ASSUME_NONNULL_END
