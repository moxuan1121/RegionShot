#import "RSInlineCamera.h"
#import <AVFoundation/AVFoundation.h>
#import "../Geometry/RSOrientation.h"
@interface RSInlineCamera () <AVCapturePhotoCaptureDelegate>
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCapturePhotoOutput *output;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *preview;
@property(nonatomic, strong) UIView *surface;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UIButton *shutter;
@property(nonatomic, strong) UIButton *flip;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic) BOOL stopped;
@end
@implementation RSInlineCamera
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    self.queue = dispatch_queue_create("com.moxuan.regionshot.inline-camera", DISPATCH_QUEUE_SERIAL);
    self.session = [AVCaptureSession new]; self.output = [AVCapturePhotoOutput new];
    self.surface = [UIView new]; self.surface.backgroundColor = UIColor.blackColor;
    self.surface.layer.cornerRadius = 20; self.surface.clipsToBounds = YES;
    self.surface.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:self.surface];
    self.preview = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill; [self.surface.layer addSublayer:self.preview];
    UIStackView *bar = [UIStackView new]; bar.distribution = UIStackViewDistributionFillEqually;
    bar.translatesAutoresizingMaskIntoConstraints = NO; bar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65];
    for (NSString *title in @[@"取消", @"拍照", @"切换镜头"]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:title forState:UIControlStateNormal]; button.tintColor = UIColor.whiteColor;
        button.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightMedium];
        SEL action = [title isEqual:@"取消"] ? @selector(cancel) : [title isEqual:@"拍照"] ? @selector(takePhoto) : @selector(switchCamera);
        [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; [bar addArrangedSubview:button];
        if (action == @selector(takePhoto)) self.shutter = button;
        if (action == @selector(switchCamera)) self.flip = button;
    }
    self.shutter.enabled = NO; self.flip.enabled = NO;
    self.status = [UILabel new]; self.status.textColor = UIColor.whiteColor; self.status.numberOfLines = 0;
    self.status.textAlignment = NSTextAlignmentCenter; self.status.translatesAutoresizingMaskIntoConstraints = NO;
    self.status.text = @"正在打开相机…";
    [self.surface addSubview:self.status]; [self.surface addSubview:bar];
    NSLayoutConstraint *width = [self.surface.widthAnchor constraintEqualToConstant:360]; width.priority = 750;
    NSLayoutConstraint *height = [self.surface.heightAnchor constraintEqualToConstant:460]; height.priority = 750;
    [NSLayoutConstraint activateConstraints:@[width, height,
        [self.surface.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [self.surface.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        [self.surface.widthAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-24],
        [self.surface.heightAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.heightAnchor constant:-24],
        [bar.leadingAnchor constraintEqualToAnchor:self.surface.leadingAnchor], [bar.trailingAnchor constraintEqualToAnchor:self.surface.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.surface.bottomAnchor], [bar.heightAnchor constraintEqualToConstant:56],
        [self.status.leadingAnchor constraintEqualToAnchor:self.surface.leadingAnchor constant:16],
        [self.status.trailingAnchor constraintEqualToAnchor:self.surface.trailingAnchor constant:-16],
        [self.status.centerYAnchor constraintEqualToAnchor:self.surface.centerYAnchor]]];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sessionError:) name:AVCaptureSessionRuntimeErrorNotification object:self.session];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(interrupted:) name:AVCaptureSessionWasInterruptedNotification object:self.session];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resumed:) name:AVCaptureSessionInterruptionEndedNotification object:self.session];
    AVAuthorizationStatus permission = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (permission == AVAuthorizationStatusDenied || permission == AVAuthorizationStatusRestricted) { [self showError:@"当前进程没有相机权限，请检查系统相机访问限制。"]; return; }
    // System hosts may carry camera authorization themselves. Never request TCC without a usage string.
    if (permission == AVAuthorizationStatusNotDetermined && [NSBundle.mainBundle objectForInfoDictionaryKey:@"NSCameraUsageDescription"]) {
        __weak typeof(self) weakSelf = self;
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{ if (granted) [weakSelf configure]; else [weakSelf showError:@"相机权限未开启。"]; });
        }];
    } else if (permission == AVAuthorizationStatusAuthorized) [self configure];
    else [self showError:@"当前系统进程未获相机授权，无法启动内嵌相机。"];
}
- (void)showError:(NSString *)message {
    if (self.stopped) return;
    self.status.text = message; self.shutter.enabled = NO; self.flip.enabled = NO;
}
- (void)configure {
    if (self.stopped) return;
    dispatch_async(self.queue, ^{
        NSError *error = nil;
        AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] error:&error];
        if (!input || ![self.session canAddInput:input] || ![self.session canAddOutput:self.output]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self showError:error.localizedDescription ?: @"当前无法打开相机。"]; }); return;
        }
        [self.session beginConfiguration];
        if ([self.session canSetSessionPreset:AVCaptureSessionPreset1280x720]) self.session.sessionPreset = AVCaptureSessionPreset1280x720;
        [self.session addInput:input]; [self.session addOutput:self.output]; [self.session commitConfiguration];
        [self.session startRunning];
        dispatch_async(dispatch_get_main_queue(), ^{ if (!self.stopped) { self.status.text = nil; self.shutter.enabled = YES; self.flip.enabled = YES; [self.view setNeedsLayout]; } });
    });
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [CATransaction begin]; [CATransaction setDisableActions:YES]; self.preview.frame = self.surface.bounds; [CATransaction commit];
    UIInterfaceOrientation orientation = RSActiveOrientation(self.view.window.windowScene);
    if (orientation != UIInterfaceOrientationUnknown && self.preview.connection.isVideoOrientationSupported)
        self.preview.connection.videoOrientation = (AVCaptureVideoOrientation)orientation;
}
- (void)takePhoto {
    if (!self.shutter.enabled || self.stopped) return;
    self.shutter.enabled = NO; self.flip.enabled = NO;
    AVCaptureConnection *connection = [self.output connectionWithMediaType:AVMediaTypeVideo];
    if (connection.isVideoOrientationSupported) connection.videoOrientation = self.preview.connection.videoOrientation;
    dispatch_async(self.queue, ^{ [self.output capturePhotoWithSettings:[AVCapturePhotoSettings photoSettings] delegate:self]; });
}
- (void)switchCamera {
    if (!self.flip.enabled || self.stopped) return;
    self.shutter.enabled = NO; self.flip.enabled = NO;
    dispatch_async(self.queue, ^{
        AVCaptureDeviceInput *old = (AVCaptureDeviceInput *)self.session.inputs.firstObject;
        AVCaptureDevicePosition position = old.device.position == AVCaptureDevicePositionBack ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera mediaType:AVMediaTypeVideo position:position];
        AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:nil] : nil;
        if (input) {
            [self.session beginConfiguration]; [self.session removeInput:old];
            if ([self.session canAddInput:input]) [self.session addInput:input]; else [self.session addInput:old];
            [self.session commitConfiguration];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ if (!self.stopped) { self.shutter.enabled = YES; self.flip.enabled = YES; [self.view setNeedsLayout]; } });
    });
}
- (void)photoOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    NSData *data = error ? nil : photo.fileDataRepresentation;
    UIImage *image = data ? [UIImage imageWithData:data] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.stopped) return;
        if (!image) { self.status.text = @"拍摄失败，请重试。"; self.shutter.enabled = YES; self.flip.enabled = YES; return; }
        if (self.completion) self.completion(image);
    });
}
- (void)sessionError:(NSNotification *)note { dispatch_async(dispatch_get_main_queue(), ^{ [self showError:@"相机不可用，请取消后重试。"]; }); }
- (void)interrupted:(NSNotification *)note { dispatch_async(dispatch_get_main_queue(), ^{ [self showError:@"相机暂时被占用或已锁屏。"]; }); }
- (void)resumed:(NSNotification *)note { dispatch_async(dispatch_get_main_queue(), ^{ if (!self.stopped) { self.status.text = nil; self.shutter.enabled = YES; self.flip.enabled = YES; } }); }
- (void)cancel { if (self.completion) self.completion(nil); }
- (void)stop {
    if (self.stopped) return; self.stopped = YES; self.completion = nil;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    AVCaptureSession *session = self.session; dispatch_async(self.queue, ^{ [session stopRunning]; });
}
@end
