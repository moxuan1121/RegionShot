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
        @{@"title":@"截图与保存", @"items":@[
            @{@"key":@"DoubleTapSelection", @"title":@"双击选区生成浮图", @"default":@NO},
            @{@"key":@"CaptureHaptic", @"title":@"截图完成震动", @"default":@NO},
            @{@"key":@"CopyOnSave", @"title":@"保存时同时复制", @"default":@NO},
            @{@"key":@"CopyOnly", @"title":@"保存时仅复制到剪贴板", @"default":@NO},
            @{@"key":@"SelectionShade", @"title":@"选区外遮罩浓度", @"default":@0.38, @"min":@0.05, @"max":@0.8} ]},
        @{@"title":@"悬浮图片", @"items":@[
            @{@"key":@"FloatShadow", @"title":@"显示阴影", @"default":@YES},
            @{@"key":@"FloatSnap", @"title":@"拖动后左右吸边", @"default":@YES},
            @{@"key":@"FloatDoubleClose", @"title":@"双击关闭当前浮图", @"default":@YES},
            @{@"key":@"FloatOpacity", @"title":@"浮图不透明度", @"default":@1.0, @"min":@0.25, @"max":@1.0},
            @{@"key":@"FloatWidth", @"title":@"初始最大宽度（点）", @"default":@260, @"min":@80, @"max":@380} ]},
        @{@"title":@"本地文字识别", @"footer":@"语言填逗号分隔的代码，例如 zh-Hans,zh-Hant,en-US。不支持的语言会自动过滤。识别结果可编辑、分词、复制、分享及提交 AI。", @"items":@[
            @{@"key":@"OCRFast", @"title":@"快速识别（关闭为准确模式）", @"default":@NO},
            @{@"key":@"OCRCorrection", @"title":@"语言纠错", @"default":@YES},
            @{@"key":@"OCRLanguages", @"title":@"识别语言", @"default":@"zh-Hans,zh-Hant,en-US", @"limit":@256},
            @{@"key":@"OCRJoinLines", @"title":@"合并识别结果换行", @"default":@NO} ]},
        @{@"title":@"长截图采样", @"footer":@"采样需要手动滚动页面并保留重叠部分。上限用于控制 SpringBoard 内存，达到后可完成保存。", @"items":@[
            @{@"key":@"LongInterval", @"title":@"采样间隔（秒）", @"default":@0.8, @"min":@0.3, @"max":@3.0},
            @{@"key":@"LongMaxMP", @"title":@"合成像素上限（百万）", @"default":@24, @"min":@4, @"max":@24},
            @{@"key":@"LongMaxSlices", @"title":@"最多采集段数", @"default":@100, @"min":@5, @"max":@100} ]},
        @{@"title":@"AI 对话", @"footer":@"服务地址、模型和密钥在 AI 服务配置窗口设置。翻译使用你配置的 AI 服务；识别文字会发送到该服务。", @"items":@[
            @{@"key":@"AIStream", @"title":@"流式输出", @"default":@YES},
            @{@"key":@"AIAutoImage", @"title":@"图片问答直接发送", @"default":@NO},
            @{@"key":@"AIAutoText", @"title":@"文字问答直接发送", @"default":@NO},
            @{@"key":@"AIPersona", @"title":@"AI 人设 / 系统提示词", @"default":@"", @"limit":@8000},
            @{@"key":@"AIImagePrompt", @"title":@"图片默认提问", @"default":@"请提取并解释图片中的内容。", @"limit":@4000},
            @{@"key":@"TranslateTarget", @"title":@"翻译目标语言", @"default":@"简体中文", @"limit":@100},
            @{@"key":@"AITheme", @"title":@"对话主题（0 系统 / 1 浅色 / 2 深色）", @"default":@0, @"min":@0, @"max":@2},
            @{@"key":@"AIBallSize", @"title":@"AI 悬浮球大小（点）", @"default":@44, @"min":@44, @"max":@80},
            @{@"key":@"AIBallOpacity", @"title":@"AI 悬浮球不透明度", @"default":@1.0, @"min":@0.25, @"max":@1.0} ]}
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
id RSOption(NSString *key) {
    for (NSDictionary *group in RSOptionGroups()) for (NSDictionary *option in group[@"items"])
        if ([option[@"key"] isEqual:key]) return RSValidateOption(option, [RSPrefs() objectForKey:key]);
    return nil;
}
void RSSetOption(NSString *key, id value) {
    for (NSDictionary *group in RSOptionGroups()) for (NSDictionary *option in group[@"items"])
        if ([option[@"key"] isEqual:key]) {
            [RSPrefs() setObject:RSValidateOption(option, value) forKey:key]; [RSPrefs() synchronize];
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFSTR("com.moxuan.regionshot/ReloadPrefs"), NULL, NULL, YES);
            return;
        }
}
void RSReloadOptions(void) { [RSPrefs() synchronize]; }
