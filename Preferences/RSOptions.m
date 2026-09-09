#import "RSOptions.h"
#include <math.h>

static NSUserDefaults *RSPrefs(void) {
    static NSUserDefaults *prefs; static dispatch_once_t once;
    dispatch_once(&once, ^{ prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"]; });
    return prefs;
}
NSArray<NSDictionary *> *RSOptionGroups(void) {
    static NSArray *groups; static dispatch_once_t once;
    dispatch_once(&once, ^{ groups = @[
        @{@"title":@"触发与选区", @"items":@[
            @{@"key":@"StatusBarSwipe", @"title":@"状态栏右半侧右滑截图", @"default":@YES},
            @{@"key":@"SelectionShade", @"title":@"选区外遮罩深度", @"default":@0.38, @"min":@0.05, @"max":@0.8},
            @{@"key":@"CaptureHaptic", @"title":@"截图反馈振动", @"default":@YES} ]},
        @{@"title":@"菜单外观", @"items":@[
            @{@"key":@"MenuBlurOpacity", @"title":@"菜单不透明度", @"default":@0.88, @"min":@0.15, @"max":@1.0} ]},
        @{@"title":@"悬浮图片", @"items":@[
            @{@"key":@"FloatShadow", @"title":@"显示阴影", @"default":@YES},
            @{@"key":@"FloatDoubleClose", @"title":@"双击关闭当前悬浮图片", @"default":@YES},
            @{@"key":@"FloatOpacity", @"title":@"悬浮图片不透明度", @"default":@1.0, @"min":@0.25, @"max":@1.0},
            @{@"key":@"FloatWidth", @"title":@"初始宽度上限（pt）", @"default":@260, @"min":@80, @"max":@380} ]},
        @{@"title":@"截图历史", @"footer":@"保存 RegionShot 新生成的截图（悬浮图片、复制、保存和图片问答）。关闭后停止新增；已存记录仍可查看或清空。达到上限时自动清理旧图，修改限额在下次写入时执行。", @"items":@[
            @{@"key":@"HistoryEnabled", @"title":@"记录截图历史", @"default":@YES},
            @{@"key":@"HistoryCount", @"title":@"保留数量上限", @"default":@80, @"min":@5, @"max":@200},
            @{@"key":@"HistoryMB", @"title":@"容量上限（MB）", @"default":@64, @"min":@16, @"max":@128} ]},
        @{@"title":@"AI 对话", @"footer":@"服务地址、模型和密钥在“服务配置”中设置。发送的图片和文字会提交到该服务。", @"items":@[
            @{@"key":@"AIChatMaxHeight", @"title":@"对话窗口高度上限（%）", @"default":@75, @"min":@30, @"max":@95},
            @{@"key":@"AIFastResponse", @"title":@"快速响应（通义兼容模型）", @"default":@YES},
            @{@"key":@"AIStream", @"title":@"流式输出", @"default":@YES},
            @{@"key":@"AIAutoImage", @"title":@"打开图片后自动发送", @"default":@NO},
            @{@"key":@"AIAutoText", @"title":@"识别文字后自动发送", @"default":@NO},
            @{@"key":@"AIPersona", @"title":@"默认系统提示词", @"default":@"", @"limit":@8000},
            @{@"key":@"AIImagePrompt", @"title":@"默认图片提问", @"default":@"请提取并解释图片中的内容。", @"limit":@4000},
            @{@"key":@"AITheme", @"title":@"主题（0 系统／1 浅色／2 深色）", @"default":@0, @"min":@0, @"max":@2},
            @{@"key":@"AIBallSize", @"title":@"悬浮球大小（pt）", @"default":@44, @"min":@44, @"max":@80},
            @{@"key":@"AIBallOpacity", @"title":@"悬浮球不透明度", @"default":@1.0, @"min":@0.25, @"max":@1.0} ]}
    ]; });
    return groups;
}
id RSValidateOption(NSDictionary *option, id value) {
    id fallback = option[@"default"];
    if ([fallback isKindOfClass:NSString.class])
        return [value isKindOfClass:NSString.class] && [value length] <= [option[@"limit"] unsignedIntegerValue] ? value : fallback;
    if (![value isKindOfClass:NSNumber.class] || !isfinite([value doubleValue])) return fallback;
    if (!option[@"min"]) return @([value boolValue]);
    return @(MIN(MAX([value doubleValue], [option[@"min"] doubleValue]), [option[@"max"] doubleValue]));
}
static NSDictionary *RSOptionDefinitions(void) {
    static NSDictionary *definitions; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableDictionary *items = [NSMutableDictionary dictionary];
        for (NSDictionary *group in RSOptionGroups()) for (NSDictionary *option in group[@"items"])
            items[option[@"key"]] = option;
        definitions = items.copy;
    });
    return definitions;
}
id RSOption(NSString *key) {
    NSDictionary *option = RSOptionDefinitions()[key];
    return option ? RSValidateOption(option, [RSPrefs() objectForKey:key]) : nil;
}
void RSSetOption(NSString *key, id value) {
    NSDictionary *option = RSOptionDefinitions()[key];
    if (!option) return;
    [RSPrefs() setObject:RSValidateOption(option, value) forKey:key];
    [RSPrefs() synchronize];
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.moxuan.regionshot/ReloadPrefs"), NULL, NULL, YES);
}
void RSReloadOptions(void) { [RSPrefs() synchronize]; }
