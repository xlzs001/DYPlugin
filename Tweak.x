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
@property (nonatomic, copy) NSString *iconImageName;
@property (nonatomic, assign) NSInteger cellType;
@property (nonatomic, assign) NSInteger colorStyle;
@property (nonatomic, assign) BOOL isEnable;
@property (nonatomic, assign) BOOL isSwitchOn;
@property (nonatomic, copy) void (^cellTappedBlock)(void);
@property (nonatomic, copy) void (^switchChangedBlock)(void);
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
@property (nonatomic, strong) UITableView *tableView;
- (id)viewModel;
@end

// ==========================================
// 2. 核心状态存储 (全局变量)
// ==========================================
static NSMutableArray *gHarvestedPlugins = nil;
static void *kDYPluginViewModelKey = &kDYPluginViewModelKey;
static id gDummyViewModel = nil; // 强引用，保证高级插件执行跳转时不会因为底层指针释放而失效

// ==========================================
// 3. 超级模糊匹配识别器 & 安全收割器
// ==========================================
static BOOL IsTargetPlugin(NSString *title) {
    if (!title || title.length == 0) return NO;
    // 加入了所有可能出现的插件名以及特殊符号（如抖⁺的各种上标变体）
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
    
    NSString *title = [item respondsToSelector:@selector(title)] ? [item valueForKey:@"title"] : nil;
    
    // 严格按标题去重，防止多次进出设置页重复抓取
    for (id existing in gHarvestedPlugins) {
        NSString *exTitle = [existing valueForKey:@"title"];
        if (title && exTitle && [exTitle isEqualToString:title]) {
            return; 
        }
    }
    [gHarvestedPlugins addObject:item];
}

// ==========================================
// 4. 构建原生二级页面 (利用替身Wrapper修复跳转死链)
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

    // 前置钓鱼：为深层隐蔽的插件生成执行宿主
    if (!gHarvestedPlugins || gHarvestedPlugins.count == 0) {
        gDummyViewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    }
    if (gDummyViewModel) {
        [gDummyViewModel setValue:subVC forKey:@"controllerDelegate"];
        [gDummyViewModel performSelector:@selector(sectionDataArray)];
    }
    
    // 核心逻辑：为收割来的插件创建“替身(Wrapper)”，解决上下文丢失导致打不开的 Bug
    NSMutableArray *wrapperItems = [NSMutableArray array];
    for (id originalItem in gHarvestedPlugins) {
        id wrapperItem = [[NSClassFromString(@"AWESettingItemModel") alloc] init];
        
        // 拷贝 UI 属性
        NSArray *properties = @[@"identifier", @"title", @"detail", @"type", @"svgIconImageName", @"iconImageName", @"cellType", @"colorStyle", @"isEnable", @"isSwitchOn"];
        for (NSString *prop in properties) {
            if ([originalItem respondsToSelector:NSSelectorFromString(prop)]) {
                id val = [originalItem valueForKey:prop];
                if (val) [wrapperItem setValue:val forKey:prop];
            }
        }
        
        // 接管点击事件
        void (^originalBlock)(void) = [originalItem respondsToSelector:@selector(cellTappedBlock)] ? [originalItem valueForKey:@"cellTappedBlock"] : nil;
        __weak UIViewController *weakSubVC = subVC;
        
        if (originalBlock) {
            void (^newBlock)(void) = ^{
                // 1. 瞬间退回到抖音主设置页面（无动画，用户视觉无感）
                if (weakSubVC.navigationController) {
                    [weakSubVC.navigationController popViewControllerAnimated:NO];
                }
                // 2. 延迟 0.05 秒，在原生环境完全恢复后，触发真实的插件唤出逻辑
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    originalBlock();
                });
            };
            [wrapperItem setValue:newBlock forKey:@"cellTappedBlock"];
        }
        
        void (^origSwitchBlock)(void) = [originalItem respondsToSelector:@selector(switchChangedBlock)] ? [originalItem valueForKey:@"switchChangedBlock"] : nil;
        if (origSwitchBlock) {
            [wrapperItem setValue:origSwitchBlock forKey:@"switchChangedBlock"];
        }
        
        [wrapperItems addObject:wrapperItem];
    }
    
    // 配置自己的 ViewModel 数据源
    id viewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    [viewModel setValue:@(0) forKey:@"colorStyle"];
    
    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    [section setValue:wrapperItems forKey:@"itemArray"];
    
    [viewModel setValue:@[section] forKey:@"sectionDataArray"];
    objc_setAssociatedObject(subVC, kDYPluginViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // 执行跳转
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
// 5. 第二重清洗与【液态玻璃】视觉注入
// ==========================================
%hook AWESettingBaseViewController

- (id)viewModel {
    id orig = %orig;
    if (!orig) return objc_getAssociatedObject(self, kDYPluginViewModelKey);
    return orig;
}

// 拦截页面加载，铺设液态玻璃背景
- (void)viewDidLoad {
    %orig;
    if (objc_getAssociatedObject(self, kDYPluginViewModelKey)) {
        self.view.backgroundColor = [UIColor clearColor];
        UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleRegular];
        UIVisualEffectView *glassView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
        glassView.frame = self.view.bounds;
        glassView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self.view insertSubview:glassView atIndex:0];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            for (UIView *subview in self.view.subviews) {
                if ([subview isKindOfClass:[UITableView class]]) {
                    UITableView *tableView = (UITableView *)subview;
                    tableView.backgroundColor = [UIColor clearColor];
                    tableView.separatorStyle = UITableViewCellSeparatorStyleNone; 
                }
            }
        });
    }
}

