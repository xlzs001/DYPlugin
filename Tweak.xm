// DYStorage — a conservative settings-entry organizer for Douyin tweaks.
//
// The hook intentionally operates on AWESettingsViewModel's returned data
// rather than scanning UIWindow/UIView. That keeps it confined to the settings
// page and preserves each collected item's original tap callback.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#import "DYStorageManager.h"
#import "DYStorageDeveloperScanner.h"
#import "DYStorageSearchCatalog.h"
#import "DYStorageSearchCoordinator.h"

#ifndef DY_STORAGE_DEBUG
#define DY_STORAGE_DEBUG 0
#endif

#if DY_STORAGE_DEBUG
#define DYStorageLog(format, ...) NSLog(@"[DYStorage] " format, ##__VA_ARGS__)
#else
#define DYStorageLog(...)
#endif

static NSString *const kDYStorageHubSectionIdentifier = @"com.xlzs001.dystorage.section";
static NSString *const kDYStorageHubEntryIdentifier = @"com.xlzs001.dystorage.open";
static NSString *const kDYStorageHubContentIdentifier = @"com.xlzs001.dystorage.content";
static NSString *const kDYStorageHubMarkerTitle = @"__DYStorage_Hub__";
static NSString *const kDYStorageVersion = @"1.2.0";
static NSString *const kDYStorageRepositoryURL = @"https://github.com/xlzs001/DYstorage";

static void *kDYStorageViewModelAssociationKey = &kDYStorageViewModelAssociationKey;
static void *kDYStorageFallbackHiddenSectionKey = &kDYStorageFallbackHiddenSectionKey;
static void *kDYStorageSearchCoordinatorAssociationKey = &kDYStorageSearchCoordinatorAssociationKey;

static BOOL gDYStorageSettingsHookInstalled = NO;
static BOOL gDYStorageHubHookInstalled = NO;
static BOOL gDYStorageSectionFallbackHookInstalled = NO;
static BOOL gDYStorageSectionHeaderHookInstalled = NO;
static BOOL gDYStorageHubInsertedOnMainSettings = NO;
static BOOL gDYStorageHubPageVisible = NO;
static BOOL gDYStorageOrganizingMainSections = NO;
static BOOL gDYStorageCheckingFallbackHeader = NO;

static void DYStorageRefreshHubController(UIViewController *controller);
static NSArray *DYStorageHubSections(void);

#pragma mark - Runtime-safe model access

static id DYStorageValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *DYStorageStringValue(id object, NSString *key) {
    id value = DYStorageValue(object, key);
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSArray *DYStorageArrayValue(id object, NSString *key) {
    id value = DYStorageValue(object, key);
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static BOOL DYStorageSetValue(id object, id value, NSString *key) {
    if (!object || key.length == 0) return NO;
    @try {
        [object setValue:value forKey:key];
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

static NSString *DYStorageNormalizedString(NSString *value) {
    if (value.length == 0) return nil;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.lowercaseString.length ? trimmed.lowercaseString : nil;
}

static NSString *DYStorageItemKey(id item) {
    NSString *identifier = DYStorageNormalizedString(DYStorageStringValue(item, @"identifier"));
    if (identifier.length) return [@"identifier:" stringByAppendingString:identifier];
    NSString *title = DYStorageNormalizedString(DYStorageStringValue(item, @"title"));
    return title.length ? [@"title:" stringByAppendingString:title] : nil;
}

#pragma mark - View-controller helpers

static NSArray<UIWindow *> *DYStorageWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    UIApplication *application = [UIApplication sharedApplication];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
    if (windows.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [windows addObjectsFromArray:application.windows];
#pragma clang diagnostic pop
    }
    return windows;
}

static UIWindow *DYStorageKeyWindow(void) {
    for (UIWindow *window in DYStorageWindows()) {
        if (window.isKeyWindow) return window;
    }
    return [DYStorageWindows() firstObject];
}

static UIViewController *DYStorageTopViewController(UIViewController *rootController) {
    UIViewController *controller = rootController ?: DYStorageKeyWindow().rootViewController;
    if (!controller) return nil;

    while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
        controller = controller.presentedViewController;
    }
    while (YES) {
        if ([controller isKindOfClass:[UINavigationController class]]) {
            UIViewController *visible = ((UINavigationController *)controller).visibleViewController;
            if (visible) {
                controller = visible;
                continue;
            }
        }
        if ([controller isKindOfClass:[UITabBarController class]]) {
            UIViewController *selected = ((UITabBarController *)controller).selectedViewController;
            if (selected) {
                controller = selected;
                continue;
            }
        }
        break;
    }
    return controller;
}

static void DYStorageReloadListsInView(UIView *view, NSInteger depth) {
    if (!view || depth < 0) return;
    if ([view isKindOfClass:[UITableView class]]) {
        [(UITableView *)view reloadData];
        return;
    }
    if ([view isKindOfClass:[UICollectionView class]]) {
        [(UICollectionView *)view reloadData];
        return;
    }
    for (UIView *subview in view.subviews) {
        DYStorageReloadListsInView(subview, depth - 1);
    }
}

static UITableView *DYStorageFindTableView(UIView *view, NSInteger depth) {
    if (!view || depth < 0) return nil;
    if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    for (UIView *subview in view.subviews) {
        UITableView *tableView = DYStorageFindTableView(subview, depth - 1);
        if (tableView) return tableView;
    }
    return nil;
}

#pragma mark - Discovery rules

static NSArray<NSString *> *DYStorageKnownPluginTitles(void) {
    static NSArray<NSString *> *titles = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // These are root-entry names, not fuzzy keywords. Exact matching keeps
        // ordinary Douyin content and first-party settings out of the organizer.
        titles = @[
            @"DYYY", @"DYKiller", @"AwemeX", @"DouyinHelper",
            @"抖音助手", @"抖音图层", @"抖+", @"抖⁺", @"抖＋",
            @"自动消息", @"aweJ", @"SJJAwemeLoginRepair", @"𝙓𝙐𝙐ᶻ", @"𝙓𝙐𝙐²", @"XUU²", @"XUU", @"Yuki"
        ];
    });
    return titles;
}

static NSArray<NSString *> *DYStorageTargetPluginTitles(void) {
    NSMutableArray<NSString *> *titles = [DYStorageKnownPluginTitles() mutableCopy];
    id customTitles = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYStorageTargetPluginTitles"];
    if ([customTitles isKindOfClass:[NSArray class]]) {
        for (id title in (NSArray *)customTitles) {
            if ([title isKindOfClass:[NSString class]] && ((NSString *)title).length) {
                [titles addObject:title];
            }
        }
    }
    return titles;
}

