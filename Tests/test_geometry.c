#include "../Geometry/RSGeometry.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    assert(RSInStatusBarRightRegion(300, 20, 428, 44));
    assert(!RSInStatusBarRightRegion(100, 20, 428, 44));
    assert(!RSInStatusBarRightRegion(428, 20, 428, 44));
    assert(!RSInStatusBarRightRegion(NAN, 20, 428, 44));
    RSRectD pixels = RSRectToPixels((RSRectD){10, 20, 100, 200}, 428, 926, 1284, 2778);
    assert(pixels.x == 30 && pixels.y == 60);
    assert(pixels.width == 300 && pixels.height == 600);
    RSRectD clipped = RSRectToPixels((RSRectD){-10, 900, 100, 100}, 428, 926, 1284, 2778);
    assert(clipped.x == 0 && clipped.y == 2700);
    assert(clipped.width == 270 && clipped.height == 78);
    RSRectD invalid = RSRectToPixels((RSRectD){NAN, 0, 1, 1}, 428, 926, 1284, 2778);
    assert(invalid.width == 0 && invalid.height == 0);
    RSRectD safe = {16, 60, 396, 820};
    RSRectD toolbar = RSToolbarFrame((RSRectD){120, 200, 100, 200}, safe, 300, 60);
    assert(toolbar.y == 408 && toolbar.x == 20);
    toolbar = RSToolbarFrame((RSRectD){300, 750, 100, 100}, safe, 300, 60);
    assert(toolbar.y == 682 && toolbar.x == 112);
    toolbar = RSToolbarFrame((RSRectD){0, 0, 428, 926}, safe, 600, 60);
    assert(toolbar.x == 16 && toolbar.width == 396 && toolbar.y >= safe.y && toolbar.y + toolbar.height <= 880);
    // Repeated circles must cross the anchor without locking to the original corner.
    for (int pass = 0; pass < 3; pass++) for (int quadrant = 0; quadrant < 4; quadrant++) {
        double x = quadrant & 1 ? 300 : 100, y = quadrant & 2 ? 400 : 200;
        RSRectD r = RSRectAroundAnchor(200, 300, x, y, 428, 926);
        assert(r.width == 100 && r.height == 100);
        assert(r.x == fmin(200, x) && r.y == fmin(300, y));
    }
    RSRectD edge = RSRectAroundAnchor(200, 300, 250, -20, 428, 926);
    assert(edge.y == 0 && edge.height == 300);
    puts("RegionShot geometry checks passed");
}
