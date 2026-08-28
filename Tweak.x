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
// 改为存储整个 section 或者独立封装，保证插件各自的完整性
static NSMutableArray *gHarvestedSections = nil; 
static void *kDYPluginViewModelKey = &kDYPluginViewModelKey;
static id gDummyViewModel = nil; 

// ==========================================
// 3. 超级模糊匹配识别器
// ==========================================
static BOOL IsTargetPluginTitle(NSString *title) {
    if (!title || title.length == 0) return NO;
    NSArray *targets = @[
        @"DYYY", @"DYKiller", @"抖音助手", @"自动消息",
        @"抖音图层", @"抖+", @"抖⁺", @"抖＋", @"aweJ", 
        @"AwemeX", @"SJJAwemeLoginRepair", @"𝙓𝙐𝙐ᶻ", 
        @"DouyinHelper", @"Yuki"
    ];
    for (NSString *t in targets) {
        if ([title containsString:t]) {
            return YES;
        }
    }
    return NO;
}

// 检查某个 Section 是否属于插件独立区块
static BOOL IsPluginSection(id section) {
    if (![section respondsToSelector:@selector(sectionHeaderTitle)]) return NO;
    NSString *headerTitle = [section valueForKey:@"sectionHeaderTitle"];
    if (IsTargetPluginTitle(headerTitle)) {
        return YES;
    }
    
    // 检查内部 item 有没有匹配的
    if ([section respondsToSelector:@selector(itemArray)]) {
        NSArray *items = [section valueForKey:@"itemArray"];
        for (id item in items) {
            NSString *itemTitle = [item valueForKey:@"title"];
            if (IsTargetPluginTitle(itemTitle)) {
                return YES;
            }
        }
    }
    return NO;
}

static void HarvestSection(id section) {
    if (!section) return;
    if (!gHarvestedSections) gHarvestedSections = [NSMutableArray array];
    
    NSString *secTitle = [section respondsToSelector:@selector(sectionHeaderTitle)] ? [section valueForKey:@"sectionHeaderTitle"] : nil;
    
    // 去重
    for (id existing in gHarvestedSections) {
        NSString *exTitle = [existing respondsToSelector:@selector(sectionHeaderTitle)] ? [existing valueForKey:@"sectionHeaderTitle"] : nil;
        if (secTitle && exTitle && [secTitle isEqualToString:exTitle]) {
            return;
        }
    }
    
    [gHarvestedSections addObject:section];
}

// ==========================================
// 4. 构建并展示原生二级页面（支持多个Section，完美保留每个插件自己的子菜单）
// ==========================================
static void ShowPluginManagerPage(UIViewController *rootVC) {
    UIViewController *subVC = [[NSClassFromString(@"AWESettingBaseViewController") alloc] init];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        for (UIView *sub in subVC.view.subviews) {
            if ([sub isKindOfClass:NSClassFromString(@"AWENavigationBar")]) {
                if ([sub respondsToSelector:@selector(titleLabel)]) {
                    UILabel *lbl = [sub valueForKey:@"titleLabel"];
                    lbl.text = @"收纳";
                }
                break;
            }
        }
    });

    if (!gHarvestedSections || gHarvestedSections.count == 0) {
        gDummyViewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    }
    if (gDummyViewModel) {
        [gDummyViewModel setValue:subVC forKey:@"controllerDelegate"];
        [gDummyViewModel performSelector:@selector(sectionDataArray)];
    }
    
    id viewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    [viewModel setValue:@(0) forKey:@"colorStyle"];
    [viewModel setValue:subVC forKey:@"controllerDelegate"];
    
    NSMutableArray *finalSectionArray = [NSMutableArray array];
    
    // 把收割到的所有插件 Section 放进来
    if (gHarvestedSections) {
        [finalSectionArray addObjectsFromArray:gHarvestedSections];
    }
    
    // 额外在最底部追加一个“仓库地址”的分区
    NSMutableArray *repoItems = [NSMutableArray array];
    AWESettingItemModel *repoItem = [[%c(AWESettingItemModel) alloc] init];
    repoItem.identifier = @"DYPluginRepoAddress";
    repoItem.title = @"https://github.com/xlzs001/DYstorage";
    repoItem.detail = @"GitHub";
    repoItem.type = 0;
    repoItem.svgIconImageName = @"ic_link_outlined_20";
    repoItem.cellType = 26; 
    repoItem.colorStyle = 0;
    repoItem.isEnable = YES;
    repoItem.cellTappedBlock = ^{
        NSURL *url = [NSURL URLWithString:@"https://github.com/xlzs001/DYstorage]; // 请改成你的仓库地址
        if (url) {
            if (@available(iOS 10.0, *)) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
            } else {
                [[UIApplication sharedApplication] openURL:url];
            }
        }
    };
    [repoItems addObject:repoItem];

    id repoSection = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [repoSection setValue:@"关于项目" forKey:@"sectionHeaderTitle"];
    [repoSection setValue:@(40) forKey:@"sectionHeaderHeight"];
    [repoSection setValue:@(0) forKey:@"type"];
    [repoSection setValue:repoItems forKey:@"itemArray"];
    
    [finalSectionArray addObject:repoSection];

    [viewModel setValue:finalSectionArray forKey:@"sectionDataArray"];
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

%hook AWESettingBaseViewController
- (id)viewModel {
    id orig = %orig;
    if (!orig) return objc_getAssociatedObject(self, kDYPluginViewModelKey);
    return orig;
}
%end

// ==========================================
// 5. 第一重清洗：拦截主页区块，把插件整块收割
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
        
        // 如果整个区块属于插件，直接收割整块 Section，不在主页显示
        if (IsPluginSection(section)) {
            HarvestSection(section);
            continue; 
        }
        
        [finalSections addObject:section];
    }

    if (!hasMgrSection) {
        AWESettingItemModel *entry = [[%c(AWESettingItemModel) alloc] init];
        entry.identifier = @"DYPluginMgr";
        entry.title = @"收纳"; 
        entry.detail = [NSString stringWithFormat:@"已收纳 %lu 个插件", (unsigned long)(gHarvestedSections.count)];
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

// ==========================================
// 6. 第二重清洗：防止漏网之鱼
// ==========================================
%hook AWESettingSectionModel
- (NSArray *)itemArray {
    NSArray *items = %orig;
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) return items;

    NSString *headerTitle = nil;
    if ([self respondsToSelector:@selector(sectionHeaderTitle)]) {
        headerTitle = [self valueForKey:@"sectionHeaderTitle"];
    }
    
    // 如果是我们的收纳页面，绝对放行
    if ([headerTitle isEqualToString:@"已收纳的插件"] || [headerTitle isEqualToString:@"收纳"] || [headerTitle isEqualToString:@"关于项目"]) {
        return items;
    }
    
    // 主页过滤单个散落的插件项
    NSMutableArray *cleanItems = [NSMutableArray array];
    for (id item in items) {
        NSString *itemTitle = [item valueForKey:@"title"];
        if (IsTargetPluginTitle(itemTitle)) {
            // 单独项不破坏
            [cleanItems addObject:item];
        } else {
            [cleanItems addObject:item];
        }
    }
    return cleanItems;
}
%end
