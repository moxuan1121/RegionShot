#import "RSRegionShotManager.h"
#import "../Capture/RSScreenCapture.h"
#import "../Floating/RSFloatingImageView.h"
#import "../Floating/RSFloatingWindow.h"
#import "../Selection/RSSelectionWindow.h"
#import "../AI/RSChatController.h"
#import "../Capture/RSLongCaptureWindow.h"
#import <Photos/Photos.h>
#import "../Preferences/RSOptions.h"
#import "../History/RSHistoryController.h"

@interface RSRegionShotManager () <RSFloatingImageViewDelegate>
@property (nonatomic, getter=isCapturing) BOOL capturing;
@property (nonatomic, getter=isInternalCapture) BOOL internalCapture;
@property (nonatomic, strong, nullable) UIImage *frozenImage;
@property (nonatomic, strong, nullable) RSSelectionWindow *selectionWindow;
@property (nonatomic, strong, nullable) RSFloatingWindow *floatingWindow;
@property (nonatomic, strong) NSMutableArray<RSFloatingImageView *> *mutableSnaps;
@property (nonatomic, strong) RSLongCaptureWindow *longWindow;
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

- (BOOL)beginCapture {
    if (![NSThread isMainThread]) {
        __block BOOL started;
        dispatch_sync(dispatch_get_main_queue(), ^{ started = [self beginCapture]; });
        return started;
    }
    if (self.capturing) return YES;
    NSLog(@"[RegionShot] beginCapture");
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
    NSLog(@"[RegionShot] frozen image captured");
    self.frozenImage = image;

    __weak typeof(self) weakSelf = self;
    self.selectionWindow = [[RSSelectionWindow alloc] initWithImage:image confirm:^(CGRect rect, CGSize displaySize) {
        [weakSelf confirmSelection:rect displaySize:displaySize];
    } cancel:^{
        [weakSelf cancelCapture];
    }];
    self.selectionWindow.longCaptureHandler = ^(CGRect rect, CGSize size) { [weakSelf beginLongCapture:rect size:size]; };
    self.selectionWindow.editedImageHandler = ^(UIImage *edited) {
        RSRegionShotManager *manager = weakSelf;
        UIWindowScene *scene = manager.selectionWindow.windowScene;
        [manager cancelCapture];
        [manager createFloatingSnap:edited windowScene:scene];
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
        NSLog(@"[RegionShot] selection confirmed");
        [self createFloatingSnap:cropped windowScene:scene];
        RSFloatingImageView *snap = self.mutableSnaps.lastObject;
        // Match the reference: the cropped region becomes a floating image in place.
        if (snap && CGSizeEqualToSize(displaySize, self.floatingWindow.bounds.size)) {
            snap.bounds = (CGRect){CGPointZero, rect.size}; snap.center = CGPointMake(CGRectGetMidX(rect), CGRectGetMidY(rect));
            snap.alpha = 0;
            [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.12 animations:^{ snap.alpha = [RSOption(@"FloatOpacity") doubleValue]; }];
        }
    } else {
        NSLog(@"[RegionShot] selection crop failed");
    }
    self.capturing = NO;
}

- (void)cancelCapture {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self cancelCapture]; });
        return;
    }
    [self.longWindow cancel];
    self.longWindow = nil;
    [self.selectionWindow dismiss];
    self.selectionWindow = nil;
    self.frozenImage = nil;
    self.internalCapture = NO;
    self.capturing = NO;
    NSLog(@"[RegionShot] selection cancelled");
}

