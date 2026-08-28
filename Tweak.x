#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

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


static NSMutableArray *gHarvestedPlugins = nil;
static void *kDYPluginViewModelKey = &kDYPluginViewModelKey;
static void *kDYPluginSearchHandlerKey = &kDYPluginSearchHandlerKey;


static void RemoveRogueWatermarks(UIView *view) {
    if (!view) return;
    

    if ([view isKindOfClass:[UITableViewCell class]] || [view isKindOfClass:[UICollectionViewCell class]]) {
        return;
    }
    
    BOOL shouldRemove = NO;
    NSString *viewText = nil;
    
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    if ([view respondsToSelector:@selector(text)]) {
        id val = [view performSelector:@selector(text)];
        if ([val isKindOfClass:[NSString class]]) viewText = val;
    } else if ([view respondsToSelector:@selector(currentTitle)]) {
        id val = [view performSelector:@selector(currentTitle)];
        if ([val isKindOfClass:[NSString class]]) viewText = val;
    } else if ([view isKindOfClass:[UIButton class]]) {
        viewText = [(UIButton *)view titleForState:UIControlStateNormal];
    }
    #pragma clang diagnostic pop

  
    if (viewText) {
        if ([viewText localizedCaseInsensitiveContainsString:@"抖音助手"] || 
            [viewText localizedCaseInsensitiveContainsString:@"XUU"]) {
            shouldRemove = YES;
        }
    }
    
  
    if (!shouldRemove) {
        NSString *className = NSStringFromClass([view class]);
        if ([className localizedCaseInsensitiveContainsString:@"抖音助手"] || 
            [className localizedCaseInsensitiveContainsString:@"XUU"]) {
            shouldRemove = YES;
        }
    }
    
 
    if (shouldRemove) {
        view.hidden = YES;
        view.alpha = 0.0;
        [view removeFromSuperview];
        return; 
    }
    
    NSArray *subviews = [view.subviews copy];
    for (UIView *subview in subviews) {
        RemoveRogueWatermarks(subview);
    }
}


@interface DYPluginSearchHandler : NSObject
@property (nonatomic, weak) UIViewController *targetVC;
@property (nonatomic, weak) id viewModel;
@end

@implementation DYPluginSearchHandler
- (void)textFieldDidChange:(UITextField *)textField {
    NSString *searchText = textField.text ?: @"";
    NSArray *filteredItems = nil;
    
    if (searchText.length == 0) {
        filteredItems = [gHarvestedPlugins copy];
    } else {
        NSMutableArray *temp = [NSMutableArray array];
        for (id item in gHarvestedPlugins) {
            NSString *title = [item valueForKey:@"title"];
            if ([title localizedCaseInsensitiveContainsString:searchText]) {
                [temp addObject:item];
            }
        }
        filteredItems = temp;
    }

    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    [section setValue:(filteredItems ?: @[]) forKey:@"itemArray"];
    
    [self.viewModel setValue:@[section] forKey:@"sectionDataArray"];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.targetVC) {
            for (UIView *v in self.targetVC.view.subviews) {
                if ([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) {
                    if ([v respondsToSelector:@selector(reloadData)]) {
                        [v performSelector:@selector(reloadData)];
                    }
                }
            }
        }
    });
}
@end


static BOOL IsTargetPlugin(NSString *title) {
    if (!title || title.length == 0) return NO;
    NSArray *targets = @[
        @"DYYY", @"DYKiller", @"抖音助手", @"自动消息",
        @"抖音图层", @"抖+", @"抖⁺", @"抖＋", @"aweJ", 
        @"AwemeX", @"SJJAwemeLoginRepair", @"𝙓𝙐𝙐ᶻ", 
        @"DouyinHelper", @"Yuki"
    ];
    for (NSString *t in targets) {
        if ([title isEqualToString:t]) {
            return YES;
        }
    }
    return NO;
}

