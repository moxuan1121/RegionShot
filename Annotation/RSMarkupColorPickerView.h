#import <UIKit/UIKit.h>

// Bottom panel: a row of colour swatches + a line-width slider.
// Communicates back through blocks (like the original's colorSelected / widthChanged).
@interface RSMarkupColorPickerView : UIView
@property (nonatomic, copy) void (^colorSelected)(UIColor *color);
@property (nonatomic, copy) void (^widthChanged)(CGFloat width);
@property (nonatomic) CGFloat currentWidth;
- (instancetype)initWithFrame:(CGRect)frame;
@end
