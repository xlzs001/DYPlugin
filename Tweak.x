#import <UIKit/UIKit.h>
#import "DYPluginsMgr.h"
#import "DYPluginsViewController.h"

// 提前声明抖音原生的 Model 类，防止编译器报错
@interface AWESettingItemModel : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, assign) NSInteger cellType;
@property (nonatomic, assign) BOOL isEnable;
@property (nonatomic, copy) void (^cellTappedBlock)(void);
@end

@interface AWESettingSectionModel : NSObject
@property (nonatomic, copy) NSString *sectionHeaderTitle;
@property (nonatomic, assign) CGFloat sectionHeaderHeight;
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, strong) NSArray *itemArray;
@end

@interface AWESettingsViewModel : NSObject
// ViewModel 会持有当前的视图控制器，方便我们跳转
@property (nonatomic, weak) UIViewController *controllerDelegate;
@end


// 初始化你的插件中枢
static void initAllPlugins() {
    DYPluginsMgr *mgr = [DYPluginsMgr sharedInstance];
    
    // 这里依然是你主动收纳 DYYY 等插件的地方
    [mgr registerControllerWithTitle:@"DYYY 增强设置" version:@"稳定版" controller:@"DYYYSettingsViewController"];
}

// 拦截 ViewModel，从数据源头强行注入，免疫任何界面刷新
%hook AWESettingsViewModel

- (NSArray *)sectionDataArray {
    // 拿到抖音原生本来要显示的菜单数组
    NSArray *originalSections = %orig;
    
    BOOL hasMyPlugin = NO;
    BOOL isMainSettingsPage = NO;

    // 遍历检查：看看是不是设置页主页（有“账号”这栏），以及是不是已经有我们的菜单了
    for (AWESettingSectionModel *section in originalSections) {
        if ([section.sectionHeaderTitle isEqualToString:@"插件收纳"]) {
            hasMyPlugin = YES;
        }
        if ([section.sectionHeaderTitle isEqualToString:@"账号"]) {
            isMainSettingsPage = YES;
        }
    }

    // 确认是主设置页，且还没添加过，就创建我们的专属菜单
    if (isMainSettingsPage && !hasMyPlugin) {
        // 1. 创建属于我们的点击项 (Item)
        AWESettingItemModel *pluginItem = [[%c(AWESettingItemModel) alloc] init];
        pluginItem.identifier = @"DYPluginMgr_Entrance";
        pluginItem.title = @"🛠️ 插件收纳中枢";
        pluginItem.type = 0;
        pluginItem.cellType = 26; // 抖音原生的标准“向右箭头”Cell样式
        pluginItem.isEnable = YES;

        __weak typeof(self) weakSelf = self;
        pluginItem.cellTappedBlock = ^{
            // 从 ViewModel 里反向拿到当前的 ViewController 用来做页面跳转
            UIViewController *rootVC = nil;
            if ([weakSelf respondsToSelector:@selector(controllerDelegate)]) {
                rootVC = weakSelf.controllerDelegate;
            }

            if (rootVC && rootVC.navigationController) {
                DYPluginsViewController *pluginVC = [[DYPluginsViewController alloc] init];
                pluginVC.hidesBottomBarWhenPushed = YES;
                [rootVC.navigationController pushViewController:pluginVC animated:YES];
            }
        };

        // 2. 将点击项包装成一个区块 (Section)
        AWESettingSectionModel *newSection = [[%c(AWESettingSectionModel) alloc] init];
        newSection.sectionHeaderTitle = @"插件收纳";
        newSection.sectionHeaderHeight = 40;
        newSection.type = 0;
        newSection.itemArray = @[pluginItem];

        // 3. 把我们的区块强势插入到原数组的第一个位置
        NSMutableArray *newSections = [NSMutableArray arrayWithArray:originalSections];
        [newSections insertObject:newSection atIndex:0];
        
        return newSections;
    }

    return originalSections;
}

%end

%ctor {
    @autoreleasepool {
        initAllPlugins();
    }
}
