#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

static inline NSDictionary *RSChatFilePart(NSData *data, NSString *name, NSString *mime, BOOL textFile, NSString **error) {
    if (!data.length || data.length > 64 * 1024 * 1024) {
        if (error) *error = @"文件为空或超过 64 MB。";
        return nil;
    }
    if (textFile) {
        const unsigned char *bytes = data.bytes;
        NSStringEncoding encoding = NSUTF8StringEncoding;
        if (data.length >= 4 && ((bytes[0] == 0xff && bytes[1] == 0xfe && !bytes[2] && !bytes[3]) ||
            (!bytes[0] && !bytes[1] && bytes[2] == 0xfe && bytes[3] == 0xff))) encoding = NSUTF32StringEncoding;
        else if (data.length >= 2 && ((bytes[0] == 0xff && bytes[1] == 0xfe) || (bytes[0] == 0xfe && bytes[1] == 0xff))) encoding = NSUTF16StringEncoding;
        NSString *text = [[NSString alloc] initWithData:data encoding:encoding];
        if (!text && encoding == NSUTF8StringEncoding)
            text = [[NSString alloc] initWithData:data encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)];
        if (!text || [text rangeOfString:[NSString stringWithFormat:@"%C", (unichar)0]].location != NSNotFound) {
            if (error) *error = @"无法解码文本文件，请使用 UTF-8、带 BOM 的 UTF-16/UTF-32 或 GB18030 编码。";
            return nil;
        }
        return @{@"type":@"text", @"text":[NSString stringWithFormat:@"附件：%@\n%@", name, text]};
    }
    NSString *uri = [NSString stringWithFormat:@"data:%@;base64,%@", mime ?: @"application/octet-stream", [data base64EncodedStringWithOptions:0]];
    return @{@"type":@"file", @"file":@{@"filename":name, @"file_data":uri}};
}

static inline NSMutableArray *RSChatRequestHistory(NSArray *history, NSIndexSet *excluded) {
    NSMutableArray *messages = [NSMutableArray array];
    [history enumerateObjectsUsingBlock:^(id message, NSUInteger index, __unused BOOL *stop) {
        if (![excluded containsIndex:index]) [messages addObject:message];
    }];
    return messages;
}

static inline NSString *RSChatHTTPError(NSData *body, NSInteger status) {
    id json = body.length ? [NSJSONSerialization JSONObjectWithData:body options:0 error:NULL] : nil;
    id error = [json isKindOfClass:NSDictionary.class] ? json[@"error"] : nil;
    id detail = [error isKindOfClass:NSDictionary.class] ? error[@"message"] : [error isKindOfClass:NSString.class] ? error : nil;
    if (![detail isKindOfClass:NSString.class] && [json isKindOfClass:NSDictionary.class]) detail = json[@"message"];
    if (![detail isKindOfClass:NSString.class] || ![detail length]) detail = @"服务未提供具体原因，请检查请求内容与服务配置。";
    if ([detail length] > 2000) detail = [detail substringToIndex:2000];
    return [NSString stringWithFormat:@"请求失败（HTTP %ld）：%@", (long)status, detail];
}
