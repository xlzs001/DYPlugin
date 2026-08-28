// =============================================================================
//  DYstorage.xm  —  抖音第三方插件「收纳」管理器
//  重构版：修复原版编译错误 / KVC 崩溃风险 / 无效的全局查杀逻辑
//  新增：全局悬浮入口（抖音助手 等）拦截 + 收纳页内按需唤起
//  Theos / Logos  ·  ARC
// =============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

// ---- 调试开关：编译时加 -DDY_DEBUG=1 可打开日志 ------------------------------
#ifndef DY_DEBUG
#define DY_DEBUG 0
#endif

#if DY_DEBUG
#define DYLog(fmt, ...) NSLog((@"[DYstorage] " fmt), ##__VA_ARGS__)
#else
#define DYLog(...)
#endif

// =============================================================================
// 1. 抖音原生模型声明（仅用于类型提示，实际取类都走 %c / NSClassFromString）
// =============================================================================
@interface AWESettingItemModel : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *detail;
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, copy) NSString *svgIconImageName;
@property (nonatomic, assign) NSInteger cellType;
@property (nonatomic, assign) NSInteger colorStyle;
@property (nonatomic, assign) BOOL isEnable;
@property (nonatomic, copy) void (^cellTappedBlock)(void);
@end

@interface AWESettingSectionModel : NSObject
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, assign) CGFloat sectionHeaderHeight;
@property (nonatomic, copy) NSString *sectionHeaderTitle;
@property (nonatomic, strong) NSArray *itemArray;
@end

@interface AWESettingsViewModel : NSObject
@property (nonatomic, weak) id controllerDelegate;
@property (nonatomic, strong) NSArray *sectionDataArray;
@property (nonatomic, assign) NSInteger colorStyle;
@end

@interface AWESettingBaseViewController : UIViewController
- (id)viewModel;
@end

// =============================================================================
// 2. 全局状态
// =============================================================================
static NSMutableArray        *gHarvestedPlugins   = nil;  // 已收纳的设置项
static NSMutableArray<UIView *>   *gCapturedViews   = nil;  // 被拦截的悬浮视图
static NSMutableArray<UIWindow *> *gCapturedWindows = nil;  // 被拦截的悬浮窗口
static BOOL gAllowRogueDisplay = NO;   // YES 时暂时放行（仅收纳页内使用）
static BOOL gInSectionDataHook = NO;   // 防重入

static void *kDYPluginViewModelKey    = &kDYPluginViewModelKey;
static void *kDYPluginSearchHandlerKey = &kDYPluginSearchHandlerKey;

// =============================================================================
// 3. 安全工具函数（原版直接 valueForKey / performSelector，越界即崩，这里全部兜底）
// =============================================================================
static id DYGet(id obj, NSString *key) {
    if (!obj || key.length == 0) return nil;
    @try { return [obj valueForKey:key]; }
    @catch (__unused NSException *e) { return nil; }
}

static NSString *DYGetString(id obj, NSString *key) {
    id v = DYGet(obj, key);
    return [v isKindOfClass:[NSString class]] ? (NSString *)v : nil;
}

static void DYSet(id obj, id value, NSString *key) {
    if (!obj || key.length == 0) return;
    @try { [obj setValue:value forKey:key]; }
    @catch (__unused NSException *e) {}
}

/// 取所有 UIWindow（替代已废弃的 keyWindow / windows）
static NSArray<UIWindow *> *DYAllWindows(void) {
    NSMutableArray *result = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            [result addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
    if (result.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [result addObjectsFromArray:[UIApplication sharedApplication].windows];
#pragma clang diagnostic pop
    }
    return result;
}

static UIWindow *DYKeyWindow(void) {
    for (UIWindow *w in DYAllWindows()) {
        if (w.isKeyWindow) return w;
    }
    return DYAllWindows().firstObject;
}

static UIViewController *DYTopViewController(UIViewController *base) {
    UIViewController *vc = base ?: DYKeyWindow().rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

// =============================================================================
// 4. 关键词配置
//    · DYPluginNames    —— 设置页里要「收纳」的插件（精确匹配标题）
//    · DYRogueKeywords  —— 要从全局界面上「赶走」的悬浮入口（模糊匹配）
// =============================================================================
static NSArray<NSString *> *DYPluginNames(void) {
    static NSArray *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @[ @"DYYY", @"DYKiller", @"抖音助手", @"自动消息",
                   @"抖音图层", @"抖+", @"抖⁺", @"抖＋", @"aweJ",
                   @"AwemeX", @"SJJAwemeLoginRepair", @"𝙓𝙐𝙐ᶻ",
                   @"DouyinHelper", @"Yuki" ];
    });
    return names;
}

