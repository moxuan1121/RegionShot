#import "RSInlineCamera.h"

@interface RSInlineCamera () <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(nonatomic, strong) UIImagePickerController *picker;
@property(nonatomic, strong) UILabel *status;
@property(nonatomic, strong) UIButton *shutter;
@property(nonatomic, strong) UIButton *flip;
@property(nonatomic) BOOL stopped;
@property(nonatomic) NSUInteger generation;
@end

@implementation RSInlineCamera
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    UIView *panel = [UIView new]; panel.backgroundColor = UIColor.blackColor;
    panel.layer.cornerRadius = 20; panel.clipsToBounds = YES;
    panel.translatesAutoresizingMaskIntoConstraints = NO; [self.view addSubview:panel];
    UIView *preview = [UIView new]; preview.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:preview];
    UIStackView *bar = [UIStackView new]; bar.distribution = UIStackViewDistributionFillEqually;
    bar.translatesAutoresizingMaskIntoConstraints = NO; [panel addSubview:bar];
    NSArray *selectors = @[@"cancel", @"takePhoto", @"switchCamera"];
    NSArray *titles = @[@"取消", @"拍照", @"切换镜头"];
    for (NSUInteger i = 0; i < titles.count; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:titles[i] forState:UIControlStateNormal]; button.tintColor = UIColor.whiteColor;
        button.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        [button addTarget:self action:NSSelectorFromString(selectors[i]) forControlEvents:UIControlEventTouchUpInside];
        [bar addArrangedSubview:button];
        if (i == 1) self.shutter = button;
        if (i == 2) self.flip = button;
    }
    self.status = [UILabel new]; self.status.textColor = UIColor.whiteColor;
    self.status.numberOfLines = 0; self.status.textAlignment = NSTextAlignmentCenter;
    self.status.translatesAutoresizingMaskIntoConstraints = NO; [panel addSubview:self.status];
    NSLayoutConstraint *width = [panel.widthAnchor constraintEqualToConstant:360]; width.priority = 750;
    NSLayoutConstraint *height = [panel.heightAnchor constraintEqualToConstant:480]; height.priority = 750;
    [NSLayoutConstraint activateConstraints:@[width, height,
        [panel.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [panel.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        [panel.widthAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-24],
        [panel.heightAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.heightAnchor constant:-24],
        [bar.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor], [bar.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor], [bar.heightAnchor constraintEqualToConstant:56],
        [preview.topAnchor constraintEqualToAnchor:panel.topAnchor], [preview.bottomAnchor constraintEqualToAnchor:bar.topAnchor],
        [preview.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor], [preview.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor],
        [self.status.centerYAnchor constraintEqualToAnchor:preview.centerYAnchor],
        [self.status.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [self.status.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16]]];
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        self.status.text = @"系统相机当前不可用。";
        self.shutter.enabled = NO; self.flip.enabled = NO; return;
    }
    self.picker = [UIImagePickerController new]; self.picker.delegate = self;
    self.picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    self.picker.cameraCaptureMode = UIImagePickerControllerCameraCaptureModePhoto;
    self.picker.showsCameraControls = NO;
    [self addChildViewController:self.picker];
    self.picker.view.frame = preview.bounds;
    self.picker.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [preview addSubview:self.picker.view]; [self.picker didMoveToParentViewController:self];
}
- (void)takePhoto {
    if (self.stopped || !self.shutter.enabled || !self.picker) return;
    self.shutter.enabled = NO; self.flip.enabled = NO; self.status.text = @"正在拍照…";
    NSUInteger generation = ++self.generation;
    [self.picker takePicture];
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        typeof(self) camera = weakSelf;
        if (!camera || camera.stopped || camera.generation != generation) return;
        camera.status.text = @"系统未返回照片，请取消后重试。";
    });
}
- (void)switchCamera {
    if (self.stopped || !self.flip.enabled || !self.picker) return;
    UIImagePickerControllerCameraDevice device = self.picker.cameraDevice == UIImagePickerControllerCameraDeviceRear
        ? UIImagePickerControllerCameraDeviceFront : UIImagePickerControllerCameraDeviceRear;
    if ([UIImagePickerController isCameraDeviceAvailable:device]) self.picker.cameraDevice = device;
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    if (self.stopped) return;
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    ++self.generation;
    if (!image.CGImage) {
        self.status.text = @"无法读取照片，请重拍。"; self.shutter.enabled = YES; self.flip.enabled = YES; return;
    }
    if (self.completion) self.completion(image);
}
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [self cancel]; }
- (void)cancel { if (!self.stopped && self.completion) self.completion(nil); }
- (void)stop {
    if (self.stopped) return;
    self.stopped = YES; ++self.generation; self.completion = nil;
    self.picker.delegate = nil; [self.picker willMoveToParentViewController:nil];
    [self.picker.view removeFromSuperview]; [self.picker removeFromParentViewController]; self.picker = nil;
}
@end
