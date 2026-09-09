#import "RSImageEditor.h"
@implementation RSImageEditor
- (instancetype)initWithImage:(UIImage *)image completion:(void (^)(UIImage *))completion {
    if ((self = [super initWithImage:image])) self.completion = completion;
    return self;
}
@end
