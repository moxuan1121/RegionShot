#import <objc/runtime.h>
#import "../History/RSHistoryController.h"
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
#import <roothide.h>

static NSString *RSWeChatScanImagePath(void) {
    return jbroot(@"/var/mobile/Library/Caches/com.moxuan.regionshot.wechat-scan.png");
}

BOOL RSStageWeChatScanImage(UIImage *image) {
    NSData *data = UIImagePNGRepresentation(image);
    NSString *path = RSWeChatScanImagePath();
    if (!data.length || ![data writeToFile:path options:NSDataWritingAtomic error:nil]) return NO;
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
    return YES;
}

static NSString *RSLensUploadPagePath(void) {
    return jbroot(@"/var/mobile/Library/Caches/com.moxuan.regionshot.google-lens.html");
}

static NSURL *RSStageLensUploadPage(UIImage *image, NSError **error) {
    NSData *jpeg = UIImageJPEGRepresentation(image, 0.9);
    if (!jpeg.length) {
        if (error) *error = [NSError errorWithDomain:@"com.moxuan.regionshot.lens" code:1 userInfo:@{NSLocalizedDescriptionKey:@"无法编码所选图片。"}];
        return nil;
    }
    long long milliseconds = (long long)(NSDate.date.timeIntervalSince1970 * 1000.0);
    NSString *dimensions = [NSString stringWithFormat:@"%.0f,%.0f", image.size.width * image.scale, image.size.height * image.scale];
    NSString *html = [NSString stringWithFormat:
        @"<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width'><title>RegionShot 识图</title>"
         "<style>body{font:17px -apple-system;margin:0;display:grid;place-items:center;height:100vh;background:#fff;color:#555}</style>"
         "<div id=status>正在上传图片…</div><form id=upload action='https://lens.google.com/v3/upload?ep=ccm&hl=zh-CN&st=%lld' method=post enctype='multipart/form-data' hidden>"
         "<input id=image type=file name=encoded_image><input name=processed_image_dimensions value='%@'></form>"
         "<script>try{const b=atob('%@'),u=new Uint8Array(b.length);for(let i=0;i<b.length;i++)u[i]=b.charCodeAt(i);const d=new DataTransfer();d.items.add(new File([u],'regionshot.jpg',{type:'image/jpeg'}));document.getElementById('image').files=d.files;document.getElementById('upload').submit()}catch(e){document.getElementById('status').textContent='无法准备识图图片，请返回后重试。'}</script>",
        milliseconds, dimensions, [jpeg base64EncodedStringWithOptions:0]];
    NSString *path = RSLensUploadPagePath();
    if (![html writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error]) return nil;
    [[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions:@0600} ofItemAtPath:path error:nil];
    return [NSURL fileURLWithPath:path];
}

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
@property (nonatomic) UIInterfaceOrientation captureOrientation;
@property (nonatomic, strong) UIAlertController *lensProgress;
@property (nonatomic) BOOL lensPageHandedOff;
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
        _toolbarScroll.showsHorizontalScrollIndicator = NO;
        _toolbarScroll.showsVerticalScrollIndicator = NO;
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
            window.toolbarScroll.hidden = dragging || window.rootViewController.childViewControllers.count > 0;
            [window setNeedsLayout];
        };
        _toolbar.captureHandler = ^{
            RSSelectionWindow *strongSelf = weakSelf;
            if (!strongSelf.selectionView.hasValidSelection) {
                [RSRegionShotManager.sharedManager takeNativeScreenshot];
                return;
            }
            confirm(strongSelf.selectionRect, strongSelf.displaySize);
        };
        _toolbar.cancelHandler = cancel;
        _selectionView.cancelHandler = cancel;
        _selectionView.doubleTapHandler = ^{ if (weakSelf.toolbar.captureHandler) weakSelf.toolbar.captureHandler(); };
        _toolbar.fullscreenHandler = ^{ [weakSelf.selectionView selectAll]; };
        _toolbar.historyHandler = ^{ [RSRegionShotManager.sharedManager showHistory]; };
        _toolbar.longCaptureHandler = ^{ [RSRegionShotManager.sharedManager beginLongCapture]; };
        _toolbar.imageSearchHandler = ^{ [weakSelf searchSelectionWithGoogleLens]; };
        _toolbar.copyHandler = ^{
            RSSelectionWindow *window = weakSelf;
            CGRect rect = window.selectionView.hasValidSelection ? window.selectionRect : window.selectionView.bounds;
            UIImage *image = [RSScreenCapture cropImage:window.imageView.image toRect:rect displaySize:window.displaySize];
            if (!image) return;
            [RSHistoryController recordImage:image completion:nil];
            UIPasteboard.generalPasteboard.image = image;
            if (window.toolbar.cancelHandler) window.toolbar.cancelHandler();
        };
        _toolbar.saveHandler = ^{
            RSSelectionWindow *window = weakSelf;
            if (!window.selectionView.hasValidSelection) return;
            UIImage *image = [RSScreenCapture cropImage:window.imageView.image toRect:window.selectionRect displaySize:window.displaySize];
            if (!image) return;
            [RSHistoryController recordImage:image completion:nil];
            if (window.toolbar.cancelHandler) window.toolbar.cancelHandler();
            [RSRegionShotManager.sharedManager saveImage:image];
        };
        _toolbar.aiHandler = ^{
            RSSelectionWindow *window = weakSelf;
            if (!window.selectionView.hasValidSelection) [window.selectionView selectAll];
            UIImage *cropped = [RSScreenCapture cropImage:window.imageView.image toRect:window.selectionRect displaySize:window.displaySize];
            UIWindowScene *scene = window.windowScene;
            if (cropped) { [RSHistoryController recordImage:cropped completion:nil]; if (window.toolbar.cancelHandler) window.toolbar.cancelHandler(); [RSChatController showImage:cropped scene:scene]; }
        };
        _toolbar.personaHandler = ^(NSDictionary *persona) {
            RSSelectionWindow *window = weakSelf;
            if (!window.selectionView.hasValidSelection) return;
            UIImage *cropped = [RSScreenCapture cropImage:window.imageView.image toRect:window.selectionRect displaySize:window.displaySize];
            UIWindowScene *scene = window.windowScene;
            if (cropped) {
                [RSHistoryController recordImage:cropped completion:nil];
                if (window.toolbar.cancelHandler) window.toolbar.cancelHandler();
                [RSChatController showImage:cropped scene:scene persona:persona];
            }
        };
        _toolbar.recognitionHandler = ^{ [weakSelf recognizeSelection]; };
        _toolbar.wechatScanHandler = ^{
            RSSelectionWindow *window = weakSelf;
            if (!window.selectionView.hasValidSelection) return;
            UIImage *image = [RSScreenCapture cropImage:window.imageView.image toRect:window.selectionRect displaySize:window.displaySize];
            if (!image) return;
            RSStageWeChatScanImage(image);
            if (window.toolbar.cancelHandler) window.toolbar.cancelHandler();
            [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"weixin://scanqrcode"] options:@{} completionHandler:nil];
        };
        _toolbar.editHandler = ^{ [weakSelf editSelection]; };
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
    if (!self.rootViewController.childViewControllers.count) [self.rootViewController.view bringSubviewToFront:self.toolbarScroll];
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

