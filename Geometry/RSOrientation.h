#import <UIKit/UIKit.h>
#import <objc/message.h>

static inline UIInterfaceOrientation RSActiveOrientation(UIWindowScene *scene) {
    UIApplication *application = UIApplication.sharedApplication;
    SEL selector = NSSelectorFromString(@"activeInterfaceOrientation");
    NSInteger value = [application respondsToSelector:selector] ? ((NSInteger (*)(id, SEL))objc_msgSend)(application, selector) : UIInterfaceOrientationUnknown;
    UIInterfaceOrientation orientation = value >= UIInterfaceOrientationPortrait && value <= UIInterfaceOrientationLandscapeRight ? (UIInterfaceOrientation)value : UIInterfaceOrientationUnknown;
    if (orientation == UIInterfaceOrientationUnknown) orientation = scene.interfaceOrientation;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (orientation == UIInterfaceOrientationUnknown) orientation = application.statusBarOrientation;
#pragma clang diagnostic pop
    return orientation == UIInterfaceOrientationUnknown || orientation == UIInterfaceOrientationPortraitUpsideDown ? UIInterfaceOrientationPortrait : orientation;
}
