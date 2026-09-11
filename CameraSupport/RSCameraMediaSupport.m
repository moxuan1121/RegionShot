#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <string.h>

static BOOL RSIsSpringBoardClient(id client) {
    @try {
        SEL selector = NSSelectorFromString(@"applicationID");
        NSString *identifier = [client respondsToSelector:selector]
            ? ((id (*)(id, SEL))objc_msgSend)(client, selector) : nil;
        return [identifier isEqualToString:@"com.apple.springboard"];
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static void (*RSOriginalUpdateState)(id, SEL, void *, id);
static void RSUpdateState(id self, SEL selector, void *condition, id value) {
    if (!RSIsSpringBoardClient(self) && RSOriginalUpdateState)
        RSOriginalUpdateState(self, selector, condition, value);
}

__attribute__((constructor)) static void RSInstallCameraMediaSupport(void) {
    @autoreleasepool {
        Class cls = objc_getClass("FigCaptureClientSessionMonitor");
        SEL selector = NSSelectorFromString(@"_updateClientStateCondition:newValue:");
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        if (method && method_getNumberOfArguments(method) == 4 &&
            strcmp(method_getTypeEncoding(method), "v32@0:8^v16@24") == 0)
            MSHookMessageEx(cls, selector, (IMP)RSUpdateState, (IMP *)&RSOriginalUpdateState);
    }
}