- (void)searchSelectionWithGoogleLens {
    if (self.lensProgress) return;
    if (!self.selectionView.hasValidSelection) [self.selectionView selectAll];
    UIImage *image = [RSScreenCapture cropImage:self.imageView.image toRect:self.selectionRect displaySize:self.displaySize];
    if (!image) return;
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在识图" message:@"正在准备所选图片…" preferredStyle:UIAlertControllerStyleAlert];
    [progress addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        self.lensProgress = nil;
        [[NSFileManager defaultManager] removeItemAtPath:RSLensUploadPagePath() error:nil];
    }]];
    self.lensProgress = progress;
    __weak typeof(self) weakSelf = self;
    [self.rootViewController presentViewController:progress animated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                NSError *error = nil;
                NSURL *pageURL = RSStageLensUploadPage(image, &error);
                dispatch_async(dispatch_get_main_queue(), ^{
                    RSSelectionWindow *window = weakSelf;
                    if (!window || window.lensProgress != progress) {
                        if (pageURL) [[NSFileManager defaultManager] removeItemAtPath:RSLensUploadPagePath() error:nil];
                        return;
                    }
                    [progress dismissViewControllerAnimated:YES completion:^{
                        window.lensProgress = nil;
                        if (!pageURL) { [window showLensError:error.localizedDescription ?: @"无法准备识图图片，请重试。"]; return; }
                        NSURLComponents *components = [NSURLComponents new];
                        components.scheme = @"reynard"; components.host = @"open";
                        components.queryItems = @[[NSURLQueryItem queryItemWithName:@"url" value:pageURL.absoluteString]];
                        window.lensPageHandedOff = YES;
                        if (window.toolbar.cancelHandler) window.toolbar.cancelHandler();
                        [UIApplication.sharedApplication openURL:components.URL options:@{} completionHandler:nil];
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                            [[NSFileManager defaultManager] removeItemAtPath:RSLensUploadPagePath() error:nil];
                        });
                    }];
                });
            }
        });
    }];
}

