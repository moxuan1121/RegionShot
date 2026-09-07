#import "RSSelectionWindow.h"
#import "RSSelectionToolbar.h"
#import "RSSelectionView.h"
#import "RSMenuSettings.h"
#import "RSRecognitionController.h"
#import "RSImageEditor.h"
#import "../Capture/RSScreenCapture.h"
#import "../AI/RSChatController.h"
#import "../Manager/RSRegionShotManager.h"

@interface RSSelectionWindow ()
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) RSSelectionView *selectionView;
@property (nonatomic, strong) RSSelectionToolbar *toolbar;
@property (nonatomic, weak) UIWindow *previousKeyWindow;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIScrollView *toolbarScroll;
@end

@implementation RSSelectionWindow

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
        UIViewController *controller = [UIViewController new];
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
        [_toolbarScroll addSubview:_toolbar];
        _settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_settingsButton setImage:[UIImage systemImageNamed:@"gearshape"] forState:UIControlStateNormal];
        _settingsButton.tintColor = UIColor.whiteColor;
        _settingsButton.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.85];
        _settingsButton.layer.cornerRadius = 22;
        _settingsButton.accessibilityLabel = @"工具条设置";
        [_settingsButton addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
        [controller.view addSubview:_settingsButton];

        __weak typeof(self) weakSelf = self;
        _toolbar.captureHandler = ^{
            RSSelectionWindow *strongSelf = weakSelf;
            if (!strongSelf.selectionView.hasValidSelection) return;
            confirm(strongSelf.selectionRect, strongSelf.displaySize);
        };
        _toolbar.cancelHandler = cancel;
        _selectionView.doubleTapHandler = ^{ if (weakSelf.toolbar.captureHandler) weakSelf.toolbar.captureHandler(); };
        _toolbar.fullscreenHandler = ^{ [weakSelf.selectionView selectAll]; };
        _toolbar.historyHandler = ^{ [RSRegionShotManager.sharedManager showHistory]; };
        _toolbar.ocrHandler = ^{ [weakSelf showRecognition:NO]; };
        _toolbar.aiHandler = ^{
            RSSelectionWindow *window = weakSelf;
            if (!window.selectionView.hasValidSelection) return;
            UIImage *cropped = [RSScreenCapture cropImage:window.imageView.image toRect:window.selectionRect displaySize:window.displaySize];
            UIWindowScene *scene = window.windowScene;
            if (cropped) { if (window.toolbar.cancelHandler) window.toolbar.cancelHandler(); [RSChatController showImage:cropped scene:scene]; }
        };
        _toolbar.recognitionHandler = ^{ [weakSelf recognizeSelection]; };
        _toolbar.editHandler = ^{ [weakSelf editSelection]; };
        _toolbar.longCaptureHandler = ^{
            RSSelectionWindow *window = weakSelf;
            if (window.selectionView.hasValidSelection && window.longCaptureHandler)
                window.longCaptureHandler(window.selectionRect, window.displaySize);
        };
    }
    return self;
}

- (CGRect)selectionRect { return self.selectionView.selectionRect; }
- (CGSize)displaySize { return self.selectionView.bounds.size; }

- (void)layoutSubviews {
    [super layoutSubviews];
    self.rootViewController.view.frame = self.bounds;
    self.imageView.frame = self.bounds;
    self.selectionView.frame = self.bounds;
    CGFloat safeBottom = self.safeAreaInsets.bottom;
    CGFloat width = MIN(CGRectGetWidth(self.bounds) - 32, 396);
    CGFloat height = MAX(60, RSSelectionMenuSize(YES) + (RSSelectionMenuHideNames() ? 16 : 36));
    self.toolbarScroll.frame = CGRectMake((CGRectGetWidth(self.bounds) - width) / 2.0,
                                    CGRectGetHeight(self.bounds) - safeBottom - height - 12, width, height);
    CGFloat contentWidth = MAX(width, self.toolbar.subviews.count * MAX(64, RSSelectionMenuSize(YES) + 16));
    self.toolbar.frame = CGRectMake(0, 0, contentWidth, height);
    self.toolbarScroll.contentSize = self.toolbar.bounds.size;
    self.settingsButton.frame = CGRectMake(CGRectGetWidth(self.bounds) - 60, self.safeAreaInsets.top + 12, 44, 44);
    [self bringSubviewToFront:self.rootViewController.view];
    [self.rootViewController.view bringSubviewToFront:self.toolbarScroll];
    [self.rootViewController.view bringSubviewToFront:self.settingsButton];
}

- (void)openSettings {
    if (self.rootViewController.presentedViewController) return;
    RSMenuSettings *settings = [RSMenuSettings new];
    __weak typeof(self) weakSelf = self;
    settings.onClose = ^{ [weakSelf.toolbar reloadButtons]; [weakSelf setNeedsLayout]; };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self.rootViewController presentViewController:navigation animated:YES completion:nil];
}

- (void)recognizeSelection {
    if (!self.selectionView.hasValidSelection || self.rootViewController.presentedViewController) return;
    UIImage *image = [RSScreenCapture cropImage:self.imageView.image toRect:self.selectionRect displaySize:self.displaySize];
    if (!image) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"识别选区" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSNumber *barcode in @[@YES, @NO]) {
        [sheet addAction:[UIAlertAction actionWithTitle:barcode.boolValue ? @"二维码 / 条码" : @"识别文字（OCR）"
            style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self showRecognition:barcode.boolValue];
            }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.toolbar;
    sheet.popoverPresentationController.sourceRect = self.toolbar.bounds;
    [self.rootViewController presentViewController:sheet animated:YES completion:nil];
}
- (void)showRecognition:(BOOL)barcode {
    if (!self.selectionView.hasValidSelection) return;
    UIImage *image = [RSScreenCapture cropImage:self.imageView.image toRect:self.selectionRect displaySize:self.displaySize];
    if (!image) return;
    RSRecognitionController *result = [[RSRecognitionController alloc] initWithImage:image barcode:barcode];
    __weak typeof(self) weakSelf = self;
    result.onForward = ^{ if (weakSelf.toolbar.cancelHandler) weakSelf.toolbar.cancelHandler(); };
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:result];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [self.rootViewController presentViewController:navigation animated:YES completion:nil];
}

- (void)editSelection {
    if (!self.selectionView.hasValidSelection || self.rootViewController.presentedViewController) return;
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
    self.hidden = NO;
    [self makeKeyAndVisible];
}

- (void)dismiss {
    self.hidden = YES;
    [self resignKeyWindow];
    [self.previousKeyWindow makeKeyWindow];
    self.toolbar.captureHandler = nil;
    self.toolbar.cancelHandler = nil;
    self.toolbar.longCaptureHandler = nil;
    self.toolbar.recognitionHandler = nil;
    self.toolbar.editHandler = nil;
    self.toolbar.aiHandler = nil; self.toolbar.ocrHandler = nil; self.toolbar.fullscreenHandler = nil;
    self.toolbar.historyHandler = nil;
    self.selectionView.doubleTapHandler = nil;
    self.editedImageHandler = nil;
    self.longCaptureHandler = nil;
    self.rootViewController = nil;
}

@end
