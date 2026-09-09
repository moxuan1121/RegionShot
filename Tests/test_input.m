#import "../Input/RSInputStore.h"
#import "../Input/RSInputCore.h"
#include <assert.h>
int main(void) {
    assert(RSInputFittedPanelHeight(30, 80, 360, 48) == 110);
    assert(RSInputFittedPanelHeight(70, 80, 360, 48) == 150);
    assert(RSInputFittedPanelHeight(2000, 180, 360, 48) == 204);
    assert(RSInputFittedPanelHeight(2000, 180, 100, 48) == 100); @autoreleasepool {
    RSInputClearConfig();
    assert(RSInputSaveOptions(@"sileo", @{@"enabled":@YES, @"personaTitle":@"翻译"}));
    assert([RSInputConfig()[@"sileo"][@"enabled"] boolValue]);
    assert(!RSInputSaveOptions(@"unknown", @{}));
    assert(RSInputSaveConfig(@{@"endpoint":@"https://example.com/v1/chat/completions", @"model":@"test", @"actions":@[@{@"title":@"翻译", @"prompt":@"Translate"}]}, @"test-only"));
    assert([RSInputConfig()[@"sileo"][@"personaTitle"] isEqual:@"翻译"]);
    assert([RSInputReadKey() isEqual:@"test-only"]);
    assert(RSInputVisibleActions(@"wechatHiddenPersonas").count == 1);
    assert(RSInputSaveOptions(@"wechatHiddenPersonas", @[@"翻译"]));
    assert(RSInputVisibleActions(@"wechatHiddenPersonas").count == 0);
    assert(RSInputVisibleActions(@"lineHiddenPersonas").count == 1);
    assert(!RSInputSaveOptions(@"lineHiddenPersonas", @[@42]));
    assert(RSInputSaveOptions(@"wechatHiddenPersonas", @[]));
    assert(RSInputVisibleActions(@"wechatHiddenPersonas").count == 1);
    assert(RSInputSaveConfig(@{@"endpoint":@"https://example.com/v1/chat/completions", @"model":@"test", @"actions":@[@{@"id":@"100", @"title":@"改名", @"prompt":@"Translate"}]}, @"new-key"));
    assert(RSInputSaveOptions(@"clipboardHiddenPersonas", @[@"100"]));
    assert(RSInputVisibleActions(@"clipboardHiddenPersonas").count == 0);
    assert([RSInputReadKey() isEqual:@"new-key"]);
    RSInputClearConfig();
} return 0; }
