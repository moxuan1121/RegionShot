#import "../KeyboardAI/RSKACore.h"
#import "../KeyboardAI/RSKAOptions.h"
#include <assert.h>
int main(void) {



 @autoreleasepool {
    assert(RSKASupportsFastResponse(@"https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", @"qwen3.8-max"));
    assert(!RSKASupportsFastResponse(@"https://example.com/v1/chat/completions", @"qwen3.8-max"));
    assert(!RSKASupportsFastResponse(@"https://dashscope.aliyuncs.com/v1/chat/completions", @"qwen3-max-thinking"));
    NSString *text = @"区域截图 AI 👨‍👩‍👧‍👦\n第二行";
    NSArray *pieces = RSKATextPieces(text);
    assert([[pieces componentsJoinedByString:@""] isEqual:text]);
    NSString *mixed = @"HTTPServer fooBar_2\n中文，👨‍👩‍👧‍👦";
    NSArray *mixedPieces = RSKATextPieces(mixed);
    assert([[mixedPieces componentsJoinedByString:@""] isEqual:mixed]);
    assert([mixedPieces containsObject:@"HTTP"] && [mixedPieces containsObject:@"Server"]);
    assert([mixedPieces containsObject:@"foo"] && [mixedPieces containsObject:@"Bar"]);
    assert([mixedPieces containsObject:@"\n"]);
    NSMutableIndexSet *selected = [NSMutableIndexSet indexSet];
    RSKAPaintSelection(selected, 1, 3, YES);
    assert(selected.count == 3);
    RSKAUpdatePaintSelection(selected, [NSIndexSet indexSet], 1, 1, YES);
    assert(selected.count == 1 && [selected containsIndex:1]);
    NSMutableArray *words = [NSMutableArray arrayWithObject:@"截图"];
    [selected removeAllIndexes]; [selected addIndex:0];
    assert(RSKASplitPiece(words, selected, 0));
    assert([[words componentsJoinedByString:@""] isEqual:@"截图"]);

    return 0;
} }
