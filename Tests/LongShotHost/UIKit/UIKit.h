#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@interface UIImage : NSObject
@property(nonatomic, readonly) CGImageRef CGImage;
@property(nonatomic, readonly) CGFloat scale;
+ (instancetype)imageWithContentsOfFile:(NSString *)path;
+ (instancetype)imageWithData:(NSData *)data scale:(CGFloat)scale;
- (instancetype)initWithCGImage:(CGImageRef)image;
@end
@interface UIScreen : NSObject
@property(class, nonatomic, readonly) UIScreen *mainScreen;
@property(nonatomic, readonly) CGFloat scale;
@end
