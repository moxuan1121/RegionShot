#import "../Annotation/RSMarkupAnnotationViewController.h"
@interface RSImageEditor : RSMarkupAnnotationViewController
- (instancetype)initWithImage:(UIImage *)image completion:(void (^)(UIImage *))completion;
@end