static NSArray<NSString *> *DYRogueKeywords(void) {
    static NSArray *keys = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // ⚠️ 只放足够独特的词，别放 "助手"/"设置" 这种通用词，否则会误伤抖音自身 UI
        keys = @[ @"抖音助手", @"XUU", @"Xuu", @"𝙓𝙐𝙐", @"DouyinHelper", @"DYYY" ];
    });
    return keys;
}

static BOOL DYIsTargetPluginTitle(NSString *title) {
    if (title.length == 0) return NO;
    for (NSString *t in DYPluginNames()) {
        if ([title isEqualToString:t]) return YES;
    }
    return NO;
}

static BOOL DYTextLooksRogue(NSString *text) {
    if (text.length == 0) return NO;
    for (NSString *k in DYRogueKeywords()) {
        if ([text localizedCaseInsensitiveContainsString:k]) return YES;
    }
    return NO;
}

// =============================================================================
// 5. 视图识别
//    原版用 performSelector:@selector(text) 硬扒，遇到返回结构体 / 非对象的
//    text 方法会直接野指针崩溃。这里改成按类型白名单读取。
// =============================================================================
static NSString *DYExtractText(UIView *view) {
    if ([view isKindOfClass:[UILabel class]])     return ((UILabel *)view).text;
    if ([view isKindOfClass:[UITextField class]]) return ((UITextField *)view).text;
    if ([view isKindOfClass:[UITextView class]])  return ((UITextView *)view).text;
    if ([view isKindOfClass:[UIButton class]])    return ((UIButton *)view).currentTitle;
    return view.accessibilityLabel;
}

/// 判断一棵子树里是否藏着流氓入口（限制深度，避免性能塌方）
static BOOL DYViewTreeLooksRogue(UIView *view, NSInteger depth) {
    if (!view || depth < 0) return NO;

    // 列表 Cell 一律放行：收纳页里的正常条目就是 Cell，不能误伤
    if ([view isKindOfClass:[UITableViewCell class]] ||
        [view isKindOfClass:[UICollectionViewCell class]]) return NO;

    if (DYTextLooksRogue(NSStringFromClass([view class]))) return YES;
    if (DYTextLooksRogue(DYExtractText(view)))             return YES;
    if (DYTextLooksRogue(view.accessibilityIdentifier))    return YES;

    if (depth == 0) return NO;
    for (UIView *sub in view.subviews) {
        if (DYViewTreeLooksRogue(sub, depth - 1)) return YES;
    }
    return NO;
}

static BOOL DYWindowLooksRogue(UIWindow *window) {
    if (!window) return NO;
    if (window == DYKeyWindow()) return NO;                 // 主窗口绝不动
    if (window.rootViewController.class == [UIViewController class] &&
        window.subviews.count == 0) return NO;
    if (DYTextLooksRogue(NSStringFromClass([window class]))) return YES;
    NSString *rootCls = window.rootViewController ? NSStringFromClass([window.rootViewController class]) : nil;
    if (DYTextLooksRogue(rootCls)) return YES;
    for (UIView *sub in window.subviews) {
        if (DYViewTreeLooksRogue(sub, 3)) return YES;
    }
    return NO;
}

// =============================================================================
// 6. 悬浮入口拦截 & 缓存
//    思路：不销毁它（销毁了功能就没了），只是「不让它上屏」，
//    把对象强引用扣在手里，等用户在收纳页点开时再放行。
// =============================================================================
static void DYCaptureView(UIView *view) {
    if (!view) return;
    if (!gCapturedViews) gCapturedViews = [NSMutableArray array];
    if (![gCapturedViews containsObject:view]) {
        [gCapturedViews addObject:view];
        DYLog(@"捕获悬浮视图: %@", NSStringFromClass([view class]));
    }
    view.hidden = YES;
    if (view.superview) [view removeFromSuperview];
}

