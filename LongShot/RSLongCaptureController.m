#import "RSLongCaptureController.h"
#import "RSLongStitcher.h"
#import "RSLongSwipe.h"
#import <Photos/Photos.h>
#import "../Capture/RSScreenCapture.h"
#import "../Geometry/RSOrientation.h"
#import "../Geometry/RSMaterialBackground.h"
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
@property (nonatomic) RSLongCaptureMode mode;
@property (nonatomic) BOOL finishRequested;
@property (nonatomic, strong) NSURL *finishedFileURL;
@property (nonatomic, strong) RSLongStitcher *stitcher;
@property (nonatomic, strong) UIView *panel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UIButton *captureButton;
@property (nonatomic, strong) UIButton *continueButton;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) dispatch_queue_t processingQueue;
@property (nonatomic, copy) NSArray<UIWindow *> *temporarilyHiddenWindows;
@property (nonatomic) BOOL busy;
@property (nonatomic) BOOL stopped;
@property (nonatomic) BOOL retryCurrentFrame;
@property (nonatomic) CFTimeInterval nextStepAllowedTime;

@property (nonatomic, copy) void (^resultHandler)(UIWindowScene *);
@property (nonatomic, copy) dispatch_block_t cancelHandler;
@end

@implementation RSLongCaptureController

+ (instancetype)startWithScene:(UIWindowScene *)scene mode:(RSLongCaptureMode)mode
                    completion:(void (^)(UIWindowScene *))completion cancel:(dispatch_block_t)cancel {
    RSLongCaptureController *window = scene ? [[self alloc] initWithWindowScene:scene] : [[self alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.mode = mode == RSLongCaptureModeButtonStep ? RSLongCaptureModeButtonStep : RSLongCaptureModeManual;
    window.resultHandler = completion; window.cancelHandler = cancel;
    [window configure]; RSApplyWindowOrientation(window, RSActiveOrientation(scene)); window.hidden = NO; [window beginSession];
    return window;
}

- (void)configure {
    self.frame = self.windowScene ? self.windowScene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
    self.windowLevel = UIWindowLevelAlert + 210; self.backgroundColor = UIColor.clearColor;
    self.processingQueue = dispatch_queue_create("com.moxuan.regionshot.long-stitch", DISPATCH_QUEUE_SERIAL);
    RSLongCaptureRoot *root = [RSLongCaptureRoot new]; root.view.backgroundColor = UIColor.clearColor; self.rootViewController = root;
    self.panel = [UIView new]; RSInstallMaterialBackground(self.panel, 22); [root.view addSubview:self.panel];
    self.preview = [UIImageView new]; self.preview.contentMode = UIViewContentModeScaleAspectFill; self.preview.clipsToBounds = YES;
    self.preview.layer.cornerRadius = 10; self.preview.backgroundColor = UIColor.tertiarySystemFillColor;
    [self.panel addSubview:self.preview];
    self.statusLabel = [UILabel new]; self.statusLabel.textColor = UIColor.labelColor;
    self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    self.statusLabel.numberOfLines = 2; [self.panel addSubview:self.statusLabel];
    UIButton *cancel = [self button:@"取消" action:@selector(cancelPressed)];
    self.captureButton = [self button:self.mode == RSLongCaptureModeButtonStep ? @"结束" : @"截取" action:@selector(capturePressed)];
    [self.panel addSubview:cancel];
    cancel.tag = 1;
    if (self.mode == RSLongCaptureModeButtonStep) {
        self.continueButton = [self button:@"继续" action:@selector(continuePressed)];
        self.continueButton.enabled = NO; self.continueButton.tag = 2;
        self.captureButton.tag = 3; [self.panel addSubview:self.continueButton];
    } else self.captureButton.tag = 2;
    [self.panel addSubview:self.captureButton];
}

- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal]; button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; return button;
}

- (void)layoutSubviews {
    [super layoutSubviews]; CGRect bounds = self.rootViewController.view.bounds;
    UIEdgeInsets insets = self.rootViewController.view.safeAreaInsets;
    CGFloat width = MIN(390, bounds.size.width - insets.left - insets.right - 24);
    self.panel.frame = CGRectMake((bounds.size.width - width) / 2, bounds.size.height - insets.bottom - 118, width, 96);
    self.preview.frame = CGRectMake(12, 12, 54, 54);
    self.statusLabel.frame = CGRectMake(76, 9, width - 88, 38);
    CGFloat buttonWidth = (width - 24) / (self.continueButton ? 3 : 2);
    for (UIView *view in self.panel.subviews) if ([view isKindOfClass:UIButton.class])
        view.frame = CGRectMake(12 + (view.tag - 1) * buttonWidth, 51, buttonWidth, 38);
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self.rootViewController.view ? nil : hit;
}

