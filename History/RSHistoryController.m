#import "RSHistoryController.h"
#import "RSHistoryStore.h"
#import <objc/message.h>
#import "../Geometry/RSOrientation.h"
#import "../Preferences/RSOptions.h"
#import "../AI/RSChatController.h"

static dispatch_queue_t RSHistoryQueue(void) {
    static dispatch_queue_t queue; static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("com.moxuan.regionshot.history", DISPATCH_QUEUE_SERIAL); });
    return queue;
}
static RSHistoryStore *RSStore(void) {
    static RSHistoryStore *store; static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *directory = [[NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES] URLByAppendingPathComponent:@"Library/Application Support/RegionShot/History" isDirectory:YES];
        store = [[RSHistoryStore alloc] initWithDirectory:directory];
    });
    return store;
}
@interface RSHistoryPreview : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) UIImageView *picture;
@property (nonatomic, copy) dispatch_block_t restore;
@property (nonatomic, copy) dispatch_block_t ask;
@end
@implementation RSHistoryPreview
- (void)viewDidLoad {
    [super viewDidLoad];
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scroll.backgroundColor = UIColor.systemBackgroundColor; scroll.delegate = self;
    scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 6; self.view = scroll;
    self.picture = [[UIImageView alloc] initWithImage:self.image]; self.picture.contentMode = UIViewContentModeScaleAspectFit;
    self.picture.frame = scroll.bounds; self.picture.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [scroll addSubview:self.picture];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"浮图" style:UIBarButtonItemStylePlain target:self action:@selector(restoreImage)],
        [[UIBarButtonItem alloc] initWithTitle:@"问答" style:UIBarButtonItemStylePlain target:self action:@selector(askAI)],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)]];
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scroll { return self.picture; }
- (void)restoreImage { if (self.restore) self.restore(); }
- (void)askAI { if (self.ask) self.ask(); }
- (void)share {
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[self.image] applicationActivities:nil];
    activity.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:activity animated:YES completion:nil];
}
@end

@interface RSHistoryPanel : UIViewController <UIGestureRecognizerDelegate>
@property (nonatomic, strong) UINavigationController *navigation;
@property (nonatomic, copy) dispatch_block_t dismissPanel;
@end
@implementation RSHistoryPanel
- (BOOL)shouldAutorotate { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation { return RSActiveOrientation(self.view.window.windowScene); }
- (void)screenRotated:(NSNotification *)note {
    RSApplyWindowOrientation(self.view.window, [note.userInfo[@"orientation"] integerValue]);
    [self.view setNeedsLayout]; [self.view layoutIfNeeded];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenRotated:) name:@"com.moxuan.regionshot.orientation.target" object:nil];
    [self addChildViewController:self.navigation];
    UIView *panel = self.navigation.view; panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.layer.cornerRadius = 20; panel.clipsToBounds = YES;
    [self.view addSubview:panel]; [self.navigation didMoveToParentViewController:self];
    UITapGestureRecognizer *outside = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tappedOutside:)];
    outside.delegate = self; [self.view addGestureRecognizer:outside];
    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [panel.centerXAnchor constraintEqualToAnchor:safe.centerXAnchor], [panel.centerYAnchor constraintEqualToAnchor:safe.centerYAnchor],
        [panel.widthAnchor constraintEqualToAnchor:safe.widthAnchor multiplier:0.82],
        [panel.heightAnchor constraintEqualToAnchor:safe.heightAnchor multiplier:0.576]]];
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    return touch.view == self.view && !self.navigation.presentedViewController;
}
- (void)tappedOutside:(UITapGestureRecognizer *)gesture { if (self.dismissPanel) self.dismissPanel(); }
@end

