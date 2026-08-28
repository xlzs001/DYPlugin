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

// 存放被我们“收割”来的插件入口
static NSMutableArray *gHarvestedPlugins = nil;

%hook AWESettingsViewModel

- (NSArray *)sectionDataArray {
    NSArray *originalSections = %orig;
    if (![originalSections isKindOfClass:[NSArray class]]) return originalSections;

    BOOL isMainPage = NO;
    for (AWESettingSectionModel *s in originalSections) {
        if ([s respondsToSelector:@selector(sectionHeaderTitle)] && [s.sectionHeaderTitle isEqualToString:@"账号"]) {
            isMainPage = YES;
            break;
        }
    }
    
    if (!isMainPage) return originalSections;

    if (!gHarvestedPlugins) {
        gHarvestedPlugins = [NSMutableArray array];
    } else {
        [gHarvestedPlugins removeAllObjects];
    }

    NSMutableArray *finalSections = [NSMutableArray array];
    
    // ==========================================
    // 🛠️ 在这里添加你想收纳的所有插件名称！
    // 只要是插件在原版抖音设置里显示的“区块标题”，写进来就会被收割
    // ==========================================
    NSArray *targetPlugins = @[
        @"DYYY", 
        @"DYKiller", 
        @"抖音助手", 
        @"自动消息",
        @"抖音图层",
        @"抖+",
        @"Yuki"// ← 以后有新插件，直接在这里加一行名字！
    ];
    
    for (AWESettingSectionModel *section in originalSections) {
        NSString *title = section.sectionHeaderTitle;
        
        // 核心判断：如果区块标题在我们的收割清单里，或者就是我们自己，直接没收！
        if ([targetPlugins containsObject:title] || [title isEqualToString:@"插件收纳"]) {
            if (section.itemArray.count > 0) {
                [gHarvestedPlugins addObjectsFromArray:section.itemArray];
            }
        } else {
            // 抖音原生选项，放行
            [finalSections addObject:section];
        }
    }

    // 建立总入口
    AWESettingItemModel *entry = [[%c(AWESettingItemModel) alloc] init];
    entry.identifier = @"DYPluginMgr";
    entry.title = @"🛠️ 插件收纳中枢";
    entry.detail = [NSString stringWithFormat:@"已收纳 %lu 个", (unsigned long)gHarvestedPlugins.count];
    entry.type = 0;
    entry.svgIconImageName = @"ic_gearsimplify_outlined_20";
    entry.cellType = 26; 
    entry.colorStyle = 0;
    entry.isEnable = YES;

    // 点击弹出底部菜单
    __weak AWESettingsViewModel *weakSelf = self;
    entry.cellTappedBlock = ^{
        __strong AWESettingsViewModel *strongSelf = weakSelf;
        if (strongSelf && strongSelf.controllerDelegate) {
            UIViewController *rootVC = (UIViewController *)strongSelf.controllerDelegate;
            
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🛠️ 插件收纳中枢" 
                                                                           message:@"请选择要配置的插件" 
                                                                    preferredStyle:UIAlertControllerStyleActionSheet];
            
            for (AWESettingItemModel *plugin in gHarvestedPlugins) {
                if ([plugin.identifier isEqualToString:@"DYPluginMgr"]) continue;
                
                UIAlertAction *action = [UIAlertAction actionWithTitle:plugin.title 
                                                                 style:UIAlertActionStyleDefault 
                                                               handler:^(UIAlertAction * _Nonnull action) {
                    if (plugin.cellTappedBlock) {
                        plugin.cellTappedBlock();
                    }
                }];
                [alert addAction:action];
            }
            
            [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
            
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

    [finalSections insertObject:mgrSection atIndex:0];
    
    return finalSections;
}

%end
