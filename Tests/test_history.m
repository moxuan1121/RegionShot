#import "../History/RSHistoryStore.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSURL *directory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    RSHistoryStore *store = [[RSHistoryStore alloc] initWithDirectory:directory];
    NSData *image = [@"image" dataUsingEncoding:NSUTF8StringEncoding]; NSError *error = nil;
    for (int i = 0; i < 4; i++) assert([store addImage:image thumbnail:image title:@"截图" countLimit:2 byteLimit:100000 error:&error]);
    assert(store.entries.count == 2);
    NSString *identifier = store.entries.firstObject[@"id"];
    assert([[store dataForID:identifier thumbnail:NO error:nil] isEqual:image]);
    assert([store renameID:identifier title:@"测试名称" error:nil]);
    assert([store.entries.firstObject[@"title"] isEqual:@"测试名称"]);
    assert(![store removeIDs:@[@"../outside"] error:nil]);
    assert(![store dataForID:@"../outside" thumbnail:NO error:nil]);
    assert(![store addImage:image thumbnail:image title:@"过大" countLimit:2 byteLimit:1 error:&error]);
    assert(store.entries.count == 2);
    assert([store addImage:image thumbnail:image title:@"容量清理" countLimit:20 byteLimit:10000 error:nil]);
    assert(store.entries.count == 1);
    // A newly constructed store must read persisted entries, not a memory-only cache.
    RSHistoryStore *reopened = [[RSHistoryStore alloc] initWithDirectory:directory];
    assert(reopened.entries.count == 1);
    assert([reopened removeIDs:[reopened.entries valueForKey:@"id"] error:nil]);
    assert(reopened.entries.count == 0);
    [NSFileManager.defaultManager removeItemAtURL:directory error:nil];
} return 0; }
