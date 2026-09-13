#import <UIKit/UIKit.h>

static NSString *const RSProbePath = @"/var/mobile/Library/Caches/RegionShotURLFocusProbe.log";

static void RSProbeWrite(NSString *event, id object) {
    NSMutableString *line = [NSMutableString stringWithFormat:@"%.3f %@ object=%@\n", NSDate.date.timeIntervalSince1970, event, object ? NSStringFromClass([object class]) : @"nil"];
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            [line appendFormat:@"  window=%@ key=%d hidden=%d level=%.0f root=%@\n", NSStringFromClass(window.class), window.isKeyWindow, window.hidden, window.windowLevel, NSStringFromClass(window.rootViewController.class)];
    }
    if ([event containsString:@"Hide"] || [event containsString:@"Resign"] || [event containsString:@"EndEditing"])
        [line appendFormat:@"  stack=%@\n", NSThread.callStackSymbols];
    NSFileHandle *file = [NSFileHandle fileHandleForWritingAtPath:RSProbePath];
    if (!file) { [NSFileManager.defaultManager createFileAtPath:RSProbePath contents:nil attributes:nil]; file = [NSFileHandle fileHandleForWritingAtPath:RSProbePath]; }
    [file seekToEndOfFile]; [file writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [file closeFile];
}

static void RSProbeDarwin(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{ RSProbeWrite(@"DarwinAIWindow", nil); });
}

__attribute__((constructor)) static void RSInstallURLFocusProbe(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSFileManager.defaultManager removeItemAtPath:RSProbePath error:nil];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        NSDictionary<NSNotificationName, NSString *> *events = @{
            UIWindowDidBecomeKeyNotification: @"WindowDidBecomeKey",
            UIWindowDidResignKeyNotification: @"WindowDidResignKey",
            UIKeyboardWillShowNotification: @"KeyboardWillShow",
            UIKeyboardDidShowNotification: @"KeyboardDidShow",
            UIKeyboardWillHideNotification: @"KeyboardWillHide",
            UIKeyboardDidHideNotification: @"KeyboardDidHide",
            UITextViewTextDidBeginEditingNotification: @"TextDidBeginEditing",
            UITextViewTextDidEndEditingNotification: @"TextDidEndEditing",
            UIApplicationDidBecomeActiveNotification: @"ApplicationDidBecomeActive",
            UIApplicationWillResignActiveNotification: @"ApplicationWillResignActive"
        };
        [events enumerateKeysAndObjectsUsingBlock:^(NSNotificationName name, NSString *label, BOOL *stop) {
            [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { RSProbeWrite(label, note.object); }];
        }];
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, RSProbeDarwin,
            CFSTR("com.moxuan.regionshot/AIWindow"), NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        RSProbeWrite(@"ProbeInstalled", nil);
    });
}
