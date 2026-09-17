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
    double changedFraction;
} RSLongMatch;

static inline RSLongMatch RSFindVerticalOverlap(const uint8_t *previous, const uint8_t *current,
                                                 size_t width, size_t height) {
    RSLongMatch result = {0, DBL_MAX, 0, 0, 0};
    if (!previous || !current || width < 8 || height < 24) return result;
    uint64_t unchanged = 0, changed = 0;
    for (size_t i = 0; i < width * height; i++) {
        unsigned difference = (unsigned)abs((int)previous[i] - (int)current[i]);
        unchanged += difference;
        changed += difference > 8;
    }
    result.unchangedScore = (double)unchanged / (double)(width * height);
    result.changedFraction = (double)changed / (double)(width * height);

    size_t minimum = 1, maximum = height * 4 / 5;
    double *scores = calloc(maximum + 1, sizeof(*scores));
    if (!scores) return result;
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
        scores[offset] = score;
        if (score < result.score) { result.score = score; result.offset = offset; }
    }
    // Adjacent offsets belong to the same match valley. Compare the winner with
    // a genuinely different seam so repetitive rows cannot masquerade as a match.
    double second = DBL_MAX;
    size_t neighborhood = height / 300 + 3;
    for (size_t offset = minimum; offset <= maximum; offset++)
        if ((offset > result.offset ? offset - result.offset : result.offset - offset) > neighborhood &&
            scores[offset] < second) second = scores[offset];
    free(scores);
    result.margin = second == DBL_MAX ? 0 : second - result.score;
    return result;
}

static inline int RSLongMatchIsReliable(RSLongMatch match) {
    double requiredMargin = match.score * 0.08;
    if (requiredMargin < 0.5) requiredMargin = 0.5;
    return match.offset && match.score <= 16.0 && match.margin >= requiredMargin;
}

#endif
