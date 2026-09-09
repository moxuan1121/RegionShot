#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
static inline void RSOpenWindowSurface(UIView *surface) {
    if (!surface) return;
    [surface.superview layoutIfNeeded];
    surface.alpha = 1;
    CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"opacity"];
    fade.fromValue = @0; fade.toValue = @1; fade.duration = 0.65;
    fade.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [surface.layer addAnimation:fade forKey:@"rs.open.fade"];

}
static inline void RSCloseWindowSurface(UIWindow *window, UIView *surface) {
    if (!window) return;
    window.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.45 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{ window.alpha = 0; } completion:^(BOOL finished) { window.hidden = YES; window.rootViewController = nil; }];
}
