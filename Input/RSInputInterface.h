// Adapted from KeyboardAI-RootHide 23c761e, GPL-3.0; see THIRD_PARTY.md.
#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSArray<NSDictionary *> *RSInputActions(void);
FOUNDATION_EXPORT void RSInputRunAction(NSDictionary *action);
FOUNDATION_EXPORT void RSInputRunCopiedAction(NSDictionary *action, NSString *text, void (^search)(NSString *));

FOUNDATION_EXPORT void RSInputSelectionFeedback(void);
FOUNDATION_EXPORT void RSInputOpenCopiedText(NSString *text);
FOUNDATION_EXPORT BOOL RSInputIsPanelVisible(void);
FOUNDATION_EXPORT void RSInputFinishExternalWindowHandoff(UIWindow *closedWindow);
FOUNDATION_EXPORT void RSInputClosePanel(void);
