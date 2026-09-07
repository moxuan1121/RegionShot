#pragma once
#include <math.h>

typedef struct {
    double x;
    double y;
    double width;
    double height;
} RSRectD;

static inline int RSInStatusBarRightRegion(double x, double y, double width, double height) {
    return isfinite(x) && isfinite(y) && isfinite(width) && isfinite(height) &&
           width > 0 && height > 0 && x >= width * 0.5 && x < width && y >= 0 && y < height;
}

static inline RSRectD RSToolbarFrame(RSRectD selection, RSRectD safe, double width, double height) {
    width = fmin(width, safe.width); height = fmin(height, safe.height);
    double x = fmax(safe.x, fmin(selection.x + selection.width / 2 - width / 2, safe.x + safe.width - width));
    double y = selection.y + selection.height + 8;
    if (y + height > safe.y + safe.height) y = selection.y - height - 8;
    y = fmax(safe.y, fmin(y, safe.y + safe.height - height));
    return (RSRectD){x, y, width, height};
}

static inline RSRectD RSRectClamp(RSRectD rect, double width, double height) {
    if (!isfinite(rect.x) || !isfinite(rect.y) || !isfinite(rect.width) ||
        !isfinite(rect.height) || width <= 0 || height <= 0) return (RSRectD){0, 0, 0, 0};
    double x1 = fmax(0, fmin(width, rect.x));
    double y1 = fmax(0, fmin(height, rect.y));
    double x2 = fmax(x1, fmin(width, rect.x + rect.width));
    double y2 = fmax(y1, fmin(height, rect.y + rect.height));
    return (RSRectD){x1, y1, x2 - x1, y2 - y1};
}

static inline RSRectD RSRectToPixels(RSRectD rect, double displayWidth,
                                     double displayHeight, double pixelWidth,
                                     double pixelHeight) {
    rect = RSRectClamp(rect, displayWidth, displayHeight);
    if (rect.width <= 0 || rect.height <= 0 || pixelWidth <= 0 || pixelHeight <= 0)
        return (RSRectD){0, 0, 0, 0};
    double sx = pixelWidth / displayWidth;
    double sy = pixelHeight / displayHeight;
    double x1 = floor(rect.x * sx);
    double y1 = floor(rect.y * sy);
    double x2 = ceil((rect.x + rect.width) * sx);
    double y2 = ceil((rect.y + rect.height) * sy);
    return RSRectClamp((RSRectD){x1, y1, x2 - x1, y2 - y1}, pixelWidth, pixelHeight);
}