static void DYCaptureWindow(UIWindow *window) {
    if (!window) return;
    if (!gCapturedWindows) gCapturedWindows = [NSMutableArray array];
    if (![gCapturedWindows containsObject:window]) {
        [gCapturedWindows addObject:window];
        DYLog(@"捕获悬浮窗口: %@", NSStringFromClass([window class]));
    }
    window.hidden = YES;
}

static NSUInteger DYCapturedCount(void) {
    return gCapturedViews.count + gCapturedWindows.count;
}

/// 全窗口巡检：处理「在我们 hook 生效前就已经挂上去」或后续偷偷重挂的情况
static void DYSweepAllWindows(void) {
    if (gAllowRogueDisplay) return;
    for (UIWindow *w in DYAllWindows()) {
        if (DYWindowLooksRogue(w)) { DYCaptureWindow(w); continue; }
        for (UIView *sub in [w.subviews copy]) {
            if (DYViewTreeLooksRogue(sub, 3)) DYCaptureView(sub);
        }
    }
}

/// 模拟点击被扣住的入口：优先直接触发它自己的 target-action，
/// 这样不用把悬浮球放回屏幕，就能弹出它原本的面板。
static BOOL DYTriggerEntry(UIView *entry, NSInteger depth) {
    if (!entry || depth < 0) return NO;

    if ([entry isKindOfClass:[UIControl class]]) {
        UIControl *ctl = (UIControl *)entry;
        if (ctl.allTargets.count > 0) {
            [ctl sendActionsForControlEvents:UIControlEventTouchUpInside];
            return YES;
        }
    }

    for (UIGestureRecognizer *gr in entry.gestureRecognizers) {
        if (![gr isKindOfClass:[UITapGestureRecognizer class]]) continue;
        if (!gr.isEnabled) continue;
        @try {
            id targets = DYGet(gr, @"_targets");   // NSArray<UIGestureRecognizerTarget *>
            if (![targets isKindOfClass:[NSArray class]]) continue;

            for (id t in (NSArray *)targets) {
                Ivar tIvar = class_getInstanceVariable([t class], "_target");
                Ivar aIvar = class_getInstanceVariable([t class], "_action");
                if (!tIvar || !aIvar) continue;

                id target = object_getIvar(t, tIvar);
                // _action 是 SEL 类型的 ivar，object_getIvar 只适用于对象指针，
                // 这里按字节偏移读取，指针转换必须经过 void * 而不是 __bridge 到整型指针
                void *raw    = (__bridge void *)t;
                SEL   action = *(SEL *)((uint8_t *)raw + ivar_getOffset(aIvar));

                if (target && action && [target respondsToSelector:action]) {
                    ((void (*)(id, SEL, id))objc_msgSend)(target, action, gr);
                    return YES;
                }
            }
        } @catch (__unused NSException *e) {}
    }

    for (UIView *sub in entry.subviews) {
        if (DYTriggerEntry(sub, depth - 1)) return YES;
    }
    return NO;
}

/// 在收纳页里主动唤起被扣住的入口
static void DYPresentCapturedEntries(void) {
    if (DYCapturedCount() == 0) return;

    gAllowRogueDisplay = YES;   // 临时放行，避免刚放出去又被拦截器扣回来

    // 1) 窗口型：直接显示
    for (UIWindow *w in [gCapturedWindows copy]) {
        w.hidden = NO;
        if (w.windowLevel < UIWindowLevelNormal) w.windowLevel = UIWindowLevelNormal + 1;
    }

    // 2) 视图型：先尝试无痕触发它的点击回调
    BOOL triggered = NO;
    for (UIView *v in [gCapturedViews copy]) {
        if (DYTriggerEntry(v, 4)) { triggered = YES; break; }
    }

    // 3) 触发不了就把悬浮球放回主窗口，让用户自己点
    if (!triggered) {
        UIWindow *key = DYKeyWindow();
        for (UIView *v in [gCapturedViews copy]) {
            if (v.superview) continue;
            v.hidden = NO;
            v.alpha  = 1.0;
            [key addSubview:v];
        }
    }

    // 8 秒后恢复拦截：用户此时应已进入插件面板，
    // 面板通常挂在别的容器上，不会被这次巡检误伤。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        gAllowRogueDisplay = NO;
    });
}

