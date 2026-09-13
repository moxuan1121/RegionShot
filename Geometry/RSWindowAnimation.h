#import <UIKit/UIKit.h>
static inline void RSOpenWindowSurfaceOverBackdropCompletion(UIView *surface, UIView *backdrop, UIColor *backgroundColor,
                                                              void (^completion)(void)) {
    if (!surface) return;
    [surface.superview layoutIfNeeded];
    surface.alpha = 0;
    if (backdrop) backdrop.backgroundColor = UIColor.clearColor;
    [UIView animateWithDuration:0.65 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{
        surface.alpha = 1;
        if (backdrop) backdrop.backgroundColor = backgroundColor;
    } completion:^(__unused BOOL finished) { if (completion) completion(); }];
}
static inline void RSOpenWindowSurfaceOverBackdrop(UIView *surface, UIView *backdrop, UIColor *backgroundColor) {
    RSOpenWindowSurfaceOverBackdropCompletion(surface, backdrop, backgroundColor, nil);
}
static inline void RSOpenWindowSurface(UIView *surface) {
    RSOpenWindowSurfaceOverBackdrop(surface, nil, nil);
}
static inline void RSCloseWindowSurface(UIWindow *window, UIView *surface) {
    if (!window) return;
    window.userInteractionEnabled = NO;
    [UIView animateWithDuration:0.45 delay:0 options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionCurveEaseInOut animations:^{ window.alpha = 0; } completion:^(BOOL finished) { window.hidden = YES; window.rootViewController = nil; }];
}
