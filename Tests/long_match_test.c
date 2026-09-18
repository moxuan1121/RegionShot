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
    assert(match.offset == SHIFT && match.score == 0 && match.unchangedScore > 1 && RSLongMatchIsReliable(match));
    for (size_t y = 8; y < H - 8; y++) {
        memset(first + y * W, 37, W * 3 / 4);
        memset(second + y * W, 37, W * 3 / 4);
    }
    match = RSFindVerticalOverlap(first, second, W, H);
    assert(match.offset == SHIFT && RSLongMatchIsReliable(match));
    for (size_t shift = 1; shift <= 60; shift++) {
        for (size_t y = 0; y < H - shift; y++)
            memcpy(second + y * W, first + (y + shift) * W, W);
        memset(second + (H - shift) * W, 255, shift * W);
        match = RSFindVerticalOverlap(first, second, W, H);
        assert(match.offset == shift && match.score == 0);
    }
    match = RSFindVerticalOverlap(first, first, W, H);
    assert(match.unchangedScore == 0 && match.changedFraction == 0);

    // A higher-resolution local pass corrects a deliberately imprecise coarse offset.
    for (size_t y = 0; y < H - SHIFT; y++)
        memcpy(second + y * W, first + (y + SHIFT) * W, W);
    memset(second + (H - SHIFT) * W, 219, SHIFT * W);
    assert(RSRefineVerticalOffset(first, second, W, H, SHIFT + 4, 6) == SHIFT);

    // Keep an already clean hard seam, but move away from a noisy boundary.
    assert(RSFindQuietSeamRewind(first, second, W, H, SHIFT, H - SHIFT, 8) == 0);
    for (size_t x = 0; x < W; x++) second[(H - SHIFT - 1) * W + x] ^= 0xff;
    assert(RSFindQuietSeamRewind(first, second, W, H, SHIFT, H - SHIFT, 8) > 0);

    RSLongMatch recovered = RSFindVerticalOverlapNear(first, second, W, H, SHIFT + 2, 6);
    assert(recovered.offset == SHIFT && RSLongMatchIsReliable(recovered));

    uint8_t overlayFirst[W * H], overlaySecond[W * H];
    for (size_t y = 0; y < H; y++) for (size_t x = 0; x < W; x++)
        overlayFirst[y * W + x] = (uint8_t)((y * 19 + x * 11 + y * x) & 255);
    for (size_t y = 0; y < H - SHIFT; y++)
        memcpy(overlaySecond + y * W, overlayFirst + (y + SHIFT) * W, W);
    memset(overlaySecond + (H - SHIFT) * W, 211, SHIFT * W);
    for (size_t y = 48; y < 58; y++)
        for (size_t x = 10; x < 18; x++) overlayFirst[y * W + x] = overlaySecond[y * W + x] = 31;
    size_t overlay = RSFindLowerFixedOverlayStart(overlayFirst, overlaySecond, W, H, SHIFT, H / 2);
    assert(overlay >= 48 && overlay <= 50);

    memset(overlayFirst, 80, sizeof(overlayFirst));
    memset(overlaySecond, 80, sizeof(overlaySecond));
    assert(RSFindLowerFixedOverlayStart(overlayFirst, overlaySecond, W, H, SHIFT, H / 2) == H);

    memset(first, 255, sizeof(first)); memset(second, 255, sizeof(second));
    for (size_t y = 12; y < 16; y++) memset(first + y * W + 4, 0, 24);
    for (size_t y = 5; y < 9; y++) memset(second + y * W + 4, 0, 24);
    match = RSFindVerticalOverlap(first, second, W, H);
    assert(match.changedFraction > 0.002);

    for (size_t y = 0; y < H; y++) for (size_t x = 0; x < W; x++) {
        first[y * W + x] = (uint8_t)((y % 8) * 20);
        second[y * W + x] = first[((y + 8) % H) * W + x];
    }
    memset(second + (H - 8) * W, 231, 8 * W);
    match = RSFindVerticalOverlap(first, second, W, H);
    assert(match.changedFraction > 0.002 && !RSLongMatchIsReliable(match));
    return 0;
}