static void HarvestItem(id item) {
    if (!item) return;
    if (!gHarvestedPlugins) gHarvestedPlugins = [NSMutableArray array];
    
    NSString *identifier = [item valueForKey:@"identifier"];
    NSString *title = [item valueForKey:@"title"];
    
    id staleItem = nil;
    for (id existing in gHarvestedPlugins) {
        NSString *exId = [existing valueForKey:@"identifier"];
        NSString *exTitle = [existing valueForKey:@"title"];
        if ((identifier && exId && [exId isEqualToString:identifier]) || 
            (title && exTitle && [exTitle isEqualToString:title])) {
            staleItem = existing;
            break; 
        }
    }
    
    if (staleItem) {
        [gHarvestedPlugins removeObject:staleItem];
    }
    
    @try {
        void (^originalBlock)(void) = [item valueForKey:@"cellTappedBlock"];
        if (originalBlock) {
            void (^wrappedBlock)(void) = ^{
                originalBlock();
            };
            [item setValue:wrappedBlock forKey:@"cellTappedBlock"];
        }
    } @catch (NSException *exception) {}
    
    [gHarvestedPlugins addObject:item];
}

static void ShowPluginManagerPage(UIViewController *rootVC) {
    UIViewController *subVC = [[NSClassFromString(@"AWESettingBaseViewController") alloc] init];
    
    if (!gHarvestedPlugins || gHarvestedPlugins.count == 0) {
        @try {
            id dummyVM = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
            [dummyVM setValue:subVC forKey:@"controllerDelegate"];
            [dummyVM performSelector:@selector(sectionDataArray)];
            [dummyVM setValue:nil forKey:@"controllerDelegate"];
        } @catch (NSException *e) {}
    }
    
    id viewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    [viewModel setValue:@(0) forKey:@"colorStyle"];
    [viewModel setValue:subVC forKey:@"controllerDelegate"];
    
    id section = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
    [section setValue:@"已收纳的插件" forKey:@"sectionHeaderTitle"];
    [section setValue:@(40) forKey:@"sectionHeaderHeight"];
    [section setValue:@(0) forKey:@"type"];
    [section setValue:(gHarvestedPlugins ? [gHarvestedPlugins copy] : @[]) forKey:@"itemArray"];
    
    [viewModel setValue:@[section] forKey:@"sectionDataArray"];
    
    objc_setAssociatedObject(subVC, kDYPluginViewModelKey, viewModel, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    UIViewController *topVC = rootVC;
    if (!topVC) {
        topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
    }
    while (topVC.presentedViewController) {
        topVC = topVC.presentedViewController;
    }
    
    if (topVC.navigationController) {
        [topVC.navigationController pushViewController:subVC animated:YES];
    } else {
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:subVC];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [topVC presentViewController:nav animated:YES completion:nil];
    }
}

%hook AWESettingBaseViewController
- (id)viewModel {
    id orig = %orig;
    if (!orig) return objc_getAssociatedObject(self, kDYPluginViewModelKey);
    return orig;
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    
    __weak typeof(self) weakSelf = self;
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.view && strongSelf.view.window) {

            RemoveRogueWatermarks(strongSelf.view);
         
            if (strongSelf.navigationController && strongSelf.navigationController.navigationBar) {
                RemoveRogueWatermarks(strongSelf.navigationController.navigationBar);
            }
        }
    });
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (strongSelf && strongSelf.view && strongSelf.view.window) {
            RemoveRogueWatermarks(strongSelf.view);
            if (strongSelf.navigationController && strongSelf.navigationController.navigationBar) {
                RemoveRogueWatermarks(strongSelf.navigationController.navigationBar);
            }
        }
    });
}

