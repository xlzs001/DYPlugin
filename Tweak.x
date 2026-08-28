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
static id gDummyViewModel = nil; // 强引用保留后台钓鱼的 ViewModel，防止高级插件指针释放失效

// ==========================================
// 3. 超级模糊匹配识别器 & 收割去重
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
        if ([title containsString:t]) {
            return YES;
        }
    }
    return NO;
}

static void HarvestItem(id item) {
    if (!item) return;
    if (!gHarvestedPlugins) gHarvestedPlugins = [NSMutableArray array];
    
    NSString *identifier = [item valueForKey:@"identifier"] ?: [item valueForKey:@"title"];
    for (id existing in gHarvestedPlugins) {
        NSString *exId = [existing valueForKey:@"identifier"] ?: [existing valueForKey:@"title"];
        if ([exId isEqualToString:identifier]) {
            return; // 防止重复添加
        }
    }
    [gHarvestedPlugins addObject:item];
}

// ==========================================
// 4. 构建并展示原生二级页面
// ==========================================
static void ShowPluginManagerPage(UIViewController *rootVC) {
    UIViewController *subVC = [[NSClassFromString(@"AWESettingBaseViewController") alloc] init];
    
    // 异步修改顶栏标题
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

    // 前置钓鱼逻辑：强制激起插件们的表现欲，并指向新的控制器
    if (!gHarvestedPlugins || gHarvestedPlugins.count == 0) {
        gDummyViewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    }
    if (gDummyViewModel) {
        [gDummyViewModel setValue:subVC forKey:@"controllerDelegate"];
        [gDummyViewModel performSelector:@selector(sectionDataArray)];
    }
    
    // 配置自己的 ViewModel 数据源
    id viewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    [viewModel setValue:@(0) forKey:@"colorStyle"];
    
    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    [section setValue:(gHarvestedPlugins ? [gHarvestedPlugins copy] : @[]) forKey:@"itemArray"];
    
    [viewModel setValue:@[section] forKey:@"sectionDataArray"];
    objc_setAssociatedObject(subVC, kDYPluginViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // 获取顶层控制器进行跳转
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
// 5. 双重清洗：拦截 ViewController & ViewModel
// ==========================================
%hook AWESettingBaseViewController

- (id)viewModel {
    id orig = %orig;
    if (!orig) return objc_getAssociatedObject(self, kDYPluginViewModelKey);
    return orig;
}

// 视图将要显示时，进行第二道清洗，铲除生命周期较晚的高级插件
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    
    id viewModel = [self viewModel];
    if (!viewModel || ![viewModel respondsToSelector:@selector(sectionDataArray)]) return;
    
    NSArray *sections = [viewModel sectionDataArray];
    BOOL isMainPage = NO;
    for (id s in sections) {
        if ([s respondsToSelector:@selector(sectionHeaderTitle)] && [[s valueForKey:@"sectionHeaderTitle"] isEqualToString:@"账号"]) {
            isMainPage = YES; break;
        }
    }
    if (!isMainPage) return;

    BOOL needReload = NO;
    NSMutableArray *finalSections = [NSMutableArray array];
    
    for (id section in sections) {
        if (![section respondsToSelector:@selector(sectionHeaderTitle)]) {
            [finalSections addObject:section];
            continue;
        }
        NSString *sectionTitle = [section valueForKey:@"sectionHeaderTitle"];
        
        // 实时更新计数值
        if ([sectionTitle isEqualToString:@"收纳"]) {
            NSArray *items = [section valueForKey:@"itemArray"];
            if (items.count > 0) {
                id entry = items.firstObject;
                NSString *currentDetail = [entry valueForKey:@"detail"];
                NSString *newDetail = [NSString stringWithFormat:@"已收纳 %lu 个", (unsigned long)(gHarvestedPlugins.count)];
                if (![currentDetail isEqualToString:newDetail]) {
                    [entry setValue:newDetail forKey:@"detail"];
                    needReload = YES;
                }
            }
            [finalSections addObject:section];
            continue;
        }
        
        if (IsTargetPlugin(sectionTitle)) {
            NSArray *items = [section valueForKey:@"itemArray"];
            for (id item in items) HarvestItem(item);
            needReload = YES; 
        } else {
            NSArray *items = [section valueForKey:@"itemArray"];
            NSMutableArray *cleanItems = [NSMutableArray array];
            BOOL sectionModified = NO;
            for (id item in items) {
                NSString *itemTitle = [item valueForKey:@"title"];
                if (IsTargetPlugin(itemTitle)) {
                    HarvestItem(item);
                    sectionModified = YES;
                    needReload = YES;
                } else {
                    [cleanItems addObject:item];
                }
            }
            if (sectionModified) {
                [section setValue:cleanItems forKey:@"itemArray"];
            }
            if (cleanItems.count > 0 || items.count == 0) {
                [finalSections addObject:section];
            }
        }
    }
    
    if (needReload) {
        [viewModel setValue:finalSections forKey:@"sectionDataArray"];
        UITableView *tableView = [self valueForKey:@"tableView"];
        if ([tableView respondsToSelector:@selector(reloadData)]) {
            [tableView reloadData];
        }
    }
}
%end

// 第一道清洗：数据源层拦截
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
        } else {
            NSArray *items = [section valueForKey:@"itemArray"];
            NSMutableArray *cleanItems = [NSMutableArray array];
            for (id item in items) {
                NSString *itemTitle = [item valueForKey:@"title"];
                if (IsTargetPlugin(itemTitle)) {
                    HarvestItem(item);
                } else {
                    [cleanItems addObject:item];
                }
            }
            [section setValue:cleanItems forKey:@"itemArray"];
            if (cleanItems.count > 0 || items.count == 0) {
                [finalSections addObject:section];
            }
        }
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
