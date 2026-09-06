#import "RSFloatingWindow.h"

@implementation RSFloatingWindow

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 50;
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        UIViewController *controller = [UIViewController new];
        controller.view.backgroundColor = UIColor.clearColor;
        self.rootViewController = controller;
    }
    return self;
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
