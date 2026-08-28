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
static id gDummyViewModel = nil; 


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
    
   
    for (id existing in gHarvestedPlugins) {
        NSString *exId = [existing valueForKey:@"identifier"];
        NSString *exTitle = [existing valueForKey:@"title"];
        if ((identifier && exId && [exId isEqualToString:identifier]) || 
            (title && exTitle && [exTitle isEqualToString:title])) {
            return; 
        }
    }
    
    @try {
        void (^originalBlock)(void) = [item valueForKey:@"cellTappedBlock"];
        if (originalBlock) {
            void (^wrappedBlock)(void) = ^{
                originalBlock();
            };
            [item setValue:wrappedBlock forKey:@"cellTappedBlock"];
        }
    } @catch (NSException *exception) {
    }
    
    [gHarvestedPlugins addObject:item];
}


static void ShowPluginManagerPage(UIViewController *rootVC) {
    UIViewController *subVC = [[NSClassFromString(@"AWESettingBaseViewController") alloc] init];
    
    dispatch_async(dispatch_get_main_queue(), ^{
       
        for (UIView *sub in subVC.view.subviews) {
            if ([sub isKindOfClass:NSClassFromString(@"AWENavigationBar")]) {
                if ([sub respondsToSelector:@selector(titleLabel)]) {
                    UILabel *lbl = [sub valueForKey:@"titleLabel"];
                    lbl.text = @"收纳";
                }
                break;
            }
        }
        
       
        CGFloat screenW = [UIScreen mainScreen].bounds.size.width;
        CGFloat screenH = [UIScreen mainScreen].bounds.size.height;
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
        
  
        NSAttributedString *line1 = [[NSAttributedString alloc] initWithString:@"开源仓库地址\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:14 weight:UIFontWeightMedium], NSForegroundColorAttributeName: [UIColor colorWithRed:0.18 green:0.49 blue:0.36 alpha:1.0]}];
        
        
        NSAttributedString *line2 = [[NSAttributedString alloc] initWithString:@"https://github.com/xlzs001/DYstorage\n" attributes:@{
            NSFontAttributeName: [UIFont systemFontOfSize:12],
            NSForegroundColorAttributeName: [UIColor grayColor],
            NSLinkAttributeName: @"https://github.com/xlzs001/DYstorage" 
        }];
        
    
        NSAttributedString *line3 = [[NSAttributedString alloc] initWithString:@"Developed by xlzs001\n" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:12], NSForegroundColorAttributeName: [UIColor grayColor]}];
        
  
        NSAttributedString *line4 = [[NSAttributedString alloc] initWithString:@"© 2026 xlzs001. All rights reserved." attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:11], NSForegroundColorAttributeName: [UIColor lightGrayColor]}];
        
       
        NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
        paragraphStyle.lineSpacing = 8;
        paragraphStyle.alignment = NSTextAlignmentCenter;
        
        [footerText appendAttributedString:line1];
        [footerText appendAttributedString:line2];
        [footerText appendAttributedString:line3];
        [footerText appendAttributedString:line4];
        [footerText addAttribute:NSParagraphStyleAttributeName value:paragraphStyle range:NSMakeRange(0, footerText.length)];
        
        footerView.attributedText = footerText;
        [subVC.view addSubview:footerView];
    });

    if (!gHarvestedPlugins || gHarvestedPlugins.count == 0) {
        gDummyViewModel = [[NSClassFromString(@"AWESettingsViewModel") alloc] init];
    }
    if (gDummyViewModel) {
        [gDummyViewModel setValue:subVC forKey:@"controllerDelegate"];
        [gDummyViewModel performSelector:@selector(sectionDataArray)];
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
            hasPlugin = YES; 
            break;
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
