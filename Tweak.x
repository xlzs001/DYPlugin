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
static id gDummyViewModel = nil; // 【关键修复】：必须强引用保留后台钓鱼的 ViewModel，否则高级插件会因为指针释放而无法跳转！

// ==========================================
// 3. 构建并展示原生二级页面
// ==========================================
static void ShowPluginManagerPage(UIViewController *rootVC) {
    // 实例化我们要弹出的原生设置页面
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

    // 【前置钓鱼逻辑】：如果没有数据，在后台触发一次设置页的生成机制
    if (!gHarvestedPlugins || gHarvestedPlugins.count == 0) {
        gDummyViewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    }
    // 【关键修复】：将插件依赖的 controllerDelegate 永远指向我们当前活着的 subVC，这样无论从哪里启动都能成功 push 界面
    if (gDummyViewModel) {
        [gDummyViewModel setValue:subVC forKey:@"controllerDelegate"];
        [gDummyViewModel performSelector:@selector(sectionDataArray)];
    }
    
    // 构建我们自己的二级列表数据
    id viewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    [viewModel setValue:@(0) forKey:@"colorStyle"];
    
    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    [section setValue:(gHarvestedPlugins ? [gHarvestedPlugins copy] : @[]) forKey:@"itemArray"];
    
    [viewModel setValue:@[section] forKey:@"sectionDataArray"];
    
    // 绑定数据源
    objc_setAssociatedObject(subVC, kDYPluginViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // 寻找最顶层控制器并进行跳转
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
// 4. 接管并兼容自定义数据源
// ==========================================
%hook AWESettingBaseViewController
- (id)viewModel {
    id orig = %orig;
    if (!orig) return objc_getAssociatedObject(self, kDYPluginViewModelKey);
    return orig;
}
%end

// ==========================================
// 5. 数据源透视收割 (完美拦截区块与Item)
// ==========================================
%hook AWESettingsViewModel
- (NSArray *)sectionDataArray {
    NSArray *originalSections = %orig;
    if (![originalSections isKindOfClass:[NSArray class]]) return originalSections;

    // 避开自己的二级页面，防止死循环无限收割
    for (id s in originalSections) {
        if ([s respondsToSelector:@selector(sectionHeaderTitle)] && [[s valueForKey:@"sectionHeaderTitle"] isEqualToString:@"已收纳的插件"]) {
            return originalSections;
        }
    }

    if (!gHarvestedPlugins) {
        gHarvestedPlugins = [NSMutableArray array];
    }

    NSMutableArray *finalSections = [NSMutableArray array];
    
    // ⚠️ 收纳目标名单
    NSArray *targetPlugins = @[
        @"DYYY", @"DYKiller", @"抖音助手", @"自动消息",
        @"抖音图层", @"抖+", @"aweJ", @"AwemeX",
        @"SJJAwemeLoginRepair", @"𝙓𝙐𝙐ᶻ", @"DouyinHelper", @"Yuki"
    ];
    
    for (id section in originalSections) {
        if (![section respondsToSelector:@selector(sectionHeaderTitle)]) {
            [finalSections addObject:section];
            continue;
        }
        
        NSString *sectionTitle = [section valueForKey:@"sectionHeaderTitle"];
        NSArray *items = [section valueForKey:@"itemArray"];
        
        // 【情况 A】：整个区块都是插件专属的（如 DYYY）
        if ([targetPlugins containsObject:sectionTitle] || [sectionTitle isEqualToString:@"收纳"]) {
            if (items.count > 0) {
                for (id item in items) {
                    BOOL exists = NO;
                    NSString *identifier = [item valueForKey:@"identifier"];
                    for (id existing in gHarvestedPlugins) {
                        if ([[existing valueForKey:@"identifier"] isEqualToString:identifier]) { exists = YES; break; }
                    }
                    if (!exists) [gHarvestedPlugins addObject:item];
                }
            }
        } else {
            // 【情况 B】：插件像寄生虫一样藏在原生区块内部（如 抖音图层、抖+ 藏在"通用"里）
            NSMutableArray *filteredItems = [NSMutableArray array];
            for (id item in items) {
                NSString *itemTitle = [item valueForKey:@"title"];
                // 透视扫描内部的每一个选项
                if ([targetPlugins containsObject:itemTitle]) {
                    BOOL exists = NO;
                    NSString *identifier = [item valueForKey:@"identifier"];
                    for (id existing in gHarvestedPlugins) {
                        if ([[existing valueForKey:@"identifier"] isEqualToString:identifier]) { exists = YES; break; }
                    }
                    if (!exists) [gHarvestedPlugins addObject:item];
                } else {
                    [filteredItems addObject:item]; // 不是插件的选项，还给抖音原生列表
                }
            }
            [section setValue:filteredItems forKey:@"itemArray"];
            if (filteredItems.count > 0 || items.count == 0) {
                [finalSections addObject:section];
            }
        }
    }

    // 检查是否在设置主页（我们只在主页注入唯一入口）
    BOOL isMainPage = NO;
    for (id s in finalSections) {
        NSString *title = [s valueForKey:@"sectionHeaderTitle"];
        if ([title isEqualToString:@"账号"] || [title isEqualToString:@"关于抖音"]) {
            isMainPage = YES;
            break;
        }
    }

    if (isMainPage) {
        AWESettingItemModel *entry = [[%c(AWESettingItemModel) alloc] init];
        entry.identifier = @"DYPluginMgr";
        entry.title = @"收纳"; 
        entry.detail = [NSString stringWithFormat:@"已收纳 %lu 个", (unsigned long)gHarvestedPlugins.count];
        entry.type = 0;
        entry.svgIconImageName = @"ic_gearsimplify_outlined_20";
        entry.cellType = 26; 
        entry.colorStyle = 0;
        entry.isEnable = YES;

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
        mgrSection.sectionHeaderTitle = @"收纳"; 
        [finalSections insertObject:mgrSection atIndex:0];
    }
    
    return finalSections;
}
%end

// ==========================================
// 6. 强穿透手势识别代理 (解决手势被点赞吃掉的问题)
// ==========================================
@interface DYPluginGestureDelegate : NSObject <UIGestureRecognizerDelegate>
+ (instancetype)sharedInstance;
@end

@implementation DYPluginGestureDelegate
+ (instancetype)sharedInstance {
    static DYPluginGestureDelegate *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}
// 【绝对核心】：强制允许我们的三连击手势与抖音自带的滑动、点赞等手势同时触发！
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}
@end

// ==========================================
// 7. 挂载全局手势唤出
// ==========================================
%hook UIWindow

- (void)becomeKeyWindow {
    %orig;
    
    BOOL hasGesture = NO;
    for (UIGestureRecognizer *g in self.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]] && ((UITapGestureRecognizer *)g).numberOfTapsRequired == 3) {
            hasGesture = YES;
            break;
        }
    }
    
    if (!hasGesture) {
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dyplugin_tap:)];
        tap.numberOfTapsRequired = 3; 
        
        // 绑定强穿透代理
        tap.delegate = [DYPluginGestureDelegate sharedInstance]; 
        // 禁止吃掉触摸事件，保证抖音本身的逻辑正常运转
        tap.cancelsTouchesInView = NO; 
        tap.delaysTouchesEnded = NO;
        
        [self addGestureRecognizer:tap];
    }
}

%new
- (void)dyplugin_tap:(UITapGestureRecognizer *)sender {
    if (sender.state == UIGestureRecognizerStateRecognized) {
        UIViewController *topVC = self.rootViewController;
        while (topVC.presentedViewController) {
            topVC = topVC.presentedViewController;
        }
        ShowPluginManagerPage(topVC);
    }
}

%end
