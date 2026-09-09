#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
static inline void RSOpenWindowSurface(UIView *surface) {
    if (!surface) return;
    [surface.superview layoutIfNeeded];
    if (UIAccessibilityIsReduceMotionEnabled()) return;
    CASpringAnimation *spring = [CASpringAnimation animationWithKeyPath:@"transform.scale"];
    spring.fromValue = @0.94; spring.toValue = @1; spring.mass = 1; spring.stiffness = 260; spring.damping = 25;
    spring.duration = spring.settlingDuration;
    [surface.layer addAnimation:spring forKey:@"rs.open.scale"];
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0; fade.toValue = @1; fade.duration = 0.18;
    [surface.layer addAnimation:fade forKey:@"rs.open.opacity"];
}
static inline void RSCloseWindowSurface(UIWindow *window, UIView *surface) {
    if (!window) return;
    window.userInteractionEnabled = NO;
    void (^finish)(void) = ^{ window.hidden = YES; window.rootViewController = nil; };
    if (!surface || window.hidden || !UIApplication.sharedApplication.protectedDataAvailable || UIAccessibilityIsReduceMotionEnabled()) { finish(); return; }
    // Retain only the departing window. A newly opened window is never touched
    // by this completion, including when close/open happen on the same turn.
    [surface.layer removeAnimationForKey:@"rs.open.scale"];
    [surface.layer removeAnimationForKey:@"rs.open.opacity"];
    [UIView animateWithDuration:0.24 delay:0 usingSpringWithDamping:0.92 initialSpringVelocity:0
        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
        animations:^{ surface.transform = CGAffineTransformMakeScale(0.95, 0.95); window.alpha = 0; }
        completion:^(BOOL finished) { finish(); }];
}
