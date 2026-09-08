#import "RSSelectionWindow.h"
#import "RSSelectionToolbar.h"
#import "RSSelectionView.h"
#import "RSMenuSettings.h"
#import "RSRecognitionController.h"
#import "RSImageEditor.h"
#import "../Capture/RSScreenCapture.h"
#import "../AI/RSChatController.h"
#import "../Manager/RSRegionShotManager.h"
#import "../Geometry/RSGeometry.h"
#import "../Geometry/RSOrientation.h"
#import "../Preferences/RSOptions.h"

@interface RSSelectionController : UIViewController
@property (nonatomic) UIInterfaceOrientation captureOrientation;
@end
@implementation RSSelectionController
- (BOOL)shouldAutorotate { return NO; }
- (BOOL)autorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return self.captureOrientation;
}
- (UIRectEdge)preferredScreenEdgesDeferringSystemGestures { return UIRectEdgeAll; }
- (UIViewController *)childViewControllerForScreenEdgesDeferringSystemGestures { return nil; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
@end

@interface RSSelectionWindow ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) RSSelectionView *selectionView;
@property (nonatomic, strong) RSSelectionToolbar *toolbar;
@property (nonatomic, strong) UIVisualEffectView *toolbarBlur;
@property (nonatomic, weak) UIWindow *previousKeyWindow;
@property (nonatomic, strong) UIScrollView *toolbarScroll;
@property (nonatomic, strong) id systemGestureAssertion;
@property (nonatomic) UIInterfaceOrientation captureOrientation;
@end

@implementation RSSelectionWindow

- (BOOL)autorotates { return NO; }

+ (UIWindow *)currentKeyWindow {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (window.isKeyWindow) return window;
    }
    return nil;
}

- (instancetype)initWithImage:(UIImage *)image
                       confirm:(void (^)(CGRect, CGSize))confirm
                        cancel:(dispatch_block_t)cancel {
    UIWindowScene *scene = [RSSelectionWindow currentKeyWindow].windowScene;
    self = scene ? [super initWithWindowScene:scene] : [super initWithFrame:UIScreen.mainScreen.bounds];
    if (self) {
        self.frame = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
        self.windowLevel = UIWindowLevelAlert + 200;
        self.backgroundColor = UIColor.blackColor;
        self.captureOrientation = RSActiveOrientation(scene);
        RSSelectionController *controller = [RSSelectionController new];
        controller.captureOrientation = self.captureOrientation;
        controller.view.backgroundColor = UIColor.blackColor;
        self.rootViewController = controller;

        _imageView = [[UIImageView alloc] initWithImage:image];
        _imageView.contentMode = UIViewContentModeScaleToFill;
        [controller.view addSubview:_imageView];
        _selectionView = [[RSSelectionView alloc] initWithFrame:controller.view.bounds];
        [controller.view addSubview:_selectionView];
        _toolbar = [[RSSelectionToolbar alloc] initWithFrame:CGRectZero];
        _toolbarScroll = [UIScrollView new];
        [controller.view addSubview:_toolbarScroll];
        _toolbarBlur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
        _toolbarBlur.userInteractionEnabled = NO;
        _toolbarBlur.clipsToBounds = YES;
        [_toolbarScroll addSubview:_toolbarBlur];
        [_toolbarScroll addSubview:_toolbar];
        __weak typeof(self) weakSelf = self;
        _selectionView.selectionChanged = ^(BOOL dragging) {
            RSSelectionWindow *window = weakSelf;
            BOOL selected = window.selectionView.hasValidSelection;
            if (window.toolbar.selectionActive != selected) {
                window.toolbar.selectionActive = selected; [window.toolbar reloadButtons];
            }
            window.toolbarScroll.hidden = dragging;
            [window setNeedsLayout];
        };
        _toolbar.captureHandler = ^{
            RSSelectionWindow *strongSelf = weakSelf;
            if (!strongSelf.selectionView.hasValidSelection) {
                UIImage *image = strongSelf.imageView.image;
                if (strongSelf.toolbar.cancelHandler) strongSelf.toolbar.cancelHandler();
                if (image) [RSRegionShotManager.sharedManager saveImage:image];
                return;
            }
            confirm(strongSelf.selectionRect, strongSelf.displaySize);
        };
        _toolbar.cancelHandler = cancel;
        _selectionView.cancelHandler = cancel;
        _selectionView.doubleTapHandler = ^{ if (weakSelf.toolbar.captureHandler) weakSelf.toolbar.captureHandler(); };
        _toolbar.fullscreenHandler = ^{ [weakSelf.selectionView selectAll]; };
        _toolbar.historyHandler = ^{ [RSRegionShotManager.sharedManager showHistory]; };
        _toolbar.copyHandler = ^{
            RSSelectionWindow *window = weakSelf;
            CGRect rect = window.selectionView.hasValidSelection ? window.selectionRect : window.selectionView.bounds;
            UIImage *image = [RSScreenCapture cropImage:window.imageView.image toRect:rect displaySize:window.displaySize];
            if (!image) return;
            UIPasteboard.generalPasteboard.image = image;
            if (window.toolbar.cancelHandler) window.toolbar.cancelHandler();
        };
        _toolbar.saveHandler = ^{
            RSSelectionWindow *window = weakSelf;
            if (!window.selectionView.hasValidSelection) return;
            UIImage *image = [RSScreenCapture cropImage:window.imageView.image toRect:window.selectionRect displaySize:window.displaySize];
            if (!image) return;
            if (window.toolbar.cancelHandler) window.toolbar.cancelHandler();
            [RSRegionShotManager.sharedManager saveImage:image];
        };
        _toolbar.aiHandler = ^{
            RSSelectionWindow *window = weakSelf;
            if (!window.selectionView.hasValidSelection) [window.selectionView selectAll];
            UIImage *cropped = [RSScreenCapture cropImage:window.imageView.image toRect:window.selectionRect displaySize:window.displaySize];
            UIWindowScene *scene = window.windowScene;
            if (cropped) { if (window.toolbar.cancelHandler) window.toolbar.cancelHandler(); [RSChatController showImage:cropped scene:scene]; }
        };
        _toolbar.personaHandler = ^(NSDictionary *persona) {
            RSSelectionWindow *window = weakSelf;
            if (!window.selectionView.hasValidSelection) return;
            UIImage *cropped = [RSScreenCapture cropImage:window.imageView.image toRect:window.selectionRect displaySize:window.displaySize];
            UIWindowScene *scene = window.windowScene;
            if (cropped) {
                if (window.toolbar.cancelHandler) window.toolbar.cancelHandler();
                [RSChatController showImage:cropped scene:scene persona:persona];
            }
        };
        _toolbar.recognitionHandler = ^{ [weakSelf recognizeSelection]; };
        _toolbar.editHandler = ^{ [weakSelf editSelection]; };
        _toolbar.longCaptureHandler = ^{
            RSSelectionWindow *window = weakSelf;
            if (!window.selectionView.hasValidSelection) [window.selectionView selectAll];
            if (window.longCaptureHandler)
                window.longCaptureHandler(window.selectionRect, window.displaySize);
        };
    }
    return self;
}

