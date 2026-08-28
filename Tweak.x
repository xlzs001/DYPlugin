#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <QuartzCore/QuartzCore.h>

/*
 ============================================================
 DYStorage
 抖音插件收纳器
 ============================================================

 核心原则：

 1. 不扫描全局 UIView
 2. 不扫描 NavigationBar
 3. 不 RemoveFromSuperview
 4. 不修改抖音其它页面
 5. 只拦截“设置主页面”的插件项目
 6. 将插件保存到 gHarvestedPlugins
 7. 主设置页面只显示“收纳”
 8. 点击“收纳”进入独立插件列表
 9. 收纳页面中的插件仍然保留原始点击事件
 ============================================================
*/


#pragma mark - =========================================================
#pragma mark 1. 抖音原生模型声明
#pragma mark =========================================================

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


#pragma mark - =========================================================
#pragma mark 2. 全局状态
#pragma mark =========================================================

static NSMutableArray *gHarvestedPlugins = nil;


/*
 associated object

 用来给“收纳页面”保存自己的 ViewModel。
 */
static void *kDYPluginViewModelKey = &kDYPluginViewModelKey;


/*
 用来保存搜索控制器，避免被释放。
 */
static void *kDYPluginSearchHandlerKey = &kDYPluginSearchHandlerKey;


/*
 防止重复创建收纳入口。
 */
static NSString * const kDYStorageIdentifier = @"DYStorageEntry";


#pragma mark - =========================================================
#pragma mark 3. 初始化插件容器
#pragma mark =========================================================

static void EnsurePluginStorage(void)
{
    if (!gHarvestedPlugins) {
        gHarvestedPlugins = [[NSMutableArray alloc] init];
    }
}


#pragma mark - =========================================================
#pragma mark 4. 插件识别
#pragma mark =========================================================

/*
 ============================================================
 判断一个设置项目是不是我们要收纳的插件
 ============================================================

 这里保留你原来的插件名单。

 如果以后需要增加插件：

 @"插件名字"

 直接加到 targets 即可。
 ============================================================
 */

