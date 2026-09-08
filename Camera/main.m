#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <notify.h>
#import <objc/message.h>
#import "RSCameraBridge.h"
@interface RSCameraController : UIViewController <UIImagePickerControllerDelegate, UINavigationControllerDelegate>
@property(copy) NSString *requestID;
- (void)start;
@end
@implementation RSCameraController
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor = UIColor.systemBackgroundColor; }
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated]; if (!self.requestID) [self start]; }
- (void)finish:(UIImage *)image {
    NSMutableDictionary *result = [[NSDictionary dictionaryWithContentsOfFile:RSCameraRequestPath()] mutableCopy];
    if (![result[@"id"] isEqual:self.requestID]) return;
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
    if (![result writeToFile:RSCameraRequestPath() atomically:YES]) return;
    [self dismissViewControllerAnimated:NO completion:nil];
    // Return to the preceding application before restoring the floating conversation.
    notify_post(RS_CAMERA_FINISHED);
    SEL suspend = NSSelectorFromString(@"suspend");
    if ([UIApplication.sharedApplication respondsToSelector:suspend]) ((void (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, suspend);
}
- (void)error:(NSString *)text completion:(void (^)(void))completion {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"RegionShot 拍照" message:text preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"返回对话" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { completion(); }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)start {
    NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:RSCameraRequestPath()];
    NSString *identifier = request[@"id"];
    if (![identifier isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:identifier] || ![request[@"status"] isEqual:@"waiting"]) return;
    if (self.presentedViewController || [self.requestID isEqual:identifier]) return;
    self.requestID = identifier;
    if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
        [self error:@"当前设备无法使用相机。" completion:^{ [self finish:nil]; }]; return;
    }
    void (^present)(BOOL) = ^(BOOL granted) { dispatch_async(dispatch_get_main_queue(), ^{
        if (!granted) { [self error:@"相机权限未开启，请在系统隐私设置中允许 RegionShot 拍照使用相机。" completion:^{ [self finish:nil]; }]; return; }
        UIImagePickerController *picker = [UIImagePickerController new];
        picker.sourceType = UIImagePickerControllerSourceTypeCamera;
        picker.delegate = self; picker.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:picker animated:YES completion:nil];
    }); };
    AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if (status == AVAuthorizationStatusNotDetermined) [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:present];
    else present(status == AVAuthorizationStatusAuthorized);
}
- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info { [self finish:info[UIImagePickerControllerOriginalImage]]; }
- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker { [self finish:nil]; }
@end
@interface RSCameraApp : UIResponder <UIApplicationDelegate>
@property(strong) UIWindow *window;
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
