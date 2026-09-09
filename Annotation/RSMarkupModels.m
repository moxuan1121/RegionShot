#import "RSMarkupModels.h"

@implementation RSMarkupAnnotationItem
- (instancetype)init {
    if ((self = [super init])) {
        _pathPoints = [NSMutableArray array];
        _color = [UIColor systemRedColor];
        _lineWidth = 5.0;
        _magnifyScale = 2.0;
    }
    return self;
}
@end

@implementation RSMarkupTextAnnotation
- (instancetype)init {
    if ((self = [super init])) {
        _text = @"";
        _textColor = [UIColor whiteColor];
        _fontSize = 16.0;
        _opacity = 1.0;
        _showBackground = YES;
    }
    return self;
}
@end
