#import "../Preferences/RSOptions.h"
#include <assert.h>
#include <math.h>
#import "../Selection/RSMenuConfiguration.h"
int main(void) { @autoreleasepool {
    NSArray *personas = @[@{@"id":@100, @"enabled":@YES, @"persona":@{@"prompt":@"updated"}}];
    NSArray *personaMenu = RSNormalizeMenu(@[@{@"id":@100, @"enabled":@NO, @"persona":@{@"prompt":@"stale"}}], personas, nil);
    assert(![personaMenu[0][@"enabled"] boolValue]);
    assert([personaMenu[0][@"persona"][@"prompt"] isEqual:@"updated"]);
    assert(RSNormalizeMenu(personaMenu, @[], nil).count == 0);

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
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"];
    for (NSDictionary *group in RSOptionGroups()) for (NSDictionary *option in group[@"items"])
        assert([RSOption(option[@"key"]) isEqual:RSValidateOption(option, [prefs objectForKey:option[@"key"]])]);
    assert(RSOption(@"UnknownReleaseCheckKey") == nil);
    NSArray *defaults = @[@{@"id":@0, @"title":@"截图", @"enabled":@YES}, @{@"id":@1, @"title":@"关闭", @"enabled":@YES}];
    NSArray *menu = RSNormalizeMenu(@[@{@"id":@1, @"enabled":@NO}, @{@"id":@1}, @{@"id":@(-1)}, @{@"id":@0.5}, @{@"id":@88}], defaults, @1);
    assert(menu.count == 2 && [menu[0][@"id"] isEqual:@1] && [menu[0][@"enabled"] boolValue]);
    NSArray *dismissible = RSNormalizeMenu(@[@{@"id":@1, @"enabled":@NO}], defaults, nil);
    assert(dismissible.count == 2 && ![dismissible[0][@"enabled"] boolValue]);
    assert([menu[1] isEqual:defaults[0]]);
    assert([RSNormalizeMenu(@{}, defaults, @1) isEqual:defaults]);
    NSArray *remaining = @[@{@"id":@0, @"title":@"复制"}, @{@"id":@4, @"title":@"关闭", @"enabled":@YES}, @{@"id":@9, @"title":@"新增复制"}, @{@"id":@10, @"title":@"新增保存"}];
    NSArray *migrated = RSNormalizeMenu(@[@{@"id":@4, @"title":@"自定义关闭"}, @{@"id":@3}, @{@"id":@6}, @{@"id":@0}], remaining, @4);
    assert(migrated.count == 4);
    assert([migrated[0][@"id"] isEqual:@4] && [migrated[0][@"title"] isEqual:@"自定义关闭"]);
    assert([migrated[1][@"id"] isEqual:@0] && [migrated[2][@"id"] isEqual:@9] && [migrated[3][@"id"] isEqual:@10]);
} return 0; }
