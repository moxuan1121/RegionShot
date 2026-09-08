#import <UIKit/UIKit.h>
#import <Security/Security.h>

NS_ASSUME_NONNULL_BEGIN
NSString *RSAIReadKey(void);
OSStatus RSAIWriteKey(NSString *key);
NSString *RSAIPersonaPrompt(BOOL imageQuestion);

@interface RSAISettingsController : UITableViewController
- (instancetype)initWithSaved:(dispatch_block_t)saved;
@end
NS_ASSUME_NONNULL_END

NSArray<NSDictionary *> *RSAIPersonas(void);
