#import <Foundation/Foundation.h>

static inline NSDataDetector *RSWebURLDetector(void) {
    static NSDataDetector *detector;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
    });
    return detector;
}

static inline NSURL *RSContainedWebURL(NSString *text) {
    NSString *value = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!value.length) return nil;
    __block NSURL *url;
    [RSWebURLDetector() enumerateMatchesInString:value options:0 range:NSMakeRange(0, value.length) usingBlock:^(NSTextCheckingResult *match, NSMatchingFlags flags, BOOL *stop) {
        (void)flags;
        NSString *scheme = match.URL.scheme.lowercaseString;
        if ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) {
            url = match.URL;
            *stop = YES;
        }
    }];
    return url;
}

static inline NSURL *RSWebURL(NSString *text) {
    NSString *value = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSTextCheckingResult *match = [RSWebURLDetector() firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    NSString *scheme = match.URL.scheme.lowercaseString;
    return match && NSEqualRanges(match.range, NSMakeRange(0, value.length)) &&
        ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) ? match.URL : nil;
}

static inline BOOL RSWebURLLooksLikeWeChat(NSURL *url) {
    if (!url) return NO;
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"weixin"] || [scheme isEqualToString:@"wechat"]) return YES;
    NSString *value = url.absoluteString.lowercaseString;
    for (NSString *token in @[@"wechat", @"weixin", @"wechatpay", @"wxpay", @"pay.weixin.", @"weixin.qq.com"])
        if ([value containsString:token]) return YES;
    return NO;
}

static inline NSURL *RSWeChatURLForWebURL(NSURL *url) {
    if (!RSWebURLLooksLikeWeChat(url)) return nil;
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"weixin"] || [scheme isEqualToString:@"wechat"]) return url;
    NSURLComponents *components = [NSURLComponents componentsWithString:@"weixin://dl/businessWebview/link/"];
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"url" value:url.absoluteString]];
    return components.URL;
}
