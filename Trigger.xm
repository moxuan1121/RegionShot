#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>
#include <dlfcn.h>
#include <atomic>
#import "Manager/RSRegionShotManager.h"
#import "Preferences/RSOptions.h"
#import "AI/RSChatController.h"
#import "Input/RSInputClipboard.h"
#import "KeyboardAI/RSKAInterface.h"
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
@interface SBLockScreenManager : NSObject
- (BOOL)_finishUIUnlockFromSource:(int)source withOptions:(id)options;
@end
@interface SSScreenCapturer : NSObject
- (void)takeScreenshotWithPresentationOptions:(id)options;
@end
static BOOL RSEnabled = YES;
static BOOL RSStatusBarSwipeEnabled = YES;
static BOOL RSTargetOrientationInstalled;
static __thread NSUInteger RSOriginalDepth;
static std::atomic<bool> RSNativeScreenshotPending(false);
static NSUInteger RSNativeScreenshotGeneration;
static CFAbsoluteTime RSLastUnlock;
static BOOL RSDelayFirstAIWindow;
static NSUInteger RSUnlockGeneration;
static void RSReload(void) {
    RSReloadOptions();
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"];
    [prefs synchronize];
    RSEnabled = ![prefs objectForKey:@"Enabled"] || [prefs boolForKey:@"Enabled"];
    RSStatusBarSwipeEnabled = [RSOption(@"StatusBarSwipe") boolValue];
}
static BOOL RSTryCapture(void) {
    if (RSOriginalDepth || RSNativeScreenshotPending) return NO;
    if (!NSThread.isMainThread) {
        __block BOOL handled;
        dispatch_sync(dispatch_get_main_queue(), ^{ handled = RSTryCapture(); });
        return handled;
    }
    if (!RSEnabled) return NO;
    RSRegionShotManager *manager = RSRegionShotManager.sharedManager;
    if (manager.isInternalCapture) return NO;
    if (manager.isCapturing) return YES;

    @try { return [manager beginCapture]; }
    @catch (NSException *exception) {
        [manager cancelCapture];

        return NO;
    }
}
extern "C" BOOL RSRequestNativeScreenshot(void) {
    NSCAssert(NSThread.isMainThread, @"Native screenshot requires main thread");
    SpringBoard *app = (id)UIApplication.sharedApplication;
    if (![app respondsToSelector:@selector(takeScreenshot)]) return NO;
    RSNativeScreenshotPending = YES;
    NSUInteger generation = ++RSNativeScreenshotGeneration;
    RSOriginalDepth++;
    @try { [app takeScreenshot]; }
    @catch (NSException *exception) { RSNativeScreenshotPending = false; return NO; }
    @finally { RSOriginalDepth--; }
    // The capturer consumes this bypass. Expire it if that private path is absent.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation == RSNativeScreenshotGeneration) RSNativeScreenshotPending = NO;
    });
    return YES;
}
@interface RSStatusBarGesture : NSObject <UIGestureRecognizerDelegate>
@end
@implementation RSStatusBarGesture
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    UIView *view = gesture.view;
    CGPoint point = [touch locationInView:view]; CGRect bounds = view.bounds;
    return RSEnabled && RSStatusBarSwipeEnabled && !RSRegionShotManager.sharedManager.isCapturing && view.window && !view.hidden && view.alpha > 0.01 &&
        RSInStatusBarRightRegion(point.x - bounds.origin.x, point.y - bounds.origin.y, bounds.size.width, bounds.size.height);
}
- (void)swiped:(UISwipeGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateRecognized || !gesture.view.window) return;
    dispatch_async(dispatch_get_main_queue(), ^{ if (RSStatusBarSwipeEnabled) RSTryCapture(); });
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
    if (RSTryCapture()) return;
    RSOriginalDepth++;
    @try { %orig; } @finally { RSOriginalDepth--; }
}
%end
%end
%group RSEditEntry
%hook SpringBoard
- (void)takeScreenshotAndEdit:(BOOL)edit {
    if (RSTryCapture()) return;
    RSOriginalDepth++;
    @try { %orig(edit); } @finally { RSOriginalDepth--; }
}
%end
%end
%group RSHardwareEntry
%hook SBCombinationHardwareButtonActions
- (void)performTakeScreenshotAction {
    if (RSTryCapture()) return;
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
    if (RSTryCapture()) return;
    RSOriginalDepth++;
    @try { %orig(options); } @finally { RSOriginalDepth--; }
}
%end
%end
%group RSUnlockLifecycle
%hook SBLockScreenManager
- (BOOL)_finishUIUnlockFromSource:(int)source withOptions:(id)options {
    BOOL result = %orig(source, options);
    RSLastUnlock = CFAbsoluteTimeGetCurrent();
    RSDelayFirstAIWindow = YES;
    RSUnlockGeneration++;
    return result;
}
%end
%end
static BOOL RSUnlockCompatible(Class cls) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(@"_finishUIUnlockFromSource:withOptions:"));
    if (!method || method_getNumberOfArguments(method) != 4) return NO;
    char type[16] = {0}; method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'B' && type[0] != 'c') return NO;
    method_getArgumentType(method, 2, type, sizeof(type)); if (type[0] != 'i') return NO;
    method_getArgumentType(method, 3, type, sizeof(type)); return type[0] == '@';
}
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
    if (CFEqual(name, CFSTR("com.apple.springboard.lockcomplete"))) {
        dispatch_async(dispatch_get_main_queue(), ^{ RSDelayFirstAIWindow = NO; RSUnlockGeneration++; [RSRegionShotManager.sharedManager cancelCapture]; [RSChatController minimizeForLock]; }); return;
    }
    if ((CFEqual(name, CFSTR("com.moxuan.regionshot/History")) || CFEqual(name, CFSTR("com.jontelang.snapper3.history")))) {
        dispatch_async(dispatch_get_main_queue(), ^{ [RSRegionShotManager.sharedManager showHistory]; }); return;
    }
    if (CFEqual(name, CFSTR("com.moxuan.regionshot/AIWindow"))) {
        dispatch_async(dispatch_get_main_queue(), ^{
            CFTimeInterval age = CFAbsoluteTimeGetCurrent() - RSLastUnlock;
            BOOL delay = RSDelayFirstAIWindow && age >= 0 && age < 3.0;
            RSDelayFirstAIWindow = NO;
            NSUInteger generation = RSUnlockGeneration;
            void (^show)(void) = ^{ if (generation == RSUnlockGeneration) [RSChatController showImage:nil scene:nil]; };
            if (delay) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), show);
            else show();
        }); return;
    }
    if (CFEqual(name, CFSTR("com.moxuan.regionshot/AICamera"))) {
        dispatch_async(dispatch_get_main_queue(), ^{ [RSChatController showCameraInScene:nil]; }); return;
    }
    if (CFEqual(name, CFSTR("com.moxuan.regionshot/AISettings"))) {
        dispatch_async(dispatch_get_main_queue(), ^{ [RSChatController showServiceSettings]; });
        return;
    }
    BOOL launch = CFEqual(name, CFSTR("com.moxuan.regionshot/TakeScreenshot"));
    dispatch_async(dispatch_get_main_queue(), ^{ RSReload(); if (launch) RSTryCapture(); });
}
%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        RSReload();
        RSInputStartClipboardPrompt();
        [NSNotificationCenter.defaultCenter addObserverForName:@"com.moxuan.regionshot.input.close" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) { RSKAClosePanel(); }];
        [NSNotificationCenter.defaultCenter addObserverForName:@"com.moxuan.regionshot.input.tokens" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            NSDictionary *request = note.object;
            NSString *text = [request isKindOfClass:NSDictionary.class] ? request[@"text"] : nil;
            if ([text isKindOfClass:NSString.class] && text.length <= 24000) {
                if ([request isKindOfClass:NSMutableDictionary.class]) ((NSMutableDictionary *)request)[@"handled"] = @YES;
                RSKAOpenTokens(text);
            }
        }];

        if ([NSClassFromString(@"_UIStatusBar") isSubclassOfClass:UIView.class]) { %init(RSStatusBarEntry); }
        Class lockManager = NSClassFromString(@"SBLockScreenManager");
        if (RSUnlockCompatible(lockManager)) { %init(RSUnlockLifecycle); }
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

        }
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
        CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.apple.springboard.lockcomplete"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/AIWindow"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/AICamera"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
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
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/TakeScreenshot"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

    }
}
