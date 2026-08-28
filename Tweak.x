#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ==========================================
// 1. 声明抖音原生模型
// ==========================================
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

// ==========================================
// 2. 核心状态与代理
// ==========================================
static NSMutableArray *gHarvestedPlugins = nil;
static void *kDYPluginViewModelKey = &kDYPluginViewModelKey;
static void *kDYPluginSearchHandlerKey = &kDYPluginSearchHandlerKey;

@interface DYPluginSearchHandler : NSObject
@property (nonatomic, weak) UIViewController *targetVC;
@property (nonatomic, weak) id viewModel;
@end

@implementation DYPluginSearchHandler
- (void)textFieldDidChange:(UITextField *)textField {
    NSString *searchText = textField.text ?: @"";
    
    // 💡 优化：使用 NSPredicate 极简实现模糊搜索过滤
    NSArray *filtered = searchText.length == 0 ? [gHarvestedPlugins copy] : [gHarvestedPlugins filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id item, NSDictionary *bindings) {
        return [[item valueForKey:@"title"] localizedCaseInsensitiveContainsString:searchText];
    }]];

    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    [section setValue:filtered ?: @[] forKey:@"itemArray"];
    
    [self.viewModel setValue:@[section] forKey:@"sectionDataArray"];

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *vc = self.targetVC;
        if (vc && vc.isViewLoaded && vc.view.window) {
            for (UIView *v in vc.view.subviews) {
                if ([v respondsToSelector:@selector(reloadData)]) {
                    [v performSelector:@selector(reloadData)];
                }
            }
        }
    });
}
@end

// ==========================================
// 3. 核心插件抓取与去重
// ==========================================
static BOOL IsTargetPlugin(NSString *title) {
    if (!title || title.length == 0) return NO;
    // 💡 优化：使用静态 NSSet 提升匹配性能为 O(1)
    static NSSet *targets = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        targets = [NSSet setWithArray:@[@"DYYY", @"DYKiller", @"抖音助手", @"自动消息", @"抖音图层", @"抖+", @"抖⁺", @"抖＋", @"aweJ", @"AwemeX", @"SJJAwemeLoginRepair", @"𝙓𝙐𝙐ᶻ", @"DouyinHelper", @"Yuki"]];
    });
    return [targets containsObject:title];
}

static void HarvestItem(id item) {
    if (!item) return;
    if (!gHarvestedPlugins) gHarvestedPlugins = [NSMutableArray array];
    
    NSString *identifier = [item valueForKey:@"identifier"];
    NSString *title = [item valueForKey:@"title"];
    
    // 💡 优化：倒序遍历安全剔除僵尸对象，确保上下文时刻保持最新 (防卡死打不开)
    for (NSInteger i = gHarvestedPlugins.count - 1; i >= 0; i--) {
        id existing = gHarvestedPlugins[i];
        NSString *exId = [existing valueForKey:@"identifier"];
        NSString *exTitle = [existing valueForKey:@"title"];
        if ((identifier && exId && [exId isEqualToString:identifier]) || 
            (title && exTitle && [exTitle isEqualToString:title])) {
            [gHarvestedPlugins removeObjectAtIndex:i];
            break;
        }
    }
    // 原汁原味保留 Block，杜绝套层引发的野指针
    [gHarvestedPlugins addObject:item];
}

