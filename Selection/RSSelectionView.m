#import "RSSelectionView.h"
#import <math.h>
#import "../Preferences/RSOptions.h"

typedef NS_ENUM(NSInteger, RSSelectionDragMode) {
    RSSelectionDragNew,
    RSSelectionDragMove,
    RSSelectionDragTopLeft,
    RSSelectionDragTopRight,
    RSSelectionDragBottomLeft,
    RSSelectionDragBottomRight,
};

static const CGFloat RSMinimumSelectionSize = 44.0;
static const CGFloat RSHandleHitRadius = 28.0;

@interface RSSelectionView ()
@property (nonatomic) CGRect selectionRect;
@property (nonatomic) CGPoint startPoint;
@property (nonatomic) CGPoint lastPoint;
@property (nonatomic) RSSelectionDragMode dragMode;
@end

@implementation RSSelectionView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.opaque = NO;
        self.multipleTouchEnabled = NO;
    }
    return self;
}

- (BOOL)hasValidSelection {
    return CGRectGetWidth(self.selectionRect) >= RSMinimumSelectionSize &&
           CGRectGetHeight(self.selectionRect) >= RSMinimumSelectionSize;
}
- (void)selectAll { self.selectionRect = self.bounds; [self setNeedsDisplay]; }

- (CGPoint)clampedPoint:(CGPoint)point {
    return CGPointMake(MIN(MAX(point.x, 0), CGRectGetWidth(self.bounds)),
                       MIN(MAX(point.y, 0), CGRectGetHeight(self.bounds)));
}

- (CGRect)newRectFromPoint:(CGPoint)start toPoint:(CGPoint)end {
    CGFloat dx = end.x - start.x;
    CGFloat dy = end.y - start.y;
    CGFloat x2 = start.x + (dx < 0 ? -MAX(fabs(dx), RSMinimumSelectionSize)
                                   : MAX(dx, RSMinimumSelectionSize));
    CGFloat y2 = start.y + (dy < 0 ? -MAX(fabs(dy), RSMinimumSelectionSize)
                                   : MAX(dy, RSMinimumSelectionSize));
    x2 = MIN(MAX(x2, 0), CGRectGetWidth(self.bounds));
    y2 = MIN(MAX(y2, 0), CGRectGetHeight(self.bounds));
    CGRect rect = CGRectStandardize(CGRectMake(start.x, start.y, x2 - start.x, y2 - start.y));
    if (CGRectGetWidth(rect) < RSMinimumSelectionSize) {
        rect.origin.x = MIN(MAX(start.x - RSMinimumSelectionSize / 2.0, 0),
                            CGRectGetWidth(self.bounds) - RSMinimumSelectionSize);
        rect.size.width = RSMinimumSelectionSize;
    }
    if (CGRectGetHeight(rect) < RSMinimumSelectionSize) {
        rect.origin.y = MIN(MAX(start.y - RSMinimumSelectionSize / 2.0, 0),
                            CGRectGetHeight(self.bounds) - RSMinimumSelectionSize);
        rect.size.height = RSMinimumSelectionSize;
    }
    return rect;
}

- (RSSelectionDragMode)modeForPoint:(CGPoint)point {
    if (![self hasValidSelection]) return RSSelectionDragNew;
    CGRect rect = self.selectionRect;
    CGPoint corners[] = {
        rect.origin,
        CGPointMake(CGRectGetMaxX(rect), CGRectGetMinY(rect)),
        CGPointMake(CGRectGetMinX(rect), CGRectGetMaxY(rect)),
        CGPointMake(CGRectGetMaxX(rect), CGRectGetMaxY(rect)),
    };
    RSSelectionDragMode modes[] = {
        RSSelectionDragTopLeft, RSSelectionDragTopRight,
        RSSelectionDragBottomLeft, RSSelectionDragBottomRight,
    };
    for (NSUInteger index = 0; index < 4; index++) {
        if (hypot(point.x - corners[index].x, point.y - corners[index].y) <= RSHandleHitRadius)
            return modes[index];
    }
    return CGRectContainsPoint(rect, point) ? RSSelectionDragMove : RSSelectionDragNew;
}