- (void)showLensError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"识图失败" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self.rootViewController presentViewController:alert animated:YES completion:nil];
}

- (void)editSelection {
    if (self.rootViewController.presentedViewController || self.rootViewController.childViewControllers.count) return;
    if (!self.selectionView.hasValidSelection) [self.selectionView selectAll];
    UIImage *image = [RSScreenCapture cropImage:self.imageView.image toRect:self.selectionRect displaySize:self.displaySize];
    if (!image) return;
    __weak typeof(self) weakSelf = self;
    RSImageEditor *editor = [[RSImageEditor alloc] initWithImage:image completion:^(UIImage *edited) {
        RSSelectionWindow *window = weakSelf;
        if (window.editedImageHandler) window.editedImageHandler(edited);
    }];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:editor];
    [RSRegionShotManager.sharedManager closeAllSnaps];
    self.toolbarScroll.hidden = YES;
    self.selectionView.hidden = YES;
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    __weak UINavigationController *weakNavigation = navigation;
    editor.dismissEditor = ^{
        UINavigationController *page = weakNavigation;
        [page dismissViewControllerAnimated:YES completion:^{
            [RSRegionShotManager.sharedManager cancelCapture];
        }];
    };
    [self.rootViewController presentViewController:navigation animated:YES completion:nil];
}

- (void)show {
    self.previousKeyWindow = [RSSelectionWindow currentKeyWindow];
    RSApplyWindowOrientation(self, self.captureOrientation);
    self.hidden = NO;
    [self makeKeyAndVisible];
    RSApplyWindowOrientation(self, self.captureOrientation);
    [self setNeedsLayout];
    [self layoutIfNeeded];

    [self.rootViewController setNeedsUpdateOfScreenEdgesDeferringSystemGestures];
}

- (BOOL)_shouldCreateScreenEdgesDeferringGestureRecognizer { return YES; }
- (BOOL)_containedGestureRecognizersShouldRespectGestureServerInstructions { return NO; }
- (BOOL)_shouldDelayTouchForSystemGestures:(UITouch *)touch { return NO; }

- (void)dismiss {
    if (!self.lensPageHandedOff) [[NSFileManager defaultManager] removeItemAtPath:RSLensUploadPagePath() error:nil];
    self.lensProgress = nil;
    self.hidden = YES;
    [self resignKeyWindow];
    [self.previousKeyWindow makeKeyWindow];
    self.toolbar.captureHandler = nil;
    self.toolbar.cancelHandler = nil;
    self.toolbar.recognitionHandler = nil;
    self.toolbar.wechatScanHandler = nil;
    self.toolbar.editHandler = nil;
    self.toolbar.personaHandler = nil;
    self.toolbar.aiHandler = nil; self.toolbar.copyHandler = nil; self.toolbar.saveHandler = nil; self.toolbar.fullscreenHandler = nil;
    self.toolbar.historyHandler = nil;
    self.toolbar.longCaptureHandler = nil;
    self.toolbar.imageSearchHandler = nil;
    self.selectionView.doubleTapHandler = nil;
    self.selectionView.cancelHandler = nil;
    self.selectionView.selectionChanged = nil;
    self.editedImageHandler = nil;
    self.rootViewController = nil;
}

@end
