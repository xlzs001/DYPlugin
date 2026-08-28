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
// 2. 核心状态存储
// ==========================================
static NSMutableArray *gHarvestedPlugins = nil;
static void *kDYPluginViewModelKey = &kDYPluginViewModelKey;
static id gDummyViewModel = nil; 

// ==========================================
// 3. 搜索处理中心 (💡新增：处理搜索框输入事件和列表刷新)
// ==========================================
@interface DYPluginSearchHandler : NSObject
@property (nonatomic, weak) UIViewController *targetVC;
@property (nonatomic, weak) id viewModel;
@end

@implementation DYPluginSearchHandler
- (void)textFieldDidChange:(UITextField *)textField {
    NSString *searchText = textField.text ?: @"";
    NSArray *filteredItems = nil;
    
    // 如果没有输入，展示全部；否则进行模糊匹配搜索插件名称
    if (searchText.length == 0) {
        filteredItems = [gHarvestedPlugins copy];
    } else {
        NSMutableArray *temp = [NSMutableArray array];
        for (id item in gHarvestedPlugins) {
            NSString *title = [item valueForKey:@"title"];
            // localizedCaseInsensitiveContainsString 忽略大小写
            if ([title localizedCaseInsensitiveContainsString:searchText]) {
                [temp addObject:item];
            }
        }
        filteredItems = temp;
    }

    // 重新构建模型并覆盖
    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    [section setValue:(filteredItems ?: @[]) forKey:@"itemArray"];
    
    [self.viewModel setValue:@[section] forKey:@"sectionDataArray"];

    // 自动寻找底层的 TableView 或 CollectionView 触发刷新
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.targetVC) {
            for (UIView *v in self.targetVC.view.subviews) {
                if ([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) {
                    if ([v respondsToSelector:@selector(reloadData)]) {
                        [v performSelector:@selector(reloadData)];
                    }
                }
            }
        }
    });
}
@end

static DYPluginSearchHandler *gSearchHandler = nil;

// ==========================================
// 4. 超级精确匹配识别器 & 收割去重
// ==========================================
static BOOL IsTargetPlugin(NSString *title) {
    if (!title || title.length == 0) return NO;
    NSArray *targets = @[
        @"DYYY", @"DYKiller", @"抖音助手", @"自动消息",
        @"抖音图层", @"抖+", @"抖⁺", @"抖＋", @"aweJ", 
        @"AwemeX", @"SJJAwemeLoginRepair", @"𝙓𝙐𝙐ᶻ", 
        @"DouyinHelper", @"Yuki"
    ];
    for (NSString *t in targets) {
        if ([title isEqualToString:t]) {
            return YES;
        }
    }
    return NO;
}

static void HarvestItem(id item) {
    if (!item) return;
    if (!gHarvestedPlugins) gHarvestedPlugins = [NSMutableArray array];
    
    NSString *identifier = [item valueForKey:@"identifier"];
    NSString *title = [item valueForKey:@"title"];
    
    for (id existing in gHarvestedPlugins) {
        NSString *exId = [existing valueForKey:@"identifier"];
        NSString *exTitle = [existing valueForKey:@"title"];
        if ((identifier && exId && [exId isEqualToString:identifier]) || 
            (title && exTitle && [exTitle isEqualToString:title])) {
            return; 
        }
    }
    
    @try {
        void (^originalBlock)(void) = [item valueForKey:@"cellTappedBlock"];
        if (originalBlock) {
            void (^wrappedBlock)(void) = ^{
                originalBlock();
            };
            [item setValue:wrappedBlock forKey:@"cellTappedBlock"];
        }
    } @catch (NSException *exception) {}
    
    [gHarvestedPlugins addObject:item];
}