- (void)hideOtherRegionShotWindows {
    NSMutableArray *windows = [NSMutableArray array];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window != self && !window.hidden && [NSStringFromClass(window.class) hasPrefix:@"RS"]) {
                window.hidden = YES; [windows addObject:window];
            }
        }
    }
    self.temporarilyHiddenWindows = windows;
}

- (UIImage *)screenImage {
    UIImage *screen = [RSScreenCapture captureScreen];
    CGSize displaySize = self.rootViewController.view.bounds.size;
    CGFloat bottom = CGRectGetMinY(self.panel.frame);
    if (!screen || displaySize.width <= 0 || bottom <= 0) return nil;
    return [RSScreenCapture cropImage:screen
                               toRect:CGRectMake(0, 0, displaySize.width, bottom)
                          displaySize:displaySize];
}

- (UIImage *)finalScreenImage {
    CGSize displaySize = self.rootViewController.view.bounds.size;
    CGFloat height = CGRectGetMinY(self.panel.frame);
    if (displaySize.width <= 0 || height <= 0) return nil;
    UIImage *screen = [RSScreenCapture captureScreen];
    if (!screen) return nil;
    return [RSScreenCapture cropImage:screen
                               toRect:CGRectMake(0, displaySize.height - height, displaySize.width, height)
                          displaySize:displaySize];
}

- (void)captureFinalFrame {
    if (self.stopped) return;
    self.busy = YES;
    self.hidden = YES; [CATransaction flush];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (self.stopped) return;
        UIImage *image = [self finalScreenImage];
        self.hidden = NO; [CATransaction flush];
        self.busy = NO;
        [self processImage:image finalFrame:YES];
    });
}

- (void)beginSession {
    [self layoutIfNeeded];
    [self hideOtherRegionShotWindows];
    self.stitcher = [[RSLongStitcher alloc] initWithTopInset:self.rootViewController.view.safeAreaInsets.top];
    self.statusLabel.text = self.mode == RSLongCaptureModeButtonStep
        ? @"正在记录首屏…" : @"缓慢向上滑动，结束后点击截取";
    [self startSampling];
    [CATransaction flush];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 80 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [self manualTick];
    });
}

- (void)startSampling {
    if (self.mode == RSLongCaptureModeButtonStep || self.stopped || self.timer || self.finishedFileURL) return;
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

- (void)enableContinueWhenReady {
    if (!self.continueButton || self.stopped || self.busy || self.finishRequested) return;
    NSTimeInterval delay = MAX(0, self.nextStepAllowedTime - CACurrentMediaTime());
    if (delay <= 0) { self.continueButton.enabled = YES; return; }
    self.continueButton.enabled = NO;
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        typeof(self) self = weakSelf;
        if (self && !self.stopped && !self.busy && !self.finishRequested && CACurrentMediaTime() >= self.nextStepAllowedTime)
            self.continueButton.enabled = YES;
    });
}

- (void)capturePressed {
    if (self.stopped || self.finishRequested) return;
    self.finishRequested = YES;
    [self.timer invalidate]; self.timer = nil;
    self.captureButton.enabled = NO;
    if (self.finishedFileURL) { [self saveFinishedImage]; return; }
    if (!self.busy) [self captureFinalFrame];
}

