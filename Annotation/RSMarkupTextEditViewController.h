#import <UIKit/UIKit.h>
#import "RSMarkupModels.h"

// Modal-ish panel for entering / styling a text annotation.
// On confirm, calls `completion` with the finished RSMarkupTextAnnotation (or nil on cancel).
@interface RSMarkupTextEditViewController : UIViewController
@property (nonatomic, copy) NSString *initialText;
@property (nonatomic, strong) UIColor *initialColor;
@property (nonatomic) CGFloat initialFontSize;
@property (nonatomic) CGFloat initialOpacity;
@property (nonatomic) BOOL initialBorder;
@property (nonatomic) BOOL initialBackground;
@property (nonatomic) BOOL initialShadow;
@property (nonatomic, copy) void (^completion)(RSMarkupTextAnnotation *annotation);
@end
