// Adapted from KeyboardAI-RootHide 23c761e, GPL-3.0; see THIRD_PARTY.md.
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSDictionary *RSInputConfig(void);
FOUNDATION_EXPORT NSString *RSInputReadKey(void);
FOUNDATION_EXPORT BOOL RSInputSaveConfig(NSDictionary *config, NSString *key);
FOUNDATION_EXPORT BOOL RSInputClearConfig(void);
FOUNDATION_EXPORT BOOL RSInputSaveOptions(NSString *field, id value);
