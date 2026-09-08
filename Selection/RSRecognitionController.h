#import <UIKit/UIKit.h>

@interface RSRecognitionController : UIViewController
@property (nonatomic, copy) dispatch_block_t onForward;
- (instancetype)initWithImage:(UIImage *)image;
@end