// =============================================================================
// 7. 收纳数据管理
// =============================================================================
static void DYHarvestItem(id item) {
    if (!item) return;
    if (!gHarvestedPlugins) gHarvestedPlugins = [NSMutableArray array];

    NSString *identifier = DYGetString(item, @"identifier");
    NSString *title      = DYGetString(item, @"title");

    // 去重：同 identifier 或同 title 视为同一项，用新对象替换旧的僵尸对象
    id staleItem = nil;
    for (id existing in gHarvestedPlugins) {
        NSString *exId    = DYGetString(existing, @"identifier");
        NSString *exTitle = DYGetString(existing, @"title");
        if ((identifier.length && exId.length    && [exId isEqualToString:identifier]) ||
            (title.length      && exTitle.length && [exTitle isEqualToString:title])) {
            staleItem = existing;
            break;
        }
    }
    if (staleItem) [gHarvestedPlugins removeObject:staleItem];

    [gHarvestedPlugins addObject:item];
    DYLog(@"收纳: %@", title);
}

/// 生成「悬浮入口」这一条，点击后唤起被扣住的原生面板
static id DYMakeFloatingEntryItem(void) {
    if (DYCapturedCount() == 0) return nil;

    Class itemCls = NSClassFromString(@"AWESettingItemModel");
    if (!itemCls) return nil;

    AWESettingItemModel *item = [[itemCls alloc] init];
    item.identifier       = @"DYFloatingEntry";
    item.title            = @"悬浮入口（已从全局隐藏）";
    item.detail           = [NSString stringWithFormat:@"%lu 个", (unsigned long)DYCapturedCount()];
    item.type             = 0;
    item.svgIconImageName = @"ic_squarearrow_outlined_20";
    item.cellType         = 26;
    item.colorStyle       = 0;
    item.isEnable         = YES;
    item.cellTappedBlock  = ^{ DYPresentCapturedEntries(); };
    return item;
}

/// 收纳页要展示的完整数据 = 悬浮入口 + 已收纳的设置项
static NSArray *DYStorageItems(NSString *filter) {
    NSMutableArray *all = [NSMutableArray array];
    id floating = DYMakeFloatingEntryItem();
    if (floating) [all addObject:floating];
    if (gHarvestedPlugins.count) [all addObjectsFromArray:gHarvestedPlugins];

    if (filter.length == 0) return all;

    NSMutableArray *matched = [NSMutableArray array];
    for (id item in all) {
        NSString *title = DYGetString(item, @"title");
        if (title && [title localizedCaseInsensitiveContainsString:filter]) {
            [matched addObject:item];
        }
    }
    return matched;
}

static id DYMakeStorageSection(NSArray *items) {
    Class secCls = NSClassFromString(@"AWESettingSectionModel");
    if (!secCls) return nil;
    id section = [[secCls alloc] init];
    DYSet(section, @"已收纳的插件", @"sectionHeaderTitle");
    DYSet(section, @(40),          @"sectionHeaderHeight");
    DYSet(section, @(0),           @"type");
    DYSet(section, items ?: @[],   @"itemArray");
    return section;
}

// =============================================================================
// 8. 搜索处理
// =============================================================================
@interface DYPluginSearchHandler : NSObject
@property (nonatomic, weak) UIViewController *targetVC;
@property (nonatomic, weak) id viewModel;
@end

@implementation DYPluginSearchHandler

- (void)reloadListInView:(UIView *)root depth:(NSInteger)depth {
    if (!root || depth < 0) return;
    if ([root isKindOfClass:[UITableView class]]) {
        [(UITableView *)root reloadData];
        return;
    }
    if ([root isKindOfClass:[UICollectionView class]]) {
        [(UICollectionView *)root reloadData];
        return;
    }
    for (UIView *sub in root.subviews) [self reloadListInView:sub depth:depth - 1];
}

- (void)textFieldDidChange:(UITextField *)textField {
    NSString *searchText = textField.text ?: @"";
    id section = DYMakeStorageSection(DYStorageItems(searchText));
    if (!section) return;

    DYSet(self.viewModel, @[ section ], @"sectionDataArray");

    // 原版只扫了一层 subviews，抖音的 tableView 通常嵌在容器里，导致刷不出来
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.targetVC.isViewLoaded) {
            [self reloadListInView:self.targetVC.view depth:4];
        }
    });
}

