#import "RSMenuSettings.h"
#import "RSMenuConfiguration.h"
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>

static NSUserDefaults *RSMenuPrefs(void) {
    static NSUserDefaults *prefs;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ prefs = [[NSUserDefaults alloc] initWithSuiteName:@"com.moxuan.regionshot"]; });
    return prefs;
}
static NSArray *RSMenuDefaults(BOOL floating) {
    if (floating) return @[
        @{@"id":@0, @"title":@"复制", @"symbol":@"doc.on.doc", @"enabled":@YES},
        @{@"id":@1, @"title":@"保存", @"symbol":@"square.and.arrow.down", @"enabled":@YES},
        @{@"id":@2, @"title":@"分享", @"symbol":@"square.and.arrow.up", @"enabled":@YES},
        @{@"id":@4, @"title":@"关闭全部", @"symbol":@"trash", @"enabled":@YES},
        @{@"id":@5, @"title":@"图片问答", @"symbol":@"text.bubble", @"enabled":@YES},
        @{@"id":@6, @"title":@"关闭当前", @"symbol":@"xmark", @"enabled":@YES},
        @{@"id":@7, @"title":@"截图历史", @"symbol":@"clock.arrow.circlepath", @"enabled":@YES}];
    return @[@{@"id":@0, @"title":@"截图", @"symbol":@"camera", @"enabled":@YES},
             @{@"id":@1, @"title":@"标记", @"symbol":@"pencil.tip", @"enabled":@YES},
             @{@"id":@2, @"title":@"长截图", @"symbol":@"doc.on.doc", @"enabled":@YES},
             @{@"id":@3, @"title":@"扫码", @"symbol":@"qrcode.viewfinder", @"enabled":@YES},
             @{@"id":@4, @"title":@"取消", @"symbol":@"xmark", @"enabled":@YES},
             @{@"id":@5, @"title":@"图片问答", @"symbol":@"text.bubble", @"enabled":@YES},
             @{@"id":@7, @"title":@"全屏", @"symbol":@"arrow.up.left.and.arrow.down.right", @"enabled":@YES},
             @{@"id":@8, @"title":@"历史", @"symbol":@"clock.arrow.circlepath", @"enabled":@YES},
             @{@"id":@9, @"title":@"复制", @"symbol":@"doc.on.clipboard", @"enabled":@YES},
             @{@"id":@10, @"title":@"保存", @"symbol":@"square.and.arrow.down", @"enabled":@YES}];
}
static NSArray *RSMenuItems(BOOL floating) {
    [RSMenuPrefs() synchronize];
    return RSNormalizeMenu([RSMenuPrefs() objectForKey:floating ? @"FloatingMenu" : @"SelectionMenu"], RSMenuDefaults(floating), floating ? @6 : nil);
}
NSArray<NSDictionary *> *RSSelectionMenuItems(void) { return RSMenuItems(NO); }
NSArray<NSDictionary *> *RSFloatingMenuItems(void) { return RSMenuItems(YES); }
NSArray<NSDictionary *> *RSFrozenMenuItems(void) {
    [RSMenuPrefs() synchronize];
    NSMutableArray *defaults = [NSMutableArray array];
    for (NSDictionary *item in RSMenuDefaults(NO)) {
        NSMutableDictionary *entry = item.mutableCopy;
        if ([entry[@"id"] integerValue] > 4 && [entry[@"id"] integerValue] != 9) entry[@"enabled"] = @NO;
        [defaults addObject:entry];
    }
    return RSNormalizeMenu([RSMenuPrefs() objectForKey:@"FrozenMenu"], defaults, nil);
}
UIImage *RSSelectionMenuIcon(NSDictionary *item) {
    NSData *data = item[@"image"];
    UIImage *image = data ? [UIImage imageWithData:data] : nil;
    return image ? [image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal] : [UIImage systemImageNamed:item[@"symbol"]];
}
CGFloat RSSelectionMenuSize(BOOL icon) {
    NSUserDefaults *prefs = RSMenuPrefs();
    NSString *key = icon ? @"SelectionIconSize" : @"SelectionTextSize";
    CGFloat value = [prefs objectForKey:key] ? [prefs doubleForKey:key] : (icon ? 32 : 12);
    return isfinite(value) ? MIN(MAX(value, icon ? 16 : 8), icon ? 80 : 16) : (icon ? 32 : 12);
}
BOOL RSSelectionMenuHideNames(void) { return [RSMenuPrefs() boolForKey:@"HideSelectionNames"]; }

