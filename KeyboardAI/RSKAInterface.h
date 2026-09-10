#import <UIKit/UIKit.h>
#ifdef __cplusplus
extern "C" {
#endif
void RSKASelectionFeedback(void);
BOOL RSKABeginAnswer(NSString *name, dispatch_block_t closed);
void RSKAUpdateAnswer(NSString *text, BOOL finished, NSString *error);
void RSKAOpenTokens(NSString *text);

void RSKAClosePanel(void);
BOOL RSKAIsPanelVisible(void);
#ifdef __cplusplus
}
#endif
