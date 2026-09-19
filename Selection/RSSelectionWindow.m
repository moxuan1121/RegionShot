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

@interface RSSelectionWindow () <NSURLSessionTaskDelegate>
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) RSSelectionView *selectionView;
@property (nonatomic, strong) RSSelectionToolbar *toolbar;
@property (nonatomic, strong) UIVisualEffectView *toolbarBlur;
@property (nonatomic, weak) UIWindow *previousKeyWindow;
@property (nonatomic, strong) UIScrollView *toolbarScroll;
@property (nonatomic) UIInterfaceOrientation captureOrientation;
@property (nonatomic, strong) UIAlertController *lensProgress;
@property (nonatomic, strong) NSURLSession *lensSession;
@property (nonatomic, strong) NSURLSessionTask *lensTask;
- (void)uploadLensJPEG:(NSData *)jpeg dimensions:(NSString *)dimensions;
- (void)finishLensWithURL:(NSURL *)resultURL errorText:(NSString *)errorText;
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
    UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"正在识图" message:@"正在上传所选图片…" preferredStyle:UIAlertControllerStyleAlert];
    [progress addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
        [self.lensSession invalidateAndCancel];
        self.lensSession = nil; self.lensTask = nil;
        self.lensProgress = nil;
    }]];
    self.lensProgress = progress;
    __weak typeof(self) weakSelf = self;
    [self.rootViewController presentViewController:progress animated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            @autoreleasepool {
                NSData *jpeg = UIImageJPEGRepresentation(image, 0.9);
                NSString *dimensions = [NSString stringWithFormat:@"%.0f,%.0f", image.size.width * image.scale, image.size.height * image.scale];
                dispatch_async(dispatch_get_main_queue(), ^{
                    RSSelectionWindow *window = weakSelf;
                    if (!window || window.lensProgress != progress) return;
                    if (!jpeg.length) { [window finishLensWithURL:nil errorText:@"无法编码所选图片。"]; return; }
                    [window uploadLensJPEG:jpeg dimensions:dimensions];
                });
            }
        });
    }];
}

- (void)uploadLensJPEG:(NSData *)jpeg dimensions:(NSString *)dimensions {
    NSString *boundary = [@"RegionShot-" stringByAppendingString:NSUUID.UUID.UUIDString];
    NSMutableData *body = [NSMutableData data];
    void (^append)(NSString *) = ^(NSString *text) { [body appendData:[text dataUsingEncoding:NSUTF8StringEncoding]]; };
    append([NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"encoded_image\"; filename=\"regionshot.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n", boundary]);
    [body appendData:jpeg];
    append([NSString stringWithFormat:@"\r\n--%@\r\nContent-Disposition: form-data; name=\"processed_image_dimensions\"\r\n\r\n%@\r\n--%@--\r\n", boundary, dimensions, boundary]);

    long long milliseconds = (long long)(NSDate.date.timeIntervalSince1970 * 1000.0);
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://lens.google.com/v3/upload?ep=ccm&hl=zh-CN&st=%lld", milliseconds]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:30];
    request.HTTPMethod = @"POST"; request.HTTPBody = body;
    [request setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary] forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/136.0.0.0 Safari/537.36" forHTTPHeaderField:@"User-Agent"];
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    self.lensSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:NSOperationQueue.mainQueue];
    self.lensTask = [self.lensSession dataTaskWithRequest:request];
    [self.lensTask resume];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    if (task != self.lensTask) { completionHandler(nil); return; }
    NSString *host = request.URL.host.lowercaseString;
    BOOL valid = [request.URL.scheme.lowercaseString isEqualToString:@"https"] &&
        ([host isEqualToString:@"google.com"] || [host hasSuffix:@".google.com"]) &&
        [request.URL.query containsString:@"gsessionid="] && [request.URL.query containsString:@"lsessionid="];
    completionHandler(nil);
    [self finishLensWithURL:valid ? request.URL : nil errorText:valid ? nil : @"Google 没有返回完整的识图结果链接。"];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    if (task != self.lensTask) return;
    NSString *message = error.code == NSURLErrorTimedOut ? @"识图请求超时，请检查网络后重试。" :
        error.localizedDescription ?: @"识图请求失败，请稍后重试。";
    [self finishLensWithURL:nil errorText:message];
}

- (void)finishLensWithURL:(NSURL *)resultURL errorText:(NSString *)errorText {
    [self.lensSession invalidateAndCancel];
    self.lensSession = nil; self.lensTask = nil;
    UIAlertController *progress = self.lensProgress;
    self.lensProgress = nil;
    [progress dismissViewControllerAnimated:YES completion:^{
        if (!resultURL) { [self showLensError:errorText ?: @"识图请求失败，请稍后重试。"]; return; }
        NSURLComponents *components = [NSURLComponents new];
        components.scheme = @"reynard"; components.host = @"open";
        components.queryItems = @[[NSURLQueryItem queryItemWithName:@"url" value:resultURL.absoluteString]];
        if (self.toolbar.cancelHandler) self.toolbar.cancelHandler();
        [UIApplication.sharedApplication openURL:components.URL options:@{} completionHandler:nil];
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
    [self.lensSession invalidateAndCancel];
    self.lensSession = nil; self.lensTask = nil;
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
