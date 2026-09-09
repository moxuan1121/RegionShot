#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#include <string.h>
#import "../Manager/RSRegionShotManager.h"
// Entry points verified in ShellX 3.0.1 at 0x1881c0–0x188390.
%group RSControlAllowed
%hook SBControlCenterController
- (BOOL)canBePresented { if (RSRegionShotManager.sharedManager.isFrozenSelectionVisible) return NO; return %orig; }
%end
%end
%group RSControlPresent
%hook SBControlCenterController
- (void)presentAnimated:(BOOL)animated { if (!RSRegionShotManager.sharedManager.isFrozenSelectionVisible) %orig; }
%end
%end
%group RSControlCompletion
%hook SBControlCenterController
- (void)presentAnimated:(BOOL)animated completion:(id)completion { if (!RSRegionShotManager.sharedManager.isFrozenSelectionVisible) %orig; }
%end
%end
%group RSControlGesture
%hook SBControlCenterController
- (void)presentAnimated:(BOOL)animated fromGestureRecognizer:(id)gesture { if (!RSRegionShotManager.sharedManager.isFrozenSelectionVisible) %orig; }
%end
%end
%group RSGrabber
%hook SBGrabberTongue
- (BOOL)gestureRecognizerShouldBegin:(id)gesture { if (RSRegionShotManager.sharedManager.isFrozenSelectionVisible) return NO; return %orig; }
%end
%end
%group RSCover
%hook SBCoverSheetPresentationManager
- (void)setCoverSheetPresented:(BOOL)presented animated:(BOOL)animated withCompletion:(id)completion { if (presented) [RSRegionShotManager.sharedManager cancelCapture]; %orig; }
%end
%end
%group RSCoverOptions
%hook SBCoverSheetPresentationManager
- (void)setCoverSheetPresented:(BOOL)presented animated:(BOOL)animated options:(id)options withCompletion:(id)completion { if (presented) [RSRegionShotManager.sharedManager cancelCapture]; %orig; }
%end
%end
%group RSLock
%hook SBLockScreenManager
- (void)lockUIFromSource:(int)source withOptions:(id)options { [RSRegionShotManager.sharedManager cancelCapture]; %orig; }
%end
%end
%group RSLockCompletion
%hook SBLockScreenManager
- (void)lockUIFromSource:(int)source withOptions:(id)options completion:(id)completion { [RSRegionShotManager.sharedManager cancelCapture]; %orig; }
%end
%end
%group RSLockWide
%hook SBLockScreenManager
- (void)lockUIFromSource:(long long)source withOptions:(id)options { [RSRegionShotManager.sharedManager cancelCapture]; %orig; }
%end
%end
%group RSLockWideCompletion
%hook SBLockScreenManager
- (void)lockUIFromSource:(long long)source withOptions:(id)options completion:(id)completion { [RSRegionShotManager.sharedManager cancelCapture]; %orig; }
%end
%end
static BOOL RSFreezeMethod(Class cls, NSString *selector, const char *result, NSArray<NSString *> *args) {
    Method m = class_getInstanceMethod(cls, NSSelectorFromString(selector));
    if (!m || method_getNumberOfArguments(m) != args.count+2) return NO;
    char type[128]; method_getReturnType(m,type,sizeof(type));
    if (!type[0] || !strchr(result,type[0])) return NO;
    for (NSUInteger i=0;i<args.count;i++) { method_getArgumentType(m,(unsigned)i+2,type,sizeof(type)); if (!type[0] || !strchr(args[i].UTF8String,type[0])) return NO; }
    return YES;
}
%ctor {
    if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
    if (RSFreezeMethod(NSClassFromString(@"SBControlCenterController"), @"canBePresented", "Bc", @[])) { %init(RSControlAllowed);  }
    if (RSFreezeMethod(NSClassFromString(@"SBControlCenterController"), @"presentAnimated:", "v", @[@"Bc"])) { %init(RSControlPresent);  }
    if (RSFreezeMethod(NSClassFromString(@"SBControlCenterController"), @"presentAnimated:fromGestureRecognizer:", "v", @[@"Bc", @"@"])) { %init(RSControlGesture);  }
    if (RSFreezeMethod(NSClassFromString(@"SBControlCenterController"), @"presentAnimated:completion:", "v", @[@"Bc", @"@"])) { %init(RSControlCompletion); }
    if (RSFreezeMethod(NSClassFromString(@"SBGrabberTongue"), @"gestureRecognizerShouldBegin:", "Bc", @[@"@"])) { %init(RSGrabber);  }
    if (RSFreezeMethod(NSClassFromString(@"SBCoverSheetPresentationManager"), @"setCoverSheetPresented:animated:withCompletion:", "v", @[@"Bc", @"Bc", @"@"])) { %init(RSCover);  }
    if (RSFreezeMethod(NSClassFromString(@"SBCoverSheetPresentationManager"), @"setCoverSheetPresented:animated:options:withCompletion:", "v", @[@"Bc", @"Bc", @"@", @"@"])) { %init(RSCoverOptions);  }
    if (RSFreezeMethod(NSClassFromString(@"SBLockScreenManager"), @"lockUIFromSource:withOptions:", "v", @[@"i", @"@"])) { %init(RSLock);  }
    if (RSFreezeMethod(NSClassFromString(@"SBLockScreenManager"), @"lockUIFromSource:withOptions:completion:", "v", @[@"i", @"@", @"@"])) { %init(RSLockCompletion);  }
    if (RSFreezeMethod(NSClassFromString(@"SBLockScreenManager"), @"lockUIFromSource:withOptions:", "v", @[@"q", @"@"])) { %init(RSLockWide);  }
    if (RSFreezeMethod(NSClassFromString(@"SBLockScreenManager"), @"lockUIFromSource:withOptions:completion:", "v", @[@"q", @"@", @"@"])) { %init(RSLockWideCompletion);  }
}
