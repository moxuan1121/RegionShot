#import <Foundation/Foundation.h>

// Receives bytes, so a UTF-8 character or CRLF split across packets stays intact.
@interface RSSSEDecoder : NSObject
@property (nonatomic, copy) void (^onEvent)(NSString *data);
@property (nonatomic, readonly) NSError *error;
- (void)appendData:(NSData *)data;
- (void)finish;
@end