- (CGRect)selectionRect { return self.selectionView.selectionRect; }
- (CGSize)displaySize { return self.selectionView.bounds.size; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.rootViewController.view.bounds;
    UIEdgeInsets insets = self.rootViewController.view.safeAreaInsets;
    self.imageView.frame = bounds;
    self.selectionView.frame = bounds;
    CGFloat safeBottom = insets.bottom;
    CGFloat buttonWidth = MAX(44, RSSelectionMenuSize(YES) + 16);
    CGFloat width = MIN(CGRectGetWidth(bounds) - 32, MIN(396, self.toolbar.subviews.count * buttonWidth));
    CGFloat height = MAX(40, RSSelectionMenuSize(YES) + (RSSelectionMenuHideNames() ? 6 : 24));
    self.toolbarScroll.frame = CGRectMake((CGRectGetWidth(bounds) - width) / 2.0,
                                    CGRectGetHeight(bounds) - safeBottom - height - 12, width, height);
    if (self.selectionView.hasValidSelection) {
        CGRect rect = self.selectionRect;
        RSRectD safe = {16 + insets.left, insets.top + 8,
            bounds.size.width - insets.left - insets.right - 32,
            bounds.size.height - insets.top - insets.bottom - 20};
        RSRectD frame = RSToolbarFrame((RSRectD){rect.origin.x, rect.origin.y, rect.size.width, rect.size.height}, safe, width, height);
        self.toolbarScroll.frame = CGRectMake(frame.x, frame.y, frame.width, frame.height);
    }
    CGFloat contentWidth = MAX(width, self.toolbar.subviews.count * buttonWidth);
    self.toolbarBlur.frame = CGRectMake(0, 0, contentWidth, height);
    self.toolbarBlur.layer.cornerRadius = height / 2.0;
    self.toolbarBlur.alpha = [RSOption(@"MenuBlurOpacity") doubleValue];
    self.toolbar.frame = CGRectMake(0, 0, contentWidth, height);
    self.toolbarScroll.contentSize = self.toolbar.bounds.size;
    [self bringSubviewToFront:self.rootViewController.view];
    [self.rootViewController.view bringSubviewToFront:self.toolbarScroll];
}

