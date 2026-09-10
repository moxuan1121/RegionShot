#import "../AI/RSChatAttachments.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSString *error = nil;
    NSString *source = @"崩溃日志\n{\"exception\":\"SIGABRT\"}";
    for (NSNumber *encoding in @[@(NSUTF8StringEncoding), @(NSUTF16StringEncoding), @(NSUTF32StringEncoding), @(CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000))]) {
        NSData *data = [source dataUsingEncoding:encoding.unsignedIntegerValue];
        assert(data);
        for (NSString *name in @[@"123.txt", @"Sileo.ips", @"app.crash", @"app.log"]) {
            NSDictionary *part = RSChatFilePart(data, name, @"text/plain", YES, &error);
            assert([part[@"type"] isEqual:@"text"] && [part[@"text"] containsString:source]);
            assert(!part[@"file"] && !error);
        }
    }
    NSData *pdf = [@"%PDF-1.7" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *part = RSChatFilePart(pdf, @"a.pdf", @"application/pdf", NO, &error);
    assert([part[@"file"][@"file_data"] isEqual:[@"data:application/pdf;base64," stringByAppendingString:[pdf base64EncodedStringWithOptions:0]]]);
    assert(!RSChatFilePart(NSData.data, @"empty.txt", @"text/plain", YES, &error) && error.length);
    unsigned char invalid[] = {0, 1, 0};
    assert(!RSChatFilePart([NSData dataWithBytes:invalid length:3], @"bad.txt", @"text/plain", YES, &error));
    NSMutableArray *history = [@[@{@"role":@"user", @"content":@[part]}, @{@"role":@"assistant", @"content":@"PDF answer"}, @{@"role":@"user", @"content":@"rejected file"}, @{@"role":@"assistant", @"content":@""}, @{@"role":@"user", @"content":@"你好"}] mutableCopy];
    NSMutableIndexSet *excluded = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(2, 2)];
    NSArray *request = RSChatRequestHistory(history, excluded);
    assert(request.count == 3 && [request.lastObject[@"content"] isEqual:@"你好"]);
    assert(history.count == 5 && [request[0][@"content"] isEqual:@[part]]);
    [excluded removeAllIndexes];
    assert(RSChatRequestHistory(history, excluded).count == 5);
    NSData *body = [@"{\"error\":{\"message\":\"Unsupported file format\"}}" dataUsingEncoding:NSUTF8StringEncoding];
    assert([RSChatHTTPError(body, 400) containsString:@"Unsupported file format"]);
    assert([RSChatHTTPError(nil, 401) containsString:@"401"]);
    assert([RSChatHTTPError([@"<html>bad gateway</html>" dataUsingEncoding:NSUTF8StringEncoding], 502) containsString:@"502"]);
    puts("Text decoding, PDF payload, rejected-turn recovery and server errors verified");
} return 0; }