// 挖空选项 Cell，透出液态玻璃
- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    %orig;
    if (objc_getAssociatedObject(self, kDYPluginViewModelKey)) {
        cell.backgroundColor = [UIColor clearColor];
        cell.contentView.backgroundColor = [UIColor clearColor];
    }
}

// 屏幕渲染前的最后一秒执行深度清洗（对付后期强行注入的高级插件）
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    
    id viewModel = [self viewModel];
    if (!viewModel || ![viewModel respondsToSelector:@selector(sectionDataArray)]) return;
    
    NSArray *sections = [viewModel sectionDataArray];
    if (![sections isKindOfClass:[NSArray class]]) return;
    
    BOOL isMainPage = NO;
    BOOL isMyPluginPage = NO;
    for (id s in sections) {
        NSString *title = [s respondsToSelector:@selector(sectionHeaderTitle)] ? [s valueForKey:@"sectionHeaderTitle"] : nil;
        if ([title isEqualToString:@"账号"]) isMainPage = YES;
        if ([title isEqualToString:@"已收纳的插件"]) isMyPluginPage = YES;
    }
    
    if (isMyPluginPage || !isMainPage) return;

    if (!gHarvestedPlugins) gHarvestedPlugins = [NSMutableArray array];
    NSMutableArray *finalSections = [NSMutableArray array];
    BOOL needReload = NO;
    
    for (id section in sections) {
        if (![section respondsToSelector:@selector(sectionHeaderTitle)]) {
            [finalSections addObject:section];
            continue;
        }
        
        NSString *sectionTitle = [section valueForKey:@"sectionHeaderTitle"];
        
        // 动态更新收纳中心计数值
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
        
        // 斩首行动 A：整块没收
        if (IsTargetPlugin(sectionTitle)) {
            NSArray *items = [section respondsToSelector:@selector(itemArray)] ? [section valueForKey:@"itemArray"] : nil;
            if ([items isKindOfClass:[NSArray class]]) {
                for (id item in items) HarvestItem(item);
            }
            needReload = YES; 
        } else {
            // 斩首行动 B：透视通用列表，揪出"抖音图层"和"抖+"
            NSArray *items = [section respondsToSelector:@selector(itemArray)] ? [section valueForKey:@"itemArray"] : nil;
            if ([items isKindOfClass:[NSArray class]]) {
                NSMutableArray *cleanItems = [NSMutableArray array];
                BOOL sectionModified = NO;
                
                for (id item in items) {
                    NSString *itemTitle = [item respondsToSelector:@selector(title)] ? [item valueForKey:@"title"] : nil;
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
            }
            [finalSections addObject:section];
        }
    }
    
    if (needReload) {
        [viewModel setValue:finalSections forKey:@"sectionDataArray"];
        UITableView *tv = nil;
        for (UIView *v in self.view.subviews) {
            if ([v isKindOfClass:[UITableView class]]) { tv = (UITableView *)v; break; }
        }
        if (tv && [tv respondsToSelector:@selector(reloadData)]) {
            [tv reloadData];
        }
    }
}
%end

// ==========================================
// 6. 第一重清洗：数据源构建层拦截
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

    if (!gHarvestedPlugins) gHarvestedPlugins = [NSMutableArray array];
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
        } else {
            NSArray *items = [section respondsToSelector:@selector(itemArray)] ? [section valueForKey:@"itemArray"] : nil;
            if ([items isKindOfClass:[NSArray class]]) {
                NSMutableArray *cleanItems = [NSMutableArray array];
                for (id item in items) {
                    NSString *itemTitle = [item respondsToSelector:@selector(title)] ? [item valueForKey:@"title"] : nil;
                    if (IsTargetPlugin(itemTitle)) {
                        HarvestItem(item);
                    } else {
                        [cleanItems addObject:item];
                    }
                }
                [section setValue:cleanItems forKey:@"itemArray"];
            }
            [finalSections addObject:section];
        }
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
