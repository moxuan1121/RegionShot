#import <UIKit/UIKit.h>

// Full-screen editor hosted in its own UIWindow. Shows the screenshot, a
// transparent drawing canvas on top, a bottom toolbar of modes, and the
// collapsible colour/width picker. Handles undo/clear/save/copy/share/about.
@interface RSMarkupAnnotationViewController : UIViewController
- (instancetype)initWithImage:(UIImage *)image;
@property (nonatomic, copy) void (^completion)(UIImage *);
- (void)closeAnimated;   // dismiss + tear down window
@end
