#import "RSFloatingWindow.h"
#import "RSFloatingImageView.h"
#import "../Geometry/RSOrientation.h"

@interface RSFloatingController : UIViewController
@property (nonatomic) BOOL centerImages;
@property (nonatomic) UIInterfaceOrientation targetOrientation;
@end
@implementation RSFloatingController
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.centerImages) return;
    BOOL landscape = UIInterfaceOrientationIsLandscape(self.targetOrientation);
    if (landscape != (self.view.bounds.size.width > self.view.bounds.size.height)) return;
    self.centerImages = NO;
    CGPoint center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.3 delay:0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionCurveEaseInOut
        animations:^{
            for (UIView *view in self.view.subviews)
                if ([view isKindOfClass:RSFloatingImageView.class]) view.center = center;
        } completion:nil];
}
- (BOOL)shouldAutorotate { return NO; }
- (BOOL)autorotate { return NO; }
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
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(deviceRotated:) name:@"com.moxuan.regionshot.orientation.target" object:nil];
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

- (void)deviceRotated:(NSNotification *)note {
    if (self.hidden) return;
    // SpringBoard supplies its interface target; never infer it from accelerometer names.
    NSNumber *target = note.userInfo[@"orientation"];
    UIInterfaceOrientation orientation = target ? target.integerValue : RSActiveOrientation(self.windowScene);
    RSFloatingController *controller = (RSFloatingController *)self.rootViewController;
    if (!RSValidInterfaceOrientation((int)orientation)) return;
    if (controller.targetOrientation == orientation) return;
    controller.targetOrientation = orientation; controller.centerImages = YES;
    if ([self respondsToSelector:@selector(_setRotatableViewOrientation:updateStatusBar:duration:force:)])
        [self _setRotatableViewOrientation:orientation updateStatusBar:NO duration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.3 force:YES];
    else RSApplyWindowOrientation(self, orientation);
    [controller.view setNeedsLayout]; [controller.view layoutIfNeeded];
}
- (void)updateOrientation {
    if (self.hidden) return;
    UIInterfaceOrientation orientation = RSActiveOrientation(self.windowScene);
    ((RSFloatingController *)self.rootViewController).targetOrientation = orientation;
    RSApplyWindowOrientation(self, orientation);
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
