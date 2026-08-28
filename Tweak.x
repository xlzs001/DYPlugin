#import <UIKit/UIKit.h>

// 1. 声明模型
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
@end

// 静态数组：专门用来存放被我们“收割”来的各大插件入口
static NSMutableArray *gHarvestedPlugins = nil;

%hook AWESettingsViewModel

- (NSArray *)sectionDataArray {
    // 1. 获取原数组（此时 DYYY 和 DYKiller 的钩子已经执行完，把它们自己加进去了）
    NSArray *originalSections = %orig;
    if (![originalSections isKindOfClass:[NSArray class]]) return originalSections;

    BOOL isMainPage = NO;
    for (AWESettingSectionModel *s in originalSections) {
        if ([s respondsToSelector:@selector(sectionHeaderTitle)] && [s.sectionHeaderTitle isEqualToString:@"账号"]) {
            isMainPage = YES;
            break;
        }
    }
    
    // 如果不是设置主页，安全放行
    if (!isMainPage) return originalSections;

    // 初始化我们的“收割筐”
    if (!gHarvestedPlugins) {
        gHarvestedPlugins = [NSMutableArray array];
    } else {
        [gHarvestedPlugins removeAllObjects];
    }

    NSMutableArray *finalSections = [NSMutableArray array];
    
    // 2. 遍历原数组，执行收割！
    for (AWESettingSectionModel *section in originalSections) {
        NSString *title = section.sectionHeaderTitle;
        
        // 只要发现是其他插件，统统没收！
        if ([title isEqualToString:@"DYYY"] || [title isEqualToString:@"DYKiller"] || [title isEqualToString:@"插件收纳"]) {
            if (section.itemArray.count > 0) {
                // 把它们带跳转事件的入口装进我们的口袋
                [gHarvestedPlugins addObjectsFromArray:section.itemArray];
            }
            // 注意：这里没有把它们加入 finalSections，所以它们在外面被隐藏了！
        } else {
            // 抖音原生的正常设置项，放行
            [finalSections addObject:section];
        }
    }

    // 3. 建立我们独一无二的入口
    AWESettingItemModel *entry = [[%c(AWESettingItemModel) alloc] init];
    entry.identifier = @"DYPluginMgr";
    entry.title = @"插件收纳";
    entry.detail = [NSString stringWithFormat:@"已收纳 %lu 个", (unsigned long)gHarvestedPlugins.count];
    entry.type = 0;
    entry.svgIconImageName = @"ic_gearsimplify_outlined_20";
    entry.cellType = 26; 
    entry.colorStyle = 0;
    entry.isEnable = YES;

    // 4. 点击弹出底部“收纳菜单”
    __weak AWESettingsViewModel *weakSelf = self;
    entry.cellTappedBlock = ^{
        __strong AWESettingsViewModel *strongSelf = weakSelf;
        if (strongSelf && strongSelf.controllerDelegate) {
            UIViewController *rootVC = (UIViewController *)strongSelf.controllerDelegate;
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"插件收纳" 
                                                                           message:@"请选择要配置的插件" 
                                                                    preferredStyle:UIAlertControllerStyleActionSheet];
            
            // 把收割来的插件全部做成按钮
            for (AWESettingItemModel *plugin in gHarvestedPlugins) {
                if ([plugin.identifier isEqualToString:@"DYPluginMgr"]) continue; // 排除自己
                
                UIAlertAction *action = [UIAlertAction actionWithTitle:plugin.title 
                                                                 style:UIAlertActionStyleDefault 
                                                               handler:^(UIAlertAction * _Nonnull action) {
                    // 完美触发它们原生写好的跳转代码！
                    if (plugin.cellTappedBlock) {
                        plugin.cellTappedBlock();
                    }
                }];
                [alert addAction:action];
            }
            
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            
            // 兼容 iPad
            if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
                alert.popoverPresentationController.sourceView = rootVC.view;
                alert.popoverPresentationController.sourceRect = CGRectMake(rootVC.view.bounds.size.width / 2.0, rootVC.view.bounds.size.height / 2.0, 1.0, 1.0);
            }
            
            [rootVC presentViewController:alert animated:YES completion:nil];
        }
    };

    AWESettingSectionModel *mgrSection = [[%c(AWESettingSectionModel) alloc] init];
    mgrSection.itemArray = @[ entry ];
    mgrSection.type = 0;
    mgrSection.sectionHeaderHeight = 40;
    mgrSection.sectionHeaderTitle = @"插件收纳";

    // 插在最上面
    [finalSections insertObject:mgrSection atIndex:0];
    
    return finalSections;
}

%end
