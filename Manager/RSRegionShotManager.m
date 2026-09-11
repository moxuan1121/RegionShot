#import "RSRegionShotManager.h"
#import "../Capture/RSScreenCapture.h"
#import "../Floating/RSFloatingImageView.h"
#import "../Floating/RSFloatingWindow.h"
#import "../Selection/RSSelectionWindow.h"
#import "../AI/RSChatController.h"
#import <Photos/Photos.h>
#import "../Preferences/RSOptions.h"
#import "../History/RSHistoryController.h"
#import "../Geometry/RSOrientation.h"
#import "../LongShot/RSLongCaptureController.h"

@interface RSRegionShotManager () <RSFloatingImageViewDelegate>
@property (nonatomic, getter=isCapturing) BOOL capturing;
@property (nonatomic, getter=isInternalCapture) BOOL internalCapture;
@property (nonatomic, strong, nullable) UIImage *frozenImage;
@property (nonatomic, strong, nullable) RSSelectionWindow *selectionWindow;
@property (nonatomic, strong, nullable) RSLongCaptureController *longCaptureWindow;
@property (nonatomic, strong, nullable) RSFloatingWindow *floatingWindow;
@property (nonatomic, strong) NSMutableArray<RSFloatingImageView *> *mutableSnaps;
@end

@implementation RSRegionShotManager

+ (instancetype)sharedManager {
    static RSRegionShotManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [RSRegionShotManager new];
        manager.mutableSnaps = [NSMutableArray array];
    });
    return manager;
}

- (NSArray<RSFloatingImageView *> *)activeSnaps { return self.mutableSnaps.copy; }

- (BOOL)isFrozenSelectionVisible { return self.selectionWindow && !self.selectionWindow.hidden; }

- (BOOL)beginCapture {
    if (![NSThread isMainThread]) {
        __block BOOL started;
        dispatch_sync(dispatch_get_main_queue(), ^{ started = [self beginCapture]; });
        return started;
    }
    if (self.capturing) return YES;

    self.capturing = YES;

    BOOL floatingWasVisible = self.floatingWindow && !self.floatingWindow.hidden;
    if (floatingWasVisible) self.floatingWindow.hidden = YES;
    UIImage *image = nil;
    @try {
        self.internalCapture = YES;
        image = [RSScreenCapture captureScreen];
    } @finally {
        self.internalCapture = NO;
        if (floatingWasVisible) self.floatingWindow.hidden = NO;
    }
    if (!image) {
        [self cancelCapture];
        return NO;
    }

    self.frozenImage = image;

    __weak typeof(self) weakSelf = self;
    self.selectionWindow = [[RSSelectionWindow alloc] initWithImage:image confirm:^(CGRect rect, CGSize displaySize) {
        [weakSelf confirmSelection:rect displaySize:displaySize];
    } cancel:^{
        [weakSelf cancelCapture];
    }];
    self.selectionWindow.editedImageHandler = ^(UIImage *edited) {
        RSRegionShotManager *manager = weakSelf;
        UIPasteboard.generalPasteboard.image = edited;
        [manager cancelCapture];
    };
    [self.selectionWindow show];
    return YES;
}

- (void)confirmSelection:(CGRect)rect displaySize:(CGSize)displaySize {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self confirmSelection:rect displaySize:displaySize]; });
        return;
    }
    UIImage *cropped = self.frozenImage ? [RSScreenCapture cropImage:self.frozenImage
                                                               toRect:rect
                                                          displaySize:displaySize] : nil;
    UIWindowScene *scene = self.selectionWindow.windowScene;
    [self.selectionWindow dismiss];
    self.selectionWindow = nil;
    self.frozenImage = nil;
    if (cropped) {

        [self createFloatingSnap:cropped windowScene:scene];
        RSFloatingImageView *snap = self.mutableSnaps.lastObject;
        // Match the reference: the cropped region becomes a floating image in place.
        if (snap && CGSizeEqualToSize(displaySize, self.floatingWindow.rootViewController.view.bounds.size)) {
            snap.bounds = (CGRect){CGPointZero, rect.size}; snap.center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));

        }
    } else {

    }
    self.capturing = NO;
}

- (void)cancelCapture {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self cancelCapture]; });
        return;
    }
    [self.selectionWindow dismiss];
    [self.longCaptureWindow stop];
    self.longCaptureWindow = nil;
    self.selectionWindow = nil;
    self.frozenImage = nil;
    self.internalCapture = NO;
    self.capturing = NO;

}

