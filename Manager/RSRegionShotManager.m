#import "RSRegionShotManager.h"
#import "../Capture/RSScreenCapture.h"
#import "../Floating/RSFloatingImageView.h"
#import "../Floating/RSFloatingWindow.h"
#import "../Selection/RSSelectionWindow.h"
#import "../AI/RSChatController.h"
#import <Photos/Photos.h>

@interface RSRegionShotManager () <RSFloatingImageViewDelegate>
@property (nonatomic, getter=isCapturing) BOOL capturing;
@property (nonatomic, getter=isInternalCapture) BOOL internalCapture;
@property (nonatomic, strong, nullable) UIImage *frozenImage;
@property (nonatomic, strong, nullable) RSSelectionWindow *selectionWindow;
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
    [self.selectionWindow dismiss];
    self.selectionWindow = nil;
    self.frozenImage = nil;
    self.internalCapture = NO;
    self.capturing = NO;
    NSLog(@"[RegionShot] selection cancelled");
}

- (void)createFloatingSnap:(UIImage *)image windowScene:(UIWindowScene *)scene {
    if (!self.floatingWindow) {
        self.floatingWindow = scene ? [[RSFloatingWindow alloc] initWithWindowScene:scene]
                                    : [[RSFloatingWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        self.floatingWindow.hidden = NO;
    }
    CGSize screen = self.floatingWindow.bounds.size;
    CGFloat factor = MIN(MIN(260.0 / image.size.width, 320.0 / image.size.height), 1.0);
    CGSize size = CGSizeMake(MAX(80, image.size.width * factor), MAX(80, image.size.height * factor));
    RSFloatingImageView *snap = [[RSFloatingImageView alloc] initWithCroppedImage:image];
    snap.bounds = (CGRect){CGPointZero, size};
    CGFloat offset = (self.mutableSnaps.count % 5) * 18.0;
    snap.center = CGPointMake(screen.width - size.width / 2.0 - 16 - offset,
                              self.floatingWindow.safeAreaInsets.top + size.height / 2.0 + 70 + offset);
    snap.actionDelegate = self;
    [self.floatingWindow.rootViewController.view addSubview:snap];
    [self.mutableSnaps addObject:snap];
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
    }
}

- (void)saveImage:(UIImage *)image {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if (status == PHAuthorizationStatusNotDetermined) {
        __weak typeof(self) weakSelf = self;
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (result == PHAuthorizationStatusAuthorized || result == PHAuthorizationStatusLimited)
                    [weakSelf saveImage:image];
                else
                    NSLog(@"[RegionShot] photo permission denied");
            });
        }];
        return;
    }
    if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
        NSLog(@"[RegionShot] photo permission denied");
        return;
    }
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromImage:image];
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"[RegionShot] photo save %@%@", success ? @"succeeded" : @"failed",
                  error ? [NSString stringWithFormat:@": %@", error] : @"");
        });
    }];
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