@end

// =============================================================================
// 9. 收纳页构建与跳转
// =============================================================================
static void DYShowStoragePage(UIViewController *rootVC) {
    Class vcCls = NSClassFromString(@"AWESettingBaseViewController");
    Class vmCls = NSClassFromString(@"AWESettingsViewModel");
    if (!vcCls || !vmCls) return;

    UIViewController *subVC = [[vcCls alloc] init];

    id viewModel = [[vmCls alloc] init];
    DYSet(viewModel, @(0),  @"colorStyle");
    DYSet(viewModel, subVC, @"controllerDelegate");

    id section = DYMakeStorageSection(DYStorageItems(nil));
    DYSet(viewModel, section ? @[ section ] : @[], @"sectionDataArray");

    objc_setAssociatedObject(subVC, kDYPluginViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    UIViewController *topVC = DYTopViewController(rootVC);
    if (topVC.navigationController) {
        [topVC.navigationController pushViewController:subVC animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:subVC];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [topVC presentViewController:nav animated:YES completion:nil];
    }
}

// =============================================================================
// 10. ★ 全局悬浮入口拦截 ★
//     不去 hook 对方插件的类（类名会变、也未必加载得到），
//     而是守住它「上屏」的唯一必经之路：UIWindow。
// =============================================================================

%hook UIWindow

- (void)makeKeyAndVisible {
    if (!gAllowRogueDisplay && DYWindowLooksRogue(self)) {
        DYCaptureWindow(self);
        return;                     // 直接不让它 show
    }
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    if (!hidden && !gAllowRogueDisplay && DYWindowLooksRogue(self)) {
        DYCaptureWindow(self);
        %orig(YES);
        return;
    }
    %orig;
}

- (void)addSubview:(UIView *)view {
    if (!gAllowRogueDisplay && view && DYViewTreeLooksRogue(view, 3)) {
        DYCaptureView(view);        // 扣下来，不 addSubview
        return;
    }
    %orig;
}

%end

// 兜底：某些悬浮球挂在普通容器视图上，而不是直接挂 window
%hook UIView

- (void)didMoveToWindow {
    %orig;
    if (gAllowRogueDisplay) return;
    if (!self.window) return;
    // 只在自身层面判断（不递归），避免每个视图上屏都跑一遍深度遍历
    if (DYTextLooksRogue(NSStringFromClass([self class])) ||
        DYTextLooksRogue(self.accessibilityIdentifier)) {
        DYCaptureView(self);
    }
}

%end

// =============================================================================
// 11. 收纳页 UI
// =============================================================================
%hook AWESettingBaseViewController

- (id)viewModel {
    id custom = objc_getAssociatedObject(self, kDYPluginViewModelKey);
    if (custom) return custom;      // 自建页面：优先返回自己的 VM
    return %orig;
}

- (void)viewDidLoad {
    %orig;

    id customVM = objc_getAssociatedObject(self, kDYPluginViewModelKey);
    if (!customVM) return;          // 不是收纳页，什么都不做

    CGFloat screenW = self.view.bounds.size.width ?: [UIScreen mainScreen].bounds.size.width;

    // ---- 标题改成「收纳」------------------------------------------------
    self.title = @"收纳";
    for (UIView *sub in self.view.subviews) {
        if (![sub isKindOfClass:NSClassFromString(@"AWENavigationBar")]) continue;
        id lbl = DYGet(sub, @"titleLabel");
        if ([lbl isKindOfClass:[UILabel class]]) ((UILabel *)lbl).text = @"收纳";
    }

    // ---- 搜索框 ---------------------------------------------------------
    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenW, 56)];
    headerContainer.backgroundColor = [UIColor clearColor];
    headerContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UITextField *searchBox = [[UITextField alloc] initWithFrame:CGRectMake(16, 10, screenW - 32, 36)];
    searchBox.placeholder      = @"🔍 搜索已收纳的插件";
    searchBox.textAlignment    = NSTextAlignmentCenter;
    searchBox.backgroundColor  = [UIColor colorWithRed:0.95 green:0.95 blue:0.96 alpha:1.0];
    searchBox.textColor        = [UIColor darkTextColor];
    searchBox.layer.cornerRadius = 8;
    searchBox.clipsToBounds    = YES;
    searchBox.clearButtonMode  = UITextFieldViewModeWhileEditing;
    searchBox.font             = [UIFont systemFontOfSize:14];
    searchBox.returnKeyType    = UIReturnKeyDone;
    searchBox.autocorrectionType    = UITextAutocorrectionTypeNo;
    searchBox.autocapitalizationType = UITextAutocapitalizationTypeNone;
    searchBox.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [headerContainer addSubview:searchBox];

    DYPluginSearchHandler *handler = [[DYPluginSearchHandler alloc] init];
    handler.targetVC  = self;
    handler.viewModel = customVM;
    objc_setAssociatedObject(self, kDYPluginSearchHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [searchBox addTarget:handler
                  action:@selector(textFieldDidChange:)
        forControlEvents:UIControlEventEditingChanged];

    // ---- 挂到列表头部 ----------------------------------------------------
    UIScrollView *listView = nil;
    for (UIView *v in self.view.subviews) {
        if ([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) {
            listView = (UIScrollView *)v;
            break;
        }
    }

    if ([listView isKindOfClass:[UITableView class]]) {
        ((UITableView *)listView).tableHeaderView = headerContainer;
    } else {
        CGFloat topY = self.view.safeAreaInsets.top + 44;
        headerContainer.frame = CGRectMake(0, topY, screenW, 56);
        [self.view addSubview:headerContainer];
        if (listView) {
            UIEdgeInsets inset = listView.contentInset;
            inset.top += 56;
            listView.contentInset = inset;
        }
    }

    // ---- 底部版权 --------------------------------------------------------
    UITextView *footerView = [[UITextView alloc] init];
    footerView.backgroundColor = [UIColor clearColor];
    footerView.editable        = NO;
    footerView.selectable      = YES;
    footerView.scrollEnabled   = NO;
    footerView.userInteractionEnabled = YES;
    footerView.textContainerInset = UIEdgeInsetsZero;
    footerView.textContainer.lineFragmentPadding = 0;
    footerView.linkTextAttributes = @{
        NSForegroundColorAttributeName: [UIColor grayColor],
        NSUnderlineStyleAttributeName : @(NSUnderlineStyleNone)
    };

    NSMutableAttributedString *footerText = [[NSMutableAttributedString alloc] init];
    [footerText appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"开源仓库地址\n"
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium],
                          NSForegroundColorAttributeName: [UIColor colorWithRed:0.18 green:0.49 blue:0.36 alpha:1.0] }]];
    [footerText appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"https://github.com/xlzs001/DYstorage\n"
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:12],
                          NSForegroundColorAttributeName: [UIColor grayColor],
                          NSLinkAttributeName: [NSURL URLWithString:@"https://github.com/xlzs001/DYstorage"] }]];
    [footerText appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"Developed by xlzs001\n"
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:12],
                          NSForegroundColorAttributeName: [UIColor grayColor] }]];
    [footerText appendAttributedString:[[NSAttributedString alloc]
        initWithString:@"© 2026 xlzs001. All rights reserved."
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:11],
                          NSForegroundColorAttributeName: [UIColor lightGrayColor] }]];

    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineSpacing = 8;
    style.alignment   = NSTextAlignmentCenter;
    [footerText addAttribute:NSParagraphStyleAttributeName
                       value:style
                       range:NSMakeRange(0, footerText.length)];
    footerView.attributedText = footerText;

    // 用 AutoLayout 贴底，替代原版写死的 screenH - 180（刘海屏 / 分屏会错位）
    footerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:footerView];
    [NSLayoutConstraint activateConstraints:@[
        [footerView.leadingAnchor  constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [footerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [footerView.bottomAnchor   constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-24]
    ]];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!objc_getAssociatedObject(self, kDYPluginViewModelKey)) return;
    // 进入收纳页时刷新一次「悬浮入口」计数
    id vm = objc_getAssociatedObject(self, kDYPluginViewModelKey);
    id section = DYMakeStorageSection(DYStorageItems(nil));
    if (section) DYSet(vm, @[ section ], @"sectionDataArray");
}

