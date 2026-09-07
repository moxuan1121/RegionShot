#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>
#import "Manager/RSRegionShotManager.h"
#import "Capture/RSScreenCapture.h"
#import "Capture/RSCaptureStatus.h"
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
static __thread NSUInteger RSOriginalDepth;
static int RSCheckToken = -1, RSStatusToken = -1;
static uint32_t RSHookStatus;
static void RSReload(void) {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"];
    [prefs synchronize];
    RSEnabled = ![prefs objectForKey:@"Enabled"] || [prefs boolForKey:@"Enabled"];
}
static BOOL RSTryCapture(NSString *source) {
    if (RSOriginalDepth) return NO;
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
        Class app = NSClassFromString(@"SpringBoard");
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
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR(RS_CAPTURE_CHECK), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/TakeScreenshot"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        NSLog(@"[RegionShot] installed entries: hardware=%d application=%d edit=%d capturer=%d", keys, direct, edit, capturer);
    }
}
