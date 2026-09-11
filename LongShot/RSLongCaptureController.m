#import "RSLongCaptureController.h"
#import "RSLongStitcher.h"
#import "RSHIDSwipe.h"
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
@property (nonatomic) RSLongCaptureMode mode;
@property (nonatomic, strong) RSLongStitcher *stitcher;
@property (nonatomic, strong) UIVisualEffectView *panel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIImageView *preview;
@property (nonatomic, strong) UIButton *captureButton;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) dispatch_queue_t processingQueue;
@property (nonatomic) BOOL busy;
@property (nonatomic) BOOL stopped;
@property (nonatomic) NSUInteger unchangedCount;
@property (nonatomic, copy) void (^resultHandler)(UIImage *, UIWindowScene *);
@property (nonatomic, copy) dispatch_block_t cancelHandler;
@end

@implementation RSLongCaptureController

+ (instancetype)startWithScene:(UIWindowScene *)scene mode:(RSLongCaptureMode)mode
                    completion:(void (^)(UIImage *, UIWindowScene *))completion cancel:(dispatch_block_t)cancel {
    RSLongCaptureController *window = scene ? [[self alloc] initWithWindowScene:scene] : [[self alloc] initWithFrame:UIScreen.mainScreen.bounds];
    window.mode = MIN(MAX(mode, RSLongCaptureModeRolling), RSLongCaptureModeAutomatic);
    window.resultHandler = completion; window.cancelHandler = cancel;
    [window configure]; [window makeKeyAndVisible]; [window beginSession];
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
    UIButton *done = [self button:@"完成" action:@selector(donePressed)];
    self.captureButton = [self button:@"截取" action:@selector(capturePressed)];
    [self.panel.contentView addSubview:cancel]; [self.panel.contentView addSubview:self.captureButton]; [self.panel.contentView addSubview:done];
    cancel.tag = 1; self.captureButton.tag = 2; done.tag = 3;
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
    CGFloat buttonWidth = (width - 24) / 3;
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
    self.statusLabel.text = @[@"请缓慢向上滚动", @"每次截取后自动滚动", @"正在自动拼接"][self.mode];
    self.captureButton.hidden = self.mode != RSLongCaptureModeStep;
    __weak typeof(self) weakSelf = self;
    [self processImage:[self screenImage] completion:^(RSLongAppendResult result) {
        RSLongCaptureController *window = weakSelf;
        if (!window || window.stopped) return;
        if (window.mode == RSLongCaptureModeRolling) {
            window.timer = [NSTimer scheduledTimerWithTimeInterval:0.42 target:window selector:@selector(manualTick) userInfo:nil repeats:YES];
        } else if (window.mode == RSLongCaptureModeAutomatic) {
            [window scrollAndCapture];
        }
    }];
}

- (void)manualTick {
    if (self.busy || self.stopped) return;
    [self captureSettledFrameThen:nil];
}

- (void)capturePressed {
    if (self.busy || self.stopped) return;
    [self scrollAndCapture];
}

- (void)scrollAndCapture {
    if (self.busy || self.stopped) return;
    self.busy = YES; self.captureButton.enabled = NO;
    if (!RSLongPerformUpwardSwipe(self.bounds.size)) {
        self.busy = NO; self.captureButton.enabled = YES;
        self.statusLabel.text = @"自动滚动不可用，请手动滚动后完成。"; return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 420 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [self captureSettledFrameThen:^(RSLongAppendResult result) {
            if (self.mode == RSLongCaptureModeAutomatic && !self.stopped) {
                if (result == RSLongAppendResultAdded) { self.unchangedCount = 0; [self scrollAndCapture]; }
                else if (result == RSLongAppendResultUnchanged && ++self.unchangedCount < 2) [self scrollAndCapture];
                else if (result == RSLongAppendResultUnchanged) [self donePressed];
                else { self.statusLabel.text = result == RSLongAppendResultLimit ? @"已达到长图上限，请完成。" : @"接缝不确定，已暂停，请检查后完成。"; }
            }
        }];
    });
}

- (void)captureSettledFrameThen:(void (^)(RSLongAppendResult))completion {
    if (self.stopped) return;
    self.busy = YES; UIImage *first = [self screenImage];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 130 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (self.stopped) return;
        UIImage *second = [self screenImage] ?: first;
        [self processImage:second completion:completion];
    });
}

- (void)processImage:(UIImage *)image completion:(void (^)(RSLongAppendResult))completion {
    if (!image || self.stopped) { self.busy = NO; return; }
    dispatch_async(self.processingQueue, ^{
        RSLongAppendResult result = [self.stitcher appendImage:image];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopped) return;
            self.busy = NO; self.captureButton.enabled = YES; self.preview.image = image;
            self.statusLabel.text = [NSString stringWithFormat:@"已拼接 %lu 段 · 约 %.0f 屏", (unsigned long)self.stitcher.frameCount, self.stitcher.estimatedHeight];
            if (completion) completion(result);
        });
    });
}

- (void)donePressed {
    if (self.stopped || self.busy || !self.stitcher.frameCount) return;
    self.busy = YES; self.statusLabel.text = @"正在生成长图…"; self.userInteractionEnabled = NO;
    dispatch_async(self.processingQueue, ^{
        NSError *error = nil; UIImage *image = [self.stitcher finish:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.stopped) return;
            if (!image) { self.busy = NO; self.userInteractionEnabled = YES; self.statusLabel.text = error.localizedDescription ?: @"长截图生成失败。"; return; }
            void (^handler)(UIImage *, UIWindowScene *) = self.resultHandler; UIWindowScene *scene = self.windowScene;
            [self stop]; if (handler) handler(image, scene);
        });
    });
}

- (void)cancelPressed {
    dispatch_block_t handler = self.cancelHandler; [self stop]; if (handler) handler();
}

- (void)stop {
    if (self.stopped) return; self.stopped = YES;
    [self.timer invalidate]; self.timer = nil;
    RSLongStitcher *stitcher = self.stitcher; self.stitcher = nil;
    if (stitcher) dispatch_async(self.processingQueue, ^{ [stitcher cancel]; });
    self.resultHandler = nil; self.cancelHandler = nil; self.hidden = YES; self.rootViewController = nil;
}

@end