// ==========================================
// 5. 构建并跳转二级页面 (纯逻辑，移除了这里面难看的强行 UI 注入)
// ==========================================
static void ShowPluginManagerPage(UIViewController *rootVC) {
    UIViewController *subVC = [[NSClassFromString(@"AWESettingBaseViewController") alloc] init];
    
    if (!gHarvestedPlugins || gHarvestedPlugins.count == 0) {
        gDummyViewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    }
    if (gDummyViewModel) {
        [gDummyViewModel setValue:subVC forKey:@"controllerDelegate"];
        [gDummyViewModel performSelector:@selector(sectionDataArray)];
    }
    
    id viewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    [viewModel setValue:@(0) forKey:@"colorStyle"];
    [viewModel setValue:subVC forKey:@"controllerDelegate"];
    
    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    [section setValue:(gHarvestedPlugins ? [gHarvestedPlugins copy] : @[]) forKey:@"itemArray"];
    
    [viewModel setValue:@[section] forKey:@"sectionDataArray"];
    
    // 💡 关键标记：给这个页面打上属于我们的烙印
 
    objc_setAssociatedObject(subVC, kDYPluginViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UIViewController *topVC = rootVC;                  
    if (!topVC) { 
        topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    }
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    
    if (topVC.navigationController) {
        [topVC.navigationController pushViewController:subVC animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:subVC];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [topVC presentViewController:nav animated:YES completion:nil];
    }
}

// ==========================================
// 6. 视图拦截：精准注入搜索栏和底部文字
// ==========================================
%hook AWESettingBaseViewController
- (id)viewModel {
    id orig = %orig;
    if (!orig) return objc_getAssociatedObject(self, kDYPluginViewModelKey);
    return orig;
}

- (void)viewDidLoad {
    %orig;
    
    // 💡只在属于我们的“收纳”页面注入 UI
    id customVM = objc_getAssociatedObject(self, kDYPluginViewModelKey);
    if (customVM) {
        CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
        CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
        
        // 1. 替换导航栏标题
        CGFloat navBottomY = 88.0; // 默认高度
        for (UIView *sub in self.view.subviews) {
            if ([sub isKindOfClass:NSClassFromString(@"AWENavigationBar")]) {
                navBottomY = CGRectGetMaxY(sub.frame); // 获取导航栏底部的真实Y坐标
                if ([sub respondsToSelector:@selector(titleLabel)]) {
                    UILabel *lbl = [sub valueForKey:@"titleLabel"];
                    lbl.text = @"收纳";
                }
            }
        }
        
        // 2. 注入搜索框容器
        UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenW, 56)];
        headerContainer.backgroundColor = [UIColor clearColor];
        
        UITextField *searchBox = [[UITextField alloc] initWithFrame:CGRectMake(16, 10, screenW - 32, 36)];
        searchBox.placeholder = @"🔍 搜索已收纳的插件...";
        searchBox.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.96 alpha:1.0];
        searchBox.layer.cornerRadius = 8;
        searchBox.clipsToBounds = YES;
        searchBox.clearButtonMode = UITextFieldViewModeWhileEditing;
        searchBox.font = [UIFont systemFontOfSize:14];
        searchBox.returnKeyType = UIReturnKeyDone;
        
        UIView *leftPadding = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 36)];
        searchBox.leftView = leftPadding;
        searchBox.leftViewMode = UITextFieldViewModeAlways;
        
        [headerContainer addSubview:searchBox];
        
        if (!gSearchHandler) {
            gSearchHandler = [[DYPluginSearchHandler alloc] init];
        }
        gSearchHandler.targetVC = self;
        gSearchHandler.viewModel = customVM;
        
        [searchBox addTarget:gSearchHandler action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
        
        // 尝试设置为 TableView 的 Header
        BOOL injectedAsHeader = NO;
        for (UIView *v in self.view.subviews) {
            if ([v isKindOfClass:[UITableView class]]) {
                ((UITableView *)v).tableHeaderView = headerContainer;
                injectedAsHeader = YES;
                break;
            }
        }
        
        // 兼容 CollectionView: 如果没法做 Header，就悬浮在导航栏下方，并把列表往下挤
        if (!injectedAsHeader) {
            headerContainer.frame = CGRectMake(0, navBottomY, screenW, 56);
            [self.view addSubview:headerContainer];
            
            for (UIView *v in self.view.subviews) {
                if (([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) && v != headerContainer) {
                    UIScrollView *sv = (UIScrollView *)v;
                    UIEdgeInsets inset = sv.contentInset;
                    inset.top += 56; // 挤出搜索框的高度
                    sv.contentInset = inset;
                    break;
                }
            }
        }

        // 3. 注入底部 UITextView (带链接)
        UITextView *footerView = [[UITextView alloc] initWithFrame:CGRectMake(0, screenH - 180, screenW, 120)];
        footerView.backgroundColor = [UIColor clearColor];
        footerView.editable = NO;
        footerView.selectable = YES;
        footerView.scrollEnabled = NO;
        footerView.textContainerInset = UIEdgeInsetsZero;
        footerView.textContainer.lineFragmentPadding = 0;
        footerView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
        
        footerView.linkTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor grayColor],
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleNone)
        };
        
        NSMutableAttributedString *footerText = [[NSMutableAttributedString alloc] init];
        [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"开源仓库地址\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium], NSForegroundColorAttributeName: [UIColor colorWithRed:0.18 green:0.49 blue:0.36 alpha:1.0]}]];
        [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"https://github.com/xlzs001/DYstorage\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: [UIColor grayColor], NSLinkAttributeName: @"https://github.com/xlzs001/DYstorage" }]];
        [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"Developed by xlzs001\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: [UIColor grayColor]}]];
        [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"© 2026 xlzs001. All rights reserved." attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11], NSForegroundColorAttributeName: [UIColor lightGrayColor]}]];
        
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineSpacing = 8;
        style.alignment = NSTextAlignmentCenter;
        [footerText addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, footerText.length)];
        
        footerView.attributedText = footerText;
        [self.view addSubview:footerView];
    }
}
%end

