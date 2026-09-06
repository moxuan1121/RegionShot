#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "Manager/RSRegionShotManager.h"

@interface SpringBoard : UIApplication
- (void)takeScreenshot;
@end

%group RegionShotHook
%hook SpringBoard
- (void)takeScreenshot {
    NSLog(@"[RegionShot] screenshot trigger");
    RSRegionShotManager *manager = [RSRegionShotManager sharedManager];
    if (manager.isInternalCapture) {
        %orig;
        return;
    }
    if (manager.isCapturing) {
        NSLog(@"[RegionShot] duplicate trigger ignored");
        return;
    }
    @try {
        if (![manager beginCapture]) {
            NSLog(@"[RegionShot] capture unavailable; using system screenshot");
            %orig;
        }
    } @catch (NSException *exception) {
        NSLog(@"[RegionShot] capture exception: %@", exception);
        [manager cancelCapture];
        %orig;
    }
}
%end
%end

%ctor {
    @autoreleasepool {
        Class cls = NSClassFromString(@"SpringBoard");
        SEL selector = @selector(takeScreenshot);
        Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
        char returnType[16] = {0};
        if (method) method_getReturnType(method, returnType, sizeof(returnType));
        if ([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"] &&
            method && method_getNumberOfArguments(method) == 2 && returnType[0] == 'v') {
            %init(RegionShotHook);
            NSLog(@"[RegionShot] hook initialized");
        } else {
            NSLog(@"[RegionShot] compatible screenshot entry not found");
        }
    }
}