- (void)beginLongCapture {
    if (!NSThread.isMainThread) { dispatch_async(dispatch_get_main_queue(), ^{ [self beginLongCapture]; }); return; }
    UIWindowScene *scene = self.selectionWindow.windowScene;
    [self.selectionWindow dismiss]; self.selectionWindow = nil; self.frozenImage = nil;
    __weak typeof(self) weakSelf = self;
    self.longCaptureWindow = [RSLongCaptureController startWithScene:scene
        mode:[RSOption(@"LongCaptureMode") integerValue]
        completion:^(UIImage *image, UIWindowScene *resultScene) {
            RSRegionShotManager *manager = weakSelf; manager.longCaptureWindow = nil; manager.capturing = NO;
            [manager createFloatingSnap:image windowScene:resultScene];
        } cancel:^{
            RSRegionShotManager *manager = weakSelf; manager.longCaptureWindow = nil; manager.capturing = NO;
        }];
}

- (void)createFloatingSnap:(UIImage *)image windowScene:(UIWindowScene *)scene {
    [self createFloatingSnap:image windowScene:scene record:YES];
}
- (void)showHistory {
    [self cancelCapture];
    __weak typeof(self) weakSelf = self;
    [RSHistoryController showWithRestore:^(UIImage *image, UIWindowScene *scene) { [weakSelf createFloatingSnap:image windowScene:scene record:NO]; }];
}
- (void)createFloatingSnap:(UIImage *)image windowScene:(UIWindowScene *)scene record:(BOOL)record {
    if (!self.floatingWindow) {
        self.floatingWindow = scene ? [[RSFloatingWindow alloc] initWithWindowScene:scene]
                                    : [[RSFloatingWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.floatingWindow.hidden = NO;
    }
    RSApplyWindowOrientation(self.floatingWindow, RSActiveOrientation(scene));
    CGSize screen = self.floatingWindow.rootViewController.view.bounds.size;
    RSRectD fitted = RSFloatingSize(image.size.width, image.size.height, [RSOption(@"FloatWidth") doubleValue], 320);
    if (fitted.width <= 0 || fitted.height <= 0) return;
    CGSize size = CGSizeMake(fitted.width, fitted.height);
    RSFloatingImageView *snap = [[RSFloatingImageView alloc] initWithCroppedImage:image];
    snap.bounds = (CGRect){CGPointZero, size};
    CGFloat offset = (self.mutableSnaps.count % 5) * 18.0;
    snap.center = CGPointMake(screen.width - size.width / 2.0 - 16 - offset,
                              self.floatingWindow.safeAreaInsets.top + size.height / 2.0 + 70 + offset);
    if (!record) snap.center = CGPointMake(screen.width / 2, screen.height / 2);
    snap.actionDelegate = self;
    [self.floatingWindow.rootViewController.view addSubview:snap];
    [self.mutableSnaps addObject:snap];
    [snap setShadowVisible:NO];
    snap.alpha = 0;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    snap.transform = reduceMotion ? CGAffineTransformIdentity : CGAffineTransformMakeScale(0.96, 0.96);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!snap.userInteractionEnabled || !snap.superview) return;
        [snap layoutIfNeeded];
        [UIView animateWithDuration:reduceMotion ? 0 : 0.22 delay:0
            options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseOut
            animations:^{ snap.alpha = [RSOption(@"FloatOpacity") doubleValue]; snap.transform = CGAffineTransformIdentity; }
            completion:^(BOOL finished) { if (snap.superview) [snap setShadowVisible:YES]; }];
    });
    if (record) {
        __weak typeof(self) weakSelf = self;
        [RSHistoryController recordImage:image completion:^(NSError *error) { if (error) [weakSelf notice:error.localizedDescription]; }];
    }
    if ([RSOption(@"CaptureHaptic") boolValue]) [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];

}

- (void)bringSnapToFront:(RSFloatingImageView *)snap {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self bringSnapToFront:snap]; });
        return;
    }
    if (![self.mutableSnaps containsObject:snap]) return;
    [snap.superview bringSubviewToFront:snap];
    [self.mutableSnaps removeObject:snap];
    [self.mutableSnaps addObject:snap];
}

