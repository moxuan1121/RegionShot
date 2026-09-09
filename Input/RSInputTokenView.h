// Adapted from KeyboardAI-RootHide 23c761e, GPL-3.0; see THIRD_PARTY.md.
#import <UIKit/UIKit.h>
@interface RSInputTokenView : UICollectionView
@property(copy) void (^onSelectionChanged)(void);
@property(copy) void (^onLayoutChanged)(void);
@property(copy) void (^onGutterLongPress)(void);
@property(readonly) BOOL hasSelection;
@property(readonly, copy) NSString *selectedText;
- (instancetype)initWithPieces:(NSArray<NSString *> *)pieces;
@end
