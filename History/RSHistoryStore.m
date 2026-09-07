#import "RSHistoryStore.h"

@implementation RSHistoryStore {
    NSURL *_directory;
}
- (instancetype)initWithDirectory:(NSURL *)directory {
    if ((self = [super init])) {
        _directory = directory;
        // Only our unpublished UUID staging folders can be discarded after a crash.
        for (NSURL *entry in [NSFileManager.defaultManager contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:nil]) {
            NSString *name = entry.lastPathComponent;
            if ([name hasPrefix:@"."] && [[NSUUID alloc] initWithUUIDString:[name substringFromIndex:1]])
                [NSFileManager.defaultManager removeItemAtURL:entry error:nil];
        }
    }
    return self;
}
- (NSURL *)folder:(NSString *)identifier {
    if (![identifier isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:identifier]) return nil;
    return [_directory URLByAppendingPathComponent:identifier isDirectory:YES];
}
- (NSArray<NSDictionary *> *)entries {
    NSMutableArray *entries = [NSMutableArray array];
    NSArray *folders = [NSFileManager.defaultManager contentsOfDirectoryAtURL:_directory includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    for (NSURL *folder in folders) {
        NSString *identifier = folder.lastPathComponent;
        if (![self folder:identifier]) continue;
        NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:folder.path error:nil];
        if (![attributes[NSFileType] isEqual:NSFileTypeDirectory]) continue;
        NSURL *metadata = [folder URLByAppendingPathComponent:@"info.plist"];
        NSNumber *size; [metadata getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        if (!size || size.unsignedLongLongValue > 8192) continue;
        NSDictionary *entry = [NSDictionary dictionaryWithContentsOfURL:metadata];
        if (![entry[@"id"] isEqual:identifier] || ![entry[@"title"] isKindOfClass:NSString.class] ||
            [entry[@"title"] length] > 200 || ![entry[@"date"] isKindOfClass:NSDate.class] ||
            ![entry[@"bytes"] isKindOfClass:NSNumber.class] || [entry[@"bytes"] longLongValue] <= 0) continue;
        [entries addObject:entry];
    }
    return [entries sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"date" ascending:NO]]];
}
- (BOOL)addImage:(NSData *)image thumbnail:(NSData *)thumbnail title:(NSString *)title countLimit:(NSUInteger)countLimit byteLimit:(NSUInteger)byteLimit error:(NSError **)error {
    NSUInteger bytes = image.length + thumbnail.length + 8192;
    if (!image.length || !thumbnail.length || !countLimit || bytes > byteLimit || title.length > 200) {
        if (error) *error = [NSError errorWithDomain:@"RegionShot.History" code:1 userInfo:@{NSLocalizedDescriptionKey:@"此图片超过历史容量上限，未写入历史；当前浮图仍可保存。"}];
        return NO;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    if (![files createDirectoryAtURL:_directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSURL *folder = [self folder:identifier];
    NSURL *staging = [_directory URLByAppendingPathComponent:[@"." stringByAppendingString:identifier] isDirectory:YES];
    if (![files createDirectoryAtURL:staging withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:error]) return NO;
    NSDictionary *entry = @{@"id":identifier, @"title":title ?: @"截图", @"date":NSDate.date, @"bytes":@(bytes)};
    NSData *metadata = [NSPropertyListSerialization dataWithPropertyList:entry format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    BOOL saved = metadata && [image writeToURL:[staging URLByAppendingPathComponent:@"image.png"] options:NSDataWritingAtomic error:error] &&
        [thumbnail writeToURL:[staging URLByAppendingPathComponent:@"thumb.png"] options:NSDataWritingAtomic error:error] &&
        [metadata writeToURL:[staging URLByAppendingPathComponent:@"info.plist"] options:NSDataWritingAtomic error:error] &&
        [files moveItemAtURL:staging toURL:folder error:error];
    if (!saved) { [files removeItemAtURL:staging error:nil]; return NO; }
    NSUInteger count = 0, used = 0;
    for (NSDictionary *item in [self entries]) {
        NSUInteger itemBytes = [item[@"bytes"] unsignedIntegerValue];
        if (count >= countLimit || itemBytes > byteLimit - MIN(used, byteLimit)) {
            if (![self removeIDs:@[item[@"id"]] error:error]) return NO;
        } else { count++; used += itemBytes; }
    }
    return YES;
}
- (NSData *)dataForID:(NSString *)identifier thumbnail:(BOOL)thumbnail error:(NSError **)error {
    NSURL *folder = [self folder:identifier]; if (!folder) return nil;
    NSURL *path = [folder URLByAppendingPathComponent:thumbnail ? @"thumb.png" : @"image.png"];
    NSNumber *size; [path getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    if (!size || size.unsignedLongLongValue > (thumbnail ? 256 * 1024 : 128 * 1024 * 1024)) return nil;
    return [NSData dataWithContentsOfURL:path options:0 error:error];
}
- (BOOL)renameID:(NSString *)identifier title:(NSString *)title error:(NSError **)error {
    NSURL *folder = [self folder:identifier]; if (!folder || !title.length || title.length > 200) return NO;
    NSURL *path = [folder URLByAppendingPathComponent:@"info.plist"];
    NSMutableDictionary *entry = [[NSDictionary dictionaryWithContentsOfURL:path] mutableCopy]; if (!entry) return NO;
    entry[@"title"] = title;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:entry format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    return data && [data writeToURL:path options:NSDataWritingAtomic error:error];
}
- (BOOL)removeIDs:(NSArray<NSString *> *)identifiers error:(NSError **)error {
    for (NSString *identifier in identifiers) {
        NSURL *folder = [self folder:identifier];
        if (!folder) return NO;
        if ([NSFileManager.defaultManager fileExistsAtPath:folder.path] && ![NSFileManager.defaultManager removeItemAtURL:folder error:error]) return NO;
    }
    return YES;
}
@end
