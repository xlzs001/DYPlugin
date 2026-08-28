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
// 2. 存储被收割的插件与关联Key
// ==========================================
static NSMutableArray *gHarvestedPlugins = nil;
static void *kDYPluginViewModelKey = &kDYPluginViewModelKey;

// ==========================================
// 3. 构建并展示 DYYY 同款原生二级页面
// ==========================================
static void ShowPluginManagerPage(UIViewController *rootVC) {
    // 【前置钓鱼逻辑】：如果还没进过设置，插件还没被收割，我们在后台假装建一个设置页，逼它们交出菜单
    if (!gHarvestedPlugins || gHarvestedPlugins.count == 0) {
        id dummyModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
        [dummyModel setValue:rootVC forKey:@"controllerDelegate"];
        [dummyModel performSelector:@selector(sectionDataArray)]; 
    }
    
    // 创建抖音原生二级设置页面
    UIViewController *subVC = [[NSClassFromString(@"AWESettingBaseViewController") alloc] init];
    
    // 异步修改顶栏标题为“收纳”
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
    
    // 创建数据源 ViewModel
    id viewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    [viewModel setValue:@(0) forKey:@"colorStyle"];
    
    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    [section setValue:(gHarvestedPlugins ? [gHarvestedPlugins copy] : @[]) forKey:@"itemArray"];
    
    [viewModel setValue:@[section] forKey:@"sectionDataArray"];
    
    // 强行把我们的数据源绑定给这个二级页面
    objc_setAssociatedObject(subVC, kDYPluginViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // 寻找导航控制器进行丝滑 Push 跳转
    UIViewController *topVC = rootVC;
    if (!topVC) {
        topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
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
// 4. 接管并兼容我们自定义的 ViewModel
// ==========================================
%hook AWESettingBaseViewController
- (id)viewModel {
    id orig = %orig;
    // 如果没有自带的数据源，说明这是我们自己创建的二级页面，直接读取我们绑定的 ViewModel
    if (!orig) return objc_getAssociatedObject(self, kDYPluginViewModelKey);
    return orig;
}
%end

// ==========================================
// 5. 数据源拦截收割 (设置页核心拦截)
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
    
    // 如果不是设置主页（比如进入了二级页面），安全放行，防止死循环
    if (!isMainPage) return originalSections;

    if (!gHarvestedPlugins) {
        gHarvestedPlugins = [NSMutableArray array];
    }

    NSMutableArray *finalSections = [NSMutableArray array];
    
    // ==========================================
    // 严格保留你提供的所有插件名称，绝不随意更改
    // ==========================================
    NSArray *targetPlugins = @[
        @"DYYY", 
        @"DYKiller", 
        @"抖音助手", 
        @"自动消息",
        @"抖音图层",
        @"抖+",
        @"aweJ",
        @"𝙓𝙐𝙐ᶻ",
        @"DouyinHelper",
        @"Yuki"
    ];
    
    for (id section in originalSections) {
        NSString *title = [section valueForKey:@"sectionHeaderTitle"];
        // 匹配你的清单或者是自身
        if ([targetPlugins containsObject:title] || [title isEqualToString:@"收纳"]) {
            NSArray *items = [section valueForKey:@"itemArray"];
            if (items.count > 0) {
                // 防止重复收割（用户多次进出设置页可能导致重复追加）
                for (id item in items) {
                    BOOL exists = NO;
                    NSString *identifier = [item valueForKey:@"identifier"];
                    for (id existing in gHarvestedPlugins) {
                        if ([[existing valueForKey:@"identifier"] isEqualToString:identifier]) {
                            exists = YES; break;
                        }
                    }
                    if (!exists) {
                        [gHarvestedPlugins addObject:item];
                    }
                }
            }
        } else {
            // 抖音原生选项，放行
            [finalSections addObject:section];
        }
    }

    // 建立总入口菜单
    AWESettingItemModel *entry = [[%c(AWESettingItemModel) alloc] init];
    entry.identifier = @"DYPluginMgr";
    entry.title = @"收纳"; // 名字按要求修改
    entry.detail = [NSString stringWithFormat:@"已收纳 %lu 个", (unsigned long)gHarvestedPlugins.count];
    entry.type = 0;
    entry.svgIconImageName = @"ic_gearsimplify_outlined_20";
    entry.cellType = 26; 
    entry.colorStyle = 0;
    entry.isEnable = YES;

    // 点击总入口，拉起原生的二级页面
    __weak AWESettingsViewModel *weakSelf = self;
    entry.cellTappedBlock = ^{
        __strong AWESettingsViewModel *strongSelf = weakSelf;
        if (strongSelf && strongSelf.controllerDelegate) {
            ShowPluginManagerPage((UIViewController *)strongSelf.controllerDelegate);
        }
    };

    AWESettingSectionModel *mgrSection = [[%c(AWESettingSectionModel) alloc] init];
    mgrSection.itemArray = @[ entry ];
    mgrSection.type = 0;
    mgrSection.sectionHeaderHeight = 40;
    mgrSection.sectionHeaderTitle = @"收纳"; // 名字按要求修改

    [finalSections insertObject:mgrSection atIndex:0];
    return finalSections;
}
%end

// ==========================================
// 6. 全局三连击唤出二级窗口 (挂载在 UIWindow 保证任何页面都能触发)
// ==========================================
%hook UIWindow

- (void)becomeKeyWindow {
    %orig;
    
    // 检查是否已经添加过手势，避免视图刷新导致重复添加
    BOOL hasGesture = NO;
    for (UIGestureRecognizer *g in self.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]] && ((UITapGestureRecognizer *)g).numberOfTapsRequired == 3) {
            hasGesture = YES;
            break;
        }
    }
    
    if (!hasGesture) {
        UITapGestureRecognizer *tripleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dyplugin_tripleTap:)];
        tripleTap.numberOfTapsRequired = 3;
        // 必须设置为 NO，允许触摸事件向下传递，绝不影响抖音的正常滑动和双击点赞
        tripleTap.cancelsTouchesInView = NO; 
        [self addGestureRecognizer:tripleTap];
    }
}

%new
- (void)dyplugin_tripleTap:(UITapGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateRecognized) {
        // 找到当前屏幕上最顶层的视图控制器
        UIViewController *topVC = self.rootViewController;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
        ShowPluginManagerPage(topVC);
    }
}

%end
