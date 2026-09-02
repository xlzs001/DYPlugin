# DYStorage（抖音插件收纳）

DYStorage 是注入抖音的 Theos tweak。它把兼容第三方插件散落在抖音“设置”主页的入口收进一个单独的“插件收纳”入口，同时保留原插件的点击回调，因此点进收纳页后仍然打开各插件原本的设置页面。

这个项目的目标是**整理插件设置**，不是修改抖音官方“收藏夹”或上传任何作品数据。

## 做了什么

- 在抖音设置主页插入一个原生样式的“插件收纳” section；使用稳定的 identifier 防止重复插入。
- 识别 DYYY（`huami1314/DYYY` 和 `pxx917144686/DYYY` 当前都使用的独立 `DYYY` section）以及一组常见插件根入口。
- 收纳 DYYY 等已知插件的**单项根入口 section**；对于混在普通 section 里的已知插件项，只有能安全复制原 section 时才剔除目标项，绝不原地改写其他 tweak 的模型。
- 复用被收纳 `AWESettingItemModel` 的原始 `cellTappedBlock`，不需要猜测 DYYY 的设置控制器类名。
- 提供可实际调用的运行时注册 API，供没有标准设置 section 的插件主动接入。
- 收纳页顶部提供“🔍 插件搜索”，可按插件名称或版本号搜索所有已收纳、主动接入的插件。
- 收纳页底部显示版本、作者、版权和可点击的 GitHub 仓库地址。
- 启动后在主线程延迟安装 Hook，让 `%orig` 通常能看到 DYYY 已经插入的 section；另有仅匹配“单项根入口”的 section-model 兜底，以处理后装载 Hook 追加的同类入口。

不做的事情：不扫描 `UIWindow` / `UIView`，不拦截悬浮球，不模糊匹配普通页面文本，也不接管抖音的收藏网络请求。这些做法容易误伤正常 UI 或在版本更新后崩溃。

## 兼容性与边界

抖音的 `AWESettingsViewModel`、`AWESettingItemModel`、`AWESettingSectionModel` 都是私有实现，任何抖音版本升级都可能改变它们。DYStorage 在运行时检查类和 selector，缺少目标时不会安装对应 Hook；这避免了直接崩溃，但不能替代真机验证。

目前主页判定优先看“账号 / 账户 / Account / General”等根设置 section，也会尝试 section identifier 中的 `account` / `setting` 组合。这与 `huami1314/DYYY` 的“账号”保护一致，但比无条件向所有 `AWESettingsViewModel` 注入更保守。

默认被动收纳名单在 [`Tweak.xm`](Tweak.xm) 的 `DYStorageKnownPluginTitles` 中。高级用户可在进程的 `NSUserDefaults` 中以字符串数组设置 `DYStorageTargetPluginTitles`，添加自己已验证的**设置根入口标题**；不要填写泛化词，例如“设置”或“助手”。

## 给插件作者的主动接入方式

首选注册一个负责展示你自己设置页的 block。不要把控制器或 view model 对象保存到全局；只在用户点击时创建或展示它。

DYStorage 没有要求其他 tweak 链接它。下面的 Logos / Objective-C 示例通过运行时调用，DYStorage 未安装时会自然跳过：

```objc
%ctor {
    Class managerClass = NSClassFromString(@"DYStorageManager");
    SEL sharedSelector = NSSelectorFromString(@"sharedManager");
    if (!managerClass || ![managerClass respondsToSelector:sharedSelector]) return;

    id manager = ((id (*)(id, SEL))objc_msgSend)(managerClass, sharedSelector);
    SEL registerSelector = NSSelectorFromString(@"registerActionWithIdentifier:title:version:action:");
    if (![manager respondsToSelector:registerSelector]) return;

    NSString *identifier = @"com.example.my-tweak";
    NSString *title = @"我的插件";
    NSString *version = @"1.0.0";
    void (^openSettings)(void) = ^{
        // 在主线程创建并展示你的设置控制器。
    };

    NSMethodSignature *signature = [manager methodSignatureForSelector:registerSelector];
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
    invocation.target = manager;
    invocation.selector = registerSelector;
    [invocation setArgument:&identifier atIndex:2];
    [invocation setArgument:&title atIndex:3];
    [invocation setArgument:&version atIndex:4];
    [invocation setArgument:&openSettings atIndex:5];
    [invocation invoke];
}
```

可用的接口定义见 [`DYStorageManager.h`](DYStorageManager.h)：

- `registerActionWithIdentifier:title:version:action:`
- `registerControllerWithIdentifier:title:version:controller:`
- `registerActionWithTitle:version:action:`（兼容没有稳定 identifier 的旧集成）
- `unregisterPluginWithIdentifier:`

## 构建

本地需要 Theos、iOS SDK 和 `ldid`：

```sh
make package FINALPACKAGE=1
```

GitHub Actions 会在 `main` 的任意源码、配置或工作流变更上分别构建 Rootful 和 Rootless 两种版本，生成版本化 `.deb` 并作为 `DYStorage-Packages-rootful`、`DYStorage-Packages-rootless` artifact 上传。工作流使用 Node 24 运行时的 `actions/checkout@v6` 与 `actions/upload-artifact@v6`，同时在找不到 `.deb` 时明确失败，避免误报成功。

## 参考

实现思路参考了 [huami1314/DYYY](https://github.com/huami1314/DYYY) 与 [pxx917144686/DYYY](https://github.com/pxx917144686/DYYY) 的设置入口 Hook：两者都会构建独立的 `AWESettingSectionModel` 并插入 `AWESettingsViewModel.sectionDataArray` 的首位。DYStorage 没有复制其设置页代码；它只保留已生成 entry 的原始回调。

本项目采用 [MIT License](LICENSE)。
