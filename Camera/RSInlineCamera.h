#import <UIKit/UIKit.h>
@interface RSInlineCamera : UIImagePickerController
@property(nonatomic, copy) void (^completion)(UIImage *image);
- (void)stop;
@end
