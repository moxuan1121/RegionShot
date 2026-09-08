#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <notify.h>
#import "RSURLRoute.h"
static BOOL RSHandleURL(id url) {
    NSString *notification = RSURLNotification(url);
    if (!notification) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{ notify_post(notification.UTF8String); });
    return YES;
}
%group RSSettingsURL
%hook PreferencesAppController
- (void)processURL:(id)url {
    if (!RSHandleURL(url)) %orig;
}
%end
%end
%group RSSettingsURLAnimated
%hook PreferencesAppController
- (void)processURL:(id)url animated:(BOOL)animated fromSearch:(BOOL)search {
    if (!RSHandleURL(url)) %orig;
}
%end
%end
%group RSSettingsURLCompletion
%hook PreferencesAppController
- (void)processURL:(id)url animated:(BOOL)animated fromSearch:(BOOL)search withCompletion:(void (^)(void))completion {
    if (!RSHandleURL(url)) { %orig; return; }
    if (completion) completion();
}
%end
%end
%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.Preferences"]) return;
    Class controller = NSClassFromString(@"PreferencesAppController");
    if (class_getInstanceMethod(controller, @selector(processURL:))) { %init(RSSettingsURL); }
    if (class_getInstanceMethod(controller, @selector(processURL:animated:fromSearch:))) { %init(RSSettingsURLAnimated); }
    if (class_getInstanceMethod(controller, @selector(processURL:animated:fromSearch:withCompletion:))) { %init(RSSettingsURLCompletion); }
}
