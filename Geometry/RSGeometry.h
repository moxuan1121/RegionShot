#pragma once
#include <math.h>

typedef struct {
    double x;
    double y;
    double width;
    double height;
} RSRectD;

// Device landscape and interface landscape use opposite left/right names.
static inline int RSInterfaceOrientationFromDevice(int device) {
    return device == 3 ? 4 : device == 4 ? 3 : device == 1 ? 1 : 0;
}

// Touch centroids near the physical border should crop from the border, not leave a strip.
static inline double RSEdgeStart(double point, double extent) {
    if (point <= 5) return 0;
    if (point >= extent - 5) return extent;
    return point;
}

static inline RSRectD RSSnapSelection(RSRectD r, double width, double height, int moving) {
    if (moving) {
        if (r.x <= 5) r.x = 0;
        else if (width - r.x - r.width <= 5) r.x = width - r.width;
        if (r.y <= 5) r.y = 0;
        else if (height - r.y - r.height <= 5) r.y = height - r.height;
    } else {
        double right = r.x + r.width, bottom = r.y + r.height;
        r.x = RSEdgeStart(r.x, width); r.y = RSEdgeStart(r.y, height);
        right = RSEdgeStart(right, width); bottom = RSEdgeStart(bottom, height);
        r.width = right - r.x; r.height = bottom - r.y;
    }
    return r;
}

// UIKit interface orientation values: landscape left=3, right=4.
// Screen capture may still return portrait framebuffer pixels in landscape.
static inline double RSCaptureRotation(double width, double height, int orientation) {
    if (width <= 0 || height <= width || !isfinite(width) || !isfinite(height)) return 0;
    return orientation == 3 ? -1.5707963267948966 : orientation == 4 ? 1.5707963267948966 : 0;
}

// Keep a visible one-point gap on Retina screens, while preserving one physical pixel at 1x.
static inline double RSCornerOutset(double scale, double strokeWidth) {
    return strokeWidth / 2 + fmax(1 / scale, 1);
}

// Anchor stays fixed even when a corner is dragged through all four quadrants.
static inline RSRectD RSRectAroundAnchor(double ax, double ay, double x, double y, double width, double height) {
    double x2 = fmax(0, fmin(width, x));
    double y2 = fmax(0, fmin(height, y));
    RSRectD rect = {fmin(ax, x2), fmin(ay, y2), fabs(x2 - ax), fabs(y2 - ay)};
    return rect;
}

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

// Prompt height is a percentage of the visible orientation's height, not the
// portrait screen height. Clamp the complete touch target inside that canvas.
static inline RSRectD RSPromptRect(double width, double height, double scale, double percent) {
    double w = fmin(fmax(0, width), 72 * scale), h = fmin(fmax(0, height), 44 * scale);
    double x = fmax(0, width - w - 16);
    double y = fmax(0, fmin(height - h, height * percent / 100 - h / 2));
    return (RSRectD){x, y, w, h};
}

static inline int RSValidInterfaceOrientation(int value) { return value == 1 || value == 3 || value == 4; }
