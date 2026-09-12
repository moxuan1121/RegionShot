#import <UIKit/UIKit.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN
NSString *RSAIReadKey(void);
OSStatus RSAIWriteKey(NSString *key);
NSString *RSAIPersonaPrompt(BOOL imageQuestion);

@interface RSAISettingsController : UITableViewController
- (instancetype)initWithSaved:(nullable dispatch_block_t)saved;
@end
NSArray<NSDictionary *> *RSAIPersonas(void);
NSArray<NSDictionary *> *RSAIQuickPhrases(void);
NS_ASSUME_NONNULL_END

@interface RSAIMenuController : UITableViewController
@end
