#import <UIKit/UIKit.h>
extern UIViewController *RSInputCreateOptions(BOOL search);
#import "../AI/RSAISettingsController.h"
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "../Selection/RSMenuSettings.h"
#include <notify.h>
#import "RSBehaviorSettings.h"
@interface RSPreferences : PSListController
@end
static NSArray<UIViewController *> *RSLastSettingsStack;
static __weak UINavigationController *RSSettingsNavigation;
@implementation RSPreferences
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"基础"];
    [group setProperty:@"侧边键与音量加进入区域截图。关闭后恢复系统截图。" forKey:@"footerText"];
    [items addObject:group];
    PSSpecifier *enabled = [PSSpecifier preferenceSpecifierNamed:@"启用区域截图" target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
    [enabled setProperty:@"Enabled" forKey:@"key"]; [enabled setProperty:@YES forKey:@"default"];
    [items addObject:enabled];
    NSArray *sections = @[
        @[@"截图", @[@"触发与选区", @"openCaptureOptions"]],
        @[@"菜单", @[@"选区菜单", @"openMenu"], @[@"冻结菜单", @"openFrozenMenu"], @[@"悬浮图片菜单", @"openFloatingMenu"], @[@"菜单外观", @"openMenuAppearance"]],
        @[@"悬浮图片", @[@"显示与操作", @"openFloatOptions"]],
        @[@"截图历史", @[@"打开截图历史", @"openHistory"], @[@"记录与容量", @"openHistoryOptions"]],
        @[@"AI", @[@"AI 设置", @"openAI"]],
        @[@"输入与搜索", @[@"分词", @"openTokens"], @[@"搜索引擎", @"openSearch"]]
    ];
    for (NSArray *section in sections) {
        [items addObject:[PSSpecifier groupSpecifierWithName:section[0]]];
        for (NSUInteger i = 1; i < section.count; i++) {
            NSArray *entry = section[i];
            PSSpecifier *link = [PSSpecifier preferenceSpecifierNamed:entry[0] target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
            link.buttonAction = NSSelectorFromString(entry[1]); [items addObject:link];
        }
    }
    _specifiers = items.copy; return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"];
    [prefs synchronize];
    return [prefs objectForKey:[specifier propertyForKey:@"key"]] ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSUserDefaults *prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"];
    [prefs setObject:value forKey:[specifier propertyForKey:@"key"]]; [prefs synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.moxuan.regionshot/ReloadPrefs"), NULL, NULL, YES);
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"RegionShot";
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(rememberNavigation) name:UIApplicationWillResignActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(restoreNavigation) name:UIApplicationWillEnterForegroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(restoreNavigation) name:UIApplicationDidBecomeActiveNotification object:nil];
}
- (void)rememberNavigation {
    UINavigationController *navigation = self.navigationController;
    NSArray *stack = navigation.viewControllers;
    NSUInteger root = [stack indexOfObjectIdenticalTo:self];
    if (root == NSNotFound || root + 1 == stack.count) return;
    RSLastSettingsStack = stack.copy; RSSettingsNavigation = navigation;
}
- (void)restoreNavigation {
    if (!RSLastSettingsStack.count || !RSSettingsNavigation) return;
    UINavigationController *navigation = RSSettingsNavigation;
    NSArray *stack = RSLastSettingsStack;
    if (navigation.topViewController != stack.lastObject) [navigation setViewControllers:stack animated:NO];
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) RSLastSettingsStack = nil;
}
- (void)openPage:(UIViewController *)page {
    [self.navigationController pushViewController:page animated:YES];
}
- (void)openMenu { [self openPage:[RSMenuSettings new]]; }
- (void)openFrozenMenu { RSMenuSettings *settings = [RSMenuSettings new]; settings.frozenMenu = YES; [self openPage:settings]; }
- (void)openFloatingMenu { RSMenuSettings *settings = [RSMenuSettings new]; settings.floatingMenu = YES; [self openPage:settings]; }
- (void)openOptionsGroup:(NSInteger)index { RSBehaviorSettings *page = [RSBehaviorSettings new]; page.groupIndex = index; [self openPage:page]; }
- (void)openCaptureOptions { [self openOptionsGroup:0]; }
- (void)openMenuAppearance { [self openOptionsGroup:1]; }
- (void)openFloatOptions { [self openOptionsGroup:2]; }
- (void)openHistoryOptions { [self openOptionsGroup:3]; }
- (void)openAI { [self openPage:[RSAIMenuController new]]; }
- (void)openTokens { [self openPage:RSInputCreateOptions(NO)]; }
- (void)openSearch { [self openPage:RSInputCreateOptions(YES)]; }
- (void)openHistory { notify_post("com.moxuan.regionshot/History"); }
@end
