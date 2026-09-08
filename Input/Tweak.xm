#import "RSInputClipboard.h"
#import "RSInputInterface.h"
#import <objc/runtime.h>
@interface UIInputSwitcherItem : NSObject
- (instancetype)initWithIdentifier:(NSString *)identifier;
@property(copy, nonatomic) NSString *localizedTitle;
@property(strong, nonatomic) UIFont *titleFont;
@property(readonly, nonatomic) BOOL isSegmentedItem;
@property(strong, nonatomic) NSArray *segmentImages;
@end

@interface UIInputSwitcher : NSObject
+ (instancetype)activeInstance;
- (void)hideSwitcher;
@end

@interface UIInputSwitcherView : UIView
- (void)_reloadInputSwitcherItems;
- (BOOL)shouldSelectItemAtIndex:(NSUInteger)index;
- (void)didSelectItemAtIndex:(NSUInteger)index;
- (void)willFadeForSelectionAtIndex:(NSUInteger)index;
- (BOOL)shouldShowSelectionExtraViewForIndexPath:(NSIndexPath *)path;
- (void)customizeCell:(UITableViewCell *)cell forItemAtIndex:(NSUInteger)index;
- (UIFont *)fontForItemAtIndex:(NSUInteger)index;
- (BOOL)_isHandBiasSwitchVisible;
- (void)hide;
@end

static char RSInputActionKey, RSInputCellKey, RSInputSelectionKey;
static NSArray *RSInputItems(id view) {
    @try {
        id value = [view valueForKey:@"m_inputSwitcherItems"];
        return [value isKindOfClass:NSArray.class] ? [value copy] : nil;
    } @catch (__unused NSException *exception) { return nil; }
}

static NSDictionary *RSInputActionAt(id view, NSUInteger index) {
    NSArray *items = RSInputItems(view);
    return index < items.count ? objc_getAssociatedObject(items[index], &RSInputActionKey) : nil;
}

