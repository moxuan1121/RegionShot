#import "RSSSEDecoder.h"

@implementation RSSSEDecoder {
    NSMutableData *_line;
    NSMutableArray<NSString *> *_fields;
    NSUInteger _eventBytes;
    BOOL _afterCR;
    BOOL _firstLine;
}
- (instancetype)init {
    if ((self = [super init])) {
        _line = [NSMutableData data];
        _fields = [NSMutableArray array];
        _firstLine = YES;
    }
    return self;
}
- (void)fail:(NSString *)message {
    _error = [NSError errorWithDomain:@"RegionShot.Stream" code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
- (void)consumeLine {
    NSString *line = [[NSString alloc] initWithData:_line encoding:NSUTF8StringEncoding];
    [_line setLength:0];
    if (!line) { [self fail:@"服务返回了无效的 UTF-8 文本"]; return; }
    if (_firstLine && [line hasPrefix:@"\uFEFF"]) line = [line substringFromIndex:1];
    _firstLine = NO;
    if (!line.length) {
        if (_fields.count && self.onEvent) self.onEvent([_fields componentsJoinedByString:@"\n"]);
        [_fields removeAllObjects];
        _eventBytes = 0;
    } else if ([line hasPrefix:@"data:"] || [line isEqualToString:@"data"]) {
        NSString *value = line.length >= 5 ? [line substringFromIndex:5] : @"";
        if ([value hasPrefix:@" "]) value = [value substringFromIndex:1];
        _eventBytes += [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        if (_eventBytes > 1024 * 1024) { [self fail:@"单条流式消息超过 1 MB"]; return; }
        [_fields addObject:value];
    }
}
- (void)appendData:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length && !self.error; i++) {
        uint8_t byte = bytes[i];
        if (_afterCR && byte == '\n') { _afterCR = NO; continue; }
        _afterCR = byte == '\r';
        if (byte == '\r' || byte == '\n') [self consumeLine];
        else {
            [_line appendBytes:&byte length:1];
            if (_line.length > 1024 * 1024) [self fail:@"流式消息行超过 1 MB"];
        }
    }
}
- (void)finish {
    // SSE dispatches on a blank line. A truncated final event must not become an answer.
    if (_line.length || _fields.count) [self fail:@"流式响应中途断开，请重新生成"];
}
@end
