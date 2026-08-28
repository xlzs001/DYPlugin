// ==========================================
// 5. 数据源拦截收割 (设置页核心拦截)
// ==========================================
%hook AWESettingsViewModel
- (NSArray *)sectionDataArray {
    NSArray *originalSections = %orig;
    if (![originalSections isKindOfClass:[NSArray class]]) return originalSections;

    BOOL isMainPage = NO;
    for (id s in originalSections) {
        if ([s respondsToSelector:@selector(sectionHeaderTitle)] && [[s valueForKey:@"sectionHeaderTitle"] isEqualToString:@"账号"]) {
            isMainPage = YES;
            break;
        }
    }
    
    // 如果不是设置主页，安全放行，防止死循环
    if (!isMainPage) return originalSections;

    if (!gHarvestedPlugins) {
        gHarvestedPlugins = [NSMutableArray array];
    }

    NSMutableArray *finalSections = [NSMutableArray array];
    
    // ⚠️ 插件白名单
    NSArray *targetPlugins = @[
        @"DYYY", 
        @"DYKiller", 
        @"抖音助手", 
        @"自动消息",
        @"抖音图层",
        @"抖+",
        @"aweJ",
        @"AwemeX",
        @"SJJAwemeLoginRepair",
        @"𝙓𝙐𝙐ᶻ",
        @"DouyinHelper",
        @"Yuki"
    ];
    
    for (id section in originalSections) {
        NSString *sectionTitle = [section valueForKey:@"sectionHeaderTitle"];
        
        // 场景1：如果整个区块都是插件专属的 (如 DYYY, DYKiller)
        if ([targetPlugins containsObject:sectionTitle] || [sectionTitle isEqualToString:@"收纳"]) {
            NSArray *items = [section valueForKey:@"itemArray"];
            if (items.count > 0) {
                for (id item in items) {
                    BOOL exists = NO;
                    NSString *identifier = [item valueForKey:@"identifier"];
                    for (id existing in gHarvestedPlugins) {
                        if ([[existing valueForKey:@"identifier"] isEqualToString:identifier]) {
                            exists = YES; break;
                        }
                    }
                    if (!exists) {
                        [gHarvestedPlugins addObject:item];
                    }
                }
            }
        } else {
            // 场景2：原生区块 (如 "通用")，需要遍历内部的每一个 Item
            NSArray *items = [section valueForKey:@"itemArray"];
            NSMutableArray *filteredItems = [NSMutableArray array];
            
            for (id item in items) {
                NSString *itemTitle = [item valueForKey:@"title"];
                
                // 检查这个 Item 的标题是否在我们的收割名单里
                if ([targetPlugins containsObject:itemTitle]) {
                    BOOL exists = NO;
                    NSString *identifier = [item valueForKey:@"identifier"];
                    for (id existing in gHarvestedPlugins) {
                        if ([[existing valueForKey:@"identifier"] isEqualToString:identifier]) {
                            exists = YES; break;
                        }
                    }
                    if (!exists) {
                        // 发现伪装在原生区块里的插件，收割！
                        [gHarvestedPlugins addObject:item];
                    }
                } else {
                    // 真正的原生选项，予以保留
                    [filteredItems addObject:item];
                }
            }
            
            // 将剔除插件后的纯净 items 重新还给这个原生区块
            [section setValue:filteredItems forKey:@"itemArray"];
            
            // 将处理好的区块放入最终显示的列表
            if (filteredItems.count > 0 || items.count == 0) {
                [finalSections addObject:section];
            }
        }
    }

    // 建立总入口菜单
    AWESettingItemModel *entry = [[%c(AWESettingItemModel) alloc] init];
    entry.identifier = @"DYPluginMgr";
    entry.title = @"收纳"; 
    entry.detail = [NSString stringWithFormat:@"已收纳 %lu 个", (unsigned long)gHarvestedPlugins.count];
    entry.type = 0;
    entry.svgIconImageName = @"ic_gearsimplify_outlined_20";
    entry.cellType = 26; 
    entry.colorStyle = 0;
    entry.isEnable = YES;

    // 点击总入口，拉起原生的二级页面
    __weak AWESettingsViewModel *weakSelf = self;
    entry.cellTappedBlock = ^{
        __strong AWESettingsViewModel *strongSelf = weakSelf;
        if (strongSelf && strongSelf.controllerDelegate) {
            ShowPluginManagerPage((UIViewController *)strongSelf.controllerDelegate);
        }
    };

    AWESettingSectionModel *mgrSection = [[%c(AWESettingSectionModel) alloc] init];
    mgrSection.itemArray = @[ entry ];
    mgrSection.type = 0;
    mgrSection.sectionHeaderHeight = 40;
    mgrSection.sectionHeaderTitle = @"收纳"; 

    [finalSections insertObject:mgrSection atIndex:0];
    return finalSections;
}
%end
