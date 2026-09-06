#include "../Geometry/RSStitch.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    enum { W = 48, H = 240 };
    uint8_t page[W * H * 2], next[W * H];
    uint32_t seed = 42;
    for (size_t i = 0; i < sizeof(page); i++) {
        seed = seed * 1664525u + 1013904223u;
        page[i] = seed >> 24;
    }
    assert(RSStitchOffset(page, page, W, H, 12) == 0);
    for (int shift = 3; shift <= H * 3 / 4; shift += 7) {
        memcpy(next, page + W * shift, sizeof(next));
        assert(RSStitchOffset(page, next, W, H, 12) == shift);
        for (size_t i = 0; i < sizeof(next); i++)
            if (next[i] > 2) next[i] -= 2;
        assert(RSStitchOffset(page, next, W, H, 12) == shift);
    }
    assert(RSStitchOffset(page + 40 * W, page, W, H, 12) == -1);
    memset(next, 128, sizeof(next));
    assert(RSStitchOffset(page, next, W, H, 12) == -1);
    assert(RSStitchOffset(NULL, next, W, H, 12) == -1);
    assert(RSStitchOffset(page, next, W, H, NAN) == -1);
    puts("RegionShot stitch overlap checks passed");
}