@interface RSMenuSymbols : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) void (^choose)(NSString *);
@property (nonatomic, strong) NSArray<NSString *> *symbols;
@property (nonatomic, strong) UISearchController *search;
@end
@implementation RSMenuSymbols
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"选择系统图标";
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self; self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"筛选常用图标，或输入完整 SF Symbol 名称";
    self.navigationItem.searchController = self.search; self.definesPresentationContext = YES;
    [self updateSearchResultsForSearchController:self.search];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)search {
    NSString *query = [search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
    NSArray *common = @[@"camera", @"camera.fill", @"camera.viewfinder", @"photo", @"photo.fill", @"photo.on.rectangle", @"rectangle.dashed", @"crop", @"pencil", @"pencil.tip", @"pencil.tip.crop.circle", @"paintbrush", @"paintpalette", @"scribble", @"highlighter", @"lasso", @"doc.on.doc", @"doc.text", @"doc.text.viewfinder", @"text.viewfinder", @"text.bubble", @"text.bubble.fill", @"character.textbox", @"character.cursor.ibeam", @"textformat", @"brain", @"sparkles", @"globe", @"qrcode", @"qrcode.viewfinder", @"barcode.viewfinder", @"arrow.clockwise", @"arrow.down", @"arrow.up", @"arrow.left", @"arrow.right", @"arrow.up.left.and.arrow.down.right", @"arrow.down.right.and.arrow.up.left", @"square.and.arrow.down", @"square.and.arrow.up", @"square.on.square", @"clock.arrow.circlepath", @"clock", @"tray", @"folder", @"gearshape", @"slider.horizontal.3", @"eye", @"eye.slash", @"checkmark", @"checkmark.circle", @"xmark", @"xmark.circle", @"trash", @"minus", @"plus", @"heart", @"star", @"bolt", @"pin", @"hand.draw", @"magnifyingglass"];
    NSMutableArray *filtered = [NSMutableArray array];
    if (query.length <= 100 && query.length && [UIImage systemImageNamed:query]) [filtered addObject:query];
    for (NSString *name in common) if ((!query.length || [name localizedCaseInsensitiveContainsString:query]) &&
        ![filtered containsObject:name] && [UIImage systemImageNamed:name]) [filtered addObject:name];
    self.symbols = filtered; [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.symbols.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = self.symbols[path.row]; cell.imageView.image = [UIImage systemImageNamed:self.symbols[path.row]];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (self.choose) self.choose(self.symbols[path.row]);
    self.search.active = NO; [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface RSMenuSettings () <PHPickerViewControllerDelegate, UIDocumentPickerDelegate>
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *items;
@property (nonatomic, strong) NSNumber *editingIdentifier;
@end
@implementation RSMenuSettings
- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.floatingMenu ? @"浮图长按菜单" : self.frozenMenu ? @"冻结菜单（未框选）" : @"选区菜单（已框选）";
    [self reloadItems];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"手动排序" style:UIBarButtonItemStylePlain target:self action:@selector(toggleSorting)];
}
- (void)toggleSorting {
    [self setEditing:!self.editing animated:YES];
    self.navigationItem.rightBarButtonItem.title = self.editing ? @"结束排序" : @"手动排序";
}
- (void)reloadItems {
    self.items = [NSMutableArray array];
    for (NSDictionary *item in (self.frozenMenu ? RSFrozenMenuItems() : RSMenuItems(self.floatingMenu))) [self.items addObject:item.mutableCopy];
}
- (void)save { [RSMenuPrefs() setObject:self.items forKey:self.floatingMenu ? @"FloatingMenu" : self.frozenMenu ? @"FrozenMenu" : @"SelectionMenu"]; [RSMenuPrefs() synchronize]; }
- (void)close {
    [RSMenuPrefs() synchronize];
    if (self.navigationController.viewControllers.count > 1) [self.navigationController popViewControllerAnimated:YES];
    else [self dismissViewControllerAnimated:YES completion:self.onClose];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? self.items.count : section == 1 ? (self.floatingMenu ? 0 : 3) : 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 && self.floatingMenu ? nil : @[@"图标、名称与排序", @"显示大小", @"恢复"][section];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == 0 ? @"点行修改名称或图标；点手动排序后拖动右侧把手；开关增减功能。浮图的“关闭当前”保持可用，冻结和选区菜单的“取消”可以关闭。" : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (path.section == 0) {
        NSDictionary *item = self.items[path.row]; cell.textLabel.text = item[@"title"];
        cell.imageView.image = RSSelectionMenuIcon(item); cell.detailTextLabel.text = item[@"image"] ? @"自定义图片" : item[@"symbol"];
        UISwitch *toggle = [UISwitch new]; toggle.on = [item[@"enabled"] boolValue]; toggle.tag = [item[@"id"] integerValue];
        toggle.enabled = !self.floatingMenu || toggle.tag != 6; toggle.accessibilityLabel = [@"显示 " stringByAppendingString:item[@"title"]];
        [toggle addTarget:self action:@selector(toggleItem:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    } else if (path.section == 1 && path.row == 0) {
        cell.textLabel.text = @"隐藏按钮名称";
        UISwitch *toggle = [UISwitch new]; toggle.on = RSSelectionMenuHideNames();
        [toggle addTarget:self action:@selector(toggleNames:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = toggle;
    } else if (path.section == 1) {
        BOOL icon = path.row == 1;
        cell.textLabel.text = [NSString stringWithFormat:@"%@：%.0f", icon ? @"图标大小" : @"文字大小", RSSelectionMenuSize(icon)];
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 140, 44)]; slider.tag = icon;
        slider.minimumValue = icon ? 16 : 8; slider.maximumValue = icon ? 80 : 16; slider.value = RSSelectionMenuSize(icon);
        slider.accessibilityLabel = icon ? @"图标大小" : @"文字大小";
        [slider addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged]; cell.accessoryView = slider;
    } else { cell.textLabel.text = @"恢复工具条默认设置"; cell.textLabel.textColor = UIColor.systemRedColor; }
    return cell;
}
- (NSMutableDictionary *)itemForID:(NSNumber *)identifier {
    for (NSMutableDictionary *item in self.items) if ([item[@"id"] isEqual:identifier]) return item;
    return nil;
}
- (void)toggleItem:(UISwitch *)toggle { [self itemForID:@(toggle.tag)][@"enabled"] = @(toggle.on); [self save]; }
- (void)toggleNames:(UISwitch *)toggle { [RSMenuPrefs() setBool:toggle.on forKey:@"HideSelectionNames"]; }
- (void)sizeChanged:(UISlider *)slider {
    [RSMenuPrefs() setDouble:round(slider.value) forKey:slider.tag ? @"SelectionIconSize" : @"SelectionTextSize"];
    UIView *view = slider;
    while (view && ![view isKindOfClass:UITableViewCell.class]) view = view.superview;
    ((UITableViewCell *)view).textLabel.text = [NSString stringWithFormat:@"%@：%.0f", slider.tag ? @"图标大小" : @"文字大小", round(slider.value)];
}
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)path { return path.section == 0; }
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)path { return path.section == 0; }
- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)path { return UITableViewCellEditingStyleNone; }
- (BOOL)tableView:(UITableView *)tableView shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)path { return NO; }
- (NSIndexPath *)tableView:(UITableView *)tableView targetIndexPathForMoveFromRowAtIndexPath:(NSIndexPath *)source toProposedIndexPath:(NSIndexPath *)target {
    return target.section == 0 ? target : [NSIndexPath indexPathForRow:self.items.count - 1 inSection:0];
}
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)source toIndexPath:(NSIndexPath *)target {
    NSMutableDictionary *item = self.items[source.row]; [self.items removeObjectAtIndex:source.row];
    [self.items insertObject:item atIndex:target.row]; [self save];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    if (path.section == 1) return;
    if (path.section == 2) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"恢复默认" message:@"清除工具条排序、名称、图标和大小设置？" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"恢复" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            for (NSString *key in (self.floatingMenu ? @[@"FloatingMenu"] : self.frozenMenu ? @[@"FrozenMenu"] : @[@"SelectionMenu", @"SelectionIconSize", @"SelectionTextSize", @"HideSelectionNames"])) [RSMenuPrefs() removeObjectForKey:key];
            [self reloadItems]; [self.tableView reloadData];
        }]];
        [self presentViewController:alert animated:YES completion:nil]; return;
    }
    self.editingIdentifier = self.items[path.row][@"id"];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:self.items[path.row][@"title"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"浏览系统图标" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        RSMenuSymbols *symbols = [[RSMenuSymbols alloc] initWithStyle:UITableViewStyleInsetGrouped];
        NSNumber *identifier = self.editingIdentifier;
        __weak typeof(self) weakSelf = self;
        symbols.choose = ^(NSString *symbol) {
            NSMutableDictionary *item = [weakSelf itemForID:identifier]; item[@"symbol"] = symbol; [item removeObjectForKey:@"image"];
            [weakSelf save]; [weakSelf.tableView reloadData];
        };
        [self.navigationController pushViewController:symbols animated:YES];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"修改名称 / SF Symbol" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { [self editText]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"相册图片图标" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        PHPickerConfiguration *config = [PHPickerConfiguration new]; config.selectionLimit = 1; config.filter = PHPickerFilter.imagesFilter;
        PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:config]; picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"文件图片图标" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeImage] asCopy:YES]; picker.delegate = self;
        [self presentViewController:picker animated:YES completion:nil];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"恢复原图标" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSMutableDictionary *item = [self itemForID:self.editingIdentifier]; [item removeObjectForKey:@"image"];
        for (NSDictionary *entry in RSMenuDefaults(self.floatingMenu)) if ([entry[@"id"] isEqual:self.editingIdentifier]) item[@"symbol"] = entry[@"symbol"];
        [self save]; [self.tableView reloadData];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = [tableView cellForRowAtIndexPath:path];
    sheet.popoverPresentationController.sourceRect = sheet.popoverPresentationController.sourceView.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)editText {
    NSMutableDictionary *item = [self itemForID:self.editingIdentifier];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"名称与系统图标" message:@"例如 camera、character.textbox。填写有效的 SF Symbol 名称会替换图片图标。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = item[@"title"]; field.placeholder = @"按钮名称"; }];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = item[@"symbol"]; field.placeholder = @"SF Symbol 名称";
        field.autocapitalizationType = UITextAutocapitalizationTypeNone; field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSString *title = alert.textFields[0].text;
        NSString *symbol = [alert.textFields[1].text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!title.length || title.length > 100 || !symbol.length || symbol.length > 100 || ![UIImage systemImageNamed:symbol]) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self showError:@"名称不能为空或超过 100 字符，图标必须是当前 iOS 支持的 SF Symbol。"]; }); return;
        }
        item[@"title"] = title; item[@"symbol"] = symbol; [item removeObjectForKey:@"image"];
        [self save]; [self.tableView reloadData];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"未能保存" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)importImage:(UIImage *)image identifier:(NSNumber *)identifier {
    if (!image.CGImage || image.size.width <= 0 || image.size.height <= 0) { [self showError:@"无法读取图片。"]; return; }
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat]; format.scale = 1;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(160, 160) format:format];
    CGFloat scale = MIN(160 / image.size.width, 160 / image.size.height);
    CGSize size = CGSizeMake(image.size.width * scale, image.size.height * scale);
    UIImage *icon = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [image drawInRect:CGRectMake((160 - size.width) / 2, (160 - size.height) / 2, size.width, size.height)];
    }];
    NSData *png = UIImagePNGRepresentation(icon);
    if (!png || png.length > 256 * 1024) { [self showError:@"图标编码失败或过大。"]; return; }
    [self itemForID:identifier][@"image"] = png; [self save]; [self.tableView reloadData];
}
- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSNumber *identifier = self.editingIdentifier;
    [picker dismissViewControllerAnimated:YES completion:nil];
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (!provider) return;
    if (![provider canLoadObjectOfClass:UIImage.class]) { [self showError:@"请选择图片。"]; return; }
    [provider loadObjectOfClass:UIImage.class completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self importImage:[object isKindOfClass:UIImage.class] ? (UIImage *)object : nil identifier:identifier]; });
    }];
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject; if (!url) return;
    BOOL scoped = [url startAccessingSecurityScopedResource];
    NSNumber *size = nil; [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
    UIImage *image = size && size.unsignedLongLongValue <= 12 * 1024 * 1024 ? [UIImage imageWithContentsOfFile:url.path] : nil;
    if (scoped) [url stopAccessingSecurityScopedResource];
    [self importImage:image identifier:self.editingIdentifier];
}
@end
