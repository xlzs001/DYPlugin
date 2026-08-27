#import <UIKit/UIKit.h>
#import "DYPluginsMgr.h"
#import "DYPluginsViewController.h"

@interface AWESettingsViewController : UIViewController
@end

static void initAllPlugins() {
    DYPluginsMgr *mgr = [DYPluginsMgr sharedInstance];
    [mgr registerControllerWithTitle:@"DYYY 设置" version:@"v1.2" controller:@"DYYYSettingsViewController"];
    [mgr registerSwitchWithTitle:@"无水印下载" key:@"DY_KEY_NO_WATERMARK"];
    [mgr registerSwitchWithTitle:@"自动连播" key:@"DY_KEY_AUTO_PLAY"];
}

%hook AWESettingsViewController

- (void)viewDidLoad {
    %orig;
    
    UIButton *pluginBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [pluginBtn setTitle:@"⚙️插件" forState:UIControlStateNormal];
    pluginBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [pluginBtn sizeToFit];
    
    [pluginBtn addTarget:self action:@selector(openDYPluginMgr_xy) forControlEvents:UIControlEventTouchUpInside];
    
    UIBarButtonItem *rightItem = [[UIBarButtonItem alloc] initWithCustomView:pluginBtn];
    
    // 强制转换为 UIViewController 彻底解决编译器不认识属性的问题
    ((UIViewController *)self).navigationItem.rightBarButtonItem = rightItem;
}

%new
- (void)openDYPluginMgr_xy {
    DYPluginsViewController *pluginVC = [[DYPluginsViewController alloc] init];
    pluginVC.hidesBottomBarWhenPushed = YES; 
    // 同样强制转换为 UIViewController 进行 push 跳转
    [((UIViewController *)self).navigationController pushViewController:pluginVC animated:YES];
}

%end

%ctor {
    @autoreleasepool {
        initAllPlugins();
    }
}
