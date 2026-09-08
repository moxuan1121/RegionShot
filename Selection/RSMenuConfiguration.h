#import <Foundation/Foundation.h>

static inline NSArray *RSNormalizeMenu(id saved, NSArray *defaults, NSNumber *required) {
    if (![saved isKindOfClass:NSArray.class]) return defaults;
    NSMutableArray *result = [NSMutableArray array]; NSMutableSet *seen = [NSMutableSet set];
    for (id value in saved) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        id identifier = value[@"id"];
        if (![identifier isKindOfClass:NSNumber.class] || [identifier doubleValue] != [identifier integerValue] ||
            [identifier integerValue] < 0 || [seen containsObject:identifier]) continue;
        NSDictionary *original = nil;
        for (NSDictionary *entry in defaults) if ([entry[@"id"] isEqual:identifier]) { original = entry; break; }
        if (!original) continue;
        NSMutableDictionary *item = original.mutableCopy;
        for (NSString *key in @[@"title", @"symbol"])
            if ([value[key] isKindOfClass:NSString.class] && [value[key] length] > 0 && [value[key] length] <= 100) item[key] = value[key];
        if ([value[@"enabled"] isKindOfClass:NSNumber.class]) item[@"enabled"] = value[@"enabled"];
        if ([value[@"image"] isKindOfClass:NSData.class] && [value[@"image"] length] <= 256 * 1024) item[@"image"] = value[@"image"];
        if ([identifier isEqual:required]) item[@"enabled"] = @YES;
        [seen addObject:identifier]; [result addObject:item];
    }
    for (NSDictionary *item in defaults) if (![seen containsObject:item[@"id"]]) [result addObject:item];
    return result;
}