%end

// =============================================================================
// 12. 设置页数据清洗：把散落的插件入口收进「收纳」
// =============================================================================
%hook AWESettingsViewModel

- (NSArray *)sectionDataArray {
    NSArray *originalSections = %orig;
    if (![originalSections isKindOfClass:[NSArray class]]) return originalSections;
    if (gInSectionDataHook) return originalSections;   // 防重入

    // 只处理设置主页（判定依据：存在「账号」分组）
    BOOL isMainPage = NO;
    for (id s in originalSections) {
        if ([DYGetString(s, @"sectionHeaderTitle") isEqualToString:@"账号"]) { isMainPage = YES; break; }
    }
    if (!isMainPage) return originalSections;

    gInSectionDataHook = YES;

    NSMutableArray *finalSections = [NSMutableArray array];
    BOOL hasMgrSection = NO;

    for (id section in originalSections) {
        NSString *sectionTitle = DYGetString(section, @"sectionHeaderTitle");   // ← 原版这里写成了未定义的 sectionHeaderTitle

        if ([sectionTitle isEqualToString:@"收纳"]) {
            hasMgrSection = YES;
            [finalSections addObject:section];
            continue;
        }

        // 整个分组就是某个插件 → 把它的条目全部收走，分组本身丢弃
        if (DYIsTargetPluginTitle(sectionTitle)) {
            id items = DYGet(section, @"itemArray");
            if ([items isKindOfClass:[NSArray class]]) {
                for (id item in (NSArray *)items) DYHarvestItem(item);
            }
            continue;
        }

        [finalSections addObject:section];
    }

    if (!hasMgrSection) {
        Class itemCls = NSClassFromString(@"AWESettingItemModel");
        Class secCls  = NSClassFromString(@"AWESettingSectionModel");
        if (itemCls && secCls) {
            AWESettingItemModel *entry = [[itemCls alloc] init];
            entry.identifier       = @"DYPluginMgr";
            entry.title            = @"收纳";
            entry.detail           = [NSString stringWithFormat:@"已收纳 %lu 个",
                                      (unsigned long)(gHarvestedPlugins.count + (DYCapturedCount() ? 1 : 0))];
            entry.type             = 0;
            entry.svgIconImageName = @"ic_gearsimplify_outlined_20";
            entry.cellType         = 26;
            entry.colorStyle       = 0;
            entry.isEnable         = YES;

            // controllerDelegate 是 weak，block 里直接捕获 self 会循环引用，保持 weak-strong dance
            __weak typeof(self) weakSelf = self;
            entry.cellTappedBlock = ^{
                __strong typeof(weakSelf) strongSelf = weakSelf;
                DYShowStoragePage((UIViewController *)(strongSelf ? strongSelf.controllerDelegate : nil));
            };

            id mgrSection = [[secCls alloc] init];
            DYSet(mgrSection, @[ entry ], @"itemArray");
            DYSet(mgrSection, @(0),       @"type");
            DYSet(mgrSection, @(40),      @"sectionHeaderHeight");
            DYSet(mgrSection, @"收纳",     @"sectionHeaderTitle");
            [finalSections insertObject:mgrSection atIndex:0];
        }
    }

    gInSectionDataHook = NO;
    return finalSections;
}

