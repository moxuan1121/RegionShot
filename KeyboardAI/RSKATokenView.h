#import <UIKit/UIKit.h>
@interface RSKATokenView : UICollectionView
@property(copy) void (^onSelectionChanged)(void);
@property(copy) void (^onLayoutChanged)(void);
@property(copy) void (^onGutterLongPress)(void);
@property(readonly) BOOL hasSelection;
@property(readonly, copy) NSString *selectedText;
- (instancetype)initWithPieces:(NSArray<NSString *> *)pieces;
@end
