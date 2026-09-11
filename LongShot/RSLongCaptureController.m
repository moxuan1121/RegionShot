#import "RSLongCaptureController.h"
#import "RSLongStitcher.h"
#import <Photos/Photos.h>
#import "../Capture/RSScreenCapture.h"
#import "../Geometry/RSOrientation.h"
#import <QuartzCore/QuartzCore.h>

@interface RSLongCaptureRoot : UIViewController
@end
@implementation RSLongCaptureRoot
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
@end

@interface RSLongCaptureController ()
@property (nonatomic) BOOL finishRequested;
@property (nonatomic, strong) UIImage *finishedImage;
@property (nonatomic, strong) RSLongStitcher *stitcher;
@property (nonatomic, strong) UIVisualEffectView *panel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UIButton *captureButton;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) dispatch_queue_t processingQueue;
@property (nonatomic) BOOL busy;
@property (nonatomic) BOOL stopped;

@property (nonatomic, copy) void (^resultHandler)(UIImage *, UIWindowScene *);
@property (nonatomic, copy) dispatch_block_t cancelHandler;
@end

@implementation RSLongCaptureController

+ (instancetype)startWithScene:(UIWindowScene *)scene mode:(RSLongCaptureMode)mode
                    completion:(void (^)(UIImage *, UIWindowScene *))completion cancel:(dispatch_block_t)cancel {
    RSLongCaptureController *window = scene ? [[self alloc] initWithWindowScene:scene] : [[self alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.resultHandler = completion; window.cancelHandler = cancel;
    [window configure]; RSApplyWindowOrientation(window, RSActiveOrientation(scene)); window.hidden = NO; [window beginSession];
    return window;
}

- (void)configure {
    self.frame = self.windowScene ? self.windowScene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
    self.windowLevel = UIWindowLevelAlert + 210; self.backgroundColor = UIColor.clearColor;
    self.processingQueue = dispatch_queue_create("com.moxuan.regionshot.long-stitch", DISPATCH_QUEUE_SERIAL);
    RSLongCaptureRoot *root = [RSLongCaptureRoot new]; root.view.backgroundColor = UIColor.clearColor; self.rootViewController = root;
    self.panel = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterialDark]];
    self.panel.layer.cornerRadius = 22; self.panel.clipsToBounds = YES; [root.view addSubview:self.panel];
    self.preview = [UIImageView new]; self.preview.contentMode = UIViewContentModeScaleAspectFill; self.preview.clipsToBounds = YES;
    self.preview.layer.cornerRadius = 10; self.preview.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
    [self.panel.contentView addSubview:self.preview];
    self.statusLabel = [UILabel new]; self.statusLabel.textColor = UIColor.whiteColor;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.numberOfLines = 2; [self.panel.contentView addSubview:self.statusLabel];
    UIButton *cancel = [self button:@"取消" action:@selector(cancelPressed)];
    self.captureButton = [self button:@"截取" action:@selector(capturePressed)];
    [self.panel.contentView addSubview:cancel]; [self.panel.contentView addSubview:self.captureButton];
    cancel.tag = 1; self.captureButton.tag = 2;
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal]; button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button;
}

- (void)layoutSubviews {
    [super layoutSubviews]; CGRect bounds = self.rootViewController.view.bounds;
    UIEdgeInsets insets = self.rootViewController.view.safeAreaInsets;
    CGFloat width = MIN(390, bounds.size.width - insets.left - insets.right - 24);
    self.panel.frame = CGRectMake((bounds.size.width - width) / 2, bounds.size.height - insets.bottom - 118, width, 96);
    self.preview.frame = CGRectMake(12, 12, 54, 54);
    self.statusLabel.frame = CGRectMake(76, 9, width - 88, 38);
    CGFloat buttonWidth = (width - 24) / 2;
    for (UIView *view in self.panel.contentView.subviews) if ([view isKindOfClass:UIButton.class])
        view.frame = CGRectMake(12 + (view.tag - 1) * buttonWidth, 51, buttonWidth, 38);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self.rootViewController.view ? nil : hit;
}

- (NSArray<UIWindow *> *)windowsToExclude {
    NSMutableArray *windows = [NSMutableArray arrayWithObject:self];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window != self && [NSStringFromClass(window.class) hasPrefix:@"RS"]) [windows addObject:window];
        }
    }
    return windows;
}

- (UIImage *)screenImage { return [RSScreenCapture captureScreenExcludingWindows:self.windowsToExclude]; }

