#pragma once
#include <stdint.h>
#include <stddef.h>
#include <math.h>

// Positive = downward page progress; zero = duplicate; -1 = ambiguous/no match.
// Input is a top-to-bottom, grayscale strip with identical dimensions.
static inline int RSStitchOffset(const uint8_t *previous, const uint8_t *next,
                                int width, int height, double tolerance) {
    if (!previous || !next || width < 8 || width > 256 || height < 32 || height > 4096 ||
        !isfinite(tolerance) || tolerance < 0 || tolerance > 32) return -1;
    int margin = height / 20;
    double best = INFINITY, second = INFINITY;
    int bestOffset = -1;
    // ponytail: vertical-only alignment; reject horizontal motion and ambiguous repeated content.
    for (int shift = 0; shift <= height * 3 / 4; shift++) {
        uint64_t error = 0, samples = 0;
        for (int y = margin; y < height - shift - margin; y += 3) {
            for (int x = 2; x < width - 2; x += 3) {
                int difference = previous[(size_t)(y + shift) * width + x] - next[(size_t)y * width + x];
                error += difference < 0 ? -difference : difference;
                samples++;
            }
        }
        double score = samples ? (double)error / samples : INFINITY;
        if (score < best) { second = best; best = score; bestOffset = shift; }
        else if (score < second) second = score;
    }
    if (best > tolerance) return -1;
    if (bestOffset == 0 && best < 0.5) return 0;
    if (second - best < 0.8) return -1;
    return bestOffset;
}