- (void)beginLongCapture:(CGRect)rect size:(CGSize)size {
    UIWindowScene *scene = self.selectionWindow.windowScene;
    [self.selectionWindow dismiss]; self.selectionWindow = nil; self.frozenImage = nil;
    self.floatingWindow.hidden = YES;
    __weak typeof(self) weakSelf = self;
    self.longWindow = [[RSLongCaptureWindow alloc] initWithScene:scene rect:rect displaySize:size capture:^UIImage *{
        RSRegionShotManager *manager = weakSelf;
        if (!manager) return nil;
        @try {
            manager.internalCapture = YES;
            return [RSScreenCapture captureScreen];
        } @finally { manager.internalCapture = NO; }
    } completion:^(UIImage *image) {
        RSRegionShotManager *manager = weakSelf;
        manager.longWindow = nil; manager.capturing = NO;
        manager.floatingWindow.hidden = NO;
        if (image) [manager createFloatingSnap:image windowScene:scene];
    }];
    [self.longWindow start];
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
    CGSize screen = self.floatingWindow.bounds.size;
    CGFloat factor = MIN(MIN([RSOption(@"FloatWidth") doubleValue] / image.size.width, 320.0 / image.size.height), 1.0);
    CGSize size = CGSizeMake(MAX(80, image.size.width * factor), MAX(80, image.size.height * factor));
    RSFloatingImageView *snap = [[RSFloatingImageView alloc] initWithCroppedImage:image];
    snap.bounds = (CGRect){CGPointZero, size};
    CGFloat offset = (self.mutableSnaps.count % 5) * 18.0;
    snap.center = CGPointMake(screen.width - size.width / 2.0 - 16 - offset,
                              self.floatingWindow.safeAreaInsets.top + size.height / 2.0 + 70 + offset);
    snap.actionDelegate = self;
    [self.floatingWindow.rootViewController.view addSubview:snap];
    [self.mutableSnaps addObject:snap];
    if (record) {
        __weak typeof(self) weakSelf = self;
        [RSHistoryController recordImage:image completion:^(NSError *error) { if (error) [weakSelf notice:error.localizedDescription]; }];
    }
    if ([RSOption(@"CaptureHaptic") boolValue]) [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    NSLog(@"[RegionShot] floating snap created");
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
    if (![self.mutableSnaps containsObject:snap]) return;
    [self.mutableSnaps removeObject:snap];
    snap.actionDelegate = nil;
    snap.image = nil;
    [snap removeFromSuperview];
    if (self.mutableSnaps.count == 0) {
        self.floatingWindow.hidden = YES;
        self.floatingWindow.rootViewController = nil;
        self.floatingWindow = nil;
    }
    NSLog(@"[RegionShot] floating snap removed");
}

- (void)hideAllSnaps {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self hideAllSnaps]; });
        return;
    }
    for (RSFloatingImageView *snap in self.mutableSnaps) snap.hidden = YES;
}

- (void)showAllSnaps {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self showAllSnaps]; });
        return;
    }
    for (RSFloatingImageView *snap in self.mutableSnaps) snap.hidden = NO;
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
            break;
        case RSFloatingActionSave:
            [self saveImage:image];
            break;
        case RSFloatingActionShare:
            [self shareImage:image];
            break;
        case RSFloatingActionHide:
            snap.hidden = YES;
            break;
        case RSFloatingActionCloseAll:
            [self closeAllSnaps];
            break;
        case RSFloatingActionAI:
            [RSChatController showImage:image scene:snap.window.windowScene];
            break;
        case RSFloatingActionCloseCurrent: [self removeSnap:snap]; break;
        case RSFloatingActionHistory: [self showHistory]; break;
        case RSFloatingActionRestoreAll: [self showAllSnaps]; break;
    }
}

- (void)saveImage:(UIImage *)image {
    if ([RSOption(@"CopyOnSave") boolValue] || [RSOption(@"CopyOnly") boolValue]) UIPasteboard.generalPasteboard.image = image;
    if ([RSOption(@"CopyOnly") boolValue]) { [self notice:@"已复制图片"]; return; }
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if (status == PHAuthorizationStatusNotDetermined) {
        __weak typeof(self) weakSelf = self;
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (result == PHAuthorizationStatusAuthorized || result == PHAuthorizationStatusLimited)
                    [weakSelf saveImage:image];
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
            NSLog(@"[RegionShot] photo save %@%@", success ? @"succeeded" : @"failed",
                  error ? [NSString stringWithFormat:@": %@", error] : @"");
            [self notice:success ? @"已保存到相册" : error.localizedDescription ?: @"保存失败，请重试。"];
        });
    }];
}
- (void)notice:(NSString *)message {
    UIView *view = self.floatingWindow.rootViewController.view;
    if (!view) { NSLog(@"[RegionShot] %@", message); return; }
    UILabel *label = [UILabel new]; label.text = message; label.numberOfLines = 0;
    label.textAlignment = NSTextAlignmentCenter; label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    label.textColor = UIColor.whiteColor; label.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.95];
    label.layer.cornerRadius = 12; label.clipsToBounds = YES;
    label.frame = CGRectMake(16, view.safeAreaInsets.top + 12, view.bounds.size.width - 32, 72);
    [view addSubview:label]; UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, message);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [label removeFromSuperview]; });
}

- (void)shareImage:(UIImage *)image {
    UIViewController *presenter = self.floatingWindow.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    if (!presenter.view.window) {
        NSLog(@"[RegionShot] no valid share presentation context");
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[image]
                                                                           applicationActivities:nil];
    [presenter presentViewController:activity animated:YES completion:nil];
}

@end
