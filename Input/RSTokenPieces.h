#import <Foundation/Foundation.h>

// Keep every source character, including punctuation and whitespace, selectable.
static inline NSArray<NSString *> *RSTokenPieces(NSString *text) {
    if (![text isKindOfClass:NSString.class] || text.length > 24000) return @[];
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSMutableIndexSet *occupied = [NSMutableIndexSet indexSet];
    NSUInteger length = text.length;
    for (NSUInteger i = 0; i < length;) {
        unichar c = [text characterAtIndex:i];
        if (c == '\r' || c == '\n') {
            NSUInteger end = i + (c == '\r' && i + 1 < length && [text characterAtIndex:i + 1] == '\n' ? 2 : 1);
            NSRange range = NSMakeRange(i, end - i);
            [ranges addObject:[NSValue valueWithRange:range]];
            [occupied addIndexesInRange:range];
            i = end;
            continue;
        }
        BOOL asciiWord = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
        if (!asciiWord) { i++; continue; }
        NSUInteger end = i + 1;
        while (end < length) {
            unichar next = [text characterAtIndex:end];
            if (!((next >= 'a' && next <= 'z') || (next >= 'A' && next <= 'Z') ||
                  (next >= '0' && next <= '9') || next == '_')) break;
            end++;
        }
        NSUInteger start = i;
        for (NSUInteger j = i + 1; j < end; j++) {
            unichar prev = [text characterAtIndex:j - 1], next = [text characterAtIndex:j];
            BOOL prevLower = prev >= 'a' && prev <= 'z';
            BOOL nextUpper = next >= 'A' && next <= 'Z';
            BOOL acronymEnd = j + 1 < end && prev >= 'A' && prev <= 'Z' && nextUpper &&
                [text characterAtIndex:j + 1] >= 'a' && [text characterAtIndex:j + 1] <= 'z';
            if ((prevLower && nextUpper) || acronymEnd || prev == '_' || next == '_') {
                if (j > start) {
                    NSRange range = NSMakeRange(start, j - start);
                    [ranges addObject:[NSValue valueWithRange:range]];
                    [occupied addIndexesInRange:range];
                }
                start = j;
            }
        }
        NSRange range = NSMakeRange(start, end - start);
        [ranges addObject:[NSValue valueWithRange:range]];
        [occupied addIndexesInRange:range];
        i = end;
    }
    [text enumerateSubstringsInRange:NSMakeRange(0, length)
                            options:NSStringEnumerationByWords | NSStringEnumerationLocalized
                         usingBlock:^(__unused NSString *word, NSRange range, __unused NSRange enclosing, __unused BOOL *stop) {
        if (!range.length || [occupied intersectsIndexesInRange:range]) return;
        [ranges addObject:[NSValue valueWithRange:range]];
        [occupied addIndexesInRange:range];
    }];
    [ranges sortUsingComparator:^NSComparisonResult(NSValue *a, NSValue *b) {
        NSUInteger left = a.rangeValue.location, right = b.rangeValue.location;
        return left < right ? NSOrderedAscending : left > right ? NSOrderedDescending : NSOrderedSame;
    }];
    NSMutableArray<NSString *> *pieces = [NSMutableArray arrayWithCapacity:ranges.count * 2 + 1];
    NSUInteger cursor = 0;
    for (NSValue *value in ranges) {
        NSRange range = value.rangeValue;
        if (range.location > cursor) [pieces addObject:[text substringWithRange:NSMakeRange(cursor, range.location - cursor)]];
        [pieces addObject:[text substringWithRange:range]];
        cursor = NSMaxRange(range);
    }
    if (cursor < length) [pieces addObject:[text substringFromIndex:cursor]];
    return pieces;
}
