#import "../AI/RSSSEDecoder.h"
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSData *wire = [@": ping\r\ndata: 你好🙂\r\ndata: world\r\n\r\ndata: [DONE]\n\n" dataUsingEncoding:NSUTF8StringEncoding];
        // Exercise every possible packet boundary, including inside multi-byte characters.
        for (NSUInteger split = 0; split <= wire.length; split++) {
            RSSSEDecoder *decoder = [RSSSEDecoder new];
            NSMutableArray *events = [NSMutableArray array];
            decoder.onEvent = ^(NSString *event) { [events addObject:event]; };
            [decoder appendData:[wire subdataWithRange:NSMakeRange(0, split)]];
            [decoder appendData:[wire subdataWithRange:NSMakeRange(split, wire.length - split)]];
            [decoder finish];
            assert(!decoder.error);
            assert([events isEqualToArray:(@[@"你好🙂\nworld", @"[DONE]"])]);
        }
        RSSSEDecoder *truncated = [RSSSEDecoder new];
        [truncated appendData:[@"data: incomplete" dataUsingEncoding:NSUTF8StringEncoding]];
        [truncated finish];
        assert(truncated.error);
        RSSSEDecoder *oversized = [RSSSEDecoder new];
        [oversized appendData:[NSMutableData dataWithLength:1024 * 1024 + 1]];
        assert(oversized.error);
        RSSSEDecoder *bom = [RSSSEDecoder new];
        NSMutableArray *bomEvents = [NSMutableArray array];
        bom.onEvent = ^(NSString *event) { [bomEvents addObject:event]; };
        NSData *bomWire = [@"\uFEFFdata: 汉字\r\r" dataUsingEncoding:NSUTF8StringEncoding];
        for (NSUInteger i = 0; i < bomWire.length; i++)
            [bom appendData:[bomWire subdataWithRange:NSMakeRange(i, 1)]];
        [bom finish];
        assert(!bom.error && [bomEvents isEqualToArray:@[@"汉字"]]);
        RSSSEDecoder *invalidUTF8 = [RSSSEDecoder new];
        const uint8_t invalid[] = {0xff, '\n'};
        [invalidUTF8 appendData:[NSData dataWithBytes:invalid length:sizeof(invalid)]];
        assert(invalidUTF8.error);
        puts("RegionShot SSE packet-boundary checks passed");
    }
}
