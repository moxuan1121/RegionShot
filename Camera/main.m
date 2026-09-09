#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <notify.h>
#import <objc/message.h>
#import "RSCameraBridge.h"
@interface RSCameraController : UIViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(copy) NSString *requestID;
@property(strong) UIImagePickerController *camera;
@property BOOL capturing;
- (void)start;
@end
@implementation RSCameraController
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = UIColor.systemBackgroundColor; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; if (!self.requestID) [self start]; }
- (void)finish:(UIImage *)image {
    if (!self.requestID) return;
    NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:RSCameraRequestPath()];
    if (![request[@"id"] isEqual:self.requestID] || ![request[@"status"] isEqual:@"waiting"]) { [self dismissViewControllerAnimated:NO completion:nil]; return; }
    NSMutableDictionary *result = [request mutableCopy];
    BOOL saved = NO;
    if (image) {
        // Keep one bounded attachment, never retain a full camera roll or video.
        CGFloat ratio = MIN(1, 2560 / MAX(image.size.width, image.size.height));
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat]; format.scale = 1; format.opaque = YES;
        CGSize size = CGSizeMake(MAX(1, image.size.width * ratio), MAX(1, image.size.height * ratio));
        UIImage *scaled = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) { [image drawInRect:(CGRect){CGPointZero, size}]; }];
        NSData *data = UIImageJPEGRepresentation(scaled, 0.9);
        saved = data.length && data.length <= 12 * 1024 * 1024 && [data writeToFile:RSCameraImagePath() atomically:YES];
        if (!saved) { [self error:@"无法保存拍摄图片，请检查存储空间。" completion:^{ [self finish:nil]; }]; return; }
    }
    result[@"status"] = saved ? @"image" : @"cancel";
    if (![result writeToFile:RSCameraRequestPath() atomically:YES]) { [self error:@"无法写回拍照结果，请重新安装 RegionShot 后重试。" completion:^{ [self dismissViewControllerAnimated:YES completion:nil]; }]; return; }
    [self dismissViewControllerAnimated:NO completion:nil];
    // Return to the preceding application before restoring the floating conversation.
    notify_post(RS_CAMERA_FINISHED);
    [UIApplication.sharedApplication openURL:[NSURL URLWithString:@"prefs:root=regionshot_camera_return"] options:@{} completionHandler:nil];
    SEL suspend = NSSelectorFromString(@"suspend");
    if ([UIApplication.sharedApplication respondsToSelector:suspend]) ((void (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, suspend);
}
- (void)error:(NSString *)text completion:(void (^)(void))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"RegionShot 拍照" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"返回对话" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completion(); }]];
    self.capturing = NO;
    [(self.presentedViewController ?: self) presentViewController:alert animated:YES completion:nil];
}
- (void)start {
    NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:RSCameraRequestPath()];
    NSString *identifier = request[@"id"];
    if (![identifier isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:identifier] || ![request[@"status"] isEqual:@"waiting"]) return;
    if (self.presentedViewController || [self.requestID isEqual:identifier]) return;
    self.requestID = identifier; self.capturing = NO;
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [self error:@"当前设备无法使用相机。" completion:^{ [self finish:nil]; }]; return;
    }
    void (^present)(BOOL) = ^(BOOL granted) { dispatch_async(dispatch_get_main_queue(), ^{
        if (!granted) { [self error:@"相机权限未开启，请在系统隐私设置中允许 RegionShot 拍照使用相机。" completion:^{ [self finish:nil]; }]; return; }
        UIImagePickerController *picker = [UIImagePickerController new];
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.delegate = self; picker.modalPresentationStyle = UIModalPresentationFullScreen;
        self.camera = picker;
        picker.showsCameraControls = NO;
        UIView *overlay = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UIStackView *bar = [UIStackView new]; bar.distribution = UIStackViewDistributionFillEqually;
        bar.backgroundColor = [UIColor colorWithWhite:0 alpha:0.65]; bar.translatesAutoresizingMaskIntoConstraints = NO;
        NSArray *titles = @[@"取消", @"拍照", @"切换镜头"];
        NSArray *selectors = @[@"cancelCamera", @"takePhoto", @"switchCamera"];
        for (NSUInteger i=0;i<titles.count;i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; [button setTitle:titles[i] forState:UIControlStateNormal];
            button.tintColor = UIColor.whiteColor; button.titleLabel.font = [UIFont systemFontOfSize:17];
            [button addTarget:self action:NSSelectorFromString(selectors[i]) forControlEvents:UIControlEventTouchUpInside]; [bar addArrangedSubview:button];
        }
        [overlay addSubview:bar];
        [NSLayoutConstraint activateConstraints:@[[bar.leadingAnchor constraintEqualToAnchor:overlay.leadingAnchor], [bar.trailingAnchor constraintEqualToAnchor:overlay.trailingAnchor], [bar.bottomAnchor constraintEqualToAnchor:overlay.safeAreaLayoutGuide.bottomAnchor], [bar.heightAnchor constraintEqualToConstant:64]]];
        picker.cameraOverlayView = overlay;
        [self presentViewController:picker animated:YES completion:nil];
    }); };
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusNotDetermined) [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:present];
    else present(status == AVAuthorizationStatusAuthorized);
}
- (void)takePhoto { if (self.capturing) return; self.capturing = YES; [self.camera takePicture]; }
- (void)cancelCamera { [self finish:nil]; }
- (void)switchCamera {
    if (self.capturing) return;
    UIImagePickerControllerCameraDevice device = self.camera.cameraDevice == UIImagePickerControllerCameraDeviceRear ? UIImagePickerControllerCameraDeviceFront : UIImagePickerControllerCameraDeviceRear;
    if ([UIImagePickerController isCameraDeviceAvailable:device]) self.camera.cameraDevice = device;
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info { [self finish:info[UIImagePickerControllerOriginalImage]]; }
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [self finish:nil]; }
@end
@interface RSCameraApp : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation RSCameraApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [RSCameraController new]; [self.window makeKeyAndVisible]; return YES;
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary *)options {
    if (![url.scheme isEqual:@"regionshot-camera"]) return NO;
    [(RSCameraController *)self.window.rootViewController start]; return YES;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(RSCameraApp.class)); } }
