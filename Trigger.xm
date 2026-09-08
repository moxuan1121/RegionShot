#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>
#include <dlfcn.h>
#import "Manager/RSRegionShotManager.h"
#import "Capture/RSScreenCapture.h"
#import "Capture/RSCaptureStatus.h"
#import "Preferences/RSOptions.h"
#import "AI/RSChatController.h"
#import "Geometry/RSGeometry.h"
#import "Geometry/RSOrientation.h"
@interface _UIStatusBar : UIView
@end
@interface SpringBoard : UIApplication
- (void)takeScreenshot;
- (void)takeScreenshotAndEdit:(BOOL)edit;
@end
@interface SBCombinationHardwareButtonActions : NSObject
- (void)performTakeScreenshotAction;
@end
@interface SSScreenCapturer : NSObject
- (void)takeScreenshotWithPresentationOptions:(id)options;
@end
static BOOL RSEnabled = YES;
static BOOL RSTargetOrientationInstalled;
static __thread NSUInteger RSOriginalDepth;
static BOOL RSNativeScreenshotPending;
static int RSCheckToken = -1, RSStatusToken = -1;
static uint32_t RSHookStatus;
static void RSReload(void) {
    RSReloadOptions();
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"];
    [prefs synchronize];
    RSEnabled = ![prefs objectForKey:@"Enabled"] || [prefs boolForKey:@"Enabled"];
}
static BOOL RSTryCapture(NSString *source) {
    if (RSOriginalDepth || RSNativeScreenshotPending) return NO;
    if (!NSThread.isMainThread) {
        __block BOOL handled;
        dispatch_sync(dispatch_get_main_queue(), ^{ handled = RSTryCapture(source); });
        return handled;
    }
    if (!RSEnabled) return NO;
    RSRegionShotManager *manager = RSRegionShotManager.sharedManager;
    if (manager.isInternalCapture) return NO;
    if (manager.isCapturing) return YES;
    NSLog(@"[RegionShot] screenshot entry: %@", source);
    @try { return [manager beginCapture]; }
    @catch (NSException *exception) {
        [manager cancelCapture];
        NSLog(@"[RegionShot] capture failed at %@: %@", source, exception.name);
        return NO;
    }
}
BOOL RSRequestNativeScreenshot(void) {
    NSCAssert(NSThread.isMainThread, @"Native screenshot requires main thread");
    SpringBoard *app = (id)UIApplication.sharedApplication;
    if (![app respondsToSelector:@selector(takeScreenshot)]) return NO;
    RSNativeScreenshotPending = YES;
    RSOriginalDepth++;
    @try { [app takeScreenshot]; }
    @finally { RSOriginalDepth--; }
    // The capturer consumes this bypass. Expire it if that private path is absent.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ RSNativeScreenshotPending = NO; });
    return YES;
}
@interface RSStatusBarGesture : NSObject <UIGestureRecognizerDelegate>
@end
@implementation RSStatusBarGesture
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    UIView *view = gesture.view;
    CGPoint point = [touch locationInView:view]; CGRect bounds = view.bounds;
    return RSEnabled && !RSRegionShotManager.sharedManager.isCapturing && [RSOption(@"StatusBarSwipe") boolValue] && view.window && !view.hidden && view.alpha > 0.01 &&
        RSInStatusBarRightRegion(point.x - bounds.origin.x, point.y - bounds.origin.y, bounds.size.width, bounds.size.height);
}
- (void)swiped:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized || !gesture.view.window) return;
    dispatch_async(dispatch_get_main_queue(), ^{ if ([RSOption(@"StatusBarSwipe") boolValue]) RSTryCapture(@"StatusBar.rightSwipe"); });
}
@end
static char RSStatusBarGestureKey;
%group RSStatusBarEntry
%hook _UIStatusBar
- (void)didMoveToWindow {
    %orig;
    if (!self.window || !NSThread.isMainThread || objc_getAssociatedObject(self, &RSStatusBarGestureKey)) return;
    static RSStatusBarGesture *target; static dispatch_once_t once;
    dispatch_once(&once, ^{ target = [RSStatusBarGesture new]; });
    UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:target action:@selector(swiped:)];
    swipe.direction = UISwipeGestureRecognizerDirectionRight; swipe.numberOfTouchesRequired = 1;
    swipe.delegate = target; swipe.cancelsTouchesInView = NO;
    [self addGestureRecognizer:swipe]; objc_setAssociatedObject(self, &RSStatusBarGestureKey, swipe, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end
%end
// Block SpringBoard's system touch routing only while the frozen selection is visible.
%group RSFrozenSystemGestures
%hook SBSystemGestureManager
- (BOOL)shouldSystemGestureReceiveTouchWithLocation:(CGPoint)location {
    if (RSRegionShotManager.sharedManager.isFrozenSelectionVisible) return NO;
    return %orig;
}
%end
%end

// Broadcast the actual SpringBoard orientation change to live overlays.
%group RSTargetOrientation
%hook SpringBoard
- (void)noteInterfaceOrientationChanged:(long long)orientation duration:(double)duration updateMirroredDisplays:(BOOL)update force:(BOOL)force logMessage:(id)message {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:@"com.moxuan.regionshot.orientation.target" object:nil userInfo:@{@"orientation":@(orientation)}]; });
}
%end
%end
%group RSOrientationUpdates
%hook SpringBoard
- (void)_postActiveInterfaceOrientationChangedNotificationAnimated:(BOOL)animated {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:@"com.moxuan.regionshot.orientation" object:nil];
        if (!RSTargetOrientationInstalled) [NSNotificationCenter.defaultCenter postNotificationName:@"com.moxuan.regionshot.orientation.target" object:nil userInfo:@{@"orientation":@(RSActiveOrientation(nil))}];
    });
}
%end
%end

