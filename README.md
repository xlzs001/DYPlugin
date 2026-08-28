# 🛠️ DYPluginMgr (抖音插件收纳中枢)

DYPluginMgr 是一个专为抖音 (Douyin) 越狱/注入环境设计的**第三方插件统一管理中枢**。

随着抖音第三方插件（如 DYYY、DYKiller 等）的增多，用户的抖音设置页面会被各种插件入口塞满，导致界面杂乱。本插件致力于提供一个统一的接口与 UI，将所有第三方插件的设置入口收纳进一个统一的菜单中，还用户一个纯净的原生设置页面。

## ✨ 核心特性

- **无感收纳**：自动拦截并隐藏抖音设置主页中杂乱的第三方插件入口。
- **统一调度**：提供统一的底部 ActionSheet 或独立列表框，集中唤起各插件设置页。
- **极简架构**：基于底层 `AWESettingsViewModel` 数据源拦截，免疫界面动态刷新。
- **开放生态**：提供标准化 Runtime 注册接口，完美兼容具有独立 UI 或基于 Block 动态生成的各类高级插件。

---

## 💻 开发者适配指南 (API)

如果你也是抖音插件的开发者，欢迎接入 DYPluginMgr。接入本中枢**无需导入任何头文件**，不会对你的项目产生硬依赖。

目前提供两种接入方式：

### 方式一：主动注册（推荐，支持所有高级插件）
适用于使用自定义 ViewController，或者使用函数/Block 动态生成设置界面的插件（如 DYKiller）。

在你的 `Tweak.x` (或任何入口文件) 的 `%ctor` 初始化阶段，使用 Runtime 探测并调用中枢的 `registerActionWithTitle:version:action:` 方法：

```objc
%ctor {
    @autoreleasepool {
        // 1. 探测用户的设备是否安装了 DYPluginMgr
        if (NSClassFromString(@"DYPluginsMgr")) {
            id mgr = [NSClassFromString(@"DYPluginsMgr") performSelector:@selector(sharedInstance)];
            
            // 2. 准备调用注册 Block 的接口
            SEL regSel = NSSelectorFromString(@"registerActionWithTitle:version:action:");
            if ([mgr respondsToSelector:regSel]) {
                NSMethodSignature *sig = [mgr methodSignatureForSelector:regSel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:mgr];
                [inv setSelector:regSel];
                
                // 3. 填入你的插件信息
                NSString *title = @"你的插件名称";
                NSString *version = @"v1.0.0";
                
                // 4. 将你的设置页面弹出逻辑写进 Block
                void (^actionBlock)(void) = ^{
                    // 这里写你平时怎么弹出设置页的代码
                    // 例如: 
                    // UIViewController *topVC = [UIApplication sharedApplication].windows.firstObject.rootViewController;
                    // MySettingsViewController *vc = [[MySettingsViewController alloc] init];
                    // [topVC presentViewController:vc animated:YES completion:nil];
                };
                
                // 5. 传参并执行注册
                [inv setArgument:&title atIndex:2];
                [inv setArgument:&version atIndex:3];
                [inv setArgument:&actionBlock atIndex:4];
                [inv invoke];
            }
        }
    }
}

##  如果你使用的是传统的类名跳转，中枢同样保留了 registerControllerWithTitle:version:controller: 接口，传参方式同理。

##  方式二：被动收割（无需写代码，基于原生 Hook）
如果你的插件是通过 Hook AWESettingsViewModel 的 sectionDataArray 将入口直接写入抖音设置页面的，你可以不需要修改一行代码。

你只需要在此仓库提交一个 Pull Request，将你的区块标题（sectionHeaderTitle）加入本项目的 targetPlugins 拦截白名单中即可。

Objective-C
// DYPluginMgr 会自动识别白名单中的标题，并将点击事件无缝劫持到收纳中枢里
NSArray *targetPlugins = @[
    @"DYYY", 
    @"DYKiller", 
    @"你的插件区块标题" // 在这里加上你的标题
];

##  📥 用户安装与使用
下载最新 Release 中的 .dylib 或 .deb 产物。

随同其他抖音插件一起注入进抖音应用。

打开抖音 -> 设置，即可在最上方看到 🛠️ 插件收纳中枢。

##  📄 License
本项目基于 MIT 许可证开源。允许自由学习、交流与二次开发。
