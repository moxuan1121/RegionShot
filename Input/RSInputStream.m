// Adapted from KeyboardAI-RootHide 23c761e, GPL-3.0; see THIRD_PARTY.md.
#import "RSInputStream.h"

@implementation RSInputStream {
    NSMutableData *_line;
    NSMutableString *_event;
    NSMutableString *_text;
    NSString *_error;
    BOOL _finished, _skipLF;
    NSUInteger _received;
}
- (instancetype)init {
    if ((self = [super init])) {
        _line = [NSMutableData data];
        _event = [NSMutableString string];
        _text = [NSMutableString string];
    }
    return self;
}
- (NSString *)text { return [_text copy]; }
- (NSString *)error { return _error; }
- (BOOL)finished { return _finished; }
- (void)consumeEvent {
    if (!_event.length || _finished || _error) return;
    NSString *event = [_event copy];
    [_event setString:@""];
    if ([event isEqualToString:@"[DONE]"]) { _finished = YES; return; }
    id json = [NSJSONSerialization JSONObjectWithData:[event dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    if (![json isKindOfClass:NSDictionary.class]) { _error = @"流式返回格式无效。"; return; }
    if (json[@"error"]) { _error = @"服务端返回错误，请检查模型和接口配置。"; return; }
    id choices = json[@"choices"];
    if (![choices isKindOfClass:NSArray.class]) { _error = @"流式返回缺少 choices。"; return; }
    if (![choices count]) return; // Usage-only event.
    id first = choices[0];
    if (![first isKindOfClass:NSDictionary.class]) { _error = @"流式候选格式无效。"; return; }
    id index = first[@"index"];
    if (index && (![index isKindOfClass:NSNumber.class] || [index integerValue] != 0)) return;
    id delta = first[@"delta"];
    if (delta && delta != NSNull.null && ![delta isKindOfClass:NSDictionary.class]) {
        _error = @"流式内容格式无效。"; return;
    }
    id content = [delta isKindOfClass:NSDictionary.class] ? delta[@"content"] : nil;
    if (content && content != NSNull.null) {
        if (![content isKindOfClass:NSString.class]) { _error = @"流式结果不是文本。"; return; }
        if ([content length] > 24000 - _text.length) { _error = @"结果过长，已停止接收。"; return; }
        [_text appendString:content];
    }
    id reason = first[@"finish_reason"];
    if (reason && reason != NSNull.null) {
        if (![reason isEqual:@"stop"]) _error = @"结果未完整生成，已禁止替换。";
        _finished = YES;
    }
}
- (void)consumeLine {
    NSString *line = [[NSString alloc] initWithData:_line encoding:NSUTF8StringEncoding];
    [_line setLength:0];
    if (!line) { _error = @"流式文本编码无效。"; return; }
    if (!line.length) { [self consumeEvent]; return; }
    if ([line hasPrefix:@"data:"]) {
        NSString *value = [line substringFromIndex:5];
        if ([value hasPrefix:@" "]) value = [value substringFromIndex:1];
        if (_event.length) [_event appendString:@"\n"];
        [_event appendString:value];
    }
}
- (void)appendData:(NSData *)data {
    if (_finished || _error) return;
    if (data.length > 1024 * 1024 - _received) { _error = @"响应超过 1 MB，已停止接收。"; return; }
    _received += data.length;
    const uint8_t *bytes = data.bytes;
    for (NSUInteger i = 0; i < data.length && !_finished && !_error; i++) {
        uint8_t byte = bytes[i];
        if (_skipLF && byte == '\n') { _skipLF = NO; continue; }
        _skipLF = NO;
        if (byte == '\r' || byte == '\n') {
            _skipLF = byte == '\r';
            [self consumeLine];
        } else [_line appendBytes:&byte length:1];
    }
}
- (void)endOfInput {
    if (_finished || _error) return;
    if (_line.length) [self consumeLine];
    [self consumeEvent];
    if (!_finished && !_error) _error = @"连接提前结束，结果可能不完整。";
}
@end
