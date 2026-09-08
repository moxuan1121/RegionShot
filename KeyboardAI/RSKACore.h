#import <Foundation/Foundation.h>


static inline NSString *RSKATrim(NSString *text) {
    return [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static inline NSArray<NSString *> *RSKATextPieces(NSString *text) {
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

static inline BOOL RSKASplitPiece(NSMutableArray<NSString *> *pieces, NSMutableIndexSet *selected, NSUInteger index) {
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
static inline void RSKAPaintSelection(NSMutableIndexSet *selected, NSUInteger from, NSUInteger to, BOOL selecting) {
    NSRange range = NSMakeRange(MIN(from, to), MAX(from, to) - MIN(from, to) + 1);
    if (selecting) [selected addIndexesInRange:range];
    else [selected removeIndexesInRange:range];
}

static inline void RSKAUpdatePaintSelection(NSMutableIndexSet *selected, NSIndexSet *baseline,
        NSUInteger anchor, NSUInteger current, BOOL selecting) {
    [selected removeAllIndexes];
    [selected addIndexes:baseline];
    RSKAPaintSelection(selected, anchor, current, selecting);
}

static inline BOOL RSKASupportsFastResponse(NSString *endpoint, NSString *model) {
    NSString *host = [NSURLComponents componentsWithString:endpoint].host.lowercaseString;
    NSString *name = model.lowercaseString;
    return ([host hasSuffix:@".maas.aliyuncs.com"] || [host isEqualToString:@"dashscope.aliyuncs.com"] || [host hasSuffix:@".dashscope.aliyuncs.com"]) &&
        [name hasPrefix:@"qwen3"] && ![name containsString:@"thinking"] && ![name containsString:@"instruct"];
}
