// Adapted from KeyboardAI-RootHide 23c761e, GPL-3.0; see THIRD_PARTY.md.
#import <Foundation/Foundation.h>

// Incremental SSE decoder. Feed on one serial queue; never exposes reasoning tokens.
@interface RSInputStream : NSObject
@property(nonatomic, readonly) NSString *text;
@property(nonatomic, readonly) NSString *error;
@property(nonatomic, readonly) BOOL finished;
- (void)appendData:(NSData *)data;
- (void)endOfInput;
@end