// ==========================================
// 7. 宏观清洗与底层清洗 (保持原样，提供入口和去重)
// ==========================================
%hook AWESettingsViewModel
- (NSArray *)sectionDataArray {
    NSArray *originalSections = %orig;
    if (![originalSections isKindOfClass:[NSArray class]]) return originalSections;

    BOOL isMainPage = NO;
    for (id s in originalSections) {
        if ([s respondsToSelector:@selector(sectionHeaderTitle)] && [[s valueForKey:@"sectionHeaderTitle"] isEqualToString:@"账号"]) {
            isMainPage = YES; break;
        }
    }
    if (!isMainPage) return originalSections;

    NSMutableArray *finalSections = [NSMutableArray array];
    BOOL hasMgrSection = NO;
    
    for (id section in originalSections) {
        if (![section respondsToSelector:@selector(sectionHeaderTitle)]) {
            [finalSections addObject:section];
            continue;
        }
        NSString *sectionTitle = [section valueForKey:@"sectionHeaderTitle"];
        
        if ([sectionTitle isEqualToString:@"收纳"]) {
            hasMgrSection = YES;
            [finalSections addObject:section];
            continue;
        }
        
        if (IsTargetPlugin(sectionTitle)) {
            NSArray *items = [section valueForKey:@"itemArray"];
            for (id item in items) HarvestItem(item);
            continue; 
        }
        [finalSections addObject:section];
    }

    if (!hasMgrSection) {
        AWESettingItemModel *entry = [[%c(AWESettingItemModel) alloc] init];
        entry.identifier = @"DYPluginMgr";
        entry.title = @"收纳"; 
        entry.detail = [NSString stringWithFormat:@"已收纳 %lu 个", (unsigned long)(gHarvestedPlugins.count)];
        entry.type = 0;
        entry.svgIconImageName = @"ic_gearsimplify_outlined_20";
        entry.cellType = 26; 
        entry.colorStyle = 0;
        entry.isEnable = YES;

        __weak typeof(self) weakSelf = self;
        entry.cellTappedBlock = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && strongSelf.controllerDelegate) {
                ShowPluginManagerPage((UIViewController *)strongSelf.controllerDelegate);
            }
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

    NSString *headerTitle = nil;
    if ([self respondsToSelector:@selector(sectionHeaderTitle)]) {
        headerTitle = [self valueForKey:@"sectionHeaderTitle"];
    }
    
    if ([headerTitle isEqualToString:@"已收纳的插件"] || [headerTitle isEqualToString:@"收纳"]) {
        return items;
    }
    
    BOOL hasPlugin = NO;
    for (id item in items) {
        NSString *itemTitle = [item valueForKey:@"title"];
        if (IsTargetPlugin(itemTitle)) {
            hasPlugin = YES; break;
        }
    }
    
    if (!hasPlugin) return items;
    
    NSMutableArray *cleanItems = [NSMutableArray array];
    for (id item in items) {
        NSString *itemTitle = [item valueForKey:@"title"];
        if (IsTargetPlugin(itemTitle)) {
            HarvestItem(item); 
        } else {
            [cleanItems addObject:item]; 
        }
    }
    return cleanItems; 
}
%end
