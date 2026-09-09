#import <UIKit/UIKit.h>
#import "RSMarkupModels.h"

// The transparent drawing layer that sits on top of the screenshot image.
// All graphic marks (arrows/boxes/circles/scribble/mosaic/magnifier) are drawn
// here in -drawRect:. Text marks are hosted as subviews (see the VC).
@interface RSMarkupAnnotationCanvas : UIView

@property (nonatomic, strong) UIImage *sourceImage;      // underlying screenshot
@property (nonatomic) CGRect imageDisplayRect;           // where the image is shown
@property (nonatomic) RSMarkupDrawMode drawMode;
@property (nonatomic, strong) UIColor *strokeColor;
@property (nonatomic) CGFloat lineWidth;
@property (nonatomic, strong) NSMutableArray<RSMarkupAnnotationItem *> *items;

- (void)resizeDrawingToSize:(CGSize)size;
- (void)undo;                    // remove last mark
- (void)clearAll;                // remove everything
- (UIImage *)renderedImage;      // composite source + marks -> new UIImage

// 1.6 新增：聚光灯式高亮（圆角选区 + 周边压暗）
- (void)drawHighlightMaskInContext:(CGContextRef)ctx;              // 全屏压暗 + 挖空所有高亮区
- (void)drawHighlightMaskWithItem:(RSMarkupAnnotationItem *)item inContext:(CGContextRef)ctx; // 单区版
- (void)drawHighlightBorderItem:(RSMarkupAnnotationItem *)item inContext:(CGContextRef)ctx;   // 高亮区圆角描边
@end