%group RSApplicationEntry
%hook SpringBoard
- (void)takeScreenshot {
    if (RSTryCapture(@"SpringBoard.takeScreenshot")) return;
    RSOriginalDepth++;
    @try { %orig; } @finally { RSOriginalDepth--; }
}
%end
%end
%group RSEditEntry
%hook SpringBoard
- (void)takeScreenshotAndEdit:(BOOL)edit {
    if (RSTryCapture(@"SpringBoard.takeScreenshotAndEdit:")) return;
    RSOriginalDepth++;
    @try { %orig(edit); } @finally { RSOriginalDepth--; }
}
%end
%end
%group RSHardwareEntry
%hook SBCombinationHardwareButtonActions
- (void)performTakeScreenshotAction {
    if (RSTryCapture(@"hardware.performTakeScreenshotAction")) return;
    RSOriginalDepth++;
    @try { %orig; } @finally { RSOriginalDepth--; }
}
%end
%end
%group RSCapturerEntry
%hook SSScreenCapturer
- (void)takeScreenshotWithPresentationOptions:(id)options {
    if (RSNativeScreenshotPending) {
        RSOriginalDepth++;
        @try { %orig(options); } @finally { RSOriginalDepth--; RSNativeScreenshotPending = NO; }
        return;
    }
    if (RSTryCapture(@"SSScreenCapturer.takeScreenshotWithPresentationOptions:")) return;
    RSOriginalDepth++;
    @try { %orig(options); } @finally { RSOriginalDepth--; }
}
%end
%end
static BOOL RSCompatible(Class cls, NSString *name, const char *argumentTypes) {
    Method method = cls ? class_getInstanceMethod(cls, NSSelectorFromString(name)) : NULL;
    if (!method || method_getNumberOfArguments(method) != (argumentTypes ? 3u : 2u)) return NO;
    char type[16] = {0}; method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'v') return NO;
    if (argumentTypes) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (!type[0] || !strchr(argumentTypes, type[0])) return NO;
    }
    return YES;
}
static void RSPreferenceEvent(CFNotificationCenterRef center, void *observer, CFStringRef name,
                              const void *object, CFDictionaryRef info) {
    if ((CFEqual(name, CFSTR("com.moxuan.regionshot/History")) || CFEqual(name, CFSTR("com.jontelang.snapper3.history")))) {
        dispatch_async(dispatch_get_main_queue(), ^{ [RSRegionShotManager.sharedManager showHistory]; }); return;
    }
    if (CFEqual(name, CFSTR("com.moxuan.regionshot/AIWindow"))) {
        dispatch_async(dispatch_get_main_queue(), ^{ [RSChatController showImage:nil scene:nil]; }); return;
    }
    if (CFEqual(name, CFSTR("com.moxuan.regionshot/AISettings"))) {
        dispatch_async(dispatch_get_main_queue(), ^{ [RSChatController showServiceSettings]; });
        return;
    }
    if (CFEqual(name, CFSTR(RS_CAPTURE_CHECK))) {
        uint64_t request = 0;
        if (RSCheckToken < 0 || notify_get_state(RSCheckToken, &request) != NOTIFY_STATUS_OK) return;
        dispatch_async(dispatch_get_main_queue(), ^{
            RSReload();
            uint32_t status = RSStatusLoaded | RSHookStatus;
            if (RSEnabled) status |= RSStatusEnabled;
            if ([RSScreenCapture isCaptureAvailable]) status |= RSStatusSymbol;
            if ((request & 1) && RSTryCapture(@"Settings.test")) status |= RSStatusStarted;
            if (RSStatusToken >= 0) {
                notify_set_state(RSStatusToken, (request & UINT64_C(0xffffffff00000000)) | status);
                notify_post(RS_CAPTURE_STATUS);
            }
        });
        return;
    }
    BOOL launch = CFEqual(name, CFSTR("com.moxuan.regionshot/TakeScreenshot"));
    dispatch_async(dispatch_get_main_queue(), ^{ RSReload(); if (launch) RSTryCapture(@"Settings.test"); });
}
%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        RSReload();
        if ([NSClassFromString(@"_UIStatusBar") isSubclassOfClass:UIView.class]) { %init(RSStatusBarEntry); }
        Class gestures = NSClassFromString(@"SBSystemGestureManager");
        Method receiveTouch = class_getInstanceMethod(gestures, NSSelectorFromString(@"shouldSystemGestureReceiveTouchWithLocation:"));
        char returnType[16] = {0}, argumentType[128] = {0};
        if (receiveTouch) {
            method_getReturnType(receiveTouch, returnType, sizeof(returnType));
            method_getArgumentType(receiveTouch, 2, argumentType, sizeof(argumentType));
        }
        if (receiveTouch && method_getNumberOfArguments(receiveTouch) == 3 &&
            (returnType[0] == 'B' || returnType[0] == 'c') && strcmp(argumentType, @encode(CGPoint)) == 0) {
            %init(RSFrozenSystemGestures);
            NSLog(@"[RegionShot] frozen system touch gate installed");
        } else NSLog(@"[RegionShot] frozen system touch gate unavailable");
        Class app = NSClassFromString(@"SpringBoard");
        if (RSCompatible(app, @"_postActiveInterfaceOrientationChangedNotificationAnimated:", "Bc")) { %init(RSOrientationUpdates); }
        Method rotate = class_getInstanceMethod(app, NSSelectorFromString(@"noteInterfaceOrientationChanged:duration:updateMirroredDisplays:force:logMessage:"));
        if (rotate && method_getNumberOfArguments(rotate) == 7) {
            char type[32] = {0}; method_getReturnType(rotate, type, sizeof(type)); BOOL compatible = type[0] == 'v';
            const char *types[] = {"q", "d", "Bc", "Bc", "@"};
            for (unsigned int index = 2; index < 7; index++) { method_getArgumentType(rotate, index, type, sizeof(type)); compatible = compatible && type[0] && strchr(types[index - 2], type[0]); }
            if (compatible) { %init(RSTargetOrientation); RSTargetOrientationInstalled = YES; }
        }
        Class hardware = NSClassFromString(@"SBCombinationHardwareButtonActions");
        BOOL direct = RSCompatible(app, @"takeScreenshot", NULL);
        BOOL edit = RSCompatible(app, @"takeScreenshotAndEdit:", "Bc");
        BOOL keys = RSCompatible(hardware, @"performTakeScreenshotAction", NULL);
        BOOL capturer = RSCompatible(NSClassFromString(@"SSScreenCapturer"), @"takeScreenshotWithPresentationOptions:", "@");
        if (direct) { %init(RSApplicationEntry); }
        if (edit) { %init(RSEditEntry); }
        if (keys) { %init(RSHardwareEntry); }
        if (capturer) { %init(RSCapturerEntry); }
        RSHookStatus = (keys ? RSStatusHardware : 0) | (direct ? RSStatusApplication : 0) |
                       (edit ? RSStatusEdit : 0) | (capturer ? RSStatusCapturer : 0);
        if (notify_register_check(RS_CAPTURE_CHECK, &RSCheckToken) != NOTIFY_STATUS_OK) RSCheckToken = -1;
        if (notify_register_check(RS_CAPTURE_STATUS, &RSStatusToken) != NOTIFY_STATUS_OK) RSStatusToken = -1;
        CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/AIWindow"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.jontelang.snapper3.history"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterRef (*distributedCenter)(void) = (CFNotificationCenterRef (*)(void))dlsym(RTLD_DEFAULT, "CFNotificationCenterGetDistributedCenter");
        CFNotificationCenterRef snapperCenter = distributedCenter ? distributedCenter() : NULL;
        if (snapperCenter) CFNotificationCenterAddObserver(snapperCenter, NULL, RSPreferenceEvent, CFSTR("com.jontelang.snapper3.history"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        Class distributed = snapperCenter ? Nil : NSClassFromString(@"NSDistributedNotificationCenter");
        if ([distributed respondsToSelector:@selector(defaultCenter)]) {
            id notifications = [distributed performSelector:@selector(defaultCenter)];
            [notifications addObserverForName:@"com.jontelang.snapper3.history" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { [RSRegionShotManager.sharedManager showHistory]; }];
        }
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/History"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/AISettings"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR(RS_CAPTURE_CHECK), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/TakeScreenshot"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        NSLog(@"[RegionShot] installed entries: hardware=%d application=%d edit=%d capturer=%d", keys, direct, edit, capturer);
    }
}
