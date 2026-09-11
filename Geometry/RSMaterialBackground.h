#import <UIKit/UIKit.h>

static inline void RSInstallMaterialBackground(UIView *view, CGFloat cornerRadius) {
    view.backgroundColor = UIColor.clearColor;
    UIVisualEffectView *material = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    material.userInteractionEnabled = NO;
    material.translatesAutoresizingMaskIntoConstraints = NO;
    material.layer.cornerRadius = cornerRadius;
    material.layer.cornerCurve = kCACornerCurveContinuous;
    material.clipsToBounds = YES;
    [view insertSubview:material atIndex:0];
    [NSLayoutConstraint activateConstraints:@[
        [material.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [material.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [material.topAnchor constraintEqualToAnchor:view.topAnchor],
        [material.bottomAnchor constraintEqualToAnchor:view.bottomAnchor]
    ]];
}
