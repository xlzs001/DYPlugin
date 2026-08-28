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
// 3. 超级模糊匹配识别器 & 安全收割
// ==========================================
static BOOL IsTargetPlugin(NSString *title) {
    if (!title || title.length == 0) return NO;
    // 加入了所有可能出现的插件名以及特殊符号（如抖⁺的各种变体）
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
    
    // 严格按标题去重，防止重复抓取
    for (id existing in gHarvestedPlugins) {
        NSString *exTitle = [existing valueForKey:@"title"];
        if (title && exTitle && [exTitle isEqualToString:title]) {
            return; 
        }
    }
    [gHarvestedPlugins addObject:item];
}

// ==========================================
// 4. 构建并展示原生二级页面 (利用替身技术修复死链)
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

    // 核心逻辑：为收割来的插件创建“替身(Wrapper)”，解决上下文丢失导致打不开的 Bug
    NSMutableArray *wrapperItems = [NSMutableArray array];
    for (id originalItem in gHarvestedPlugins) {
        id wrapperItem = [[NSClassFromString(@"AWESettingItemModel") alloc] init];
        
        // 安全拷贝 UI 属性
        NSArray *properties = @[@"identifier", @"title", @"detail", @"type", @"svgIconImageName", @"iconImageName", @"cellType", @"colorStyle", @"isEnable", @"isSwitchOn"];
        for (NSString *prop in properties) {
            if ([originalItem respondsToSelector:NSSelectorFromString(prop)]) {
                id val = [originalItem valueForKey:prop];
                if (val) [wrapperItem setValue:val forKey:prop];
            }
        }
        
        // 替身劫持：接管点击事件
        void (^originalBlock)(void) = [originalItem respondsToSelector:@selector(cellTappedBlock)] ? [originalItem valueForKey:@"cellTappedBlock"] : nil;
        __weak UIViewController *weakSubVC = subVC;
        
        if (originalBlock) {
            void (^newBlock)(void) = ^{
                // 1. 瞬间退回到抖音主设置页面（无动画，用户无感）
                if (weakSubVC.navigationController) {
                    [weakSubVC.navigationController popViewControllerAnimated:NO];
                }
                
                // 2. 延迟 0.05 秒，在主页面环境完全恢复后，触发插件的真实跳转代码！
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    originalBlock();
                });
            };
            [wrapperItem setValue:newBlock forKey:@"cellTappedBlock"];
        }
        
        // 如果插件带有开关，同样接管
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
    [section setValue:wrapperItems forKey:@"itemArray"]; // 放入替身
    
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
// 5. 接管并兼容我们自定义的 ViewModel
// ==========================================
%hook AWESettingBaseViewController
- (id)viewModel {
    id orig = %orig;
    if (!orig) return objc_getAssociatedObject(self, kDYPluginViewModelKey);
    return orig;
}
%end

// ==========================================
// 6. 安全拦截清洗 (修复崩溃与漏网之鱼)
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
    
    // 绝对不清洗其他子页面，防止死循环或崩溃
    if (!isMainPage) return originalSections;

    NSMutableArray *finalSections = [NSMutableArray array];
    BOOL hasMgrSection = NO;
    
    for (id section in originalSections) {
        if (![section isKindOfClass:NSClassFromString(@"AWESettingSectionModel")]) {
            [finalSections addObject:section];
            continue;
        }
        
        NSString *sectionTitle = [section respondsToSelector:@selector(sectionHeaderTitle)] ? [section valueForKey:@"sectionHeaderTitle"] : nil;
        
        if ([sectionTitle isEqualToString:@"收纳"]) {
            hasMgrSection = YES;
            [finalSections addObject:section];
            continue;
        }
        
        // 场景 A：整个区块都是插件专属的（如 DYYY）
        if (IsTargetPlugin(sectionTitle)) {
            NSArray *items = [section respondsToSelector:@selector(itemArray)] ? [section valueForKey:@"itemArray"] : nil;
            if ([items isKindOfClass:[NSArray class]]) {
                for (id item in items) HarvestItem(item);
            }
            // 不加入 finalSections，即从主页抹除
            continue; 
        } 
        // 场景 B：原生区块（如“通用”），开启透视扫描，把“抖+”和“抖音图层”挖出来
        else {
            NSArray *items = [section respondsToSelector:@selector(itemArray)] ? [section valueForKey:@"itemArray"] : nil;
            if ([items isKindOfClass:[NSArray class]]) {
                NSMutableArray *cleanItems = [NSMutableArray array];
                BOOL sectionModified = NO;
                
                for (id item in items) {
                    if ([item isKindOfClass:NSClassFromString(@"AWESettingItemModel")]) {
                        NSString *itemTitle = [item respondsToSelector:@selector(title)] ? [item valueForKey:@"title"] : nil;
                        if (IsTargetPlugin(itemTitle)) {
                            HarvestItem(item);
                            sectionModified = YES;
                            continue; // 屏蔽此选项
                        }
                    }
                    [cleanItems addObject:item]; // 不是插件的选项还给原生
                }
                if (sectionModified) {
                    [section setValue:cleanItems forKey:@"itemArray"];
                }
            }
            [finalSections addObject:section];
        }
    }

    // 7. 在第一行插入我们的【收纳】入口
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
