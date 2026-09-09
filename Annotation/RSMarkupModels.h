#import <UIKit/UIKit.h>

// Drawing modes — one per toolbar button (mirrors the original's set*Mode methods).
typedef NS_ENUM(NSInteger, RSMarkupDrawMode) {
    RSMarkupDrawModeArrow = 0,
    RSMarkupDrawModeRect,
    RSMarkupDrawModeCircle,
    RSMarkupDrawModeScribble,
    RSMarkupDrawModeMosaic,
    RSMarkupDrawModeMagnifier,
    RSMarkupDrawModeText,
    RSMarkupDrawModeHighlight,   // 1.6 新增：聚光灯式高亮（圆角选区 + 周边压暗）
};

@class RSMarkupTextAnnotation;
// One vector/graphic mark on the canvas.
@interface RSMarkupAnnotationItem : NSObject
@property (nonatomic) RSMarkupDrawMode type;
@property (nonatomic, strong) RSMarkupTextAnnotation *textAnnotation;
@property (nonatomic, strong) NSMutableArray<NSValue *> *pathPoints; // scribble/mosaic trail
@property (nonatomic, strong) UIColor *color;
@property (nonatomic) CGFloat lineWidth;
@property (nonatomic) CGFloat magnifyScale;   // magnifier only
@property (nonatomic) CGPoint startPoint;     // two-point shapes
@property (nonatomic) CGPoint endPoint;
@end

// One text mark (model only; the on-screen editable view is RSMarkupTextAnnotationView).
@interface RSMarkupTextAnnotation : NSObject
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic) CGFloat fontSize;
@property (nonatomic) CGFloat opacity;
@property (nonatomic) CGPoint center;
@property (nonatomic) BOOL showBorder;
@property (nonatomic) BOOL showBackground;
@property (nonatomic) BOOL showShadow;
@end