static BOOL DYStorageTitleIsTargetPlugin(NSString *title) {
    NSString *normalizedTitle = DYStorageNormalizedString(title);
    if (!normalizedTitle.length) return NO;

    for (NSString *candidate in DYStorageTargetPluginTitles()) {
        NSString *normalizedCandidate = DYStorageNormalizedString(candidate);
        if (!normalizedCandidate.length) continue;
        if ([normalizedTitle isEqualToString:normalizedCandidate]) return YES;

        // Some tweaks label the root entry as "DYYY 设置". Accept only a
        // constrained suffix, never a free-form substring match.
        if ([normalizedTitle hasPrefix:normalizedCandidate]) {
            NSString *suffix = [normalizedTitle substringFromIndex:normalizedCandidate.length];
            suffix = [suffix stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([suffix isEqualToString:@"设置"] ||
                [suffix isEqualToString:@"setting"] ||
                [suffix isEqualToString:@"settings"]) {
                return YES;
            }
        }
    }
    return NO;
}

static BOOL DYStorageItemIsHubEntry(id item);

static BOOL DYStorageSectionIsHubContent(id section) {
    NSString *identifier = DYStorageStringValue(section, @"identifier");
    if ([identifier isEqualToString:kDYStorageHubContentIdentifier]) {
        return YES;
    }
    return [DYStorageStringValue(section, @"sectionHeaderTitle") isEqualToString:kDYStorageHubMarkerTitle];
}

static BOOL DYStorageSectionIsHub(id section) {
    NSString *identifier = DYStorageStringValue(section, @"identifier");
    if ([identifier isEqualToString:kDYStorageHubSectionIdentifier] || DYStorageSectionIsHubContent(section)) {
        return YES;
    }

    // `identifier` is not present in a few older setting-model builds. In that
    // case fall back to a narrowly-scoped title plus our entry identifier.
    if (![DYStorageStringValue(section, @"sectionHeaderTitle") isEqualToString:@"DYStorage"]) return NO;
    for (id item in DYStorageArrayValue(section, @"itemArray")) {
        if (DYStorageItemIsHubEntry(item)) return YES;
    }
    return NO;
}

static BOOL DYStorageItemIsHubEntry(id item) {
    return [DYStorageStringValue(item, @"identifier") isEqualToString:kDYStorageHubEntryIdentifier];
}

static BOOL DYStorageIsXUUAssistantSectionWithItems(id section, NSArray *items) {
    if (items.count != 1) return NO;
    NSString *header = DYStorageNormalizedString(DYStorageStringValue(section, @"sectionHeaderTitle"));
    NSString *itemTitle = DYStorageNormalizedString(DYStorageStringValue(items.firstObject, @"title"));
    BOOL xuuHeader = [header hasPrefix:@"xuu"] ||
                     [header hasPrefix:@"𝙓𝙐𝙐"] ||
                     [header hasPrefix:@"𝓧𝓤𝓤"] ||
                     [header hasPrefix:@"𝕏𝕌𝕌"];
    return xuuHeader && [itemTitle isEqualToString:@"抖音助手"];
}

static NSArray *DYStorageRemoveXUUFromHubSections(NSArray *sections) {
    if (![sections isKindOfClass:[NSArray class]]) return sections;
    NSMutableArray *cleaned = [NSMutableArray arrayWithCapacity:sections.count];
    for (id section in sections) {
        if (DYStorageIsXUUAssistantSectionWithItems(section, DYStorageArrayValue(section, @"itemArray"))) continue;
        [cleaned addObject:section];
    }
    return cleaned;
}

static BOOL DYStorageLooksLikeMainSettingsPage(NSArray *sections) {
    if (![sections isKindOfClass:[NSArray class]]) return NO;

    for (id section in sections) {
        // A hub-content VM is our secondary settings page, never the Douyin
        // root. The root entry itself can safely coexist with an account marker
        // if another tweak has cached a previous return value.
        if (DYStorageSectionIsHubContent(section)) return NO;
        if (DYStorageSectionIsHub(section)) continue;

        NSString *title = DYStorageNormalizedString(DYStorageStringValue(section, @"sectionHeaderTitle"));
        if ([title isEqualToString:@"账号"] || [title hasPrefix:@"账号"] ||
            [title isEqualToString:@"账户"] || [title hasPrefix:@"账户"] ||
            [title isEqualToString:@"account"] || [title isEqualToString:@"general"]) {
            return YES;
        }

        NSString *identifier = DYStorageNormalizedString(DYStorageStringValue(section, @"identifier"));
        if ([identifier containsString:@"account"] && [identifier containsString:@"setting"]) {
            return YES;
        }
    }
    return NO;
}

#pragma mark - Native settings-model construction

static id DYStorageMakeItem(NSString *identifier,
                            NSString *title,
                            NSString *detail,
                            NSString *iconName,
                            void (^action)(void)) {
    Class itemClass = objc_lookUpClass("AWESettingItemModel");
    if (!itemClass) return nil;

    id item = [[itemClass alloc] init];
    if (!item) return nil;

    DYStorageSetValue(item, identifier, @"identifier");
    DYStorageSetValue(item, title, @"title");
    DYStorageSetValue(item, detail ?: @"", @"detail");
    DYStorageSetValue(item, iconName ?: @"", @"svgIconImageName");
    // Older DYYY variants use iconImageName; setting both is harmless when one
    // of the private properties is absent.
    DYStorageSetValue(item, iconName ?: @"", @"iconImageName");
    DYStorageSetValue(item, @0, @"type");
    DYStorageSetValue(item, @26, @"cellType");
    DYStorageSetValue(item, @2, @"colorStyle");
    DYStorageSetValue(item, @YES, @"isEnable");
    if (action) DYStorageSetValue(item, [action copy], @"cellTappedBlock");
    return item;
}

static id DYStorageMakeSection(NSString *identifier,
                               NSString *title,
                               NSArray *items) {
    Class sectionClass = objc_lookUpClass("AWESettingSectionModel");
    if (!sectionClass) return nil;

    id section = [[sectionClass alloc] init];
    if (!section) return nil;

    DYStorageSetValue(section, identifier, @"identifier");
    DYStorageSetValue(section, title, @"sectionHeaderTitle");
    DYStorageSetValue(section, @40, @"sectionHeaderHeight");
    DYStorageSetValue(section, @0, @"type");
    DYStorageSetValue(section, items ?: @[], @"itemArray");
    return section;
}

static id DYStorageCopySectionWithItems(id sourceSection, NSArray *items) {
    if (!sourceSection) return nil;

    id copiedSection = nil;
    @try {
        copiedSection = [sourceSection copy];
    } @catch (__unused NSException *exception) {
        copiedSection = nil;
    }

    if (copiedSection && copiedSection != sourceSection &&
        DYStorageSetValue(copiedSection, items, @"itemArray")) {
        return copiedSection;
    }
    // Do not rebuild an unknown private section class with a partial set of
    // fields. Its layout and click behavior may depend on unexposed state.
    return nil;
}

#pragma mark - Hub page

static void DYStoragePresentController(UIViewController *controller, UIViewController *rootController) {
    if (!controller) return;
    UIViewController *topController = DYStorageTopViewController(rootController);
    if (!topController) return;

    UINavigationController *navigationController = topController.navigationController;
    if (navigationController) {
        [navigationController pushViewController:controller animated:YES];
        return;
    }

    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFullScreen;
    [topController presentViewController:navigation animated:YES completion:nil];
}

static void DYStorageOpenRegistration(DYStorageRegistration *registration) {
    if (!registration) return;
    void (^open)(void) = ^{
        if (registration.action) {
            registration.action();
            return;
        }

        Class controllerClass = NSClassFromString(registration.controllerClassName);
        if (!controllerClass || ![controllerClass isSubclassOfClass:[UIViewController class]]) return;

        UIViewController *controller = [[controllerClass alloc] init];
        if (!controller) return;
        if (controller.title.length == 0) controller.title = registration.title;
        DYStoragePresentController(controller, nil);
    };
    if ([NSThread isMainThread]) open();
    else dispatch_async(dispatch_get_main_queue(), open);
}

#pragma mark - Aggregate search

static BOOL DYStorageDeveloperUIEnabled(void) {
    // Kept off for normal users. Developers can enable the scanner without a
    // rebuild by setting DYStorageDeveloperMode=YES in Aweme's preferences.
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYStorageDeveloperMode"];
}

static BOOL DYStorageTitleMatchesCatalogAlias(NSString *title, NSString *alias) {
    NSString *normalizedTitle = DYStorageNormalizedString(title);
    NSString *normalizedAlias = DYStorageNormalizedString(alias);
    if (!normalizedTitle.length || !normalizedAlias.length) return NO;
    if ([normalizedTitle isEqualToString:normalizedAlias]) return YES;
    if (![normalizedTitle hasPrefix:normalizedAlias]) return NO;
    NSString *suffix = [[normalizedTitle substringFromIndex:normalizedAlias.length]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return [suffix isEqualToString:@"设置"] ||
           [suffix isEqualToString:@"setting"] ||
           [suffix isEqualToString:@"settings"];
}

static BOOL DYStorageTitleMatchesCatalogEntry(NSString *title, NSDictionary *catalogEntry) {
    if (DYStorageTitleMatchesCatalogAlias(title, catalogEntry[@"plugin"])) return YES;
    for (NSString *alias in catalogEntry[@"aliases"]) {
        if (DYStorageTitleMatchesCatalogAlias(title, alias)) return YES;
    }
    return NO;
}

/// Maps canonical catalog names to the currently installed root entry. The
/// stored action is always the original plug-in callback, so a search result
/// opens the same UI as tapping that plug-in in DYStorage.
static NSDictionary<NSString *, NSDictionary *> *DYStorageInstalledSearchTargets(void) {
    DYStorageManager *manager = [DYStorageManager sharedManager];
    NSArray<NSDictionary *> *catalog = DYStorageSearchCatalog();
    NSMutableDictionary<NSString *, NSDictionary *> *targets = [NSMutableDictionary dictionary];

    for (id item in [manager capturedSettingsItems]) {
        NSString *title = DYStorageStringValue(item, @"title");
        id actionObject = DYStorageValue(item, @"cellTappedBlock");
        if (![NSStringFromClass([actionObject class]) containsString:@"Block"]) continue;

        for (NSDictionary *catalogEntry in catalog) {
            NSString *plugin = catalogEntry[@"plugin"];
            if (plugin.length == 0 || targets[plugin] || !DYStorageTitleMatchesCatalogEntry(title, catalogEntry)) continue;
            DYStorageAction action = [(DYStorageAction)actionObject copy];
            NSString *iconName = DYStorageStringValue(item, @"svgIconImageName") ?:
                                 DYStorageStringValue(item, @"iconImageName") ?: @"ic_search_outlined_20";
            targets[plugin] = @{
                @"action": action,
                @"icon": iconName,
                @"installedTitle": title ?: plugin
            };
            break;
        }
    }

    for (DYStorageRegistration *registration in [manager registeredPlugins]) {
        for (NSDictionary *catalogEntry in catalog) {
            NSString *plugin = catalogEntry[@"plugin"];
            if (plugin.length == 0 || targets[plugin] ||
                !DYStorageTitleMatchesCatalogEntry(registration.title, catalogEntry)) continue;
            DYStorageAction action = ^{
                DYStorageOpenRegistration(registration);
            };
            targets[plugin] = @{
                @"action": [action copy],
                @"icon": @"ic_search_outlined_20",
                @"installedTitle": registration.title ?: plugin
            };
            break;
        }
    }
    return targets;
}

static BOOL DYStorageSearchTextMatches(NSString *query, NSArray<NSString *> *components) {
    for (NSString *component in components) {
        if (![component isKindOfClass:[NSString class]] || component.length == 0) continue;
        if ([component rangeOfString:query
                            options:NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) {
            return YES;
        }
    }
    return NO;
}

static NSUInteger gDYStorageFeatureNavigationGeneration = 0;

static void DYStoragePulseHighlightView(UIView *view) {
    if (!view) return;
    UIView *overlay = [[UIView alloc] initWithFrame:view.bounds];
    overlay.userInteractionEnabled = NO;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [UIColor.systemYellowColor colorWithAlphaComponent:0.28];
    overlay.layer.cornerRadius = MIN(10.0, view.layer.cornerRadius);
    overlay.alpha = 0;
    [view addSubview:overlay];
    [UIView animateWithDuration:0.18 animations:^{
        overlay.alpha = 1;
    } completion:^(__unused BOOL finished) {
        [UIView animateWithDuration:0.65
                              delay:0.15
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{ overlay.alpha = 0; }
                         completion:^(__unused BOOL completed) { [overlay removeFromSuperview]; }];
    }];
}

static void DYStorageScrollToFeatureView(UIView *view) {
    if (!view) return;
    UIScrollView *scrollView = nil;
    for (UIView *ancestor = view.superview; ancestor; ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:[UIScrollView class]]) {
            scrollView = (UIScrollView *)ancestor;
            break;
        }
    }
    if (scrollView) {
        CGRect rect = [view convertRect:view.bounds toView:scrollView];
        [scrollView scrollRectToVisible:CGRectInset(rect, -12, -18) animated:YES];
    }
    __weak UIView *weakView = view;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.28 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYStoragePulseHighlightView(weakView);
    });
}