%group RSInputSwitcher
%hook UIInputSwitcherView
- (BOOL)_isHandBiasSwitchVisible {
    return NO;
}
- (void)_reloadInputSwitcherItems {
    %orig;
    @try {
        // Leave the dictation language picker alone.
        if ([[self valueForKey:@"m_isForDictation"] boolValue]) return;
        NSArray *existing = RSInputItems(self);
        if (!existing) return;
        NSMutableArray *items = [NSMutableArray array];
        for (UIInputSwitcherItem *item in existing) {
            BOOL handBias = [item respondsToSelector:@selector(isSegmentedItem)] && item.isSegmentedItem &&
                [item respondsToSelector:@selector(segmentImages)] && item.segmentImages.count == 3;
            if (!handBias && !objc_getAssociatedObject(item, &RSInputActionKey)) [items addObject:item];
        }
        UIFont *nativeFont = existing.count ? [self fontForItemAtIndex:0] : nil;
        NSMutableArray *actions = [RSInputActions() mutableCopy];
        for (NSDictionary *action in actions) {
            NSString *identifier = [@"com.moxuan1121.keyboardai." stringByAppendingString:NSUUID.UUID.UUIDString];
            UIInputSwitcherItem *item = [[%c(UIInputSwitcherItem) alloc] initWithIdentifier:identifier];
            if (!item) return; // Commit all rows together only after construction succeeds.
            item.localizedTitle = action[@"title"];
            item.titleFont = nativeFont ?: [UIFont systemFontOfSize:20];
            objc_setAssociatedObject(item, &RSInputActionKey, action, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [items addObject:item];
        }
        [self setValue:[items copy] forKey:@"m_inputSwitcherItems"];
    } @catch (__unused NSException *exception) {
        NSLog(@"[KeyboardAI] Switcher layout unavailable; keeping original menu.");
    }
}
- (BOOL)shouldSelectItemAtIndex:(NSUInteger)index {
    NSDictionary *action = RSInputActionAt(self, index);
    if (action) return YES;
    return %orig;
}
- (void)customizeCell:(UITableViewCell *)cell forItemAtIndex:(NSUInteger)index {
    if (objc_getAssociatedObject(cell, &RSInputCellKey)) {
        cell.configurationUpdateHandler = nil;
        cell.contentConfiguration = nil;
        cell.accessibilityLabel = nil;
        cell.accessibilityTraits = UIAccessibilityTraitNone;
        objc_setAssociatedObject(cell, &RSInputCellKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    %orig;
    NSDictionary *action = RSInputActionAt(self, index);
    if (!action) return;
    UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
    content.text = action[@"title"];
    NSArray *items = RSInputItems(self);
    content.textProperties.font = index < items.count ? [(UIInputSwitcherItem *)items[index] titleFont] : [UIFont systemFontOfSize:20];
    content.textProperties.color = UIColor.labelColor;
    content.textProperties.alignment = UIListContentTextAlignmentCenter;
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(6, 12, 6, 12);
    __block BOOL wasPressed = cell.isHighlighted || cell.isSelected;
    cell.configurationUpdateHandler = ^(UITableViewCell *updatedCell, UICellConfigurationState *state) {
        BOOL pressed = state.isHighlighted || state.isSelected;
        UIListContentConfiguration *updated = [content copy];
        updated.textProperties.color = pressed ? UIColor.whiteColor : UIColor.labelColor;
        updatedCell.contentConfiguration = updated;
        if (pressed && !wasPressed) RSInputSelectionFeedback();
        wasPressed = pressed;
    };
    content.textProperties.color = wasPressed ? UIColor.whiteColor : UIColor.labelColor;
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessibilityLabel = action[@"title"];
    cell.accessibilityTraits = UIAccessibilityTraitButton;
    objc_setAssociatedObject(cell, &RSInputCellKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (BOOL)shouldShowSelectionExtraViewForIndexPath:(NSIndexPath *)path {
    if (path.section == 0 && RSInputActionAt(self, path.row)) return NO;
    return %orig;
}
- (void)willFadeForSelectionAtIndex:(NSUInteger)index {
    if (RSInputActionAt(self, index)) return;
    %orig;
}
- (void)didSelectItemAtIndex:(NSUInteger)index {
    NSDictionary *action = RSInputActionAt(self, index);
    if (!action) {
        %orig;
        return;
    }
    if (objc_getAssociatedObject(self, &RSInputSelectionKey)) return;
    objc_setAssociatedObject(self, &RSInputSelectionKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Finish the menu selection callback before changing its view hierarchy.
    dispatch_async(dispatch_get_main_queue(), ^{
        Class switcherClass = %c(UIInputSwitcher);
        UIInputSwitcher *switcher = [switcherClass respondsToSelector:@selector(activeInstance)] ? [switcherClass activeInstance] : nil;
        if ([switcher respondsToSelector:@selector(hideSwitcher)]) [switcher hideSwitcher];
        if ([self respondsToSelector:@selector(hide)]) [self hide];
        RSInputRunAction(action);
        objc_setAssociatedObject(self, &RSInputSelectionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    });
}
%end
%end

%ctor {
    @autoreleasepool {
        NSString *bundle = NSBundle.mainBundle.bundleIdentifier;
        if ([bundle isEqual:@"com.apple.springboard"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                RSInputStartClipboardPrompt();
                [NSNotificationCenter.defaultCenter addObserverForName:@"com.moxuan.regionshot.input.close" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { RSInputClosePanel(); }];
                [NSNotificationCenter.defaultCenter addObserverForName:@"com.moxuan.regionshot.input.tokens" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                    NSMutableDictionary *request = note.object;
                    if (![request isKindOfClass:NSMutableDictionary.class] || ![request[@"text"] isKindOfClass:NSString.class] || [request[@"text"] length] > 24000) return;
                    request[@"handled"] = @YES; RSInputOpenCopiedText(request[@"text"]);
                }];
            }); return;
        }
        if (![@[@"com.tencent.xin", @"jp.naver.line"] containsObject:bundle]) return;
        Class view = NSClassFromString(@"UIInputSwitcherView");
        Class item = NSClassFromString(@"UIInputSwitcherItem");
        if (!view || !item || !class_getInstanceVariable(view, "m_inputSwitcherItems") ||
            !class_getInstanceVariable(view, "m_isForDictation")) return;
        NSArray *methods = @[@"_reloadInputSwitcherItems", @"shouldSelectItemAtIndex:",
            @"didSelectItemAtIndex:", @"willFadeForSelectionAtIndex:",
            @"shouldShowSelectionExtraViewForIndexPath:", @"customizeCell:forItemAtIndex:",
            @"fontForItemAtIndex:", @"_isHandBiasSwitchVisible", @"hide"];
        for (NSString *name in methods)
            if (![view instancesRespondToSelector:NSSelectorFromString(name)]) return;
        for (NSString *name in @[@"initWithIdentifier:", @"setLocalizedTitle:", @"setTitleFont:"])
            if (![item instancesRespondToSelector:NSSelectorFromString(name)]) return;
        %init(RSInputSwitcher);
    }
}
