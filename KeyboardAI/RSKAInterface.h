#import <UIKit/UIKit.h>
void RSKASelectionFeedback(void);
BOOL RSKABeginAnswer(NSString *name, dispatch_block_t closed);
void RSKAUpdateAnswer(NSString *text, BOOL finished, NSString *error);
void RSKAOpenTokens(NSString *text);

void RSKAClosePanel(void);
