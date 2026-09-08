#import "../KeyboardAI/RSKACore.h"
#import "../KeyboardAI/RSKAOptions.h"
#include <assert.h>
int main(void) { @autoreleasepool {
    NSString *text = @"区域截图 AI 👨‍👩‍👧‍👦\n第二行";
    NSArray *pieces = RSKATextPieces(text);
    assert([[pieces componentsJoinedByString:@""] isEqual:text]);
    NSMutableIndexSet *selected = [NSMutableIndexSet indexSet];
    RSKAPaintSelection(selected, 1, 3, YES);
    assert(selected.count == 3);
    RSKAUpdatePaintSelection(selected, [NSIndexSet indexSet], 1, 1, YES);
    assert(selected.count == 1 && [selected containsIndex:1]);
    NSMutableArray *words = [NSMutableArray arrayWithObject:@"截图"];
    [selected removeAllIndexes]; [selected addIndex:0];
    assert(RSKASplitPiece(words, selected, 0));
    assert([[words componentsJoinedByString:@""] isEqual:@"截图"]);
    assert(RSKAFittedPanelHeight(2000, 80, 800, 60) == 480);
    return 0;
} }
