#import <UIKit/UIKit.h>

@interface RSImageEditor : UIViewController
- (instancetype)initWithImage:(UIImage *)image completion:(void (^)(UIImage *))completion;
@end
