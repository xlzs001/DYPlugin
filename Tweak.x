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
// 3. 模糊匹配识别器 & 原生安全收割
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
    [gHarvestedPlugins addObject:item];
}

// ==========================================
// 4. 构建原生二级页面 (绝对禁止使用 Wrapper)
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

    if (!gHarvestedPlugins || gHarvestedPlugins.count == 0) {
        gDummyViewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    }
    if (gDummyViewModel) {
        [gDummyViewModel setValue:subVC forKey:@"controllerDelegate"];
        [gDummyViewModel performSelector:@selector(sectionDataArray)];
    }
    
    id viewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    [viewModel setValue:@(0) forKey:@"colorStyle"];
    
    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    
    // 原封不动地把原生插件对象装进去
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
// 5. 【新增核心】：不包装插件，在视图层直接劫持点击，退回主页唤醒
// ==========================================
%hook AWESettingBaseViewController

- (id)viewModel {
    id orig = %orig;
    if (!orig) return objc_getAssociatedObject(self, kDYPluginViewModelKey);
    return orig;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // 仅在我们的“收纳”子页面中生效
    if (objc_getAssociatedObject(self, kDYPluginViewModelKey)) {
        id viewModel = [self viewModel];
        if ([viewModel respondsToSelector:@selector(sectionDataArray)]) {
            NSArray *sections = [viewModel sectionDataArray];
            if (indexPath.section < sections.count) {
                id section = sections[indexPath.section];
                if ([section respondsToSelector:@selector(itemArray)]) {
                    NSArray *items = [section valueForKey:@"itemArray"];
                    if (indexPath.row < items.count) {
                        id item = items[indexPath.row];
                        void (^block)(void) = [item respondsToSelector:@selector(cellTappedBlock)] ? [item valueForKey:@"cellTappedBlock"] : nil;
                        
                        if (block) {
                            [tableView deselectRowAtIndexPath:indexPath animated:YES];
                            
                            // 1. 无动画秒退子页面
                            if (self.navigationController) {
                                [self.navigationController popViewControllerAnimated:NO];
                            } else {
                                [self dismissViewControllerAnimated:NO completion:nil];
                            }
                            
                            // 2. 延迟 0.05 秒，在最外层主设置页的环境下触发 DYYY/Yuki 等插件的原生跳转
                            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                block();
                            });
                            return; 
                        }
                    }
                }
            }
        }
    }
    %orig; 
}
%end

// ==========================================
// 6. 第一重拦截：独立区块收割
// ==========================================
%hook AWESettingsViewModel
- (NSArray *)sectionDataArray {
    NSArray *originalSections = %orig;
    if (![originalSections isKindOfClass:[NSArray class]]) return originalSections;

    BOOL isMainPage = NO;
    for (id s in originalSections) {
        if ([s respondsToSelector:@selector(sectionHeaderTitle)] && [[s valueForKey:@"sectionHeaderTitle"] isEqualToString:@"账号"]) {
            isMainPage = YES;
            break;
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

// ==========================================
// 7. 第二重拦截：内部选项透视收割
// ==========================================
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
            hasPlugin = YES; 
            break;
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