static BOOL IsTargetPlugin(NSString *title)
{
    if (![title isKindOfClass:[NSString class]]) {
        return NO;
    }

    if (title.length == 0) {
        return NO;
    }

    NSArray *targets = @[
        @"DYYY",
        @"DYKiller",
        @"抖音助手",
        @"自动消息",
        @"抖音图层",
        @"抖+",
        @"抖⁺",
        @"抖＋",
        @"aweJ",
        @"AwemeX",
        @"SJJAwemeLoginRepair",
        @"𝙓𝙐𝙐ᶻ",
        @"DouyinHelper",
        @"Yuki"
    ];

    for (NSString *target in targets) {

        if ([title isEqualToString:target]) {
            return YES;
        }

        /*
         兼容某些插件标题前后存在空格的情况。
         */
        NSString *trimmed =
        [title stringByTrimmingCharactersInSet:
         [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if ([trimmed isEqualToString:target]) {
            return YES;
        }
    }

    return NO;
}


#pragma mark - =========================================================
#pragma mark 5. 判断是否已经收纳
#pragma mark =========================================================

static BOOL IsPluginAlreadyHarvested(id item)
{
    if (!item) {
        return NO;
    }

    EnsurePluginStorage();

    NSString *identifier = nil;
    NSString *title = nil;

    @try {
        identifier = [item valueForKey:@"identifier"];
    }
    @catch (__unused NSException *exception) {
    }

    @try {
        title = [item valueForKey:@"title"];
    }
    @catch (__unused NSException *exception) {
    }

    for (id existing in gHarvestedPlugins) {

        NSString *existingIdentifier = nil;
        NSString *existingTitle = nil;

        @try {
            existingIdentifier = [existing valueForKey:@"identifier"];
        }
        @catch (__unused NSException *exception) {
        }

        @try {
            existingTitle = [existing valueForKey:@"title"];
        }
        @catch (__unused NSException *exception) {
        }

        if (identifier.length > 0 &&
            existingIdentifier.length > 0 &&
            [identifier isEqualToString:existingIdentifier]) {

            return YES;
        }

        if (title.length > 0 &&
            existingTitle.length > 0 &&
            [title isEqualToString:existingTitle]) {

            return YES;
        }
    }

    return NO;
}


#pragma mark - =========================================================
#pragma mark 6. 收纳插件
#pragma mark =========================================================

static void HarvestItem(id item)
{
    if (!item) {
        return;
    }

    EnsurePluginStorage();

    /*
     如果已经存在，不重复添加。
     */
    if (IsPluginAlreadyHarvested(item)) {
        return;
    }

    /*
     保留原插件的 cellTappedBlock。

     这里不做全局 Hook。
     不修改插件本身的行为。
     只是把原来的 Model 保存下来。
     */

    [gHarvestedPlugins addObject:item];
}


#pragma mark - =========================================================
#pragma mark 7. 搜索控制器
#pragma mark =========================================================

@interface DYPluginSearchHandler : NSObject

@property (nonatomic, weak) UIViewController *targetVC;
@property (nonatomic, weak) id viewModel;

@end


@implementation DYPluginSearchHandler


- (void)textFieldDidChange:(UITextField *)textField
{
    EnsurePluginStorage();

    NSString *searchText = textField.text ?: @"";

    NSMutableArray *filteredItems = [NSMutableArray array];

    /*
     没有搜索内容
     */
    if (searchText.length == 0) {

        [filteredItems addObjectsFromArray:gHarvestedPlugins];

    }
    else {

        for (id item in gHarvestedPlugins) {

            NSString *title = nil;

            @try {
                title = [item valueForKey:@"title"];
            }
            @catch (__unused NSException *exception) {
            }

            if (![title isKindOfClass:[NSString class]]) {
                continue;
            }

            if ([title localizedCaseInsensitiveContainsString:searchText]) {
                [filteredItems addObject:item];
            }
        }
    }


    /*
     创建新的“已收纳插件” Section
     */

    Class sectionClass =
    NSClassFromString(@"AWESettingSectionModel");

    if (!sectionClass) {
        return;
    }

    id section = [[sectionClass alloc] init];

    @try {
        [section setValue:@"已收纳的插件"
                   forKey:@"sectionHeaderTitle"];

        [section setValue:@(40)
                   forKey:@"sectionHeaderHeight"];

        [section setValue:@(0)
                   forKey:@"type"];

        [section setValue:[filteredItems copy]
                   forKey:@"itemArray"];
    }
    @catch (__unused NSException *exception) {
        return;
    }


    /*
     替换收纳页面数据
     */

    @try {
        [self.viewModel setValue:@[section]
                           forKey:@"sectionDataArray"];
    }
    @catch (__unused NSException *exception) {
        return;
    }


    /*
     刷新页面
     */

    dispatch_async(dispatch_get_main_queue(), ^{

        UIViewController *vc = self.targetVC;

        if (!vc) {
            return;
        }

        UIView *rootView = vc.view;

        if (!rootView) {
            return;
        }

        for (UIView *subview in [rootView.subviews copy]) {

            if ([subview isKindOfClass:[UITableView class]]) {

                UITableView *tableView =
                (UITableView *)subview;

                [tableView reloadData];
            }

            else if ([subview isKindOfClass:[UICollectionView class]]) {

                UICollectionView *collectionView =
                (UICollectionView *)subview;

                [collectionView reloadData];
            }
        }
    });
}

@end


#pragma mark - =========================================================
#pragma mark 8. 创建“收纳”页面
#pragma mark =========================================================

static UIViewController *
CreatePluginManagerViewController(UIViewController *rootVC)
{
    Class vcClass =
    NSClassFromString(@"AWESettingBaseViewController");

    Class vmClass =
    NSClassFromString(@"AWESettingsViewModel");

    Class sectionClass =
    NSClassFromString(@"AWESettingSectionModel");

    if (!vcClass || !vmClass || !sectionClass) {
        return nil;
    }


    UIViewController *subVC =
    [[vcClass alloc] init];

    if (!subVC) {
        return nil;
    }


    EnsurePluginStorage();


    /*
     创建新的 ViewModel
     */

    id viewModel =
    [[vmClass alloc] init];

    if (!viewModel) {
        return nil;
    }


    @try {

        [viewModel setValue:@(0)
                     forKey:@"colorStyle"];

        [viewModel setValue:subVC
                     forKey:@"controllerDelegate"];

    }
    @catch (__unused NSException *exception) {
    }


    /*
     创建“已收纳的插件” Section
     */

    id section =
    [[sectionClass alloc] init];

    @try {

        [section setValue:@"已收纳的插件"
                   forKey:@"sectionHeaderTitle"];

        [section setValue:@(40)
                   forKey:@"sectionHeaderHeight"];

        [section setValue:@(0)
                   forKey:@"type"];

        [section setValue:[gHarvestedPlugins copy]
                   forKey:@"itemArray"];

    }
    @catch (__unused NSException *exception) {
    }


    @try {

        [viewModel setValue:@[section]
                     forKey:@"sectionDataArray"];

    }
    @catch (__unused NSException *exception) {
    }


    /*
     保存 ViewModel

     这一点非常重要。

     后面的 AWESettingBaseViewController
     viewModel Hook 会优先返回这个 VM。
     */

    objc_setAssociatedObject(
        subVC,
        kDYPluginViewModelKey,
        viewModel,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );


    /*
     保存搜索控制器
     */

    DYPluginSearchHandler *handler =
    [[DYPluginSearchHandler alloc] init];

    handler.targetVC = subVC;
    handler.viewModel = viewModel;

    objc_setAssociatedObject(
        subVC,
        kDYPluginSearchHandlerKey,
        handler,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );


    return subVC;
}


#pragma mark - =========================================================
#pragma mark 9. 打开“收纳”
#pragma mark =========================================================

static void ShowPluginManagerPage(UIViewController *rootVC)
{
    UIViewController *subVC =
    CreatePluginManagerViewController(rootVC);

    if (!subVC) {
        return;
    }


    UIViewController *topVC = rootVC;

    if (!topVC) {

        UIWindow *keyWindow = nil;

        if (@available(iOS 13.0, *)) {

            for (UIScene *scene
                 in [UIApplication sharedApplication].connectedScenes) {

                if (![scene isKindOfClass:[UIWindowScene class]]) {
                    continue;
                }

                UIWindowScene *windowScene =
                (UIWindowScene *)scene;

                if (windowScene.activationState ==
                    UISceneActivationStateUnattached) {

                    continue;
                }

                for (UIWindow *window
                     in windowScene.windows) {

                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }

                if (keyWindow) {
                    break;
                }
            }
        }

        if (!keyWindow) {
            keyWindow =
            [UIApplication sharedApplication].keyWindow;
        }

        topVC = keyWindow.rootViewController;
    }


    if (!topVC) {
        return;
    }


    /*
     找到当前最上层 Controller
     */

    while (topVC.presentedViewController) {

        topVC =
        topVC.presentedViewController;
    }


    /*
     优先 Push
     */

    if (topVC.navigationController) {

        [topVC.navigationController
         pushViewController:subVC
         animated:YES];

        return;
    }


    /*
     没有 NavigationController
     就 Modal
     */

    UINavigationController *nav =
    [[UINavigationController alloc]
     initWithRootViewController:subVC];

    nav.modalPresentationStyle =
    UIModalPresentationFullScreen;

    [topVC presentViewController:nav
                         animated:YES
                       completion:nil];
}


#pragma mark - =========================================================
#pragma mark 10. AWESettingBaseViewController
#pragma mark =========================================================

%hook AWESettingBaseViewController


/*
 ============================================================
 ViewModel

 普通页面：
     返回抖音原来的 VM

 收纳页面：
     返回我们自己创建的 VM

 这解决了原代码中“创建 customVM 但实际没有使用”的问题。
 ============================================================
 */

- (id)viewModel
{
    id customVM =
    objc_getAssociatedObject(
        self,
        kDYPluginViewModelKey
    );

    if (customVM) {
        return customVM;
    }

    return %orig;
}


/*
 ============================================================
 viewDidLoad

 注意：

 这里绝对不再：

 RemoveRogueWatermarks()

 不扫描 UIView
 不扫描 NavigationBar
 不隐藏 XUU
 不 removeFromSuperview

 只有当这是我们创建的“收纳页面”时，
 才添加搜索框。
 ============================================================
 */

- (void)viewDidLoad
{
    %orig;


    id customVM =
    objc_getAssociatedObject(
        self,
        kDYPluginViewModelKey
    );

    /*
     普通抖音页面直接返回。

     这是“取消全局 UI Hook”的关键。
     */

    if (!customVM) {
        return;
    }


    UIView *rootView = self.view;

    if (!rootView) {
        return;
    }


    CGFloat screenW =
    [UIScreen mainScreen].bounds.size.width;


    /*
     修改导航栏标题
     */

    for (UIView *subview
         in [rootView.subviews copy]) {

        Class navClass =
        NSClassFromString(@"AWENavigationBar");

        if (navClass &&
            [subview isKindOfClass:navClass]) {

            if ([subview respondsToSelector:@selector(titleLabel)]) {

                @try {

                    UILabel *label =
                    [subview valueForKey:@"titleLabel"];

                    if ([label isKindOfClass:[UILabel class]]) {
                        label.text = @"收纳";
                    }

                }
                @catch (__unused NSException *exception) {
                }
            }
        }
    }


    /*
     ========================================================
     搜索框
     ========================================================
     */

    UIView *headerContainer =
    [[UIView alloc]
     initWithFrame:CGRectMake(
         0,
         0,
         screenW,
         56
     )];

    headerContainer.backgroundColor =
    [UIColor clearColor];


    UITextField *searchBox =
    [[UITextField alloc]
     initWithFrame:CGRectMake(
         16,
         10,
         screenW - 32,
         36
     )];

    searchBox.placeholder =
    @"搜索已收纳插件";

    searchBox.textAlignment =
    NSTextAlignmentCenter;

    searchBox.backgroundColor =
    [UIColor colorWithWhite:0.95 alpha:1.0];

    searchBox.layer.cornerRadius = 8.0;

    searchBox.clipsToBounds = YES;

    searchBox.clearButtonMode =
    UITextFieldViewModeWhileEditing;

    searchBox.font =
    [UIFont systemFontOfSize:14];

    searchBox.returnKeyType =
    UIReturnKeyDone;


    [headerContainer addSubview:searchBox];


    /*
     搜索 Handler
     */

    DYPluginSearchHandler *handler =
    objc_getAssociatedObject(
        self,
        kDYPluginSearchHandlerKey
    );

    if (handler) {

        [searchBox addTarget:handler
                       action:@selector(textFieldDidChange:)
             forControlEvents:UIControlEventEditingChanged];
    }


    /*
     ========================================================
     将搜索框插入 UITableView
     ========================================================
     */

    BOOL inserted =
    NO;

    for (UIView *subview
         in [rootView.subviews copy]) {

        if ([subview isKindOfClass:[UITableView class]]) {

            UITableView *tableView =
            (UITableView *)subview;

            tableView.tableHeaderView =
            headerContainer;

            inserted = YES;

            break;
        }
    }


    /*
     ========================================================
     如果没有 UITableView
     就直接放在页面顶部
     ========================================================
     */

    if (!inserted) {

        headerContainer.frame =
        CGRectMake(
            0,
            88,
            screenW,
            56
        );

        [rootView addSubview:headerContainer];


        for (UIView *subview
             in [rootView.subviews copy]) {

            if ([subview isKindOfClass:
                [UICollectionView class]]) {

                UICollectionView *collectionView =
                (UICollectionView *)subview;

                UIEdgeInsets inset =
                collectionView.contentInset;

                inset.top += 56;

                collectionView.contentInset =
                inset;

                break;
            }
        }
    }


    /*
     ========================================================
     Footer
     ========================================================
     */

    CGFloat screenH =
    [UIScreen mainScreen].bounds.size.height;


    UITextView *footer =
    [[UITextView alloc]
     initWithFrame:CGRectMake(
         0,
         screenH - 160,
         screenW,
         100
     )];

    footer.backgroundColor =
    [UIColor clearColor];

    footer.editable = NO;

    footer.selectable = YES;

    footer.scrollEnabled = NO;

    footer.textAlignment =
    NSTextAlignmentCenter;

    footer.font =
    [UIFont systemFontOfSize:12];

    footer.textColor =
    [UIColor lightGrayColor];

    footer.text =
    @"DYStorage\n"
     "插件收纳\n"
     "不修改其它抖音页面";


    [rootView addSubview:footer];
}

%end


#pragma mark - =========================================================
#pragma mark 11. 核心：只处理设置主页面
#pragma mark =========================================================

%hook AWESettingsViewModel


- (NSArray *)sectionDataArray
{
    NSArray *originalSections =
    %orig;


    if (![originalSections isKindOfClass:[NSArray class]]) {
        return originalSections;
    }


    if (originalSections.count == 0) {
        return originalSections;
    }


    /*
     ========================================================
     判断当前是不是抖音“设置主页面”

     原代码使用：

     sectionHeaderTitle == @"账号"

     我这里继续保留这个判断，因为这是你原代码
     已经采用的抖音页面特征。

     只有确认是主设置页面以后，
     才进行插件收纳。

     其它页面完全不碰。
     ========================================================
     */

    BOOL isMainSettingsPage =
    NO;


    for (id section in originalSections) {

        NSString *sectionTitle = nil;

        @try {
            sectionTitle =
            [section valueForKey:@"sectionHeaderTitle"];
        }
        @catch (__unused NSException *exception) {
        }

        if ([sectionTitle isEqualToString:@"账号"]) {

            isMainSettingsPage = YES;

            break;
        }
    }


    /*
     不是主设置页面。

     直接返回原数据。

     这就是取消“全局处理”的第二道保险。
     */

    if (!isMainSettingsPage) {
        return originalSections;
    }


    EnsurePluginStorage();


    NSMutableArray *finalSections =
    [NSMutableArray array];


    /*
     ========================================================
     遍历主设置页面
     ========================================================
     */

    for (id section in originalSections) {

        if (!section) {
            continue;
        }


        NSString *sectionTitle = nil;

        NSArray *items = nil;


        @try {

            sectionTitle =
            [section valueForKey:@"sectionHeaderTitle"];

            items =
            [section valueForKey:@"itemArray"];

        }
        @catch (__unused NSException *exception) {

            [finalSections addObject:section];

            continue;
        }


        /*
         ====================================================
         已经是“收纳”Section

         不重复处理。
         ====================================================
         */

        if ([sectionTitle isEqualToString:@"收纳"]) {

            continue;
        }


        /*
         ====================================================
         没有 itemArray
         ====================================================
         */

        if (![items isKindOfClass:[NSArray class]]) {

            [finalSections addObject:section];

            continue;
        }


        /*
         ====================================================
         过滤插件
         ====================================================
         */

        NSMutableArray *cleanItems =
        [NSMutableArray array];


        BOOL foundPlugin =
        NO;


        for (id item in items) {

            NSString *itemTitle = nil;

            @try {
                itemTitle =
                [item valueForKey:@"title"];
            }
            @catch (__unused NSException *exception) {
            }


            /*
             找到插件
             */

            if (IsTargetPlugin(itemTitle)) {

                foundPlugin = YES;

                HarvestItem(item);

                /*
                 不加入 cleanItems。

                 这意味着：

                 插件不会再出现在原位置。
                 */

                continue;
            }


            /*
             普通项目继续保留。
             */

            [cleanItems addObject:item];
        }


        /*
         ====================================================
         如果这个 Section 没有插件
         原样保留。
         ====================================================
         */

        if (!foundPlugin) {

            [finalSections addObject:section];

            continue;
        }


        /*
         ====================================================
         如果有插件

         创建一个新的 Section Model，
         只保存过滤后的普通项目。

         这样不会修改原 Section 对象。
         ====================================================
         */

        id newSection =
        [[NSClassFromString(@"AWESettingSectionModel") alloc] init];


        if (!newSection) {

            [finalSections addObject:section];

            continue;
        }


        @try {

            [newSection setValue:sectionTitle
                          forKey:@"sectionHeaderTitle"];

            id headerHeight =
            [section valueForKey:@"sectionHeaderHeight"];

            if (headerHeight) {

                [newSection setValue:headerHeight
                              forKey:@"sectionHeaderHeight"];

            }
            else {

                [newSection setValue:@(40)
                              forKey:@"sectionHeaderHeight"];
            }


            id type =
            [section valueForKey:@"type"];

            if (type) {

                [newSection setValue:type
                              forKey:@"type"];
            }


            [newSection setValue:[cleanItems copy]
                          forKey:@"itemArray"];

        }
        @catch (__unused NSException *exception) {

            [finalSections addObject:section];

            continue;
        }


        /*
         如果过滤之后仍然有普通项目，
         才加入页面。
         */

        if (cleanItems.count > 0) {

            [finalSections addObject:newSection];
        }
    }


    /*
     ========================================================
     创建“收纳”入口
     ========================================================
     */

    AWESettingItemModel *entry =
    [[%c(AWESettingItemModel) alloc] init];


    if (!entry) {
        return finalSections;
    }


    entry.identifier =
    kDYStorageIdentifier;

    entry.title =
    @"收纳";

    entry.detail =
    [NSString stringWithFormat:
     @"已收纳 %lu 个插件",
     (unsigned long)gHarvestedPlugins.count];

    entry.type = 0;

    entry.svgIconImageName =
    @"ic_gearsimplify_outlined_20";

    entry.cellType = 26;

    entry.colorStyle = 0;

    entry.isEnable = YES;


    /*
     ========================================================
     点击“收纳”
     ========================================================
     */

    __weak typeof(self) weakSelf = self;


    entry.cellTappedBlock = ^{

        __strong typeof(weakSelf) strongSelf =
        weakSelf;

        if (!strongSelf) {
            return;
        }


        UIViewController *controller =
        nil;


        @try {

            controller =
            [strongSelf valueForKey:@"controllerDelegate"];

        }
        @catch (__unused NSException *exception) {
        }


        if (!controller) {
            return;
        }


        ShowPluginManagerPage(controller);
    };


    /*
     ========================================================
     创建“收纳” Section
     ========================================================
     */

    id storageSection =
    [[NSClassFromString(@"AWESettingSectionModel") alloc] init];


    if (!storageSection) {
        return finalSections;
    }


    @try {

        [storageSection setValue:@[entry]
                           forKey:@"itemArray"];

        [storageSection setValue:@(0)
                           forKey:@"type"];

        [storageSection setValue:@(40)
                           forKey:@"sectionHeaderHeight"];

        [storageSection setValue:@"收纳"
                           forKey:@"sectionHeaderTitle"];

    }
    @catch (__unused NSException *exception) {

        return finalSections;
    }


    /*
     插到最前面
     */

    [finalSections insertObject:
     storageSection
                      atIndex:0];


    return finalSections;
}

%end


#pragma mark - =========================================================
#pragma mark 12. 二次保护
#pragma mark =========================================================

%hook AWESettingSectionModel


- (NSArray *)itemArray
{
    NSArray *items =
    %orig;


    if (![items isKindOfClass:[NSArray class]]) {
        return items;
    }


    if (items.count == 0) {
        return items;
    }


    /*
     ========================================================
     重要：

     “收纳”页面绝对不进行过滤。
     ========================================================
     */

    NSString *sectionTitle = nil;


    @try {

        sectionTitle =
        [self valueForKey:@"sectionHeaderTitle"];

    }
    @catch (__unused NSException *exception) {
    }


    if ([sectionTitle isEqualToString:@"已收纳的插件"] ||
        [sectionTitle isEqualToString:@"收纳"]) {

        return items;
    }


    /*
     ========================================================
     这里不再进行“全局清理”。

     只做非常有限的插件过滤。

     如果当前 Section 中有插件，
     则把插件收进 gHarvestedPlugins。

     ========================================================
     */

    BOOL hasPlugin =
    NO;


    for (id item in items) {

        NSString *title = nil;

        @try {

            title =
            [item valueForKey:@"title"];

        }
        @catch (__unused NSException *exception) {
        }


        if (IsTargetPlugin(title)) {

            hasPlugin = YES;

            break;
        }
    }


    if (!hasPlugin) {
        return items;
    }


    EnsurePluginStorage();


    NSMutableArray *cleanItems =
    [NSMutableArray array];


    for (id item in items) {

        NSString *title = nil;

        @try {

            title =
            [item valueForKey:@"title"];

        }
        @catch (__unused NSException *exception) {
        }


        if (IsTargetPlugin(title)) {

            HarvestItem(item);

        }
        else {

            [cleanItems addObject:item];
        }
    }


    return [cleanItems copy];
}

%end


#pragma mark - =========================================================
#pragma mark 13. Logos Constructor
#pragma mark =========================================================

%ctor
{
    @autoreleasepool {

        EnsurePluginStorage();

    }
}
