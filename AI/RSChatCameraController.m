#import "RSChatCameraController.h"
#import "../Geometry/RSMaterialBackground.h"
#import <AVFoundation/AVFoundation.h>

@interface RSChatCameraController () <AVCapturePhotoCaptureDelegate>
@property(nonatomic, strong) UIWindow *host;
@property(nonatomic, weak) UIWindow *previousKey;
@property(nonatomic, strong) UIView *card;
@property(nonatomic, strong) AVCaptureSession *session;
@property(nonatomic, strong) AVCaptureDeviceInput *input;
@property(nonatomic, strong) AVCapturePhotoOutput *output;
@property(nonatomic, strong) AVCaptureVideoPreviewLayer *preview;
@property(nonatomic, strong) dispatch_queue_t queue;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UIButton *shutter;
@property(nonatomic, strong) UIButton *flip;
@property(nonatomic, copy) void (^completion)(UIImage *);
@property(nonatomic) AVCaptureDevicePosition position;
@property(nonatomic) CGFloat zoomAtPinchStart;
@property(nonatomic) BOOL closing;
@end

static RSChatCameraController *RSActiveCamera;

@implementation RSChatCameraController
+ (void)showInScene:(UIWindowScene *)scene completion:(void (^)(UIImage *))completion {
    if (!scene || RSActiveCamera) return;
    RSChatCameraController *camera = [RSChatCameraController new];
    camera.completion = completion;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene];
    for (UIWindow *candidate in scene.windows) if (candidate.isKeyWindow) camera.previousKey = candidate;
    window.windowLevel = UIWindowLevelAlert + 250;
    window.backgroundColor = UIColor.clearColor;
    window.rootViewController = camera;
    camera.host = window;
    RSActiveCamera = camera;
    [window makeKeyAndVisible];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.36];
    self.queue = dispatch_queue_create("com.moxuan.regionshot.springboard-camera", DISPATCH_QUEUE_SERIAL);
    self.position = AVCaptureDevicePositionBack;

    self.card = [UIView new];
    self.card.layer.cornerRadius = 20;
    self.card.layer.cornerCurve = kCACornerCurveContinuous;
    self.card.clipsToBounds = YES;
    RSInstallMaterialBackground(self.card, 20);
    self.card.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.card];

    self.preview = [AVCaptureVideoPreviewLayer layer];
    self.preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
    [self.card.layer addSublayer:self.preview];

    self.status = [UILabel new];
    self.status.text = @"正在启动相机…";
    self.status.textColor = UIColor.labelColor;
    self.status.textAlignment = NSTextAlignmentCenter;
    self.status.numberOfLines = 0;
    self.status.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:self.status];

    UIStackView *bar = [UIStackView new];
    bar.distribution = UIStackViewDistributionFillEqually;
    RSInstallMaterialBackground(bar, 0);
    bar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.card addSubview:bar];
    for (NSDictionary *item in @[
        @{@"title":@"取消", @"action":@"cancel"},
        @{@"title":@"拍照", @"action":@"takePhoto"},
        @{@"title":@"切换镜头", @"action":@"switchCamera"}
    ]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:item[@"title"] forState:UIControlStateNormal];
        [button setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
        [button addTarget:self action:NSSelectorFromString(item[@"action"]) forControlEvents:UIControlEventTouchUpInside];
        [bar addArrangedSubview:button];
        if ([item[@"action"] isEqual:@"takePhoto"]) self.shutter = button;
        if ([item[@"action"] isEqual:@"switchCamera"]) self.flip = button;
    }
    self.shutter.enabled = NO;
    self.flip.enabled = NO;
    [self.card addGestureRecognizer:[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)]];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    NSLayoutConstraint *width = [self.card.widthAnchor constraintEqualToConstant:360];
    NSLayoutConstraint *height = [self.card.heightAnchor constraintEqualToConstant:480];
    width.priority = UILayoutPriorityDefaultHigh;
    height.priority = UILayoutPriorityDefaultHigh;
    [NSLayoutConstraint activateConstraints:@[
        [self.card.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor],
        [self.card.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [self.card.leadingAnchor constraintGreaterThanOrEqualToAnchor:safe.leadingAnchor constant:12],
        [self.card.trailingAnchor constraintLessThanOrEqualToAnchor:safe.trailingAnchor constant:-12],
        [self.card.topAnchor constraintGreaterThanOrEqualToAnchor:safe.topAnchor constant:12],
        [self.card.bottomAnchor constraintLessThanOrEqualToAnchor:safe.bottomAnchor constant:-12],
        width, height,
        [bar.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:self.card.bottomAnchor],
        [bar.heightAnchor constraintEqualToConstant:56],
        [self.status.centerXAnchor constraintEqualToAnchor:self.card.centerXAnchor],
        [self.status.centerYAnchor constraintEqualToAnchor:self.card.centerYAnchor],
        [self.status.leadingAnchor constraintEqualToAnchor:self.card.leadingAnchor constant:16],
        [self.status.trailingAnchor constraintEqualToAnchor:self.card.trailingAnchor constant:-16]
    ]];
}
- (void)pinch:(UIPinchGestureRecognizer *)gesture {
    AVCaptureDevice *device = self.input.device;
    if (!device) return;
    if (gesture.state == UIGestureRecognizerStateBegan) self.zoomAtPinchStart = device.videoZoomFactor;
    if (gesture.state != UIGestureRecognizerStateBegan && gesture.state != UIGestureRecognizerStateChanged) return;
    CGFloat zoom = MIN(MAX(self.zoomAtPinchStart * gesture.scale, device.minAvailableVideoZoomFactor),
                       device.maxAvailableVideoZoomFactor);
    if ([device lockForConfiguration:nil]) {
        device.videoZoomFactor = zoom;
        [device unlockForConfiguration];
    }
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startCamera];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.preview.frame = self.card.bounds;
    [self updateVideoOrientation];
}
- (void)updateVideoOrientation {
    UIInterfaceOrientation orientation = self.view.window.windowScene.interfaceOrientation;
    AVCaptureVideoOrientation videoOrientation = AVCaptureVideoOrientationPortrait;
    if (orientation == UIInterfaceOrientationLandscapeLeft) videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
    else if (orientation == UIInterfaceOrientationLandscapeRight) videoOrientation = AVCaptureVideoOrientationLandscapeRight;
    for (AVCaptureConnection *connection in @[self.preview.connection ?: NSNull.null, [self.output connectionWithMediaType:AVMediaTypeVideo] ?: NSNull.null])
        if ([connection isKindOfClass:AVCaptureConnection.class] && connection.isVideoOrientationSupported) connection.videoOrientation = videoOrientation;
}
- (AVCaptureDevice *)deviceAtPosition:(AVCaptureDevicePosition)position {
    return [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera]
        mediaType:AVMediaTypeVideo position:position].devices.firstObject;
}
- (void)startCamera {
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.queue, ^{
        RSChatCameraController *camera = weakSelf;
        if (!camera || camera.closing) return;
        NSError *error = nil;
        AVCaptureDevice *device = [camera deviceAtPosition:camera.position];
        AVCaptureDeviceInput *input = device ? [AVCaptureDeviceInput deviceInputWithDevice:device error:&error] : nil;
        AVCaptureSession *session = [AVCaptureSession new];
        AVCapturePhotoOutput *output = [AVCapturePhotoOutput new];
        if (!input || ![session canAddInput:input] || ![session canAddOutput:output]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [camera fail:error.localizedDescription ?: @"相机启动失败。"]; });
            return;
        }
        [session addInput:input];
        [session addOutput:output];
        session.sessionPreset = AVCaptureSessionPresetPhoto;
        [session startRunning];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (camera.closing) { [session stopRunning]; return; }
            camera.session = session;
            camera.input = input;
            camera.output = output;
            camera.preview.session = session;
            [camera updateVideoOrientation];
            camera.status.hidden = YES;
            camera.shutter.enabled = YES;
            camera.flip.enabled = YES;
        });
    });
}
- (void)takePhoto {
    if (!self.output || self.closing) return;
    [self updateVideoOrientation];
    self.shutter.enabled = NO;
    [self.output capturePhotoWithSettings:[AVCapturePhotoSettings photoSettings] delegate:self];
}
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    NSData *data = error ? nil : photo.fileDataRepresentation;
    UIImage *image = data.length ? [UIImage imageWithData:data] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!image.CGImage) { self.shutter.enabled = YES; [self fail:error.localizedDescription ?: @"照片读取失败。"]; return; }
        void (^completion)(UIImage *) = self.completion;
        [self close];
        if (completion) completion(image);
    });
}
- (void)switchCamera {
    if (!self.session || self.closing) return;
    AVCaptureDevicePosition next = self.position == AVCaptureDevicePositionBack ? AVCaptureDevicePositionFront : AVCaptureDevicePositionBack;
    NSError *error = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:[self deviceAtPosition:next] error:&error];
    if (!input) return;
    [self.session beginConfiguration];
    [self.session removeInput:self.input];
    if ([self.session canAddInput:input]) { [self.session addInput:input]; self.input = input; self.position = next; }
    else [self.session addInput:self.input];
    [self.session commitConfiguration];
}
- (void)fail:(NSString *)message {
    self.status.hidden = NO;
    self.status.text = message;
    self.shutter.enabled = NO;
    self.flip.enabled = NO;
}
- (void)cancel { [self close]; }
- (void)close {
    if (self.closing) return;
    self.closing = YES;
    AVCaptureSession *session = self.session;
    dispatch_async(self.queue, ^{ [session stopRunning]; });
    self.host.hidden = YES;
    [self.previousKey makeKeyWindow];
    self.host.rootViewController = nil;
    self.host = nil;
    self.completion = nil;
    RSActiveCamera = nil;
}
@end
