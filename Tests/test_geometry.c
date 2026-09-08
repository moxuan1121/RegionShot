#include "../Geometry/RSGeometry.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    RSRectD nearEdge = RSSnapSelection((RSRectD){5, 5, 420, 916}, 428, 926, 0);
    assert(nearEdge.x == 0 && nearEdge.y == 0 && nearEdge.width == 428 && nearEdge.height == 926);
    RSRectD moving = RSSnapSelection((RSRectD){325, 821, 100, 100}, 428, 926, 1);
    assert(moving.x == 328 && moving.y == 826 && moving.width == 100 && moving.height == 100);
    assert(RSEdgeStart(6, 428) == 6);
    assert(RSInterfaceOrientationFromDevice(3) == 4);
    assert(RSInterfaceOrientationFromDevice(4) == 3);
    assert(RSInterfaceOrientationFromDevice(1) == 1);
    assert(RSInterfaceOrientationFromDevice(5) == 0);
    assert(RSEdgeStart(4, 428) == 0);
    assert(RSEdgeStart(424, 428) == 428);
    assert(RSEdgeStart(100, 428) == 100);
    assert(RSEdgeStart(924, 926) == 926);
    assert(RSCaptureRotation(1284, 2778, 3) < 0);
    assert(RSCaptureRotation(1284, 2778, 4) > 0);
    assert(RSCaptureRotation(2778, 1284, 3) == 0); // Already rotated: do not rotate twice.
    assert(RSCaptureRotation(1284, 2778, 1) == 0);
    assert(RSCaptureRotation(NAN, 2778, 3) == 0);
    RSRectD landscape = RSRectToPixels((RSRectD){800, 0, 126, 428}, 926, 428, 2778, 1284);
    assert(landscape.x == 2400 && landscape.y == 0 && landscape.width == 378 && landscape.height == 1284);
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
    for (int delta = -2; delta <= 2; delta++) {
        RSRectD small = RSRectAroundAnchor(200, 300, 200 + delta, 301, 428, 926);
        assert(small.width == abs(delta) && small.height == 1);
    }
    RSRectD edge = RSRectAroundAnchor(200, 300, 250, -20, 428, 926);
    assert(edge.y == 0 && edge.height == 300);
    for (int scale = 1; scale <= 3; scale++) {
        double innerEdge = RSCornerOutset(scale, 3) - 1.5;
        assert(fabs(innerEdge - 1) < 1e-9);
    }
    for (int landscape = 0; landscape < 2; landscape++) for (int percent = 10; percent <= 90; percent += 10) {
        double w = landscape ? 844 : 390, h = landscape ? 390 : 844;
        RSRectD button = RSPromptRect(w, h, 1.6, percent);
        assert(button.x >= 0 && button.y >= 0 && button.x + button.width <= w && button.y + button.height <= h);
        assert(fabs(button.y + button.height / 2 - h * percent / 100) < 1e-9);
    }
    puts("RegionShot geometry checks passed");
}
