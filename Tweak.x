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

// ==========================================
// 3. 超级模糊匹配识别器 & 【实时换血收割器】
// ==========================================
static BOOL IsTargetPlugin(NSString *title) {
    if (!title || title.length == 0) return NO;
    // 增加对"抖+"各种特殊上标、全角符号的模糊匹配防漏
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
    if (!item || ![item isKindOfClass:NSClassFromString(@"AWESettingItemModel")]) return;
    if (!gHarvestedPlugins) gHarvestedPlugins = [NSMutableArray array];
    
    NSString *identifier = [item respondsToSelector:@selector(identifier)] ? [item valueForKey:@"identifier"] : nil;
    NSString *title = [item respondsToSelector:@selector(title)] ? [item valueForKey:@"title"] : nil;
    
    // 【核心修复：指针实时换血】
    // 只要发现同名插件，直接替换掉旧的！保证插件绑定的环境指针永远不死！
    for (int i = 0; i < gHarvestedPlugins.count; i++) {
        id existing = gHarvestedPlugins[i];
        NSString *exId = [existing respondsToSelector:@selector(identifier)] ? [existing valueForKey:@"identifier"] : nil;
        NSString *exTitle = [existing respondsToSelector:@selector(title)] ? [existing valueForKey:@"title"] : nil;
        
        if ((identifier && exId && [exId isEqualToString:identifier]) || 
            (title && exTitle && [exTitle isEqualToString:title])) {
            [gHarvestedPlugins replaceObjectAtIndex:i withObject:item]; // 覆盖刷新！
            return; 
        }
    }
    [gHarvestedPlugins addObject:item];
}

// ==========================================
// 4. 构建原生二级页面 (绝对不使用 Wrapper)
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

    id viewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    [viewModel setValue:@(0) forKey:@"colorStyle"];
    
    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    
    // ⚠️ 完全不使用替身，直接把原汁原味的插件模型放进我们的二级列表里
    [section setValue:(gHarvestedPlugins ? [gHarvestedPlugins copy] : @[]) forKey:@"itemArray"];
    
    [viewModel setValue:@[section] forKey:@"sectionDataArray"];
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
// 5. 视图层：双重清洗防漏网
// ==========================================
%hook AWESettingBaseViewController

- (id)viewModel {
    id orig = %orig;
    if (!orig) return objc_getAssociatedObject(self, kDYPluginViewModelKey);
    return orig;
}

// 页面展现前的深度清洗，根除“通用”里寄生的图层和抖+
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    
    id viewModel = [self viewModel];
    if (!viewModel || ![viewModel respondsToSelector:@selector(sectionDataArray)]) return;
    
    NSArray *sections = [viewModel sectionDataArray];
    if (![sections isKindOfClass:[NSArray class]]) return;
    
    BOOL isMainPage = NO;
    for (id s in sections) {
        NSString *title = [s respondsToSelector:@selector(sectionHeaderTitle)] ? [s valueForKey:@"sectionHeaderTitle"] : nil;
        if ([title isEqualToString:@"账号"]) { isMainPage = YES; break; }
    }
    if (!isMainPage) return; // 绝对不清洗子页面，免疫崩溃

    BOOL needReload = NO;
    NSMutableArray *finalSections = [NSMutableArray array];
    
    for (id section in sections) {
        if (![section respondsToSelector:@selector(sectionHeaderTitle)]) {
            [finalSections addObject:section];
            continue;
        }
        
        NSString *sectionTitle = [section valueForKey:@"sectionHeaderTitle"];
        
        if ([sectionTitle isEqualToString:@"收纳"]) {
            NSArray *items = [section respondsToSelector:@selector(itemArray)] ? [section valueForKey:@"itemArray"] : nil;
            if ([items isKindOfClass:[NSArray class]] && items.count > 0) {
                id entry = items.firstObject;
                NSString *currentDetail = [entry valueForKey:@"detail"];
                NSString *newDetail = [NSString stringWithFormat:@"已收纳 %lu 个", (unsigned long)gHarvestedPlugins.count];
                if (![currentDetail isEqualToString:newDetail]) {
                    [entry setValue:newDetail forKey:@"detail"];
                    needReload = YES;
                }
            }
            [finalSections addObject:section];
            continue;
        }
        
        // 专门切除通用列表里的寄生插件
        NSArray *items = [section respondsToSelector:@selector(itemArray)] ? [section valueForKey:@"itemArray"] : nil;
        if ([items isKindOfClass:[NSArray class]]) {
            NSMutableArray *cleanItems = [NSMutableArray array];
            BOOL sectionModified = NO;
            for (id item in items) {
                NSString *itemTitle = [item respondsToSelector:@selector(title)] ? [item valueForKey:@"title"] : nil;
                if (IsTargetPlugin(itemTitle)) {
                    HarvestItem(item); // 没收！
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
        } else {
            [finalSections addObject:section];
        }
    }
    
    if (needReload) {
        [viewModel setValue:finalSections forKey:@"sectionDataArray"];
        UITableView *tv = [self respondsToSelector:@selector(tableView)] ? [self valueForKey:@"tableView"] : nil;
        if (!tv) {
            for (UIView *v in self.view.subviews) {
                if ([v isKindOfClass:[UITableView class]]) { tv = (UITableView *)v; break; }
            }
        }
        if (tv && [tv respondsToSelector:@selector(reloadData)]) {
            [tv reloadData];
        }
    }
}
%end

// ==========================================
// 6. 数据源拦截：独立区块收割
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
            NSArray *items = [section respondsToSelector:@selector(itemArray)] ? [section valueForKey:@"itemArray"] : nil;
            if ([items isKindOfClass:[NSArray class]]) {
                for (id item in items) HarvestItem(item);
            }
            continue; 
        }
        
        [finalSections addObject:section];
    }

    if (!hasMgrSection) {
        AWESettingItemModel *entry = [[NSClassFromString(@"AWESettingItemModel") alloc] init];
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
