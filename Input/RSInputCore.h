// Adapted from KeyboardAI-RootHide 23c761e, GPL-3.0; see THIRD_PARTY.md.
#import <Foundation/Foundation.h>


static inline NSString *RSInputTrim(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static inline NSString *RSInputConfigError(NSString *endpoint, NSString *model, NSString *key) {
    if (![endpoint isKindOfClass:NSString.class] || endpoint.length > 2048)
        return @"请填写完整的 HTTPS 接口地址。";
    NSURLComponents *url = [NSURLComponents componentsWithString:endpoint];
    if (![url.scheme.lowercaseString isEqualToString:@"https"] || !url.host.length ||
        !url.URL || url.user || url.password || url.fragment || url.query ||
        [endpoint rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location != NSNotFound)
        return @"接口需为完整 HTTPS 地址，不含账号、查询参数或空格。";
    if (![model isKindOfClass:NSString.class] || !RSInputTrim(model).length || model.length > 200)
        return @"请填写有效的模型名称（最多 200 字符）。";
    if (![key isKindOfClass:NSString.class] || !key.length || key.length > 4096 ||
        [key rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound)
        return @"请填写有效的接口密钥。";
    return nil;
}

static inline NSArray<NSDictionary *> *RSInputDefaultActions(void) {
    return @[
        @{@"title": @"译为日语", @"summary": @"自然、准确地翻译为日语", @"icon": @"character.bubble", @"prompt": @"将用户文本翻译为自然、准确的日语。保持原意，只输出译文，不解释。"},
        @{@"title": @"译为英语", @"summary": @"保留原意，输出自然英文", @"icon": @"character.bubble", @"prompt": @"Translate the user's text into natural English. Preserve its meaning. Output only the translation."},
        @{@"title": @"智能助手", @"summary": @"简洁回答，生成可用内容", @"icon": @"bubble.left", @"prompt": @"根据用户输入给出简洁、自然、可直接使用的中文回答。"}
    ];
}

static inline BOOL RSInputValidActions(id actions) {
    if (![actions isKindOfClass:NSArray.class] || ![actions count] || [actions count] > 8) return NO;
    for (id item in actions) {
        if (![item isKindOfClass:NSDictionary.class]) return NO;
        id title = item[@"title"], prompt = item[@"prompt"];
        if (![title isKindOfClass:NSString.class] || !RSInputTrim(title).length || [title length] > 20 ||
            ![prompt isKindOfClass:NSString.class] || !RSInputTrim(prompt).length || [prompt length] > 4000) return NO;
    }
    return YES;
}

static inline NSData *RSInputRequestBody(NSString *model, NSString *prompt, NSString *input) {
    return [NSJSONSerialization dataWithJSONObject:@{
        @"model": model, @"stream": @YES,
        @"messages": @[@{@"role": @"system", @"content": prompt},
                        @{@"role": @"user", @"content": input}]
    } options:0 error:NULL];
}

static inline BOOL RSInputSupportsFastResponse(NSString *endpoint, NSString *model) {
    NSString *host = [NSURLComponents componentsWithString:endpoint].host.lowercaseString;
    NSString *name = model.lowercaseString;
    return ([host hasSuffix:@".maas.aliyuncs.com"] || [host isEqualToString:@"dashscope.aliyuncs.com"] || [host hasSuffix:@".dashscope.aliyuncs.com"]) &&
        [name hasPrefix:@"qwen3"] && ![name containsString:@"thinking"] && ![name containsString:@"instruct"];
}

static inline NSString *RSInputParseResponse(NSData *data, NSInteger status, NSString **error) {
    if (error) *error = nil;
    NSString *failure = nil, *result = nil;
    if (status < 200 || status >= 300) {
        failure = [NSString stringWithFormat:@"请求失败（HTTP %ld），请检查接口、密钥、模型或额度。", (long)status];
    } else if (!data.length || data.length > 1024 * 1024) {
        failure = @"接口返回为空或超过 1 MB。";
    } else {
        id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
        id choices = [json isKindOfClass:NSDictionary.class] ? json[@"choices"] : nil;
        id first = [choices isKindOfClass:NSArray.class] && [choices count] ? choices[0] : nil;
        id message = [first isKindOfClass:NSDictionary.class] ? first[@"message"] : nil;
        id content = [message isKindOfClass:NSDictionary.class] ? message[@"content"] : nil;
        id finish = [first isKindOfClass:NSDictionary.class] ? first[@"finish_reason"] : nil;
        if ([finish isEqual:@"length"]) {
            failure = @"结果被服务端截断，请缩短输入后重试。原文未修改。";
        } else if (![content isKindOfClass:NSString.class] || !RSInputTrim(content).length || [content length] > 24000) {
            failure = @"未收到有效文本结果，需使用兼容 Chat Completions 的文本模型。";
        } else result = content;
    }
    if (error) *error = failure;
    return result;
}

// Validate document identity separately in the UI layer, then use this exact snapshot check.
static inline BOOL RSInputCanReplace(NSString *original, NSString *current, NSRange range, NSString *result) {
    return original && current && result.length && [original isEqualToString:current] &&
        range.location != NSNotFound && range.location <= current.length &&
        range.length <= current.length - range.location;
}

// Preserve punctuation and spaces so selecting every piece reproduces the exact result.
static inline NSArray<NSString *> *RSInputTextPieces(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length > 24000) return @[];
    NSMutableArray *pieces = [NSMutableArray array];
    __block NSUInteger end = 0;
    [text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByWords usingBlock:^(NSString *word, NSRange range, __unused NSRange enclosing, __unused BOOL *stop) {
        if (range.location > end) [pieces addObject:[text substringWithRange:NSMakeRange(end, range.location - end)]];
        [pieces addObject:word];
        end = NSMaxRange(range);
    }];
    if (end < text.length) [pieces addObject:[text substringFromIndex:end]];
    return pieces;
}

static inline BOOL RSInputSplitPiece(NSMutableArray<NSString *> *pieces, NSMutableIndexSet *selected, NSUInteger index) {
    if (index >= pieces.count) return NO;
    NSString *piece = pieces[index];
    NSMutableArray *characters = [NSMutableArray array];
    [piece enumerateSubstringsInRange:NSMakeRange(0, piece.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *character, __unused NSRange range, __unused NSRange enclosing, __unused BOOL *stop) {
        [characters addObject:character];
    }];
    if (characters.count < 2) return NO;
    BOOL wasSelected = [selected containsIndex:index];
    [selected removeIndex:index];
    [selected shiftIndexesStartingAtIndex:index + 1 by:(NSInteger)characters.count - 1];
    [pieces replaceObjectsInRange:NSMakeRange(index, 1) withObjectsFromArray:characters];
    if (wasSelected) [selected addIndexesInRange:NSMakeRange(index, characters.count)];
    return YES;
}
static inline void RSInputPaintSelection(NSMutableIndexSet *selected, NSUInteger from, NSUInteger to, BOOL selecting) {
    NSRange range = NSMakeRange(MIN(from, to), MAX(from, to) - MIN(from, to) + 1);
    if (selecting) [selected addIndexesInRange:range];
    else [selected removeIndexesInRange:range];
}

static inline void RSInputUpdatePaintSelection(NSMutableIndexSet *selected, NSIndexSet *baseline,
        NSUInteger anchor, NSUInteger current, BOOL selecting) {
    [selected removeAllIndexes];
    [selected addIndexes:baseline];
    RSInputPaintSelection(selected, anchor, current, selecting);
}
