#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>
static BOOL RSLongActive;
static NSUInteger RSLeaseEpoch;
static char RSIndicatorKey;
static void RSIndicators(UIScrollView *scroll, BOOL hide) {
    NSArray *saved = objc_getAssociatedObject(scroll, &RSIndicatorKey);
    if (hide) {
        if (!saved) objc_setAssociatedObject(scroll, &RSIndicatorKey, @[@(scroll.showsVerticalScrollIndicator), @(scroll.showsHorizontalScrollIndicator)], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        scroll.showsVerticalScrollIndicator = NO; scroll.showsHorizontalScrollIndicator = NO;
    } else if (saved) {
        objc_setAssociatedObject(scroll, &RSIndicatorKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        scroll.showsVerticalScrollIndicator = [saved[0] boolValue]; scroll.showsHorizontalScrollIndicator = [saved[1] boolValue];
    }
}
static void RSVisitScrolls(UIView *view) {
    if ([view isKindOfClass:UIScrollView.class]) RSIndicators((id)view, RSLongActive);
    for (UIView *child in view.subviews) RSVisitScrolls(child);
}
%group RSScrollCapture
%hook UIScrollView
- (void)didMoveToWindow { %orig; if (RSLongActive) RSIndicators(self, YES); }
- (void)setShowsVerticalScrollIndicator:(BOOL)show { %orig(RSLongActive ? NO : show); }
- (void)setShowsHorizontalScrollIndicator:(BOOL)show { %orig(RSLongActive ? NO : show); }
%end
%end
%ctor {
    if (![NSBundle.mainBundle.bundlePath.pathExtension isEqual:@"app"] || [NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
    %init(RSScrollCapture);
    int token;
    notify_register_dispatch("com.moxuan.regionshot/LongCaptureState", &token, dispatch_get_main_queue(), ^(int value) {
        uint64_t state = 0; notify_get_state(value, &state); RSLongActive = state > (uint64_t)NSDate.date.timeIntervalSince1970;
        NSUInteger epoch = ++RSLeaseEpoch;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (epoch != RSLeaseEpoch || !RSLongActive) return;
            RSLongActive = NO;
            for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class])
                for (UIWindow *window in ((UIWindowScene *)scene).windows) RSVisitScrolls(window);
        });
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) if ([scene isKindOfClass:UIWindowScene.class])
            for (UIWindow *window in ((UIWindowScene *)scene).windows) RSVisitScrolls(window);
    });
}
