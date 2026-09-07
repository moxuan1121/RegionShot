#import <Foundation/Foundation.h>

@class RSFloatingImageView;

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
- (void)hideAllSnaps;
- (void)showAllSnaps;
- (void)closeAllSnaps;
- (void)showHistory;

@end

NS_ASSUME_NONNULL_END