static NSString *DYStorageVisibleTextForView(UIView *view) {
    if ([view isKindOfClass:[UILabel class]]) return ((UILabel *)view).text;
    if ([view isKindOfClass:[UIButton class]]) {
        return [(UIButton *)view titleForState:UIControlStateNormal] ?: view.accessibilityLabel;
    }
    if ([view isKindOfClass:[UITextField class]]) return ((UITextField *)view).text;
    return view.accessibilityLabel;
}

static UIView *DYStorageFindFeatureTextView(UIView *view,
                                            UIView *ignoredRoot,
                                            NSString *normalizedTitle,
                                            NSInteger depth) {
    if (!view || depth < 0 || view.hidden || view.alpha < 0.01) return nil;
    if (ignoredRoot && (view == ignoredRoot || [view isDescendantOfView:ignoredRoot])) return nil;
    NSString *text = DYStorageNormalizedString(DYStorageVisibleTextForView(view));
    if (text.length && [text isEqualToString:normalizedTitle]) return view;
    for (UIView *subview in [view.subviews reverseObjectEnumerator]) {
        UIView *match = DYStorageFindFeatureTextView(subview, ignoredRoot, normalizedTitle, depth - 1);
        if (match) return match;
    }
    return nil;
}

static BOOL DYStorageLocateFeatureInVisibleWindows(UIViewController *sourceController,
                                                   NSString *title) {
    NSString *normalizedTitle = DYStorageNormalizedString(title);
    if (!normalizedTitle.length) return NO;
    // Ignore the organizer's result table itself, but not the whole source
    // controller: XUU/AwemeX may attach their floating panel directly above
    // that same controller instead of presenting a new controller/window.
    UIView *ignoredRoot = DYStorageFindTableView(sourceController.viewIfLoaded, 8) ?: sourceController.viewIfLoaded;
    NSArray<UIWindow *> *windows = [DYStorageWindows() sortedArrayUsingComparator:^NSComparisonResult(UIWindow *left,
                                                                                                       UIWindow *right) {
        if (left.windowLevel > right.windowLevel) return NSOrderedAscending;
        if (left.windowLevel < right.windowLevel) return NSOrderedDescending;
        if (left.isKeyWindow != right.isKeyWindow) return left.isKeyWindow ? NSOrderedAscending : NSOrderedDescending;
        return NSOrderedSame;
    }];
    for (UIWindow *window in windows) {
        if (window.hidden || window.alpha < 0.01) continue;
        UIView *match = DYStorageFindFeatureTextView(window, ignoredRoot, normalizedTitle, 24);
        if (!match) continue;
        DYStorageScrollToFeatureView(match);
        return YES;
    }
    return NO;
}