- (void)beginSession {
    [self layoutIfNeeded];
    self.stitcher = [[RSLongStitcher alloc] initWithTopInset:self.rootViewController.view.safeAreaInsets.top];
    self.statusLabel.text = @"缓慢向上滑动，结束后点击截取";
    [self startSampling];
    [self manualTick];
}

- (void)startSampling {
    if (self.stopped || self.timer || self.finishedImage) return;
    __weak typeof(self) weakSelf = self;
    self.timer = [NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        [weakSelf manualTick];
    }];
    [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)manualTick {
    if (self.busy || self.stopped || self.finishRequested) return;
    [self processImage:[self screenImage] finalFrame:NO];
}

- (void)capturePressed {
    if (self.stopped || self.finishRequested) return;
    self.finishRequested = YES;
    [self.timer invalidate]; self.timer = nil;
    self.captureButton.enabled = NO;
    if (self.finishedImage) { [self saveFinishedImage]; return; }
    if (!self.busy) [self processImage:[self screenImage] finalFrame:YES];
}

- (void)processImage:(UIImage *)image finalFrame:(BOOL)finalFrame {
    if (self.stopped) return;
    if (!image) {
        self.busy = NO;
        self.statusLabel.text = @"未能读取屏幕，请重试截取";
        if (self.finishRequested) { self.finishRequested = NO; self.captureButton.enabled = YES; [self startSampling]; }
        return;
    }
    self.busy = YES;
    RSLongStitcher *stitcher = self.stitcher;
    dispatch_async(self.processingQueue, ^{
        RSLongAppendResult result = [stitcher appendImage:image];
        NSUInteger count = stitcher.frameCount;
        CGFloat height = stitcher.estimatedHeight;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopped) return;
            self.busy = NO; self.preview.image = image;
            self.statusLabel.text = result == RSLongAppendResultUncertain
                ? @"接缝未匹配，请滑回上一段后缓慢上滑"
                : [NSString stringWithFormat:@"已记录 %lu 段 · 约 %.1f 屏", (unsigned long)count, height];
            if (result == RSLongAppendResultLimit) {
                [self.timer invalidate]; self.timer = nil;
                self.statusLabel.text = @"已到尺寸上限，请点击截取";
            }
            if (self.finishRequested) {
                if (!finalFrame) [self processImage:[self screenImage] finalFrame:YES];
                else if (result == RSLongAppendResultUncertain) {
                    self.finishRequested = NO; self.captureButton.enabled = YES; [self startSampling];
                } else [self donePressed];
            }
        });
    });
}

- (void)donePressed {
    if (self.stopped || self.busy) return;
    self.busy = YES; self.statusLabel.text = @"正在生成长图…";
    RSLongStitcher *stitcher = self.stitcher;
    dispatch_async(self.processingQueue, ^{
        NSError *error = nil; UIImage *image = [stitcher finish:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopped) return;
            self.busy = NO;
            if (!image) {
                self.finishRequested = NO; self.captureButton.enabled = YES;
                self.statusLabel.text = error.localizedDescription ?: @"生成失败，请重试"; return;
            }
            self.finishedImage = image;
            UIPasteboard.generalPasteboard.image = image;
            [self saveFinishedImage];
        });
    });
}

- (void)saveFinishedImage {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus result) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (!self.stopped) [self saveFinishedImage]; });
        }]; return;
    }
    if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
        self.statusLabel.text = @"已复制；请允许相册写入后重试截取";
        self.finishRequested = NO; self.captureButton.enabled = YES; return;
    }
    self.statusLabel.text = @"已复制，正在保存到相册…";
    UIImage *imageToSave = self.finishedImage;
    [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromImage:imageToSave];
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopped) return;
            if (!success) {
                self.statusLabel.text = error.localizedDescription ?: @"已复制，相册保存失败，请重试";
                self.finishRequested = NO; self.captureButton.enabled = YES; return;
            }
            void (^handler)(UIImage *, UIWindowScene *) = self.resultHandler;
            UIImage *image = self.finishedImage; UIWindowScene *scene = self.windowScene;
            [self stop]; if (handler) handler(image, scene);
        });
    }];
}

- (void)cancelPressed {
    dispatch_block_t handler = self.cancelHandler; [self stop]; if (handler) handler();
}

- (void)stop {
    if (self.stopped) return; self.stopped = YES;
    [self.timer invalidate]; self.timer = nil;
    RSLongStitcher *stitcher = self.stitcher; self.stitcher = nil;
    if (stitcher) dispatch_async(self.processingQueue, ^{ [stitcher cancel]; });
    self.finishedImage = nil; self.resultHandler = nil; self.cancelHandler = nil; self.hidden = YES; self.rootViewController = nil;
}

@end