- (void)viewDidLoad {
    %orig;
    
    RemoveRogueWatermarks(self.view);
    
    id customVM = objc_getAssociatedObject(self, kDYPluginViewModelKey);
    if (customVM) {
        CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
        CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
        
        CGFloat navBottomY = 88.0; 
        for (UIView *sub in self.view.subviews) {
            if ([sub isKindOfClass:NSClassFromString(@"AWENavigationBar")]) {
                navBottomY = CGRectGetMaxY(sub.frame); 
                if ([sub respondsToSelector:@selector(titleLabel)]) {
                    UILabel *lbl = [sub valueForKey:@"titleLabel"];
                    lbl.text = @"收纳";
                }
            }
        }
        
        UIView *headerContainer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenW, 56)];
        headerContainer.backgroundColor = [UIColor clearColor];
        
        UITextField *searchBox = [[UITextField alloc] initWithFrame:CGRectMake(16, 10, screenW - 32, 36)];
        searchBox.placeholder = @"🔍 怎么能够做到全局搜索啊";
        searchBox.textAlignment = NSTextAlignmentCenter; 
        searchBox.backgroundColor = [UIColor colorWithRed:0.95 green:0.95 blue:0.96 alpha:1.0];
        searchBox.layer.cornerRadius = 8;
        searchBox.clipsToBounds = YES;
        searchBox.clearButtonMode = UITextFieldViewModeWhileEditing;
        searchBox.font = [UIFont systemFontOfSize:14];
        searchBox.returnKeyType = UIReturnKeyDone;
        
        [headerContainer addSubview:searchBox];
        
        DYPluginSearchHandler *handler = [[DYPluginSearchHandler alloc] init];
        handler.targetVC = self;
        handler.viewModel = customVM;
        objc_setAssociatedObject(self, kDYPluginSearchHandlerKey, handler, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        [searchBox addTarget:handler action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
        
        BOOL injectedAsHeader = NO;
        for (UIView *v in self.view.subviews) {
            if ([v isKindOfClass:[UITableView class]]) {
                ((UITableView *)v).tableHeaderView = headerContainer;
                injectedAsHeader = YES;
                break;
            }
        }
        
        if (!injectedAsHeader) {
            headerContainer.frame = CGRectMake(0, navBottomY, screenW, 56);
            [self.view addSubview:headerContainer];
            
            for (UIView *v in self.view.subviews) {
                if (([v isKindOfClass:[UITableView class]] || [v isKindOfClass:[UICollectionView class]]) && v != headerContainer) {
                    UIScrollView *sv = (UIScrollView *)v;
                    UIEdgeInsets inset = sv.contentInset;
                    inset.top += 56;
                    sv.contentInset = inset;
                    break;
                }
            }
        }

        UITextView *footerView = [[UITextView alloc] initWithFrame:CGRectMake(0, screenH - 180, screenW, 120)];
        footerView.backgroundColor = [UIColor clearColor];
        footerView.editable = NO;
        footerView.selectable = YES;
        footerView.scrollEnabled = NO;
        footerView.textContainerInset = UIEdgeInsetsZero;
        footerView.textContainer.lineFragmentPadding = 0;
        footerView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleWidth;
        
        footerView.linkTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor grayColor],
            NSUnderlineStyleAttributeName: @(NSUnderlineStyleNone)
        };
        
        NSMutableAttributedString *footerText = [[NSMutableAttributedString alloc] init];
        [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"开源仓库地址\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium], NSForegroundColorAttributeName: [UIColor colorWithRed:0.18 green:0.49 blue:0.36 alpha:1.0]}]];
        [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"https://github.com/xlzs001/DYstorage\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: [UIColor grayColor], NSLinkAttributeName: @"https://github.com/xlzs001/DYstorage" }]];
        [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"Developed by xlzs001\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: [UIColor grayColor]}]];
        [footerText appendAttributedString:[[NSAttributedString alloc] initWithString:@"© 2026 xlzs001. All rights reserved." attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11], NSForegroundColorAttributeName: [UIColor lightGrayColor]}]];
        
        NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
        style.lineSpacing = 8;
        style.alignment = NSTextAlignmentCenter;
        [footerText addAttribute:NSParagraphStyleAttributeName value:style range:NSMakeRange(0, footerText.length)];
        
        footerView.attributedText = footerText;
        [self.view addSubview:footerView];
    }
}
%end


