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
    
    // 延迟 1 秒执行，确保抖音原生的界面完全加载完毕后再强制盖在最上面
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIViewController *vc = (UIViewController *)self;
        
        // 创建一个圆形的悬浮球
        UIButton *floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        
        // 获取屏幕宽高，固定在屏幕右下角区域
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        CGFloat screenHeight = [UIScreen mainScreen].bounds.size.height;
        floatBtn.frame = CGRectMake(screenWidth - 80, screenHeight - 160, 60, 60);
        
        // 设置悬浮球的 UI 样式（半透明黑底白字）
        floatBtn.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
        [floatBtn setTitle:@"插件" forState:UIControlStateNormal];
        [floatBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        floatBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
        floatBtn.layer.cornerRadius = 30; // 圆形
        floatBtn.layer.masksToBounds = YES;
        
        // 绑定点击事件
        [floatBtn addTarget:self action:@selector(openDYPluginMgr_xy) forControlEvents:UIControlEventTouchUpInside];
        
        // 强行贴到当前视图的最顶层
        [vc.view addSubview:floatBtn];
        [vc.view bringSubviewToFront:floatBtn];
    });
}

%new
- (void)openDYPluginMgr_xy {
    DYPluginsViewController *pluginVC = [[DYPluginsViewController alloc] init];
    pluginVC.hidesBottomBarWhenPushed = YES; 
    [((UIViewController *)self).navigationController pushViewController:pluginVC animated:YES];
}

%end

%ctor {
    @autoreleasepool {
        initAllPlugins();
    }
}
