#import "../Input/RSInputStore.h"
#import "../Input/RSInputCore.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    RSInputClearConfig();
    assert(RSInputSaveOptions(@"sileo", @{@"enabled":@YES, @"personaTitle":@"翻译"}));
    assert([RSInputConfig()[@"sileo"][@"enabled"] boolValue]);
    assert(!RSInputSaveOptions(@"unknown", @{}));
    assert(RSInputSaveConfig(@{@"endpoint":@"https://example.com/v1/chat/completions", @"model":@"test", @"actions":@[@{@"title":@"翻译", @"prompt":@"Translate"}]}, @"test-only"));
    assert([RSInputConfig()[@"sileo"][@"personaTitle"] isEqual:@"翻译"]);
    assert([RSInputReadKey() isEqual:@"test-only"]);
    RSInputClearConfig();
} return 0; }