@interface RSHistoryController () <UISearchResultsUpdating>
@property (nonatomic, strong) UIWindow *host;
@property (nonatomic, weak) UIWindow *previous;
@property (nonatomic, strong) NSArray<NSDictionary *> *entries;
@property (nonatomic, strong) NSArray<NSDictionary *> *filtered;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) NSCache *thumbnails;
@property (nonatomic, copy) void (^restore)(UIImage *, UIWindowScene *);
@property (nonatomic) BOOL loading;
@property (nonatomic, copy) NSString *sourceFilter;
@property (nonatomic, strong) UIStackView *filters;
@end
static RSHistoryController *RSActiveHistory;
@implementation RSHistoryController
+ (void)recordImage:(UIImage *)image completion:(void (^)(NSError *))completion {
    if (![RSOption(@"HistoryEnabled") boolValue]) return;
    NSUInteger count = [RSOption(@"HistoryCount") unsignedIntegerValue];
    NSUInteger bytes = [RSOption(@"HistoryMB") unsignedIntegerValue] * 1024 * 1024;
    id app = nil;
    SEL front = NSSelectorFromString(@"_accessibilityFrontMostApplication");
    if ([UIApplication.sharedApplication respondsToSelector:front]) app = ((id (*)(id, SEL))objc_msgSend)(UIApplication.sharedApplication, front);
    NSString *name = @"截图", *source = @"";
    if ([app respondsToSelector:NSSelectorFromString(@"displayName")]) name = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"displayName")) ?: name;
    if ([app respondsToSelector:NSSelectorFromString(@"bundleIdentifier")]) source = ((id (*)(id, SEL))objc_msgSend)(app, NSSelectorFromString(@"bundleIdentifier")) ?: source;
    if (name.length > 200) name = [name substringToIndex:200];
    if (source.length > 200) source = @"";
    dispatch_async(RSHistoryQueue(), ^{ @autoreleasepool {
        NSData *png = UIImagePNGRepresentation(image);
        CGFloat factor = MIN(160 / image.size.width, 160 / image.size.height);
        CGSize size = CGSizeMake(MAX(1, image.size.width * factor), MAX(1, image.size.height * factor));
        UIGraphicsImageRendererFormat *format = UIGraphicsImageRendererFormat.defaultFormat; format.scale = 1;
        UIImage *thumb = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [image drawInRect:(CGRect){CGPointZero, size}]; }];
        NSError *error = nil;
        [RSStore() addImage:png thumbnail:UIImagePNGRepresentation(thumb) title:name source:source countLimit:count byteLimit:bytes error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(error); [RSActiveHistory reloadHistory]; });
    } });
}
+ (void)showWithRestore:(void (^)(UIImage *, UIWindowScene *))restore {
    if (RSActiveHistory) { [RSActiveHistory.host makeKeyAndVisible]; return; }
    UIWindow *previous = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) previous = window;
    }
    RSHistoryController *controller = [[self alloc] initWithStyle:UITableViewStylePlain];
    controller.previous = previous; controller.restore = restore;
    UIWindowScene *scene = previous.windowScene;
    controller.host = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    controller.host.frame = scene ? scene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
    controller.host.windowLevel = UIWindowLevelAlert + 160;
    RSHistoryPanel *panel = [RSHistoryPanel new];
    panel.navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    __weak RSHistoryController *weakController = controller;
    panel.dismissPanel = ^{ [weakController close]; };
    controller.host.backgroundColor = UIColor.clearColor;
    controller.host.rootViewController = panel;
    RSActiveHistory = controller; RSApplyWindowOrientation(controller.host, RSActiveOrientation(scene)); [controller.host makeKeyAndVisible]; RSApplyWindowOrientation(controller.host, RSActiveOrientation(scene));
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = @"截图历史";
    self.thumbnails = [NSCache new]; self.thumbnails.countLimit = 30;
    self.tableView.rowHeight = 78;
    self.tableView.separatorInset = UIEdgeInsetsMake(0, 8, 0, 8);
    self.tableView.backgroundColor = UIColor.systemBackgroundColor;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self; self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = @"搜索名称或日期";
    self.navigationItem.searchController = self.search; self.definesPresentationContext = YES;
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"清空" style:UIBarButtonItemStylePlain target:self action:@selector(clearHistory)];
    [self reloadHistory];
}
- (void)close {
    [self.view endEditing:YES]; self.host.hidden = YES;
    [self.previous makeKeyWindow]; self.host.rootViewController = nil; self.host = nil; RSActiveHistory = nil;
}
- (void)error:(NSString *)message {
    if (self.presentedViewController) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"截图历史" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)reloadHistory {
    __weak typeof(self) weakSelf = self;
    dispatch_async(RSHistoryQueue(), ^{
        NSArray *entries = RSStore().entries;
        dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.entries = entries; [weakSelf rebuildFilters]; [weakSelf updateSearchResultsForSearchController:weakSelf.search]; });
    });
}
- (void)rebuildFilters {
    UIScrollView *scroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 48)];
    scroll.showsHorizontalScrollIndicator = NO;
    UIStackView *stack = [UIStackView new]; stack.spacing = 4; stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack]; self.filters = stack;
    NSMutableOrderedSet *sources = [NSMutableOrderedSet orderedSetWithObject:@""];
    for (NSDictionary *entry in self.entries) if ([entry[@"source"] isKindOfClass:NSString.class] && [entry[@"source"] length]) [sources addObject:entry[@"source"]];
    for (NSString *source in sources) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem]; button.accessibilityIdentifier = source;
        NSString *name = @"全部";
        for (NSDictionary *entry in self.entries) if ([entry[@"source"] isEqual:source]) { name = entry[@"title"]; break; }
        SEL iconSelector = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
        UIImage *icon = source.length && [UIImage respondsToSelector:iconSelector] ? ((id (*)(id, SEL, id, int, CGFloat))objc_msgSend)(UIImage.class, iconSelector, source, 0, UIScreen.mainScreen.scale) : nil;
        if (icon) { [button setImage:icon forState:UIControlStateNormal]; button.imageView.contentMode = UIViewContentModeScaleAspectFit; UIButtonConfiguration *configuration = UIButtonConfiguration.plainButtonConfiguration; configuration.image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(30, 30)] imageWithActions:^(UIGraphicsImageRendererContext *context) { [icon drawInRect:CGRectMake(0, 0, 30, 30)]; }]; configuration.contentInsets = NSDirectionalEdgeInsetsMake(6, 8, 6, 8); button.configuration = configuration; }
        else { [button setTitle:source.length ? name : @"全部" forState:UIControlStateNormal]; button.titleLabel.font = [UIFont systemFontOfSize:12]; }
        button.accessibilityLabel = name; button.layer.cornerRadius = 10;
        button.backgroundColor = [source isEqual:self.sourceFilter ?: @""] ? UIColor.systemGray4Color : UIColor.secondarySystemBackgroundColor;
        [button.widthAnchor constraintEqualToConstant:50].active = YES; [button.heightAnchor constraintEqualToConstant:44].active = YES;
        [button addTarget:self action:@selector(filterSource:) forControlEvents:UIControlEventTouchUpInside]; [stack addArrangedSubview:button];
    }
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:8], [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-8], [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:2], [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-2]]];
    self.tableView.tableHeaderView = scroll;
}
- (void)filterSource:(UIButton *)button { self.sourceFilter = button.accessibilityIdentifier; [self rebuildFilters]; [self updateSearchResultsForSearchController:self.search]; }
- (NSString *)dateText:(NSDictionary *)entry {
    NSDateFormatter *format = [NSDateFormatter new]; format.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    return [format stringFromDate:entry[@"date"]];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)search {
    NSString *query = search.searchBar.text ?: @"";
    self.filtered = [self.entries filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *entry, NSDictionary *bindings) {
        if (self.sourceFilter.length && ![entry[@"source"] isEqual:self.sourceFilter]) return NO;
        return !query.length || [entry[@"title"] localizedCaseInsensitiveContainsString:query] || [[self dateText:entry] containsString:query];
    }]];
    UILabel *empty = [UILabel new]; empty.textAlignment = NSTextAlignmentCenter; empty.numberOfLines = 0;
    empty.text = query.length ? @"没有匹配的截图" : @"暂无截图记录\n开启历史记录后，新生成的截图会保存在这里";
    self.tableView.backgroundView = self.filtered.count ? nil : empty;
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.filtered.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSDictionary *entry = self.filtered[path.row]; NSString *identifier = entry[@"id"];
    cell.textLabel.text = entry[@"title"]; cell.detailTextLabel.text = [self dateText:entry]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.imageView.image = [self.thumbnails objectForKey:identifier] ?: [UIImage systemImageNamed:@"photo"];
    if (![self.thumbnails objectForKey:identifier]) {
        __weak typeof(self) weakSelf = self; __weak UITableViewCell *weakCell = cell;
        dispatch_async(RSHistoryQueue(), ^{
            UIImage *image = [UIImage imageWithData:[RSStore() dataForID:identifier thumbnail:YES error:nil]];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (image) { [weakSelf.thumbnails setObject:image forKey:identifier]; weakCell.imageView.image = image; [weakCell setNeedsLayout]; }
            });
        });
    }
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES]; if (self.loading) return;
    self.loading = YES; NSDictionary *entry = self.filtered[path.row];
    __weak typeof(self) weakSelf = self;
    dispatch_async(RSHistoryQueue(), ^{
        UIImage *image = [UIImage imageWithData:[RSStore() dataForID:entry[@"id"] thumbnail:NO error:nil]];
        dispatch_async(dispatch_get_main_queue(), ^{
            RSHistoryController *controller = weakSelf; controller.loading = NO;
            if (!controller.host) return;
            if (!image.CGImage) { [controller error:@"无法读取此截图。文件可能已被清理。"]; return; }
            RSHistoryPreview *preview = [RSHistoryPreview new]; preview.title = entry[@"title"]; preview.image = image;
            preview.restore = ^{ RSHistoryController *owner = weakSelf; UIWindowScene *scene = owner.host.windowScene; [owner close]; if (owner.restore) owner.restore(image, scene); };
            preview.ask = ^{ RSHistoryController *owner = weakSelf; UIWindowScene *scene = owner.host.windowScene; [owner close]; [RSChatController showImage:image scene:scene]; };
            [controller.navigationController pushViewController:preview animated:YES];
        });
    });
}
- (void)removeEntries:(NSArray *)entries {
    __weak typeof(self) weakSelf = self;
    dispatch_async(RSHistoryQueue(), ^{
        NSError *error = nil; BOOL success = [RSStore() removeIDs:[entries valueForKey:@"id"] error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ if (!success) [weakSelf error:error.localizedDescription ?: @"删除失败，请重试。"]; [weakSelf reloadHistory]; });
    });
}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path {
    NSDictionary *entry = self.filtered[path.row];
    UIContextualAction *remove = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) { [self removeEntries:@[entry]]; done(YES); }];
    UIContextualAction *rename = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"改名" handler:^(UIContextualAction *action, UIView *view, void (^done)(BOOL)) {
        done(YES);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"截图名称" message:@"1–200 字符" preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = entry[@"title"]; }];
        [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *item) {
            NSString *title = alert.textFields.firstObject.text;
            dispatch_async(RSHistoryQueue(), ^{
                NSError *error = nil; BOOL success = [RSStore() renameID:entry[@"id"] title:title error:&error];
                dispatch_async(dispatch_get_main_queue(), ^{ if (!success) [self error:error.localizedDescription ?: @"名称必须是 1–200 字符。"]; [self reloadHistory]; });
            });
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }];
    UISwipeActionsConfiguration *actions = [UISwipeActionsConfiguration configurationWithActions:@[remove, rename]]; actions.performsFirstActionWithFullSwipe = NO; return actions;
}
- (void)clearHistory {
    if (!self.entries.count) return;
    NSArray *entries = self.entries;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空截图历史" message:@"删除这里的全部历史记录？已保存到相册的图片与当前浮图不受影响。" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { [self removeEntries:entries]; }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