- (void)processImage:(UIImage *)image finalFrame:(BOOL)finalFrame {
    if (self.stopped) return;
    if (!image) {
        self.busy = NO;
        self.statusLabel.text = @"未能读取屏幕，请重试截取";
        if (self.finishRequested) { self.finishRequested = NO; self.captureButton.enabled = YES; [self startSampling]; }
        [self enableContinueWhenReady];
        return;
    }
    self.busy = YES;
    RSLongStitcher *stitcher = self.stitcher;
    dispatch_async(self.processingQueue, ^{
        @autoreleasepool {
            RSLongAppendResult result = [stitcher appendImage:image];
            NSUInteger count = stitcher.frameCount;
            CGFloat height = stitcher.estimatedHeight;
            UIImage *thumbnail = [image imageByPreparingThumbnailOfSize:CGSizeMake(108, 108)];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.stopped) return;
                self.busy = NO; self.preview.image = thumbnail;
                self.statusLabel.text = result == RSLongAppendResultUncertain
                    ? @"接缝未匹配，请滑回上一段后缓慢上滑"
                    : [NSString stringWithFormat:@"已记录 %lu 段 · 约 %.1f 屏", (unsigned long)count, height];
                if (self.mode == RSLongCaptureModeButtonStep && !self.finishRequested) {
                    self.retryCurrentFrame = result == RSLongAppendResultUncertain;
                    [self.continueButton setTitle:self.retryCurrentFrame ? @"重试" : @"继续" forState:UIControlStateNormal];
                    self.continueButton.enabled = NO;
                    if (result != RSLongAppendResultLimit) [self enableContinueWhenReady];
                    if (self.retryCurrentFrame) self.statusLabel.text = @"本次未记录，页面稳定后点重试";
                    else if (result == RSLongAppendResultUnchanged) self.statusLabel.text = @"页面未移动，可能已到底；可结束或继续";
                }
                if (result == RSLongAppendResultLimit) {
                    [self.timer invalidate]; self.timer = nil;
                    self.statusLabel.text = self.continueButton ? @"已到尺寸上限，请点击结束" : @"已到尺寸上限，请点击截取";
                }
                if (self.finishRequested) {
                    if (!finalFrame) [self captureFinalFrame];
                    else if (result == RSLongAppendResultUncertain) {
                        self.finishRequested = NO; self.captureButton.enabled = YES; [self startSampling];
                        if (self.continueButton) {
                            self.retryCurrentFrame = YES; [self enableContinueWhenReady];
                            [self.continueButton setTitle:@"重试" forState:UIControlStateNormal];
                        }
                    } else [self donePressed];
                }
            });
        }
    });
}

- (void)continuePressed {
    if (self.busy || self.stopped || self.finishRequested) return;
    CFTimeInterval now = CACurrentMediaTime();
    if (now < self.nextStepAllowedTime) { [self enableContinueWhenReady]; return; }
    self.nextStepAllowedTime = now + 1.8;
    self.continueButton.enabled = NO;
    if (self.retryCurrentFrame) {
        self.retryCurrentFrame = NO;
        [self.continueButton setTitle:@"继续" forState:UIControlStateNormal];
        [self manualTick]; return;
    }
    self.busy = YES;
    self.statusLabel.text = @"正在向下移动并记录…";
    CGFloat screenHeight = CGRectGetHeight(self.rootViewController.view.bounds);
    CGFloat startY = screenHeight > 0 ? (CGRectGetMinY(self.panel.frame) - 24) / screenHeight : 0.68;
    startY = MIN(0.68, MAX(0.38, startY));
    CGFloat endY = MAX(0.16, startY - 0.20);
    __weak typeof(self) weakSelf = self;
    RSPerformLongStepSwipe(startY, endY, ^(BOOL success) {
        typeof(self) self = weakSelf;
        if (!self || self.stopped) return;
        self.busy = NO;
        if (!success) {
            self.statusLabel.text = @"系统滚动不可用，请切换手动滚动";
            [self enableContinueWhenReady]; return;
        }
        [self manualTick];
    });
}

- (void)donePressed {
    if (self.stopped || self.busy) return;
    self.busy = YES; self.statusLabel.text = @"正在生成长图…";
    RSLongStitcher *stitcher = self.stitcher;
    dispatch_async(self.processingQueue, ^{
        NSError *error = nil; NSURL *url = [stitcher finishToURL:&error];
        NSData *png = url ? [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:&error] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopped) return;
            self.busy = NO;
            if (!url || !png) {
                self.finishRequested = NO; self.captureButton.enabled = YES;
                self.statusLabel.text = error.localizedDescription ?: @"生成失败，请重试"; return;
            }
            self.finishedFileURL = url;
            [UIPasteboard.generalPasteboard setData:png forPasteboardType:@"public.png"];
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
    NSURL *fileURL = self.finishedFileURL;
    [PHPhotoLibrary.sharedPhotoLibrary performChanges:^{
        PHAssetCreationRequest *request = [PHAssetCreationRequest creationRequestForAsset];
        [request addResourceWithType:PHAssetResourceTypePhoto fileURL:fileURL options:nil];
    } completionHandler:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopped) return;
            if (!success) {
                self.statusLabel.text = error.localizedDescription ?: @"已复制，相册保存失败，请重试";
                self.finishRequested = NO; self.captureButton.enabled = YES; return;
            }
            void (^handler)(UIWindowScene *) = self.resultHandler;
            UIWindowScene *scene = self.windowScene;
            [self stop]; if (handler) handler(scene);
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
    self.finishedFileURL = nil; self.resultHandler = nil; self.cancelHandler = nil; self.hidden = YES; self.rootViewController = nil;
    for (UIWindow *window in self.temporarilyHiddenWindows) window.hidden = NO;
    self.temporarilyHiddenWindows = nil;
}

@end
