#import <Foundation/Foundation.h>
// prefs://root=... uses an authority, whereas prefs:root=... uses a path.
static inline NSString *RSURLNotification(id value) {
    NSString *text = [value isKindOfClass:NSURL.class] ? [value absoluteString] : ([value isKindOfClass:NSString.class] ? value : nil);
    NSRange colon = [text rangeOfString:@":"];
    if (!text.length || colon.location == NSNotFound) return nil;
    NSString *scheme = [[text substringToIndex:colon.location] lowercaseString];
    if (![@[@"prefs", @"app-prefs"] containsObject:scheme]) return nil;
    NSString *parameters = [text substringFromIndex:colon.location + 1];
    while ([parameters hasPrefix:@"/"] || [parameters hasPrefix:@"?"]) parameters = [parameters substringFromIndex:1];
    parameters = [parameters componentsSeparatedByString:@"#"].firstObject;
    NSString *root = nil;
    for (NSString *item in [parameters componentsSeparatedByString:@"&"]) {
        NSRange equals = [item rangeOfString:@"="];
        if (equals.location == NSNotFound) continue;
        NSString *key = [[item substringToIndex:equals.location] stringByRemovingPercentEncoding];
        if ([key.lowercaseString isEqual:@"root"]) {
            if (root) return nil;
            root = [[[item substringFromIndex:equals.location + 1] stringByRemovingPercentEncoding] lowercaseString];
        }
    }
    if (([root isEqual:@"regionshot_aiwindow"] || [root isEqual:@"regionshot_ai2"])) return @"com.moxuan.regionshot/AIWindow";
    if ([root isEqual:@"regionshot_camera_return"]) return @"com.moxuan.regionshot/CameraReturn";
    if ([root isEqual:@"regionshot_history"]) return @"com.moxuan.regionshot/History";
    return nil;
}
