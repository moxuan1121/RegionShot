#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/message.h>
#import <sys/stat.h>
#import "RSInlineCamera.h"
#import "RSCameraBridge.h"

@interface RSCameraHost : UIViewController
@property(nonatomic, strong) RSInlineCamera *camera;
@property(nonatomic, copy) NSString *requestID;
- (void)start;
@end
@implementation RSCameraHost
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self start];
}
- (void)start {
    if (self.camera) return;
    NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:RSCameraRequestPath()];
    NSString *identifier = request[@"id"];
    if (![identifier isKindOfClass:NSString.class] || ![request[@"status"] isEqual:@"waiting"]) { [self leave]; return; }
    self.requestID = identifier;
    RSInlineCamera *camera = [RSInlineCamera new]; self.camera = camera;
    __weak typeof(self) weakSelf = self;
    camera.completion = ^(UIImage *image) { [weakSelf finish:image]; };
    [self addChildViewController:camera]; camera.view.frame = self.view.bounds;
    camera.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:camera.view]; [camera didMoveToParentViewController:self];
}
- (void)finish:(UIImage *)image {
    NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:RSCameraRequestPath()];
    if (![request[@"id"] isEqual:self.requestID] || ![request[@"status"] isEqual:@"waiting"]) { [self leave]; return; }
    NSMutableDictionary *result = [request mutableCopy];
    NSData *data = image ? UIImageJPEGRepresentation(image, 0.88) : nil;
    BOOL saved = data.length && data.length <= 12 * 1024 * 1024 && [data writeToFile:RSCameraImagePath() atomically:YES];
    if (saved) chmod(RSCameraImagePath().fileSystemRepresentation, 0644);
    result[@"status"] = saved ? @"image" : @"cancel";
    if (![result writeToFile:RSCameraRequestPath() atomically:YES]) return;
    chmod(RSCameraRequestPath().fileSystemRepresentation, 0644);
    notify_post(RS_CAMERA_FINISHED);
    [self leave];
}
- (void)leave {
    RSInlineCamera *camera = self.camera;
    [camera stop]; [camera willMoveToParentViewController:nil];
    [camera.view removeFromSuperview]; [camera removeFromParentViewController]; self.camera = nil;
    SEL suspend = NSSelectorFromString(@"suspend");
    if ([UIApplication.sharedApplication respondsToSelector:suspend])
        ((void (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, suspend);
}
@end

@interface RSCameraApp : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation RSCameraApp
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.backgroundColor = UIColor.clearColor; self.window.opaque = NO;
    self.window.rootViewController = [RSCameraHost new]; [self.window makeKeyAndVisible]; return YES;
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary *)options {
    if (![url.scheme isEqualToString:@"regionshot-camera"]) return NO;
    [(RSCameraHost *)self.window.rootViewController start]; return YES;
}
@end
int main(int argc, char **argv) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(RSCameraApp.class)); } }
