#import <UIKit/UIKit.h>
#import <objc/message.h>

@interface UIWindow (RSOrientationPrivate)
- (void)_setRotatableViewOrientation:(UIInterfaceOrientation)orientation updateStatusBar:(BOOL)update duration:(NSTimeInterval)duration force:(BOOL)force;
- (void)_setWindowControlsStatusBarOrientation:(BOOL)controls;
@end

static inline void RSApplyWindowOrientation(UIWindow *window, UIInterfaceOrientation orientation) {
    // Rotate this window's content without changing the foreground app's status bar/scene.
    if ([window respondsToSelector:@selector(_setWindowControlsStatusBarOrientation:)])
        [window _setWindowControlsStatusBarOrientation:NO];
    if ([window respondsToSelector:@selector(_setRotatableViewOrientation:updateStatusBar:duration:force:)])
        [window _setRotatableViewOrientation:orientation updateStatusBar:NO duration:0 force:YES];
}

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
