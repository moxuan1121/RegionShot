#import <Foundation/Foundation.h>

static inline NSURL *RSKASearchURL(id engine, id text) {
    if (![engine isKindOfClass:NSString.class] || [engine length] > 2048 ||
        ![engine containsString:@"%@"] || ![text isKindOfClass:NSString.class] || ![text length] || [text length] > 24000) return nil;
    NSString *encoded = [text stringByAddingPercentEncodingWithAllowedCharacters:
        [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"]];
    NSURLComponents *url = [NSURLComponents componentsWithString:[engine stringByReplacingOccurrencesOfString:@"%@" withString:encoded]];
    return url.scheme.length ? url.URL : nil;
}
static inline BOOL RSKAValidEngines(id engines) {
    if (![engines isKindOfClass:NSArray.class] || ![engines count] || [engines count] > 12) return NO;
    for (id item in engines) {
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"name"] isKindOfClass:NSString.class] ||
            ![item[@"name"] length] || [item[@"name"] length] > 30 || !RSKASearchURL(item[@"engine"], @"测试 &/?")) return NO;
    }
    return YES;
}
static inline NSArray *RSKASearchEngines(NSDictionary *config) {
    return RSKAValidEngines(config[@"searchEngines"]) ? config[@"searchEngines"] :
        @[@{@"name": @"百度", @"engine": @"https://www.baidu.com/s?wd=%@"},
          @{@"name": @"Google", @"engine": @"https://www.google.com/search?q=%@"}];
}
static inline NSDictionary *RSKAPromptOptions(NSDictionary *config) {
    NSMutableDictionary *result = [@{@"enabled": @YES, @"size": @100, @"height": @50, @"duration": @3,
        @"gradient": @YES, @"startColor": @"FF8A4C", @"middleColor": @"FF416C", @"endColor": @"9B3FE5",
        @"animations": @YES, @"animationSpeed": @1, @"tokenMaxHeight": @60, @"aiMaxHeight": @48,
        @"tokenWindowPriority": @1000000000, @"aiWindowPriority": @1000000000, @"panelPosition": @1, @"panelHeight": @0, @"panelTop": @8, @"panelTopLandscape": @8} mutableCopy];
    id values = config[@"prompt"];
    if (![values isKindOfClass:NSDictionary.class]) return result;
    NSDictionary *ranges = @{@"size": @[@60, @160], @"height": @[@10, @90], @"duration": @[@0.5, @3], @"animationSpeed": @[@0.5, @2],
        @"tokenMaxHeight": @[@30, @90], @"aiMaxHeight": @[@30, @90],
        @"tokenWindowPriority": @[@0, @1000000000], @"aiWindowPriority": @[@0, @1000000000], @"panelPosition": @[@0, @2], @"panelHeight": @[@0, @1000], @"panelTop": @[@0, @300], @"panelTopLandscape": @[@0, @300]};
    for (NSString *key in result.allKeys) {
        id value = values[key];
        if (ranges[key] && [value isKindOfClass:NSNumber.class] && isfinite([value doubleValue]))
            result[key] = @(MAX([ranges[key][0] doubleValue], MIN([ranges[key][1] doubleValue], [value doubleValue])));
        else if ([@[@"enabled", @"gradient", @"animations"] containsObject:key] && [value isKindOfClass:NSNumber.class]) result[key] = @([value boolValue]);
        else if ([key hasSuffix:@"Color"] && [value isKindOfClass:NSString.class] && [value length] == 6 &&
            [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFabcdef"] invertedSet]].location == NSNotFound) result[key] = value;
    }
    if (!values[@"panelTopLandscape"]) result[@"panelTopLandscape"] = result[@"panelTop"];
    return result;
}