static BOOL DYStorageLocateFeatureInSettingsController(UIViewController *controller,
                                                        NSString *sectionTitle,
                                                        NSString *featureTitle) {
    if (!controller || objc_getAssociatedObject(controller, kDYStorageViewModelAssociationKey)) return NO;
    id viewModel = DYStorageValue(controller, @"viewModel");
    NSArray *sections = DYStorageArrayValue(viewModel, @"sectionDataArray");
    if (sections.count == 0) return NO;

    NSString *normalizedSection = DYStorageNormalizedString(sectionTitle);
    NSString *normalizedFeature = DYStorageNormalizedString(featureTitle);
    NSInteger matchedSection = NSNotFound;
    NSInteger matchedRow = NSNotFound;
    id matchedItem = nil;

    // Prefer the scanned section path; fall back to an exact title match when
    // a plug-in renamed or regrouped the setting in a later release.
    for (NSInteger pass = 0; pass < 2 && !matchedItem; pass++) {
        for (NSUInteger sectionIndex = 0; sectionIndex < sections.count && !matchedItem; sectionIndex++) {
            id section = sections[sectionIndex];
            NSString *candidateSection = DYStorageNormalizedString(DYStorageStringValue(section, @"sectionHeaderTitle"));
            if (pass == 0 && normalizedSection.length && ![candidateSection isEqualToString:normalizedSection]) continue;
            for (NSUInteger rowIndex = 0; rowIndex < DYStorageArrayValue(section, @"itemArray").count; rowIndex++) {
                id item = DYStorageArrayValue(section, @"itemArray")[rowIndex];
                if (![DYStorageNormalizedString(DYStorageStringValue(item, @"title")) isEqualToString:normalizedFeature]) continue;
                matchedSection = (NSInteger)sectionIndex;
                matchedRow = (NSInteger)rowIndex;
                matchedItem = item;
                break;
            }
        }
    }
    if (!matchedItem) return NO;

    NSNumber *cellType = DYStorageValue(matchedItem, @"cellType");
    id actionObject = DYStorageValue(matchedItem, @"cellTappedBlock");
    if ([cellType isKindOfClass:[NSNumber class]] && cellType.integerValue == 26 &&
        [NSStringFromClass([actionObject class]) containsString:@"Block"]) {
        // Cell type 26 is the settings framework's tappable navigation/action
        // row. Invoke the original callback so dialogs and child pages open at
        // the same destination as a direct tap in the plug-in.
        DYStorageAction action = [(DYStorageAction)actionObject copy];
        action();
        return YES;
    }

    UITableView *tableView = DYStorageFindTableView(controller.viewIfLoaded, 8);
    if (!tableView || matchedSection == NSNotFound || matchedRow == NSNotFound) return YES;
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:matchedRow inSection:matchedSection];
    @try {
        [tableView scrollToRowAtIndexPath:indexPath atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
        __weak UITableView *weakTableView = tableView;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.30 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UITableViewCell *cell = [weakTableView cellForRowAtIndexPath:indexPath];
            DYStoragePulseHighlightView(cell.contentView ?: cell);
        });
    } @catch (__unused NSException *exception) {
        // The private table model can differ between app versions. The feature
        // was still resolved, so leave the user on the correct plug-in page.
    }
    return YES;
}

static BOOL DYStorageTryLocateFeature(UIViewController *sourceController,
                                      NSString *section,
                                      NSString *title) {
    UIViewController *topController = DYStorageTopViewController(nil);
    if (topController != sourceController &&
        DYStorageLocateFeatureInSettingsController(topController, section, title)) {
        return YES;
    }
    return DYStorageLocateFeatureInVisibleWindows(sourceController, title);
}

static void DYStorageOpenAndLocateFeature(UIViewController *sourceController,
                                          DYStorageAction openPlugin,
                                          NSString *section,
                                          NSString *title) {
    if (!openPlugin) return;
    NSUInteger generation = ++gDYStorageFeatureNavigationGeneration;
    openPlugin();

    __weak UIViewController *weakSourceController = sourceController;
    for (NSNumber *delay in @[ @0.18, @0.45, @0.85, @1.35, @2.1, @3.0 ]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (generation != gDYStorageFeatureNavigationGeneration) return;
            if (!DYStorageTryLocateFeature(weakSourceController, section, title)) return;
            if (generation == gDYStorageFeatureNavigationGeneration) {
                ++gDYStorageFeatureNavigationGeneration;
            }
        });
    }
}