- (void)removeSnap:(RSFloatingImageView *)snap {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self removeSnap:snap]; });
        return;
    }
    if (![self.mutableSnaps containsObject:snap] || !snap.userInteractionEnabled) return;
    snap.userInteractionEnabled = NO;
    snap.actionDelegate = nil;
    [snap setShadowVisible:NO];
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    [UIView animateWithDuration:reduceMotion ? 0 : 0.18 delay:0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn
        animations:^{
            snap.alpha = 0;
            if (!reduceMotion) snap.transform = CGAffineTransformScale(snap.transform, 0.96, 0.96);
        } completion:^(BOOL finished) {
            [self.mutableSnaps removeObject:snap];
            snap.image = nil; [snap removeFromSuperview];
            if (self.mutableSnaps.count == 0) {
                self.floatingWindow.hidden = YES;
                self.floatingWindow.rootViewController = nil;
                self.floatingWindow = nil;
            }
        }];
}

- (void)closeAllSnaps {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self closeAllSnaps]; });
        return;
    }
    for (RSFloatingImageView *snap in self.mutableSnaps.copy) [self removeSnap:snap];
}

- (void)floatingImageViewDidActivate:(RSFloatingImageView *)snap {
    [self bringSnapToFront:snap];
}

- (void)floatingImageViewDidRequestRemoval:(RSFloatingImageView *)snap {
    [self removeSnap:snap];
}

- (void)floatingImageView:(RSFloatingImageView *)snap didRequestAction:(RSFloatingAction)action {
    UIImage *image = snap.croppedImage;
    if (!image) return;
    switch (action) {
        case RSFloatingActionCopy:
            UIPasteboard.generalPasteboard.image = image;
            [self removeSnap:snap];
            break;
        case RSFloatingActionSave: {
            [self saveImage:image completion:^{ [self removeSnap:snap]; }];
            break;
        }
        case RSFloatingActionShare: {
            [self shareImage:image completion:^{ [self removeSnap:snap]; }];
            break;
        }
        case RSFloatingActionCloseAll:
            [self closeAllSnaps];
            break;
        case RSFloatingActionAI:
            [RSChatController showImage:image scene:snap.window.windowScene];
            [self removeSnap:snap];
            break;
        case RSFloatingActionCloseCurrent: [self removeSnap:snap]; break;
        case RSFloatingActionHistory: [self showHistory]; break;
    }
}

- (void)takeNativeScreenshot {
    [self cancelCapture];
    // Let the compositor remove the frozen overlay before the system captures.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        extern BOOL RSRequestNativeScreenshot(void);
        if (!RSRequestNativeScreenshot()) [self notice:@"系统截屏入口不可用。"];
    });
}

- (void)saveImage:(UIImage *)image { [self saveImage:image completion:nil]; }
- (void)saveImage:(UIImage *)image completion:(dispatch_block_t)completion {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if (status == PHAuthorizationStatusNotDetermined) {
        __weak typeof(self) weakSelf = self;
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (result == PHAuthorizationStatusAuthorized || result == PHAuthorizationStatusLimited)
                    [weakSelf saveImage:image completion:completion];
                else
                    [weakSelf notice:@"未获得相册写入权限，请在系统设置中允许访问相册。"];
            });
        }];
        return;
    }
    if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
        [self notice:@"未获得相册写入权限，请在系统设置中允许访问相册。"];
        return;
    }
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromImage:image];
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{

            [self notice:success ? @"已保存到相册" : error.localizedDescription ?: @"保存失败，请重试。"];
            if (success && completion) completion();
        });
    }];
}
- (void)notice:(NSString *)message {
    UIView *view = self.floatingWindow.rootViewController.view;
    if (!view) {  return; }
    UILabel *label = [UILabel new]; label.text = message; label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter; label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = UIColor.whiteColor; label.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    label.layer.cornerRadius = 12; label.clipsToBounds = YES;
    label.frame = CGRectMake(16, view.safeAreaInsets.top + 12, view.bounds.size.width - 32, 72);
    [view addSubview:label]; UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [label removeFromSuperview]; });
}

- (void)shareImage:(UIImage *)image completion:(dispatch_block_t)completion {
    UIViewController *presenter = self.floatingWindow.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter.view.window) {

        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[image]
                                                                           applicationActivities:nil];
    activity.popoverPresentationController.sourceView = presenter.view;
    activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
    activity.completionWithItemsHandler = ^(UIActivityType type, BOOL completed, NSArray *items, NSError *error) {
        if (completed && !error && completion) dispatch_async(dispatch_get_main_queue(), completion);
    };
    [presenter presentViewController:activity animated:YES completion:nil];
}

@end