- (CGRect)resizedRectForPoint:(CGPoint)point {
    CGRect rect = self.selectionRect;
    point = [self clampedPoint:point];
    CGFloat left = CGRectGetMinX(rect), right = CGRectGetMaxX(rect);
    CGFloat top = CGRectGetMinY(rect), bottom = CGRectGetMaxY(rect);
    switch (self.dragMode) {
        case RSSelectionDragTopLeft:
            left = MIN(point.x, right - RSMinimumSelectionSize);
            top = MIN(point.y, bottom - RSMinimumSelectionSize);
            break;
        case RSSelectionDragTopRight:
            right = MAX(point.x, left + RSMinimumSelectionSize);
            top = MIN(point.y, bottom - RSMinimumSelectionSize);
            break;
        case RSSelectionDragBottomLeft:
            left = MIN(point.x, right - RSMinimumSelectionSize);
            bottom = MAX(point.y, top + RSMinimumSelectionSize);
            break;
        case RSSelectionDragBottomRight:
            right = MAX(point.x, left + RSMinimumSelectionSize);
            bottom = MAX(point.y, top + RSMinimumSelectionSize);
            break;
        default:
            break;
    }
    return CGRectMake(left, top, right - left, bottom - top);
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint point = [self clampedPoint:touches.anyObject ? [touches.anyObject locationInView:self] : CGPointZero];
    self.startPoint = point;
    self.lastPoint = point;
    self.dragMode = [self modeForPoint:point];
    if (self.dragMode == RSSelectionDragNew) {
        self.selectionRect = CGRectZero;
        NSLog(@"[RegionShot] selection started");
    }
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    if (!touch) return;
    CGPoint point = [self clampedPoint:[touch locationInView:self]];
    if (self.dragMode == RSSelectionDragNew) {
        self.selectionRect = [self newRectFromPoint:self.startPoint toPoint:point];
    } else if (self.dragMode == RSSelectionDragMove) {
        CGFloat dx = point.x - self.lastPoint.x;
        CGFloat dy = point.y - self.lastPoint.y;
        CGRect rect = CGRectOffset(self.selectionRect, dx, dy);
        rect.origin.x = MIN(MAX(rect.origin.x, 0), CGRectGetWidth(self.bounds) - rect.size.width);
        rect.origin.y = MIN(MAX(rect.origin.y, 0), CGRectGetHeight(self.bounds) - rect.size.height);
        self.selectionRect = rect;
    } else {
        self.selectionRect = [self resizedRectForPoint:point];
    }
    self.lastPoint = point;
    [self setNeedsDisplay];
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = touches.anyObject;
    if (touch.tapCount == 2 && self.hasValidSelection && CGRectContainsPoint(self.selectionRect, [touch locationInView:self]) &&
        [RSOption(@"DoubleTapSelection") boolValue] && self.doubleTapHandler) { self.doubleTapHandler(); return; }
    if (CGRectIsEmpty(self.selectionRect))
        self.selectionRect = [self newRectFromPoint:self.startPoint toPoint:self.startPoint];
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    UIBezierPath *shade = [UIBezierPath bezierPathWithRect:self.bounds];
    if ([self hasValidSelection]) [shade appendPath:[UIBezierPath bezierPathWithRect:self.selectionRect]];
    shade.usesEvenOddFillRule = YES;
    [[UIColor colorWithWhite:0 alpha:[RSOption(@"SelectionShade") doubleValue]] setFill];
    [shade fill];
    if (![self hasValidSelection]) return;

    UIBezierPath *border = [UIBezierPath bezierPathWithRect:CGRectInset(self.selectionRect, 0.5, 0.5)];
    border.lineWidth = 1.5;
    [UIColor.whiteColor setStroke];
    [border stroke];

    CGRect selection = self.selectionRect;
    CGPoint corners[] = {
        selection.origin,
        CGPointMake(CGRectGetMaxX(selection), CGRectGetMinY(selection)),
        CGPointMake(CGRectGetMinX(selection), CGRectGetMaxY(selection)),
        CGPointMake(CGRectGetMaxX(selection), CGRectGetMaxY(selection)),
    };
    for (NSUInteger index = 0; index < 4; index++) {
        UIBezierPath *handle = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(corners[index].x - 5,
                                                                                 corners[index].y - 5, 10, 10)];
        [UIColor.whiteColor setFill];
        [handle fill];
        [[UIColor colorWithWhite:0 alpha:0.65] setStroke];
        handle.lineWidth = 1;
        [handle stroke];
    }
}

@end
