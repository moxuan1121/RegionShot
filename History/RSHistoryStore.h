#import <Foundation/Foundation.h>

// All operations run on the history serial queue; UI never performs disk I/O.
@interface RSHistoryStore : NSObject
- (instancetype)initWithDirectory:(NSURL *)directory;
- (NSArray<NSDictionary *> *)entries;
- (BOOL)addImage:(NSData *)image thumbnail:(NSData *)thumbnail title:(NSString *)title countLimit:(NSUInteger)countLimit byteLimit:(NSUInteger)byteLimit error:(NSError **)error;
- (NSData *)dataForID:(NSString *)identifier thumbnail:(BOOL)thumbnail error:(NSError **)error;
- (BOOL)renameID:(NSString *)identifier title:(NSString *)title error:(NSError **)error;
- (BOOL)removeIDs:(NSArray<NSString *> *)identifiers error:(NSError **)error;
@end
