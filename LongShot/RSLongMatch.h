#ifndef RSLongMatch_h
#define RSLongMatch_h

#include <float.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct {
    size_t offset;
    double score;
    double margin;
    double unchangedScore;
} RSLongMatch;

static inline RSLongMatch RSFindVerticalOverlap(const uint8_t *previous, const uint8_t *current,
                                                 size_t width, size_t height) {
    RSLongMatch result = {0, DBL_MAX, 0, 0};
    if (!previous || !current || width < 8 || height < 24) return result;
    uint64_t unchanged = 0;
    for (size_t i = 0; i < width * height; i++) unchanged += (uint64_t)abs((int)previous[i] - (int)current[i]);
    result.unchangedScore = (double)unchanged / (double)(width * height);

    double second = DBL_MAX;
    size_t minimum = 1, maximum = height * 4 / 5;
    for (size_t offset = minimum; offset <= maximum; offset++) {
        size_t overlap = height - offset, stepY = overlap > 120 ? overlap / 120 : 1;
        uint64_t difference = 0, samples = 0;
        for (size_t y = 0; y < overlap; y += stepY) {
            const uint8_t *a = previous + (y + offset) * width;
            const uint8_t *b = current + y * width;
            for (size_t x = 0; x < width; x += 2) {
                difference += (uint64_t)abs((int)a[x] - (int)b[x]); samples++;
            }
        }
        double score = samples ? (double)difference / (double)samples : DBL_MAX;
        if (score < result.score) { second = result.score; result.score = score; result.offset = offset; }
        else if (score < second) second = score;
    }
    result.margin = second == DBL_MAX ? 0 : second - result.score;
    return result;
}

#endif