// ==========================================
// 4. 构建并展示收纳二级页面
// ==========================================
static void ShowPluginManagerPage(UIViewController *rootVC) {
    UIViewController *subVC = [[NSClassFromString(@"AWESettingBaseViewController") alloc] init];
    
    if (gHarvestedPlugins.count == 0) {
        @try {
            id dummyVM = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
            [dummyVM setValue:subVC forKey:@"controllerDelegate"];
            [dummyVM performSelector:@selector(sectionDataArray)];
        } @catch (...) {}
    }
    
    id viewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    [viewModel setValue:@(0) forKey:@"colorStyle"];
    [viewModel setValue:subVC forKey:@"controllerDelegate"];
    
    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    [section setValue:[gHarvestedPlugins copy] ?: @[] forKey:@"itemArray"];
    
    [viewModel setValue:@[section] forKey:@"sectionDataArray"];
    objc_setAssociatedObject(subVC, kDYPluginViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    UIViewController *topVC = rootVC ?: [UIApplication sharedApplication].keyWindow.rootViewController;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    
    if (topVC.navigationController) {
        [topVC.navigationController pushViewController:subVC animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:subVC];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [topVC presentViewController:nav animated:YES completion:nil];
    }
}

// ==========================================
// 5. 原生 UI 注入 (防手势闪退版)
// ==========================================
%hook AWESettingBaseViewController
- (id)viewModel {
    id orig = %orig;
    return orig ?: objc_getAssociatedObject(self, kDYPluginViewModelKey);
}

- (void)viewDidLoad {
    %orig;
    id customVM = objc_getAssociatedObject(self, kDYPluginViewModelKey);
    if (!customVM) return; // 只管我们自己的页面
    
    CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
    
    // --- 构建搜索栏 ---
    UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenW, 60)];
    UITextField *searchBox = [[UITextField alloc] initWithFrame:CGRectMake(16, 12, screenW - 32, 36)];
    searchBox.placeholder = @"🔍 怎么能够做到全局搜索啊";
    searchBox.textAlignment = NSTextAlignmentCenter; 
    searchBox.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.96 alpha:1.0];
    searchBox.layer.cornerRadius = 8;
    searchBox.clearButtonMode = UITextFieldViewModeWhileEditing;
    searchBox.font = [UIFont systemFontOfSize:14];
    [headerContainer addSubview:searchBox];
    
    DYPluginSearchHandler *handler = [[DYPluginSearchHandler alloc] init];
    handler.targetVC = self;
    handler.viewModel = customVM;
    objc_setAssociatedObject(self, kDYPluginSearchHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [searchBox addTarget:handler action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
    
    // --- 构建底部页脚 ---
    UITextView *footerView = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, screenW, 140)];
    footerView.backgroundColor = [UIColor clearColor];
    footerView.editable = NO;
    footerView.selectable = YES;
    footerView.scrollEnabled = NO;
    footerView.textContainerInset = UIEdgeInsetsMake(20, 0, 0, 0);
    footerView.linkTextAttributes = @{ NSForegroundColorAttributeName: [UIColor grayColor], NSUnderlineStyleAttributeName: @(NSUnderlineStyleNone) };
    
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineSpacing = 8;
    style.alignment = NSTextAlignmentCenter;
    
    NSMutableAttributedString *footerText = [[NSMutableAttributedString alloc] init];
    [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"开源仓库地址\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium], NSForegroundColorAttributeName: [UIColor colorWithRed:0.18 green:0.49 blue:0.36 alpha:1.0]}]];
    [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"https://github.com/xlzs001/DYstorage\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: [UIColor grayColor], NSLinkAttributeName: @"https://github.com/xlzs001/DYstorage" }]];
    [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"Developed by xlzs001\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: [UIColor grayColor]}]];
    [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"© 2026 xlzs001. All rights reserved." attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11], NSForegroundColorAttributeName: [UIColor lightGrayColor]}]];
    [footerText addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, footerText.length)];
    footerView.attributedText = footerText;

    // 💡 优化：一次性遍历视图，安全注入组件并修改标题
    for (UIView *sub in self.view.subviews) {
        if ([sub isKindOfClass:NSClassFromString(@"AWENavigationBar")] && [sub respondsToSelector:@selector(titleLabel)]) {
            UILabel *lbl = [sub valueForKey:@"titleLabel"];
            lbl.text = @"收纳";
        } else if ([sub isKindOfClass:[UITableView class]]) {
            UITableView *tbv = (UITableView *)sub;
            tbv.tableHeaderView = headerContainer;
            tbv.tableFooterView = footerView;
        }
    }
}
%end

// ==========================================
// 6. 数据源拦截清洗
// ==========================================
%hook AWESettingsViewModel
- (NSArray *)sectionDataArray {
    NSArray *orig = %orig;
    if (![orig isKindOfClass:[NSArray class]]) return orig;

    BOOL isMainPage = NO;
    for (id s in orig) {
        if ([[s valueForKey:@"sectionHeaderTitle"] isEqualToString:@"账号"]) {
            isMainPage = YES; break;
        }
    }
    if (!isMainPage) return orig;

    NSMutableArray *finalSections = [NSMutableArray array];
    BOOL hasMgrSection = NO;
    
    for (id section in orig) {
        NSString *title = [section valueForKey:@"sectionHeaderTitle"];
        if ([title isEqualToString:@"收纳"]) {
            hasMgrSection = YES;
        } else if (IsTargetPlugin(title)) {
            for (id item in [section valueForKey:@"itemArray"]) HarvestItem(item);
            continue; 
        }
        [finalSections addObject:section];
    }

    if (!hasMgrSection) {
        AWESettingItemModel *entry = [[%c(AWESettingItemModel) alloc] init];
        entry.identifier = @"DYPluginMgr";
        entry.title = @"收纳"; 
        entry.detail = [NSString stringWithFormat:@"已收纳 %lu 个", (unsigned long)gHarvestedPlugins.count];
        entry.type = 0;
        entry.svgIconImageName = @"ic_gearsimplify_outlined_20";
        entry.cellType = 26; 
        entry.colorStyle = 0;
        entry.isEnable = YES;

        __weak typeof(self) weakSelf = self;
        entry.cellTappedBlock = ^{
            if (weakSelf.controllerDelegate) ShowPluginManagerPage((UIViewController *)weakSelf.controllerDelegate);
        };

        id mgrSection = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
        [mgrSection setValue:@[ entry ] forKey:@"itemArray"];
        [mgrSection setValue:@(0) forKey:@"type"];
        [mgrSection setValue:@(40) forKey:@"sectionHeaderHeight"];
        [mgrSection setValue:@"收纳" forKey:@"sectionHeaderTitle"];

        [finalSections insertObject:mgrSection atIndex:0];
    }
    return finalSections;
}
%end

%hook AWESettingSectionModel
- (NSArray *)itemArray {
    NSArray *items = %orig;
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) return items;

    NSString *headerTitle = [self respondsToSelector:@selector(sectionHeaderTitle)] ? [self valueForKey:@"sectionHeaderTitle"] : nil;
    if ([headerTitle isEqualToString:@"已收纳的插件"] || [headerTitle isEqualToString:@"收纳"]) return items;
    
    BOOL hasPlugin = NO;
    for (id item in items) {
        if (IsTargetPlugin([item valueForKey:@"title"])) {
            hasPlugin = YES; break;
        }
    }
    if (!hasPlugin) return items;
    
    NSMutableArray *cleanItems = [NSMutableArray array];
    for (id item in items) {
        if (IsTargetPlugin([item valueForKey:@"title"])) {
            HarvestItem(item); 
        } else {
            [cleanItems addObject:item]; 
        }
    }
    return cleanItems; 
}
%end
