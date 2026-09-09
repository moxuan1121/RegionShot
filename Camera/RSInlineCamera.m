#import "RSInlineCamera.h"
#import <AVFoundation/AVFoundation.h>

@interface RSCameraPresentation : UIPresentationController
@property(nonatomic, strong) UIView *shade;
@end
@implementation RSCameraPresentation
- (CGRect)frameOfPresentedViewInContainerView {
    CGRect safe = UIEdgeInsetsInsetRect(self.containerView.bounds, self.containerView.safeAreaInsets);
    CGFloat width = MIN(360, MAX(1, safe.size.width - 24));
    CGFloat height = MIN(480, MAX(1, safe.size.height - 24));
    return CGRectMake(CGRectGetMidX(safe) - width / 2, CGRectGetMidY(safe) - height / 2, width, height);
}
- (void)presentationTransitionWillBegin {
    self.shade = [[UIView alloc] initWithFrame:self.containerView.bounds];
    self.shade.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    self.shade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.containerView insertSubview:self.shade atIndex:0];
}
- (void)containerViewWillLayoutSubviews {
    self.presentedView.frame = self.frameOfPresentedViewInContainerView;
    self.presentedView.layer.cornerRadius = 20;
    self.presentedView.clipsToBounds = YES;
}
- (void)dismissalTransitionDidEnd:(BOOL)completed { if (completed) [self.shade removeFromSuperview]; }
@end

@interface RSInlineCamera () <UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIViewControllerTransitioningDelegate>
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UIButton *shutter;
@property(nonatomic, strong) UIButton *flip;
@property(nonatomic) BOOL stopped;
@property(nonatomic) NSUInteger generation;
@property(nonatomic) BOOL captureStarted;
@property(nonatomic) BOOL sessionFailed;
@end
@implementation RSInlineCamera
- (instancetype)init {
    if ((self = [super init])) {
        self.delegate = self;
        self.modalPresentationStyle = UIModalPresentationCustom;
        self.transitioningDelegate = self;
        if ([UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
            self.sourceType = UIImagePickerControllerSourceTypeCamera;
            self.cameraCaptureMode = UIImagePickerControllerCameraCaptureModePhoto;
            self.showsCameraControls = NO;
        }
    }
    return self;
}
- (UIPresentationController *)presentationControllerForPresentedViewController:(UIViewController *)presented
    presentingViewController:(UIViewController *)presenting sourceViewController:(UIViewController *)source {
    return [[RSCameraPresentation alloc] initWithPresentedViewController:presented presentingViewController:presenting];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    NSNotificationCenter *notifications = NSNotificationCenter.defaultCenter;
    [notifications addObserver:self selector:@selector(cameraSessionEvent:) name:AVCaptureSessionDidStartRunningNotification object:nil];
    [notifications addObserver:self selector:@selector(cameraSessionEvent:) name:AVCaptureSessionWasInterruptedNotification object:nil];
    [notifications addObserver:self selector:@selector(cameraSessionEvent:) name:AVCaptureSessionRuntimeErrorNotification object:nil];
    UIView *overlay = [[UIView alloc] initWithFrame:self.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    UIStackView *bar = [UIStackView new]; bar.distribution = UIStackViewDistributionFillEqually;
    bar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.75];
    bar.translatesAutoresizingMaskIntoConstraints = NO; [overlay addSubview:bar];
    NSArray *titles = @[@"取消", @"拍照", @"切换镜头"];
    NSArray *actions = @[@"cancel", @"takePhoto", @"switchCamera"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[i] forState:UIControlStateNormal]; button.tintColor = UIColor.whiteColor;
        button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        [button addTarget:self action:NSSelectorFromString(actions[i]) forControlEvents:UIControlEventTouchUpInside];
        [bar addArrangedSubview:button];
        if (i == 1) self.shutter = button;
        if (i == 2) self.flip = button;
    }
    self.status = [UILabel new]; self.status.textColor = UIColor.whiteColor;
    self.status.numberOfLines = 0; self.status.textAlignment = NSTextAlignmentCenter;
    self.status.translatesAutoresizingMaskIntoConstraints = NO; [overlay addSubview:self.status];
    [NSLayoutConstraint activateConstraints:@[
        [bar.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:overlay.bottomAnchor],
        [bar.heightAnchor constraintEqualToConstant:56],
        [self.status.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
        [self.status.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor constant:16],
        [self.status.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor constant:-16]]];
    self.cameraOverlayView = overlay;
    self.status.text = @"正在启动相机…";
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 8 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        RSInlineCamera *camera = weakSelf;
        if (!camera || camera.stopped || camera.captureStarted || camera.sessionFailed) return;
        camera.status.text = @"相机未报告启动成功。\n若预览仍为黑屏，请取消。";
        NSLog(@"[RegionShot Camera] No session startup event; appState=%ld permission=%ld",
            (long)UIApplication.sharedApplication.applicationState,
            (long)[AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]);
    });
}
- (void)cameraSessionEvent:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.stopped) return;
        NSLog(@"[RegionShot Camera] %@ %@ appState=%ld", notification.name,
            notification.userInfo, (long)UIApplication.sharedApplication.applicationState);
        if ([notification.name isEqual:AVCaptureSessionDidStartRunningNotification]) {
            self.captureStarted = YES;
            if (!self.sessionFailed) self.status.text = nil;
        } else {
            self.sessionFailed = YES; self.shutter.enabled = NO; self.flip.enabled = NO;
            NSInteger reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
            NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
            self.status.text = reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableInBackground
                ? @"系统仍将相机采集进程判定为后台。\n请取消，本次无法拍摄。"
                : error ? [NSString stringWithFormat:@"相机启动失败：%@（%ld）", error.localizedDescription, (long)error.code]
                : [NSString stringWithFormat:@"相机会话被中断（%ld）。请取消。", (long)reason];
        }
    });
}
- (void)takePhoto {
    if (self.stopped || !self.shutter.enabled) return;
    self.shutter.enabled = NO; self.flip.enabled = NO; self.status.text = @"正在拍照…";
    NSUInteger generation = ++self.generation;
    [self takePicture];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        RSInlineCamera *camera = weakSelf;
        if (!camera || camera.stopped || camera.generation != generation) return;
        camera.status.text = @"系统未返回照片，请取消后重试。";
    });
}
- (void)switchCamera {
    if (self.stopped || !self.flip.enabled) return;
    UIImagePickerControllerCameraDevice device = self.cameraDevice == UIImagePickerControllerCameraDeviceRear
        ? UIImagePickerControllerCameraDeviceFront : UIImagePickerControllerCameraDeviceRear;
    if ([UIImagePickerController isCameraDeviceAvailable:device]) self.cameraDevice = device;
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    if (self.stopped) return;
    UIImage *image = info[UIImagePickerControllerOriginalImage]; ++self.generation;
    if (!image.CGImage) {
        self.status.text = @"无法读取照片，请重拍。"; self.shutter.enabled = YES; self.flip.enabled = YES; return;
    }
    if (self.completion) self.completion(image);
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [self cancel]; }
- (void)cancel { if (!self.stopped && self.completion) self.completion(nil); }
- (void)stop {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    self.stopped = YES; ++self.generation; self.completion = nil; self.delegate = nil;
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
