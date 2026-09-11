#include "../LongShot/RSLongMatch.h"
#include <assert.h>
#include <string.h>

int main(void) {
    enum { W = 32, H = 80, SHIFT = 23 };
    uint8_t first[W * H], second[W * H];
    for (size_t y = 0; y < H; y++) for (size_t x = 0; x < W; x++)
        first[y * W + x] = (uint8_t)((y * 13 + x * 7 + y * x) & 255);
    for (size_t y = 0; y < H - SHIFT; y++)
        memcpy(second + y * W, first + (y + SHIFT) * W, W);
    for (size_t y = H - SHIFT; y < H; y++) for (size_t x = 0; x < W; x++)
        second[y * W + x] = (uint8_t)((y * 17 + x * 11) & 255);
    RSLongMatch match = RSFindVerticalOverlap(first, second, W, H);
    assert(match.offset == SHIFT && match.score == 0 && match.unchangedScore > 1);
    for (size_t shift = 1; shift <= 40; shift++) {
        for (size_t y = 0; y < H - shift; y++)
            memcpy(second + y * W, first + (y + shift) * W, W);
        memset(second + (H - shift) * W, 255, shift * W);
        match = RSFindVerticalOverlap(first, second, W, H);
        assert(match.offset == shift && match.score == 0);
    }
    match = RSFindVerticalOverlap(first, first, W, H);
    assert(match.unchangedScore == 0);
    return 0;
}
