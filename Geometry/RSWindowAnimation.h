#import <UIKit/UIKit.h>
static inline void RSOpenWindowSurface(UIView *surface) {
    if (!surface) return;
    [surface.superview layoutIfNeeded];
    surface.alpha = 0;
    [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseOut animations:^{ surface.alpha = 1; } completion:nil];
}
static inline void RSCloseWindowSurface(UIWindow *window, UIView *surface) {
    if (!window) return;
    window.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.18 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseIn animations:^{ window.alpha = 0; } completion:^(BOOL finished) { window.hidden = YES; window.rootViewController = nil; }];
}