%end

%hook AWESettingSectionModel

- (NSArray *)itemArray {
    NSArray *items = %orig;
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) return items;

    NSString *headerTitle = DYGetString(self, @"sectionHeaderTitle");

    // 收纳页自身的数据不能再被清洗，否则条目会凭空消失
    if ([headerTitle isEqualToString:@"已收纳的插件"] || [headerTitle isEqualToString:@"收纳"]) {
        return items;
    }

    BOOL hasPlugin = NO;
    for (id item in items) {
        if (DYIsTargetPluginTitle(DYGetString(item, @"title"))) { hasPlugin = YES; break; }
    }
    if (!hasPlugin) return items;

    NSMutableArray *cleanItems = [NSMutableArray array];
    for (id item in items) {
        if (DYIsTargetPluginTitle(DYGetString(item, @"title"))) {
            DYHarvestItem(item);
        } else {
            [cleanItems addObject:item];
        }
    }
    return cleanItems;
}

%end

// =============================================================================
// 13. 启动巡检：处理比我们更早注入的插件
// =============================================================================
%ctor {
    @autoreleasepool {
        %init;

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
            // 冷启动 / 从后台回来时各扫一次，覆盖延迟挂载的悬浮球
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ DYSweepAllWindows(); });
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ DYSweepAllWindows(); });
        }];
    }
}
