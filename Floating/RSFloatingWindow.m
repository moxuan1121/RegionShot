#import "RSFloatingWindow.h"
#import "../Geometry/RSOrientation.h"

@interface RSFloatingController : UIViewController
@end
@implementation RSFloatingController
- (BOOL)shouldAutorotate { return YES; }
- (BOOL)autorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return RSActiveOrientation(self.view.window.windowScene);
}
@end

@implementation RSFloatingWindow

- (void)configureWindow {
    self.windowLevel = UIWindowLevelAlert + 50;
    self.backgroundColor = UIColor.clearColor;
    self.opaque = NO;
    UIViewController *controller = [RSFloatingController new];
    controller.view.backgroundColor = UIColor.clearColor;
    self.rootViewController = controller;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateOrientation) name:@"com.moxuan.regionshot.orientation" object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateOrientation) name:UIDeviceOrientationDidChangeNotification object:nil];
    [self updateOrientation];
}

- (instancetype)initWithWindowScene:(UIWindowScene *)windowScene {
    self = [super initWithWindowScene:windowScene];
    if (self) {
        self.frame = windowScene.coordinateSpace.bounds;
        [self configureWindow];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self configureWindow];
    return self;
}

- (void)updateOrientation {
    if (self.hidden) return;
    RSApplyWindowOrientation(self, RSActiveOrientation(self.windowScene));
    [self.rootViewController.view setNeedsLayout];
    [self.rootViewController.view layoutIfNeeded];
}
- (BOOL)canBecomeKeyWindow { return NO; }

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (self.rootViewController.presentedViewController) return [super pointInside:point withEvent:event];
    for (UIView *view in self.rootViewController.view.subviews.reverseObjectEnumerator) {
        if (!view.hidden && view.userInteractionEnabled && view.alpha >= 0.01 &&
            [view pointInside:[view convertPoint:point fromView:self] withEvent:event]) return YES;
    }
    return NO;
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self.rootViewController.view ? nil : hit;
}

@end
