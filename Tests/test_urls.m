#import "../Preferences/RSURLRoute.h"
#include <assert.h>
#import "../Input/RSInputOptions.h"
int main(void) { @autoreleasepool {
    for (NSString *url in @[@"prefs://root=regionshot_aiwindow", @"prefs://root=regionshot_ai2", @"prefs:root=regionshot_aiwindow", @"App-prefs:root=RegionShot_AIWindow", @"prefs://?root=regionshot%5Faiwindow"]) {
        assert([RSURLNotification(url) hasSuffix:@"/AIWindow"]);
        assert([RSURLNotification([NSURL URLWithString:url]) hasSuffix:@"/AIWindow"]);
    }
    assert([RSURLNotification(@"prefs:root=regionshot_history") hasSuffix:@"/History"]);
    for (id url in @[@"https://root=regionshot_aiwindow", @"prefs:root=General", @"prefs://root=shellx_ai2", @"prefs:root=regionshot_aiwindow_other", @"prefs:root=regionshot_aiwindow&root=General", @42, @"", @"no-scheme"])
        assert(!RSURLNotification(url));
    assert(!RSURLNotification(nil));
    assert([RSInputPromptOptions(@{@"prompt":@{@"panelTop":@25}})[@"panelTopLandscape"] intValue] == 25);
    NSDictionary *spacing = RSInputPromptOptions(@{@"prompt":@{@"panelTop":@10, @"panelTopLandscape":@40}});
    assert([spacing[@"panelTop"] intValue] == 10 && [spacing[@"panelTopLandscape"] intValue] == 40);
    assert([RSInputSearchURL(@"prefs:root=General", @"文字").absoluteString isEqual:@"prefs:root=General"]);
    assert([RSInputSearchURL(@"myapp://search?text=%@", @"a&中").absoluteString isEqual:@"myapp://search?text=a%26%E4%B8%AD"]);
    assert(RSInputSearchURL(@"https://example.org/search?q=fixed", @"文字"));
    assert(!RSInputSearchURL(@"", @"文字"));
    assert(!RSInputSearchURL(@42, @"文字"));
    assert(!RSInputSearchURL(@"app://search?q=%@", @42));
} return 0; }
