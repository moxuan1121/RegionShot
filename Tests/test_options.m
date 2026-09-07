#import "../Preferences/RSOptions.h"
#include <assert.h>
#include <math.h>
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
} return 0; }
