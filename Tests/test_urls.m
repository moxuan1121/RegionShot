#import "../Preferences/RSURLRoute.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    for (NSString *url in @[@"prefs://root=regionshot_aiwindow", @"prefs:root=regionshot_aiwindow", @"App-prefs:root=RegionShot_AIWindow", @"prefs://?root=regionshot%5Faiwindow"]) {
        assert([RSURLNotification(url) hasSuffix:@"/AIWindow"]);
        assert([RSURLNotification([NSURL URLWithString:url]) hasSuffix:@"/AIWindow"]);
    }
    assert([RSURLNotification(@"prefs:root=regionshot_history") hasSuffix:@"/History"]);
    for (id url in @[@"https://root=regionshot_aiwindow", @"prefs:root=General", @"prefs:root=regionshot_aiwindow_other", @"prefs:root=regionshot_aiwindow&root=General", @42, @"", @"no-scheme"])
        assert(!RSURLNotification(url));
    assert(!RSURLNotification(nil));
} return 0; }
