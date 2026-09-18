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
                unsigned aligned = (unsigned)abs((int)a[x] - (int)b[x]);
                unsigned stationary = (unsigned)abs((int)previous[y * width + x] - (int)b[x]);
                if (stationary <= 2 && aligned > 8) continue;
                difference += aligned; samples++;
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

// Refine a cheap coarse match in a small, higher-resolution search window.
// The caller supplies grayscale or vertical-edge rows; fixed screen pixels are
// ignored when they disagree with the aligned scrolling candidate.
static inline size_t RSRefineVerticalOffset(const uint8_t *previous, const uint8_t *current,
                                            size_t width, size_t height, size_t coarse,
                                            size_t radius) {
    if (!previous || !current || width < 8 || height < 24 || !coarse) return coarse;
    size_t minimum = coarse > radius ? coarse - radius : 1;
    size_t maximum = coarse + radius;
    size_t limit = height * 4 / 5;
    if (maximum > limit) maximum = limit;
    size_t best = coarse;
    double bestScore = DBL_MAX, coarseScore = DBL_MAX;
    for (size_t offset = minimum; offset <= maximum; offset++) {
        size_t overlap = height - offset;
        size_t stepY = overlap > 240 ? overlap / 240 : 1;
        uint64_t difference = 0, samples = 0;
        for (size_t y = 0; y < overlap; y += stepY) {
            const uint8_t *aligned = previous + (y + offset) * width;
            const uint8_t *stationary = previous + y * width;
            const uint8_t *incoming = current + y * width;
            for (size_t x = 0; x < width; x += 2) {
                unsigned alignedDifference = (unsigned)abs((int)aligned[x] - (int)incoming[x]);
                unsigned stationaryDifference = (unsigned)abs((int)stationary[x] - (int)incoming[x]);
                if (stationaryDifference <= 2 && alignedDifference > 8) continue;
                difference += alignedDifference;
                samples++;
            }
        }
        double score = samples ? (double)difference / (double)samples : DBL_MAX;
        if (offset == coarse) coarseScore = score;
        if (score < bestScore) { bestScore = score; best = offset; }
    }
    // The coarse result is already confidence-checked. Change it only when the
    // detailed rows provide a material improvement, not a neighboring tie.
    return best != coarse && bestScore + 0.25 < coarseScore * 0.97 ? best : coarse;
}

// Move a hard cut upward only when a nearby aligned row is substantially
// quieter. This keeps the output height unchanged: the stitcher trims the same
// number of rows from its tail before appending the longer incoming strip.
static inline size_t RSFindQuietSeamRewind(const uint8_t *previous, const uint8_t *current,
                                           size_t width, size_t height, size_t offset,
                                           size_t incomingEnd, size_t maximumRewind) {
    if (!previous || !current || width < 8 || !offset || incomingEnd < 2) return 0;
    if (maximumRewind >= incomingEnd) maximumRewind = incomingEnd - 1;
    double bestScore = DBL_MAX, baseScore = DBL_MAX;
    size_t bestRewind = 0;
    for (size_t rewind = 0; rewind <= maximumRewind; rewind++) {
        size_t seam = incomingEnd - rewind;
        uint64_t difference = 0, samples = 0;
        size_t band = seam < 4 ? seam : 4;
        for (size_t row = 1; row <= band; row++) {
            size_t currentY = seam - row;
            size_t previousY = currentY + offset;
            if (previousY >= height) continue;
            const uint8_t *a = previous + previousY * width;
            const uint8_t *b = current + currentY * width;
            for (size_t x = 0; x < width; x += 2) {
                difference += (unsigned)abs((int)a[x] - (int)b[x]);
                samples++;
            }
        }
        double score = samples ? (double)difference / (double)samples : DBL_MAX;
        if (!rewind) baseScore = score;
        if (score < bestScore) { bestScore = score; bestRewind = rewind; }
    }
    // Avoid moving a clean seam just because another row is microscopically better.
    return bestRewind && bestScore + 0.5 < baseScore * 0.75 ? bestRewind : 0;
}

#endif
