#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>
#import <notify.h>
#import "RSURLRoute.h"
static BOOL RSHandleURL(id url) {
    NSString *notification = RSURLNotification(url);
    if (!notification) return NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        notify_post(notification.UTF8String);
    });
    return YES;
}
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
    }
}

%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{ RSInstallURLHooks(); });
}
