#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <string.h>
#import <notify.h>
#import <WebKit/WebKit.h>
#import "RSURLRoute.h"
static BOOL RSHandleURL(id url) {
    NSString *notification = RSURLNotification(url);
    if (!notification) return NO;
    NSLog(@"[RegionShot] Settings URL route: %@", notification);
    dispatch_async(dispatch_get_main_queue(), ^{
        // In SpringBoard dispatch directly; do not depend on a second injected URL dylib.
        Class chat = NSClassFromString(@"RSChatController");
        SEL show = NSSelectorFromString(@"showImage:scene:");
        if ([notification hasSuffix:@"/AIWindow"] && [chat respondsToSelector:show])
            ((void (*)(id, SEL, id, id))objc_msgSend)(chat, show, nil, nil);
        else notify_post(notification.UTF8String);
    });
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
- (void)processURL:(id)url animated:(BOOL)animated fromSearch:(BOOL)search withCompletion:(id)completion {
    if (!RSHandleURL(url)) { %orig; return; }
    // Keep the private completion opaque: Preferences invokes its own block with
    // the correct ABI after resolving the real, single RegionShot settings entry.
    id destination = [url isKindOfClass:NSString.class] ? (id)@"prefs:root=RegionShot" : [NSURL URLWithString:@"prefs:root=RegionShot"];
    %orig(destination, animated, search, completion);
}
%end
%end
// Verified against ShellX 3.0.1's external URL registration at 0x189208.
%group RSSystemExternalURL
%hook SpringBoard
- (void)applicationOpenURL:(id)url withApplication:(id)application sender:(id)sender publicURLsOnly:(BOOL)publicOnly animating:(BOOL)animating needsConfirm:(BOOL)confirm options:(id)options windowContext:(id)context {
    if (!RSHandleURL(url)) %orig;
}
%end
%end
%group RSSystemURLPort
%hook FBSSystemService
- (void)openURL:(id)url application:(id)application options:(id)options clientPort:(unsigned int)port withResult:(void (^)(NSError *))result {
    if (!RSHandleURL(url)) { %orig; return; }
    if (result) result(nil);
}
%end
%end
%group RSSystemURLProcess
%hook FBSSystemService
- (void)openURL:(id)url application:(id)application options:(id)options clientProcess:(id)process withResult:(void (^)(NSError *))result {
    if (!RSHandleURL(url)) { %orig; return; }
    if (result) result(nil);
}
%end
%end
%group RSSafariTypedURL
%hook TabDocument
- (id)loadURL:(NSURL *)url userDriven:(BOOL)userDriven {
    if (userDriven && RSHandleURL(url)) return nil;
    return %orig;
}
%end
%end
%group RSSafariLinkURL
%hook TabDocument
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action preferences:(WKWebpagePreferences *)preferences decisionHandler:(void (^)(WKNavigationActionPolicy, WKWebpagePreferences *))decision {
    if (action.navigationType == WKNavigationTypeLinkActivated && RSHandleURL(action.request.URL)) { decision(WKNavigationActionPolicyCancel, preferences); return; }
    %orig;
}
%end
%end
%group RSSystemShortURL
%hook SpringBoard
- (void)applicationOpenURL:(id)url { if (!RSHandleURL(url)) %orig; }
%end
%end
%group RSApplicationURL
%hook UIApplication
- (BOOL)openURL:(NSURL *)url { if (RSHandleURL(url)) return YES; return %orig; }
- (void)openURL:(NSURL *)url options:(NSDictionary *)options completionHandler:(void (^)(BOOL))completion {
    if (!RSHandleURL(url)) { %orig; return; }
    if (completion) completion(YES);
}
%end
%end
static BOOL RSURLMethod(Class cls, NSString *name, const char *result, NSArray<NSString *> *arguments) {
    Method method = class_getInstanceMethod(cls, NSSelectorFromString(name));
    if (!method || method_getNumberOfArguments(method) != arguments.count + 2) return NO;
    char type[128] = {0}; method_getReturnType(method, type, sizeof(type));
    if (!type[0] || !strchr(result, type[0])) return NO;
    for (NSUInteger i = 0; i < arguments.count; i++) {
        method_getArgumentType(method, (unsigned int)i + 2, type, sizeof(type));
        if (!type[0] || !strchr(arguments[i].UTF8String, type[0])) return NO;
    }
    return YES;
}
static void RSInstallURLHooks(void) {
    static BOOL installed = NO;
    if (installed) return;
    installed = YES;
    %init(RSApplicationURL);
    NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
    if ([bundle isEqual:@"com.apple.springboard"]) {
        Class app = NSClassFromString(@"SpringBoard"), service = NSClassFromString(@"FBSSystemService");
        if (RSURLMethod(app, @"applicationOpenURL:", "v", @[@"@"])) { %init(RSSystemShortURL); }
        if (RSURLMethod(app, @"applicationOpenURL:withApplication:sender:publicURLsOnly:animating:needsConfirm:options:windowContext:", "v", @[@"@", @"@", @"@", @"Bc", @"Bc", @"Bc", @"@", @"@"])) { %init(RSSystemExternalURL); }
        if (RSURLMethod(service, @"openURL:application:options:clientPort:withResult:", "v", @[@"@", @"@", @"@", @"I", @"@"])) { %init(RSSystemURLPort); }
        if (RSURLMethod(service, @"openURL:application:options:clientProcess:withResult:", "v", @[@"@", @"@", @"@", @"@", @"@"])) { %init(RSSystemURLProcess); }
    } else if ([bundle isEqual:@"com.apple.mobilesafari"]) {
        Class tab = NSClassFromString(@"TabDocument");
        if (RSURLMethod(tab, @"loadURL:userDriven:", "@", @[@"@", @"Bc"])) { %init(RSSafariTypedURL); }
        if (RSURLMethod(tab, @"webView:decidePolicyForNavigationAction:preferences:decisionHandler:", "v", @[@"@", @"@", @"@", @"@"])) { %init(RSSafariLinkURL); }
    } else if ([bundle isEqual:@"com.apple.Preferences"]) {
        Class controller = NSClassFromString(@"PreferencesAppController");
        if (class_getInstanceMethod(controller, @selector(processURL:))) { %init(RSSettingsURL); }
        if (class_getInstanceMethod(controller, @selector(processURL:animated:fromSearch:))) { %init(RSSettingsURLAnimated); }
        if (class_getInstanceMethod(controller, @selector(processURL:animated:fromSearch:withCompletion:))) { %init(RSSettingsURLCompletion); }
    }
}

%ctor {
#ifndef RS_URLS_IN_MAIN
    if ([NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
#endif
    // Safari's TabDocument is not guaranteed to exist during early dylib loading.
    dispatch_async(dispatch_get_main_queue(), ^{ RSInstallURLHooks(); });
}
