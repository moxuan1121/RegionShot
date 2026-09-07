#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Manager/RSRegionShotManager.h"
@interface SpringBoard : UIApplication
- (void)takeScreenshot;
- (void)takeScreenshotAndEdit:(BOOL)edit;
@end
@interface SBCombinationHardwareButtonActions : NSObject
- (void)performTakeScreenshotAction;
@end
static BOOL RSEnabled = YES;
static __thread NSUInteger RSOriginalDepth;
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
static BOOL RSCompatible(Class cls, NSString *name, BOOL booleanArgument) {
    Method method = cls ? class_getInstanceMethod(cls, NSSelectorFromString(name)) : NULL;
    if (!method || method_getNumberOfArguments(method) != (booleanArgument ? 3u : 2u)) return NO;
    char type[16] = {0}; method_getReturnType(method, type, sizeof(type));
    if (type[0] != 'v') return NO;
    if (booleanArgument) {
        method_getArgumentType(method, 2, type, sizeof(type));
        if (type[0] != 'B' && type[0] != 'c') return NO;
    }
    return YES;
}
static void RSPreferenceEvent(CFNotificationCenterRef center, void *observer, CFStringRef name,
                              const void *object, CFDictionaryRef info) {
    BOOL launch = CFEqual(name, CFSTR("com.moxuan.regionshot/TakeScreenshot"));
    dispatch_async(dispatch_get_main_queue(), ^{ RSReload(); if (launch) RSTryCapture(@"Settings.test"); });
}
%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        RSReload();
        Class app = NSClassFromString(@"SpringBoard");
        Class hardware = NSClassFromString(@"SBCombinationHardwareButtonActions");
        BOOL direct = RSCompatible(app, @"takeScreenshot", NO);
        BOOL edit = RSCompatible(app, @"takeScreenshotAndEdit:", YES);
        BOOL keys = RSCompatible(hardware, @"performTakeScreenshotAction", NO);
        if (direct) { %init(RSApplicationEntry); }
        if (edit) { %init(RSEditEntry); }
        if (keys) { %init(RSHardwareEntry); }
        CFNotificationCenterRef center = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/ReloadPrefs"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(center, NULL, RSPreferenceEvent, CFSTR("com.moxuan.regionshot/TakeScreenshot"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        NSLog(@"[RegionShot] installed entries: hardware=%d application=%d edit=%d", keys, direct, edit);
    }
}