static NSArray *DYStorageAggregateSearchSections(NSString *searchText, UIViewController *sourceController) {
    NSString *query = [searchText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (query.length == 0) return DYStorageHubSections();

    NSDictionary<NSString *, NSDictionary *> *targets = DYStorageInstalledSearchTargets();
    NSMutableDictionary<NSString *, NSMutableArray *> *groupedItems = [NSMutableDictionary dictionary];
    NSMutableArray<NSString *> *orderedPaths = [NSMutableArray array];
    NSUInteger resultIndex = 0;

    for (NSDictionary *catalogEntry in DYStorageSearchCatalog()) {
        NSString *plugin = catalogEntry[@"plugin"];
        NSDictionary *target = targets[plugin];
        DYStorageAction action = (DYStorageAction)target[@"action"];
        if (plugin.length == 0 || !action) continue;

        NSArray<NSString *> *aliases = catalogEntry[@"aliases"] ?: @[];
        for (NSDictionary *feature in catalogEntry[@"features"]) {
            NSString *title = feature[@"title"];
            NSString *section = feature[@"section"] ?: @"功能";
            // DYYY's scanned model contained XUU's independently injected root
            // entry. It is not a DYYY feature and must not appear unless the
            // actual assistant plug-in is installed as its own catalog target.
            if ([plugin isEqualToString:@"DYYY"] &&
                ([section hasPrefix:@"XUU"] || [section hasPrefix:@"𝙓𝙐𝙐"] ||
                 DYStorageTitleMatchesCatalogAlias(title, @"抖音助手"))) {
                continue;
            }
            NSMutableArray<NSString *> *searchable = [NSMutableArray arrayWithObjects:plugin, section, title ?: @"", nil];
            [searchable addObjectsFromArray:aliases];
            if (!DYStorageSearchTextMatches(query, searchable)) continue;

            NSString *path = section.length ? [NSString stringWithFormat:@"%@ - %@", plugin, section] : plugin;
            NSMutableArray *items = groupedItems[path];
            if (!items) {
                items = [NSMutableArray array];
                groupedItems[path] = items;
                [orderedPaths addObject:path];
            }
            NSString *identifier = [NSString stringWithFormat:@"com.xlzs001.dystorage.search.%lu", (unsigned long)resultIndex++];
            __weak UIViewController *weakSourceController = sourceController;
            DYStorageAction resultAction = ^{
                DYStorageOpenAndLocateFeature(weakSourceController, action, section, title);
            };
            id resultItem = DYStorageMakeItem(identifier,
                                              title ?: @"未命名功能",
                                              [NSString stringWithFormat:@"点击定位 %@ 中的此功能", target[@"installedTitle"] ?: plugin],
                                              target[@"icon"],
                                              resultAction);
            if (resultItem) [items addObject:resultItem];
        }
    }

    NSMutableArray *sections = [NSMutableArray array];
    for (NSString *path in orderedPaths) {
        NSArray *items = groupedItems[path];
        if (items.count == 0) continue;
        NSString *identifier = [NSString stringWithFormat:@"com.xlzs001.dystorage.search.section.%lu",
                                  (unsigned long)sections.count];
        id section = DYStorageMakeSection(identifier, path, items);
        if (section) [sections addObject:section];
    }

    if (sections.count == 0) {
        NSString *detail = targets.count
            ? @"请尝试其他关键词"
            : @"当前没有已安装且已建立搜索目录的插件";
        id emptyItem = DYStorageMakeItem(@"com.xlzs001.dystorage.search.empty",
                                         @"未找到相关设置",
                                         detail,
                                         @"ic_search_outlined_20",
                                         nil);
        id emptySection = DYStorageMakeSection(@"com.xlzs001.dystorage.search.empty-section",
                                                @"聚合搜索",
                                                emptyItem ? @[ emptyItem ] : @[]);
        if (emptySection) [sections addObject:emptySection];
    }
    return sections;
}

static void DYStorageInstallAggregateSearch(UIViewController *controller) {
    if (!controller || objc_getAssociatedObject(controller, kDYStorageSearchCoordinatorAssociationKey)) return;
    id viewModel = objc_getAssociatedObject(controller, kDYStorageViewModelAssociationKey);
    if (!viewModel) return;
    __weak UIViewController *weakController = controller;
    DYStorageSearchCoordinator *coordinator =
        [DYStorageSearchCoordinator installOnController:controller
                                               viewModel:viewModel
                                        sectionsProvider:^NSArray *(NSString *query) {
                                            return DYStorageAggregateSearchSections(query, weakController);
                                        }];
    if (coordinator) {
        objc_setAssociatedObject(controller,
                                 kDYStorageSearchCoordinatorAssociationKey,
                                 coordinator,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static UIView *DYStorageMakeAboutFooter(void) {
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 112)];
    footer.backgroundColor = UIColor.clearColor;
    footer.accessibilityIdentifier = @"DYStorageAboutFooter";

    UILabel *(^label)(NSString *, CGFloat) = ^UILabel *(NSString *text, CGFloat size) {
        UILabel *view = [[UILabel alloc] init];
        view.text = text;
        view.textAlignment = NSTextAlignmentCenter;
        view.textColor = [UIColor secondaryLabelColor];
        view.font = [UIFont systemFontOfSize:size];
        view.translatesAutoresizingMaskIntoConstraints = NO;
        return view;
    };
    UILabel *version = label([NSString stringWithFormat:@"Version: %@", kDYStorageVersion], 14.0);
    UILabel *author = label(@"Developed by xlzs001", 13.0);
    UIButton *repository = [UIButton buttonWithType:UIButtonTypeSystem];
    [repository setTitle:@"GitHub: xlzs001/DYstorage" forState:UIControlStateNormal];
    repository.titleLabel.font = [UIFont systemFontOfSize:13.0];
    repository.translatesAutoresizingMaskIntoConstraints = NO;
    [repository addAction:[UIAction actionWithHandler:^(__unused UIAction *action) {
        NSURL *url = [NSURL URLWithString:kDYStorageRepositoryURL];
        if (url) [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
    }] forControlEvents:UIControlEventTouchUpInside];
    [footer addSubview:version];
    [footer addSubview:author];
    [footer addSubview:repository];
    [NSLayoutConstraint activateConstraints:@[
        [version.topAnchor constraintEqualToAnchor:footer.topAnchor constant:14],
        [version.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [author.topAnchor constraintEqualToAnchor:version.bottomAnchor constant:7],
        [author.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [repository.topAnchor constraintEqualToAnchor:author.bottomAnchor constant:10],
        [repository.centerXAnchor constraintEqualToAnchor:footer.centerXAnchor],
        [repository.bottomAnchor constraintLessThanOrEqualToAnchor:footer.bottomAnchor constant:-8]
    ]];
    return footer;
}

static void DYStorageInstallAboutFooter(UIViewController *controller) {
    if (!controller || !controller.isViewLoaded) return;
    UIView *footer = DYStorageMakeAboutFooter();
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [controller.view addSubview:footer];
    UITableView *tableView = DYStorageFindTableView(controller.view, 6);
    if (tableView) {
        UIEdgeInsets inset = tableView.contentInset;
        inset.bottom = MAX(inset.bottom, 112.0);
        tableView.contentInset = inset;
        tableView.scrollIndicatorInsets = inset;
    }
    [NSLayoutConstraint activateConstraints:@[
        [footer.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:controller.view.safeAreaLayoutGuide.bottomAnchor],
        [footer.heightAnchor constraintEqualToConstant:112.0]
    ]];
}

static NSArray *DYStorageHubSections(void) {
    DYStorageManager *manager = [DYStorageManager sharedManager];
    DYStorageDeveloperScanner *scanner = [DYStorageDeveloperScanner sharedScanner];
    BOOL developerUIEnabled = DYStorageDeveloperUIEnabled();
    // A scan uses a repeating main-run-loop timer. If developer mode was
    // disabled while a scan was active, stop it here so a hidden scanner can
    // never keep traversing the complete window hierarchy indefinitely.
    if (!developerUIEnabled && scanner.isScanning) [scanner stopScanning];
    NSArray *capturedItems = [manager capturedSettingsItems];
    NSArray<DYStorageRegistration *> *registeredPlugins = [manager registeredPlugins];
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableSet<NSString *> *seenKeys = [NSMutableSet set];

    if (capturedItems.count) {
        NSMutableArray *displayItems = [NSMutableArray arrayWithCapacity:capturedItems.count];
        for (id item in capturedItems) {
            NSString *key = DYStorageItemKey(item);
            if (key.length) [seenKeys addObject:key];

            id displayItem = item;
            if (scanner.isScanning) {
                NSString *title = DYStorageStringValue(item, @"title") ?: @"未命名插件";
                NSString *identifier = DYStorageStringValue(item, @"identifier") ?: [@"scan:" stringByAppendingString:title];
                NSString *detail = DYStorageStringValue(item, @"detail") ?: @"";
                NSString *iconName = DYStorageStringValue(item, @"svgIconImageName") ?: DYStorageStringValue(item, @"iconImageName");
                id actionObject = DYStorageValue(item, @"cellTappedBlock");
                if ([NSStringFromClass([actionObject class]) containsString:@"Block"]) {
                    DYStorageAction originalAction = (DYStorageAction)[actionObject copy];
                    id wrappedItem = DYStorageMakeItem(identifier, title, detail, iconName, ^{
                        [[DYStorageDeveloperScanner sharedScanner] selectPluginWithTitle:title];
                        originalAction();
                    });
                    if (wrappedItem) displayItem = wrappedItem;
                }
            }
            [displayItems addObject:displayItem];
        }
        id capturedSection = DYStorageMakeSection(kDYStorageHubContentIdentifier, @"已收纳的插件", displayItems);
        if (capturedSection) [sections addObject:capturedSection];
    }

    NSMutableArray *registeredItems = [NSMutableArray array];
    for (DYStorageRegistration *registration in registeredPlugins) {
        NSString *titleKey = DYStorageNormalizedString(registration.title);
        if (titleKey.length && ([seenKeys containsObject:[@"title:" stringByAppendingString:titleKey]] ||
                                [seenKeys containsObject:[@"identifier:" stringByAppendingString:titleKey]])) {
            continue;
        }

        __weak DYStorageRegistration *weakRegistration = registration;
        id item = DYStorageMakeItem([@"com.xlzs001.dystorage.registration." stringByAppendingString:registration.identifier ?: @"item"],
                                    registration.title,
                                    registration.version,
                                    @"ic_gearsimplify_outlined_20",
                                    ^{
                                        if ([DYStorageDeveloperScanner sharedScanner].isScanning) {
                                            [[DYStorageDeveloperScanner sharedScanner] selectPluginWithTitle:weakRegistration.title];
                                        }
                                        DYStorageOpenRegistration(weakRegistration);
                                    });
        if (item) [registeredItems addObject:item];
    }
    if (registeredItems.count) {
        id registeredSection = DYStorageMakeSection(@"com.xlzs001.dystorage.registered", @"主动接入", registeredItems);
        if (registeredSection) [sections addObject:registeredSection];
    }

    if (developerUIEnabled) {
        NSString *scannerTitle = scanner.isScanning ? @"结束扫描并导出" : @"开发者扫描";
        NSString *scannerDetail = scanner.isScanning
            ? [NSString stringWithFormat:@"已记录 %lu 个功能，点击生成 JSON", (unsigned long)scanner.recordCount]
            : @"记录插件设置页中的功能名称和位置";
        id scannerItem = DYStorageMakeItem(@"com.xlzs001.dystorage.developer-scan",
                                           scannerTitle,
                                           scannerDetail,
                                           @"ic_search_outlined_20",
                                           ^{
                                               DYStorageDeveloperScanner *activeScanner = [DYStorageDeveloperScanner sharedScanner];
                                               UIViewController *presenter = DYStorageTopViewController(nil);
                                               if (!activeScanner.isScanning) {
                                                   [activeScanner startNewScan];
                                                   UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"开发者扫描已开始"
                                                                                                                  message:@"请一次只打开一个插件，展开所有分类并缓慢滚动到底部；每个页面停留约 1 秒。悬浮窗会优先扫描最上层窗口。完成后返回 DYStorage，点击“结束扫描并导出”。"
                                                                                                           preferredStyle:UIAlertControllerStyleAlert];
                                                   [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                                                   [presenter presentViewController:alert animated:YES completion:nil];
                                                   DYStorageRefreshHubController(presenter);
                                                   return;
                                               }

                                               [activeScanner stopScanning];
                                               NSError *error = nil;
                                               if (![activeScanner exportReportFromController:presenter error:&error]) {
                                                   UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败"
                                                                                                                  message:error.localizedDescription ?: @"无法生成扫描数据"
                                                                                                           preferredStyle:UIAlertControllerStyleAlert];
                                                   [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                                                   [presenter presentViewController:alert animated:YES completion:nil];
                                               }
                                               DYStorageRefreshHubController(presenter);
                                           });
        id scannerSection = DYStorageMakeSection(@"com.xlzs001.dystorage.developer-tools",
                                                 @"开发者工具",
                                                 scannerItem ? @[ scannerItem ] : @[]);
        if (scannerSection) [sections addObject:scannerSection];
    }

    if (capturedItems.count == 0 && registeredItems.count == 0) {
        id emptyItem = DYStorageMakeItem(@"com.xlzs001.dystorage.empty",
                                         @"暂无可收纳的插件",
                                         @"打开抖音设置后会自动识别已安装的兼容插件",
                                         @"ic_gearsimplify_outlined_20",
                                         nil);
        id emptySection = DYStorageMakeSection(kDYStorageHubContentIdentifier, @"已收纳的插件", emptyItem ? @[ emptyItem ] : @[]);
        if (emptySection) [sections addObject:emptySection];
    }
    return sections;
}

static void DYStorageRefreshHubController(UIViewController *controller) {
    id viewModel = objc_getAssociatedObject(controller, kDYStorageViewModelAssociationKey);
    if (!viewModel) return;
    DYStorageSearchCoordinator *coordinator =
        objc_getAssociatedObject(controller, kDYStorageSearchCoordinatorAssociationKey);
    if (coordinator) {
        // The coordinator owns the current normal/search query. Let it build
        // and install the model once instead of replacing it twice on every
        // appearance of the organizer page.
        [coordinator refreshWithCurrentQuery];
        return;
    }

    DYStorageSetValue(viewModel, DYStorageHubSections(), @"sectionDataArray");
    if (controller.isViewLoaded) {
        DYStorageReloadListsInView(controller.view, 5);
    }
}

static void DYStorageShowHub(UIViewController *rootController) {
    void (^show)(void) = ^{
        Class controllerClass = objc_lookUpClass("AWESettingBaseViewController");
        Class viewModelClass = objc_lookUpClass("AWESettingsViewModel");
        if (!controllerClass || !viewModelClass) return;

        UIViewController *controller = [[controllerClass alloc] init];
        id viewModel = [[viewModelClass alloc] init];
        if (!controller || !viewModel) return;

        DYStorageSetValue(viewModel, @2, @"colorStyle");
        DYStorageSetValue(viewModel, controller, @"controllerDelegate");
        DYStorageSetValue(viewModel, DYStorageHubSections(), @"sectionDataArray");
        objc_setAssociatedObject(controller,
                                 kDYStorageViewModelAssociationKey,
                                 viewModel,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        controller.title = @"DYStorage";
        DYStoragePresentController(controller, rootController);
    };
    if ([NSThread isMainThread]) show();
    else dispatch_async(dispatch_get_main_queue(), show);
}

#pragma mark - Settings data-source transformation

static BOOL DYStorageSectionIsTargetPlugin(id section) {
    return DYStorageTitleIsTargetPlugin(DYStorageStringValue(section, @"sectionHeaderTitle"));
}

static BOOL DYStorageItemIsTargetPlugin(id item) {
    return DYStorageTitleIsTargetPlugin(DYStorageStringValue(item, @"title"));
}

/// Both referenced DYYY branches inject exactly one root item into a section
/// titled "DYYY". Restrict the fallback path to that shape so a plugin's own
/// multi-row settings page can never be mistaken for its root entry.
static BOOL DYStorageIsStandalonePluginEntrySection(id section, NSArray *items) {
    if (!DYStorageSectionIsTargetPlugin(section) || items.count != 1) return NO;
    return DYStorageItemIsTargetPlugin(items.firstObject);
}

/// Late-hook fallback is intentionally stricter than normal collection. Both
/// DYYY variants use `sectionHeaderTitle == item.identifier == item.title` and
/// cellType 26 for their one-row root entry. Requiring that shape avoids hiding
/// an unrelated one-row section merely because its visible title overlaps.
static BOOL DYStorageIsFallbackPluginEntrySection(id section, NSArray *items) {
    if (!DYStorageIsStandalonePluginEntrySection(section, items)) {
        // XUU's current build puts “抖音助手” in a one-row section headed
        // “XUUᶻ”, so it cannot satisfy the usual title==identifier shape.
        // Keep this exception exact to avoid hiding ordinary settings groups.
        if (items.count != 1) return NO;
        NSString *header = DYStorageNormalizedString(DYStorageStringValue(section, @"sectionHeaderTitle"));
        id item = items.firstObject;
        if (![header isEqualToString:@"xuuᶻ"] && ![header isEqualToString:@"xuu"]) return NO;
        if (!DYStorageItemIsTargetPlugin(item) ||
            ![DYStorageNormalizedString(DYStorageStringValue(item, @"title")) isEqualToString:@"抖音助手"]) return NO;
        return YES;
    }

    id item = items.firstObject;
    NSString *sectionTitle = DYStorageNormalizedString(DYStorageStringValue(section, @"sectionHeaderTitle"));
    NSString *itemIdentifier = DYStorageNormalizedString(DYStorageStringValue(item, @"identifier"));
    NSString *itemTitle = DYStorageNormalizedString(DYStorageStringValue(item, @"title"));
    NSNumber *cellType = DYStorageValue(item, @"cellType");
    return sectionTitle.length && [itemIdentifier isEqualToString:sectionTitle] &&
           [itemTitle isEqualToString:sectionTitle] &&
           [cellType isKindOfClass:[NSNumber class]] && cellType.integerValue == 26;
}

static id DYStorageMakeHubEntrySection(id viewModel) {
    __weak id weakViewModel = viewModel;
    DYStorageManager *manager = [DYStorageManager sharedManager];
    NSUInteger count = [manager capturedSettingsItems].count + [manager registeredPlugins].count;
    NSString *detail = count ? [NSString stringWithFormat:@"已收纳 %lu 个", (unsigned long)count] : @"集中管理第三方插件设置";

    id entry = DYStorageMakeItem(kDYStorageHubEntryIdentifier,
                                 @"插件收纳",
                                 detail,
                                 @"ic_gearsimplify_outlined_20",
                                 ^{
                                     UIViewController *root = DYStorageValue(weakViewModel, @"controllerDelegate");
                                     DYStorageShowHub(root);
                                 });
    return entry ? DYStorageMakeSection(kDYStorageHubSectionIdentifier, @"DYStorage", @[ entry ]) : nil;
}

static NSArray *DYStorageOrganizedMainSections(id viewModel, NSArray *originalSections) {
    if (![originalSections isKindOfClass:[NSArray class]] || originalSections.count == 0) return originalSections;
    if (!DYStorageLooksLikeMainSettingsPage(originalSections)) return originalSections;
    if (gDYStorageOrganizingMainSections) return originalSections;

    gDYStorageOrganizingMainSections = YES;
    @try {
        NSMutableArray *finalSections = [NSMutableArray array];
        NSMutableArray *capturedItems = [NSMutableArray array];

        for (id section in originalSections) {
            if (DYStorageSectionIsHub(section)) continue; // refresh our own count and action block

            NSArray *items = DYStorageArrayValue(section, @"itemArray");
            // The fallback hook may already have captured a section that was
            // appended by an outer Hook. Do not leave its now-empty shell in a
            // subsequent pass through this data source.
            if (objc_getAssociatedObject(section, kDYStorageFallbackHiddenSectionKey)) continue;
            if (DYStorageIsStandalonePluginEntrySection(section, items)) {
                if (items.count) [capturedItems addObjectsFromArray:items];
                continue;
            }

            if (items.count == 0) {
                [finalSections addObject:section];
                continue;
            }

            NSMutableArray *remainingItems = [NSMutableArray arrayWithCapacity:items.count];
            NSMutableArray *targetItems = [NSMutableArray array];
            BOOL removedItem = NO;
            for (id item in items) {
                if (DYStorageItemIsHubEntry(item)) {
                    removedItem = YES;
                    continue;
                }
                if (DYStorageItemIsTargetPlugin(item)) {
                    [targetItems addObject:item];
                    removedItem = YES;
                } else {
                    [remainingItems addObject:item];
                }
            }

            if (!removedItem || targetItems.count == 0) {
                [finalSections addObject:section];
                continue;
            }

            if (remainingItems.count == 0) {
                [capturedItems addObjectsFromArray:targetItems];
            } else {
                id copiedSection = DYStorageCopySectionWithItems(section, remainingItems);
                // Only capture an item after its source section was copied
                // successfully. Otherwise the same private model could be owned by
                // two view models at once, so leave the original section untouched.
                if (copiedSection) {
                    [capturedItems addObjectsFromArray:targetItems];
                    [finalSections addObject:copiedSection];
                } else {
                    [finalSections addObject:section];
                }
            }
        }

        if (capturedItems.count) {
            [[DYStorageManager sharedManager] captureSettingsItems:capturedItems];
            DYStorageLog(@"Captured %lu settings items", (unsigned long)capturedItems.count);
        }

        id hubSection = DYStorageMakeHubEntrySection(viewModel);
        if (hubSection) {
            [finalSections insertObject:hubSection atIndex:0];
            gDYStorageHubInsertedOnMainSettings = YES;
        }
        return finalSections;
    } @finally {
        gDYStorageOrganizingMainSections = NO;
    }
}

#pragma mark - Delayed, selector-checked Logos installation

static void DYStorageInstallAvailableHooks(void);

%group DYStorageSettingsHooks
%hook DYStorageSettingsViewModelTarget

- (NSArray *)sectionDataArray {
    NSArray *sections = %orig;
    // XUU hooks AWESettingsViewModel globally and can prepend its own section
    // after DYStorage has built the hub model. Never show that duplicate on
    // the organizer page; the preserved item already lives in our collection.
    for (id section in sections) {
        if (DYStorageSectionIsHubContent(section)) {
            return DYStorageRemoveXUUFromHubSections(sections);
        }
    }
    return DYStorageOrganizedMainSections(self, sections);
}

%end
%end

%group DYStorageSectionFallbackHooks
%hook DYStorageSectionModelTarget

- (NSArray *)itemArray {
    NSArray *items = %orig;
    BOOL hideHubDuplicate = gDYStorageHubPageVisible && DYStorageIsXUUAssistantSectionWithItems(self, items);
    BOOL hideLateRoot = gDYStorageHubInsertedOnMainSettings && DYStorageIsFallbackPluginEntrySection(self, items);
    if (gDYStorageOrganizingMainSections || (!hideHubDuplicate && !hideLateRoot)) {
        return items;
    }

    if (hideLateRoot) [[DYStorageManager sharedManager] captureSettingsItems:items];
    objc_setAssociatedObject(self,
                             kDYStorageFallbackHiddenSectionKey,
                             @YES,
                             OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // This path is only needed if a later-installed tweak appends its section
    // outside our sectionDataArray hook. The original click block is retained
    // in the hub, while the source table receives no duplicate row.
    return @[];
}

%end
%end

%group DYStorageSectionHeaderHooks
%hook DYStorageSectionHeaderTarget

- (CGFloat)sectionHeaderHeight {
    CGFloat height = %orig;
    // UIKit can ask for a section header before asking for its row count. Probe
    // the item model once in that order so the fallback can mark a qualifying
    // late-added root section before this height is returned.
    if (!objc_getAssociatedObject(self, kDYStorageFallbackHiddenSectionKey) &&
        !gDYStorageOrganizingMainSections && !gDYStorageCheckingFallbackHeader &&
        (gDYStorageHubInsertedOnMainSettings || gDYStorageHubPageVisible) &&
        DYStorageSectionIsTargetPlugin(self)) {
        gDYStorageCheckingFallbackHeader = YES;
        @try {
            (void)DYStorageArrayValue(self, @"itemArray");
        } @catch (__unused NSException *exception) {
            // Keep the original header if an unfamiliar private model rejects
            // the probe; DYStorage must never make that a page-level failure.
        } @finally {
            gDYStorageCheckingFallbackHeader = NO;
        }
    }
    return objc_getAssociatedObject(self, kDYStorageFallbackHiddenSectionKey) ? 0 : height;
}

%end
%end

%group DYStorageHubHooks
%hook DYStorageHubViewControllerTarget

- (id)viewModel {
    id customViewModel = objc_getAssociatedObject(self, kDYStorageViewModelAssociationKey);
    return customViewModel ?: %orig;
}

- (void)viewDidLoad {
    %orig;
    if (!objc_getAssociatedObject(self, kDYStorageViewModelAssociationKey)) return;
    [(UIViewController *)self setTitle:@"DYStorage"];
    gDYStorageHubPageVisible = YES;
    DYStorageRefreshHubController((UIViewController *)self);
    DYStorageInstallAboutFooter((UIViewController *)self);
    DYStorageInstallAggregateSearch((UIViewController *)self);
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    id customViewModel = objc_getAssociatedObject(self, kDYStorageViewModelAssociationKey);
    if (customViewModel) {
        gDYStorageHubPageVisible = YES;
        DYStorageRefreshHubController((UIViewController *)self);
        DYStorageInstallAggregateSearch((UIViewController *)self);
        return;
    }

    if ([DYStorageDeveloperScanner sharedScanner].isScanning) {
        __weak UIViewController *weakController = (UIViewController *)self;
        for (NSNumber *delay in @[ @0.25, @1.0 ]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIViewController *controller = weakController;
                if (!controller || ![DYStorageDeveloperScanner sharedScanner].isScanning) return;
                id viewModel = DYStorageValue(controller, @"viewModel");
                [[DYStorageDeveloperScanner sharedScanner] captureSettingsController:controller viewModel:viewModel];
            });
        }
    }
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!objc_getAssociatedObject(self, kDYStorageViewModelAssociationKey)) return;
    DYStorageSearchCoordinator *coordinator =
        objc_getAssociatedObject(self, kDYStorageSearchCoordinatorAssociationKey);
    [coordinator updateLayout];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    if (objc_getAssociatedObject(self, kDYStorageViewModelAssociationKey)) {
        [[(UIViewController *)self viewIfLoaded] endEditing:YES];
        gDYStorageHubPageVisible = NO;
    }
}

%end
%end

static void DYStorageInstallAvailableHooks(void) {
    Class settingsViewModelClass = objc_lookUpClass("AWESettingsViewModel");
    if (!gDYStorageSettingsHookInstalled && settingsViewModelClass &&
        class_getInstanceMethod(settingsViewModelClass, @selector(sectionDataArray))) {
        %init(DYStorageSettingsHooks, DYStorageSettingsViewModelTarget = settingsViewModelClass);
        gDYStorageSettingsHookInstalled = YES;
        DYStorageLog(@"Installed settings hook");
    }

    Class settingsControllerClass = objc_lookUpClass("AWESettingBaseViewController");
    if (!gDYStorageHubHookInstalled && settingsControllerClass &&
        class_getInstanceMethod(settingsControllerClass, @selector(viewModel))) {
        %init(DYStorageHubHooks, DYStorageHubViewControllerTarget = settingsControllerClass);
        gDYStorageHubHookInstalled = YES;
        DYStorageLog(@"Installed hub hook");
    }

    Class sectionModelClass = objc_lookUpClass("AWESettingSectionModel");
    if (!gDYStorageSectionFallbackHookInstalled && sectionModelClass &&
        class_getInstanceMethod(sectionModelClass, @selector(itemArray))) {
        %init(DYStorageSectionFallbackHooks, DYStorageSectionModelTarget = sectionModelClass);
        gDYStorageSectionFallbackHookInstalled = YES;
        DYStorageLog(@"Installed section fallback hook");
    }
    if (!gDYStorageSectionHeaderHookInstalled && sectionModelClass &&
        class_getInstanceMethod(sectionModelClass, @selector(sectionHeaderHeight))) {
        %init(DYStorageSectionHeaderHooks, DYStorageSectionHeaderTarget = sectionModelClass);
        gDYStorageSectionHeaderHookInstalled = YES;
        DYStorageLog(@"Installed section header hook");
    }
}

%ctor {
    @autoreleasepool {
        // DYYY installs its settings hook in its constructor. Installing ours on
        // later main-loop turns usually makes %orig observe that injected
        // section. A narrowly-scoped AWESettingSectionModel fallback below also
        // handles a root section appended by a later-installed Hook.
        dispatch_async(dispatch_get_main_queue(), ^{
            DYStorageInstallAvailableHooks();
            for (NSNumber *delay in @[ @0.5, @2.0 ]) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW,
                                              (int64_t)(delay.doubleValue * NSEC_PER_SEC)),
                               dispatch_get_main_queue(), ^{
                                   DYStorageInstallAvailableHooks();
                               });
            }
        });

        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(__unused NSNotification *note) {
                        DYStorageInstallAvailableHooks();
                    }];
    }
}
