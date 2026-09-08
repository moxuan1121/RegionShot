// Adapted from KeyboardAI-RootHide 23c761e, GPL-3.0; see THIRD_PARTY.md.
#import "RSInputStore.h"
#import "RSInputCore.h"
#import "RSInputOptions.h"
static BOOL RSInputWriteConfig(NSDictionary *clean);
#import <unistd.h>
#ifndef RSInput_STORE_TESTING
#import <roothide.h>
#endif

static NSString *RSInputPath(void) {
#ifdef RSInput_STORE_TESTING
    return [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"keyboardai-test-%d.plist", getpid()]];
#else
    return jbroot(@"/var/mobile/Library/Preferences/com.moxuan.regionshot.input.plist");
#endif
}

NSDictionary *RSInputConfig(void) {
    // Read fresh snapshots; never cache secrets or stale personas in per-app defaults.
    @try {
        NSFileHandle *file = [NSFileHandle fileHandleForReadingAtPath:RSInputPath()];
        NSData *data = [file readDataOfLength:65537];
        [file closeFile];
        if (!data.length || data.length > 65536) return @{};
        id config = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
        return [config isKindOfClass:NSDictionary.class] ? config : @{};
    } @catch (__unused NSException *exception) { return @{}; }
}
NSString *RSInputReadKey(void) {
    id key = RSInputConfig()[@"key"];
    return [key isKindOfClass:NSString.class] ? key : nil;
}
NSArray<NSDictionary *> *RSInputActions(void) {
    id actions = RSInputConfig()[@"actions"];
    return RSInputValidActions(actions) ? actions : RSInputDefaultActions();
}
BOOL RSInputSaveConfig(NSDictionary *config, NSString *key) {
    if (![config isKindOfClass:NSDictionary.class] || RSInputConfigError(config[@"endpoint"], config[@"model"], key) || !RSInputValidActions(config[@"actions"])) return NO;
    NSMutableArray *actions = [NSMutableArray array];
    for (NSDictionary *action in config[@"actions"]) {
        NSMutableDictionary *clean = [@{@"title": action[@"title"], @"prompt": action[@"prompt"]} mutableCopy];
        for (NSString *field in @[@"icon", @"summary"])
            if ([action[field] isKindOfClass:NSString.class] && [action[field] length] <= 4000) clean[field] = action[field];
        [actions addObject:clean];
    }
    NSMutableDictionary *clean = [RSInputConfig() mutableCopy];
    [clean addEntriesFromDictionary:@{@"endpoint": config[@"endpoint"], @"model": config[@"model"], @"key": key, @"actions": actions, @"fastResponse": @([config[@"fastResponse"] isEqual:@YES])}];
    return RSInputWriteConfig(clean);
}
BOOL RSInputSaveOptions(NSString *field, id value) {
    if ([field isEqualToString:@"searchEngines"]) {
        if (!RSInputValidEngines(value)) return NO;
    } else if ([field isEqualToString:@"prompt"] && [value isKindOfClass:NSDictionary.class]) {
        value = RSInputPromptOptions(@{@"prompt": value});
    } else if ([field isEqual:@"sileo"] && [value isKindOfClass:NSDictionary.class]) {
        NSString *title = [value[@"personaTitle"] isKindOfClass:NSString.class] ? value[@"personaTitle"] : @"";
        if (title.length > 200) return NO;
        value = @{@"enabled":@([value[@"enabled"] boolValue]), @"personaTitle":title};
    } else return NO;
    NSMutableDictionary *config = [RSInputConfig() mutableCopy];
    config[field] = value;
    return RSInputWriteConfig(config);
}
static BOOL RSInputWriteConfig(NSDictionary *clean) {
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:clean format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    if (!data.length || data.length > 65536) return NO;
    NSString *path = RSInputPath();
    NSFileManager *manager = NSFileManager.defaultManager;
    if (![manager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:NULL]) return NO;
    if (![data writeToFile:path options:NSDataWritingAtomic error:NULL]) return NO;
    return [manager setAttributes:@{NSFilePosixPermissions: @0600} ofItemAtPath:path error:NULL];
}
BOOL RSInputClearConfig(void) {
    NSError *error = nil;
    return [NSFileManager.defaultManager removeItemAtPath:RSInputPath() error:&error] || error.code == NSFileNoSuchFileError;
}
