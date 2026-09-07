#import <Foundation/Foundation.h>

NSArray<NSDictionary *> *RSOptionGroups(void);
id RSValidateOption(NSDictionary *option, id value);
id RSOption(NSString *key);
void RSSetOption(NSString *key, id value);
void RSReloadOptions(void);
