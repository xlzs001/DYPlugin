#import <UIKit/UIKit.h>
#import "DYPluginsMgr.h"
#import "DYPluginsViewController.h"

// 在这里集中注册你的插件
static void initAllPlugins() {
    DYPluginsMgr *mgr = [DYPluginsMgr sharedInstance];
    
    // 示例：注册独立子页面（如 DYYY 的设置页）
    [mgr registerControllerWithTitle:@"DYYY 设置" version:@"v1.2" controller:@"DYYYSettingsViewController"];
    
    // 示例：注册独立功能开关
    [mgr registerSwitchWithTitle:@"无水印下载" key:@"DY_KEY_NO_WATERMARK"];
    [mgr registerSwitchWithTitle:@"自动连播" key:@"DY_KEY_AUTO_PLAY"];
}

// Hook 抖音设置控制器
%hook AWESettingsViewController

- (void)viewDidLoad {
    %orig;
    
    NSMutableArray *sectionDataArray = [self valueForKey:@"sectionDataArray"];
    if (!sectionDataArray || ![sectionDataArray isKindOfClass:[NSMutableArray class]]) {
        return;
    }
    
    Class itemModelClass = NSClassFromString(@"AWESettingItemModel");
    if (!itemModelClass) return;
    
    id managerItem = [[itemModelClass alloc] init];
    if ([managerItem respondsToSelector:@selector(setTitle:)]) {
        [managerItem setValue:@"🛠️ 插件收纳中枢" forKey:@"title"];
    }
    
    __weak typeof(self) weakSelf = self;
    if ([managerItem respondsToSelector:@selector(setCellTappedBlock:)]) {
        void (^tapBlock)(void) = ^{
            DYPluginsViewController *pluginVC = [[DYPluginsViewController alloc] init];
            [weakSelf.navigationController pushViewController:pluginVC animated:YES];
        };
        [managerItem setValue:tapBlock forKey:@"cellTappedBlock"];
    }
    
    NSMutableArray *firstSection = [sectionDataArray firstObject];
    if ([firstSection isKindOfClass:[NSMutableArray class]]) {
        [firstSection insertObject:managerItem atIndex:0];
    }
    
    UITableView *tableView = [self valueForKey:@"tableView"];
    if (tableView) {
        [tableView reloadData];
    }
}

%end

%ctor {
    @autoreleasepool {
        initAllPlugins();
    }
}
