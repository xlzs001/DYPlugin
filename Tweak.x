#import <UIKit/UIKit.h>
#import "DYPluginsMgr.h"
#import "DYPluginsViewController.h"

static void initAllPlugins() {
    DYPluginsMgr *mgr = [DYPluginsMgr sharedInstance];
    [mgr registerControllerWithTitle:@"DYYY 设置" version:@"v1.2" controller:@"DYYYSettingsViewController"];
    [mgr registerSwitchWithTitle:@"无水印下载" key:@"DY_KEY_NO_WATERMARK"];
    [mgr registerSwitchWithTitle:@"自动连播" key:@"DY_KEY_AUTO_PLAY"];
}

%hook AWESettingsViewController

- (void)viewDidLoad {
    %orig;
    
    // 强行在导航栏右侧添加一个独立的“插件”按钮，免疫列表数据刷新
    UIButton *pluginBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [pluginBtn setTitle:@"⚙️插件" forState:UIControlStateNormal];
    pluginBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [pluginBtn sizeToFit];
    
    // 绑定点击事件
    [pluginBtn addTarget:self action:@selector(openDYPluginMgr_xy) forControlEvents:UIControlEventTouchUpInside];
    
    UIBarButtonItem *rightItem = [[UIBarButtonItem alloc] initWithCustomView:pluginBtn];
    self.navigationItem.rightBarButtonItem = rightItem;
}

// 利用 %new 动态为该控制器添加我们自定义的跳转方法
%new
- (void)openDYPluginMgr_xy {
    DYPluginsViewController *pluginVC = [[DYPluginsViewController alloc] init];
    // 隐藏底部 TabBar 保证页面清爽
    pluginVC.hidesBottomBarWhenPushed = YES; 
    [self.navigationController pushViewController:pluginVC animated:YES];
}

%end

%ctor {
    @autoreleasepool {
        initAllPlugins();
    }
}
