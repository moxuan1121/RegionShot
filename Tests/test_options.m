#import "../Preferences/RSOptions.h"
#include <assert.h>
#include <math.h>
#import "../Selection/RSMenuConfiguration.h"
int main(void) { @autoreleasepool {
    NSMutableSet *keys = [NSMutableSet set];
    for (NSDictionary *group in RSOptionGroups()) for (NSDictionary *option in group[@"items"]) {
        assert(![keys containsObject:option[@"key"]]); [keys addObject:option[@"key"]];
        assert([RSValidateOption(option, nil) isEqual:option[@"default"]]);
        assert([RSValidateOption(option, @[]) isEqual:option[@"default"]]);
        assert([RSValidateOption(option, @(NAN)) isEqual:option[@"default"]]);
        if (option[@"min"]) {
            assert([RSValidateOption(option, @(-999)) doubleValue] == [option[@"min"] doubleValue]);
            assert([RSValidateOption(option, @(999999)) doubleValue] == [option[@"max"] doubleValue]);
        }
    }
    assert(keys.count >= 20);
    NSArray *defaults = @[@{@"id":@0, @"title":@"截图", @"enabled":@YES}, @{@"id":@1, @"title":@"关闭", @"enabled":@YES}];
    NSArray *menu = RSNormalizeMenu(@[@{@"id":@1, @"enabled":@NO}, @{@"id":@1}, @{@"id":@(-1)}, @{@"id":@0.5}, @{@"id":@88}], defaults, @1);
    assert(menu.count == 2 && [menu[0][@"id"] isEqual:@1] && [menu[0][@"enabled"] boolValue]);
    assert([menu[1] isEqual:defaults[0]]);
    assert([RSNormalizeMenu(@{}, defaults, @1) isEqual:defaults]);
} return 0; }
