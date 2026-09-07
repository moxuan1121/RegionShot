#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif
NSArray<NSDictionary *> *RSOptionGroups(void);
id RSValidateOption(NSDictionary *option, id value);
id RSOption(NSString *key);
void RSSetOption(NSString *key, id value);
void RSReloadOptions(void);
#ifdef __cplusplus
}
#endif