- (void)recognizeSelection {
    if (!self.selectionView.hasValidSelection) [self.selectionView selectAll];
    UIImage *image = [RSScreenCapture cropImage:self.imageView.image toRect:self.selectionRect displaySize:self.displaySize];
    if (!image) return;
    RSRecognitionController *result = [[RSRecognitionController alloc] initWithImage:image];
    __weak typeof(self) weakSelf = self;
    result.onForward = ^{ if (weakSelf.toolbar.cancelHandler) weakSelf.toolbar.cancelHandler(); };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:result];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self.rootViewController presentViewController:navigation animated:YES completion:nil];
}

- (void)editSelection {
    if (self.rootViewController.presentedViewController) return;
    if (!self.selectionView.hasValidSelection) [self.selectionView selectAll];
    UIImage *image = [RSScreenCapture cropImage:self.imageView.image toRect:self.selectionRect displaySize:self.displaySize];
    if (!image) return;
    __weak typeof(self) weakSelf = self;
    RSImageEditor *editor = [[RSImageEditor alloc] initWithImage:image completion:^(UIImage *edited) {
        RSSelectionWindow *window = weakSelf;
        if (window.editedImageHandler) window.editedImageHandler(edited);
    }];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self.rootViewController presentViewController:navigation animated:YES completion:nil];
}

- (void)show {
    self.previousKeyWindow = [RSSelectionWindow currentKeyWindow];
    Class managerClass = NSClassFromString(@"SBSystemGestureManager");
    SEL mainDisplay = NSSelectorFromString(@"mainDisplayManager");
    SEL acquire = NSSelectorFromString(@"acquireSystemGestureDisableAssertionForReason:exceptSystemGestureTypes:");
    id manager = [managerClass respondsToSelector:mainDisplay] ? ((id (*)(id, SEL))objc_msgSend)(managerClass, mainDisplay) : nil;
    if ([manager respondsToSelector:acquire])
        self.systemGestureAssertion = ((id (*)(id, SEL, id, id))objc_msgSend)(manager, acquire, @"RegionShot frozen selection", [NSSet set]);
    RSApplyWindowOrientation(self, self.captureOrientation);
    self.hidden = NO;
    [self makeKeyAndVisible];
    RSApplyWindowOrientation(self, self.captureOrientation);
    [self setNeedsLayout];
    [self layoutIfNeeded];
    NSLog(@"[RegionShot] freeze orientation=%ld window=%@ canvas=%@ systemGestureAssertion=%@", (long)self.captureOrientation, NSStringFromCGRect(self.bounds), NSStringFromCGRect(self.selectionView.bounds), self.systemGestureAssertion ? @"active" : @"unavailable");
    [self.rootViewController setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
}

- (BOOL)_shouldCreateScreenEdgesDeferringGestureRecognizer { return YES; }
- (BOOL)_containedGestureRecognizersShouldRespectGestureServerInstructions { return NO; }
- (BOOL)_shouldDelayTouchForSystemGestures:(UITouch *)touch { return NO; }

- (void)releaseSystemGestures {
    SEL invalidate = NSSelectorFromString(@"invalidate");
    if ([self.systemGestureAssertion respondsToSelector:invalidate])
        ((void (*)(id, SEL))objc_msgSend)(self.systemGestureAssertion, invalidate);
    self.systemGestureAssertion = nil;
}

- (void)dealloc { [self releaseSystemGestures]; }

- (void)dismiss {
    self.hidden = YES;
    [self releaseSystemGestures];
    [self resignKeyWindow];
    [self.previousKeyWindow makeKeyWindow];
    self.toolbar.captureHandler = nil;
    self.toolbar.cancelHandler = nil;
    self.toolbar.longCaptureHandler = nil;
    self.toolbar.recognitionHandler = nil;
    self.toolbar.editHandler = nil;
    self.toolbar.personaHandler = nil;
    self.toolbar.aiHandler = nil; self.toolbar.copyHandler = nil; self.toolbar.saveHandler = nil; self.toolbar.fullscreenHandler = nil;
    self.toolbar.historyHandler = nil;
    self.selectionView.doubleTapHandler = nil;
    self.selectionView.cancelHandler = nil;
    self.selectionView.selectionChanged = nil;
    self.editedImageHandler = nil;
    self.longCaptureHandler = nil;
    self.rootViewController = nil;
}

@end
