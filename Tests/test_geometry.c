#include "../Geometry/RSGeometry.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    RSRectD pixels = RSRectToPixels((RSRectD){10, 20, 100, 200}, 428, 926, 1284, 2778);
    assert(pixels.x == 30 && pixels.y == 60);
    assert(pixels.width == 300 && pixels.height == 600);
    RSRectD clipped = RSRectToPixels((RSRectD){-10, 900, 100, 100}, 428, 926, 1284, 2778);
    assert(clipped.x == 0 && clipped.y == 2700);
    assert(clipped.width == 270 && clipped.height == 78);
    RSRectD invalid = RSRectToPixels((RSRectD){NAN, 0, 1, 1}, 428, 926, 1284, 2778);
    assert(invalid.width == 0 && invalid.height == 0);
    puts("RegionShot geometry checks passed");
}