%hook AWESettingsViewModel
- (NSArray *)sectionDataArray {
    NSArray *originalSections = %orig;
    if (![originalSections isKindOfClass:[NSArray class]]) return originalSections;

    BOOL isMainPage = NO;
    for (id s in originalSections) {
        if ([s respondsToSelector:@selector(sectionHeaderTitle)] && [[s valueForKey:@"sectionHeaderTitle"] isEqualToString:@"账号"]) {
            isMainPage = YES; break;
        }
    }
    if (!isMainPage) return originalSections;

    NSMutableArray *finalSections = [NSMutableArray array];
    BOOL hasMgrSection = NO;
    
    for (id section in originalSections) {
        if (![section respondsToSelector:@selector(sectionHeaderTitle)]) {
            [finalSections addObject:section];
            continue;
        }
      
        NSString *sectionTitle = [section valueForKey:@"sectionHeaderTitle"];
        if ([sectionTitle isEqualToString:@"收纳"]) {
            hasMgrSection = YES;
            [finalSections addObject:section];
            continue;
        }
        
        if (IsTargetPlugin(sectionTitle)) {
            NSArray *items = [section valueForKey:@"itemArray"];
            for (id item in items) HarvestItem(item);
            continue; 
        }
        [finalSections addObject:section];
    }

    if (!hasMgrSection) {
        AWESettingItemModel *entry = [[%c(AWESettingItemModel) alloc] init];
        entry.identifier = @"DYPluginMgr";
        entry.title = @"收纳"; 
        entry.detail = [NSString stringWithFormat:@"已收纳 %lu 个", (unsigned long)(gHarvestedPlugins.count)];
        entry.type = 0;
        entry.svgIconImageName = @"ic_gearsimplify_outlined_20";
        entry.cellType = 26; 
        entry.colorStyle = 0;
        entry.isEnable = YES;

        __weak typeof(self) weakSelf = self;
        entry.cellTappedBlock = ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (strongSelf && strongSelf.controllerDelegate) {
                ShowPluginManagerPage((UIViewController *)strongSelf.controllerDelegate);
            }
        };

        id mgrSection = [[NSClassFromString(@"AWESettingSectionModel") alloc] init];
        [mgrSection setValue:@[ entry ] forKey:@"itemArray"];
        [mgrSection setValue:@(0) forKey:@"type"];
        [mgrSection setValue:@(40) forKey:@"sectionHeaderHeight"];
        [mgrSection setValue:@"收纳" forKey:@"sectionHeaderTitle"];

        [finalSections insertObject:mgrSection atIndex:0];
    }
    
    return finalSections;
}
%end

%hook AWESettingSectionModel
- (NSArray *)itemArray {
    NSArray *items = %orig;
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) return items;

    NSString *headerTitle = nil;
    if ([self respondsToSelector:@selector(sectionHeaderTitle)]) {
        headerTitle = [self valueForKey:@"sectionHeaderTitle"];
    }
    
    if ([headerTitle isEqualToString:@"已收纳的插件"] || [headerTitle isEqualToString:@"收纳"]) {
        return items;
    }
    
    BOOL hasPlugin = NO;
    for (id item in items) {
        NSString *itemTitle = [item valueForKey:@"title"];
        if (IsTargetPlugin(itemTitle)) {
            hasPlugin = YES; break;
        }
    }
    
    if (!hasPlugin) return items;
    
    NSMutableArray *cleanItems = [NSMutableArray array];
    for (id item in items) {
        NSString *itemTitle = [item valueForKey:@"title"];
        if (IsTargetPlugin(itemTitle)) {
            HarvestItem(item); 
        } else {
            [cleanItems addObject:item]; 
        }
    }
    return cleanItems; 
}
%end
