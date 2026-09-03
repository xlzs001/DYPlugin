#import "DYStorageDeveloperScanner.h"

#import <UIKit/UIKit.h>
#import <mach-o/dyld.h>

static NSString *DYScannerString(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        id value = [object valueForKey:key];
        if ([value isKindOfClass:[NSString class]]) {
            return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        return nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static id DYScannerValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        return [object valueForKey:key];
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSArray *DYScannerArray(id object, NSString *key) {
    id value = DYScannerValue(object, key);
    return [value isKindOfClass:[NSArray class]] ? value : nil;
}

static BOOL DYScannerIgnoredPageTitle(NSString *title) {
    if (title.length == 0) return YES;
    static NSSet<NSString *> *ignoredTitles = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        ignoredTitles = [NSSet setWithArray:@[ @"设置", @"DYStorage", @"插件收纳" ]];
    });
    return [ignoredTitles containsObject:title];
}

static NSString *DYScannerControllerTitle(UIViewController *controller) {
    NSString *title = controller.title;
    if (title.length == 0) title = controller.navigationItem.title;
    return [title stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static NSArray<UIWindow *> *DYScannerWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]] || scene.activationState == UISceneActivationStateUnattached) continue;
            [windows addObjectsFromArray:((UIWindowScene *)scene).windows];
        }
    }
    if (windows.count == 0) [windows addObjectsFromArray:UIApplication.sharedApplication.windows];
    return windows;
}

static UIViewController *DYScannerTopController(void) {
    UIWindow *keyWindow = nil;
    for (UIWindow *window in DYScannerWindows()) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
        if (!keyWindow && !window.hidden && window.alpha > 0.0 && window.windowLevel == UIWindowLevelNormal) keyWindow = window;
    }

    UIViewController *controller = keyWindow.rootViewController;
    BOOL advanced = YES;
    while (controller && advanced) {
        advanced = NO;
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
            controller = controller.presentedViewController;
            advanced = YES;
            continue;
        }
        if ([controller isKindOfClass:[UINavigationController class]]) {
            UIViewController *visible = ((UINavigationController *)controller).visibleViewController;
            if (visible && visible != controller) {
                controller = visible;
                advanced = YES;
                continue;
            }
        }
        if ([controller isKindOfClass:[UITabBarController class]]) {
            UIViewController *selected = ((UITabBarController *)controller).selectedViewController;
            if (selected && selected != controller) {
                controller = selected;
                advanced = YES;
            }
        }
    }
    return controller;
}

@interface DYStorageDeveloperScanner ()
@property (nonatomic, readwrite, getter=isScanning) BOOL scanning;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *recordsByKey;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *visibleTextsByKey;
@property (nonatomic, strong) NSDate *startedAt;
@property (nonatomic, strong) NSTimer *scanTimer;
@property (nonatomic, copy) NSString *activePluginTitle;
- (NSArray<NSString *> *)pagePathForController:(UIViewController *)controller pluginTitle:(NSString **)pluginTitle;
- (void)captureVisibleInterface;
- (void)captureVisibleTextsInView:(UIView *)view
                       controller:(UIViewController *)controller
                            plugin:(NSString *)plugin
                              path:(NSArray<NSString *> *)path
                             depth:(NSInteger)depth;
- (void)startScanTimer;
@end

@implementation DYStorageDeveloperScanner

+ (instancetype)sharedScanner {
    static DYStorageDeveloperScanner *scanner = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        scanner = [[self alloc] init];
    });
    return scanner;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _recordsByKey = [NSMutableDictionary dictionary];
        _visibleTextsByKey = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSUInteger)recordCount {
    @synchronized (self) {
        return self.recordsByKey.count + self.visibleTextsByKey.count;
    }
}

- (void)startNewScan {
    @synchronized (self) {
        [self.recordsByKey removeAllObjects];
        [self.visibleTextsByKey removeAllObjects];
        self.startedAt = [NSDate date];
        self.activePluginTitle = nil;
        self.scanning = YES;
    }
    [self startScanTimer];
}

- (void)stopScanning {
    @synchronized (self) {
        self.scanning = NO;
    }
    [self.scanTimer invalidate];
    self.scanTimer = nil;
}

- (void)startScanTimer {
    if (![NSThread isMainThread]) {
        __weak DYStorageDeveloperScanner *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf startScanTimer];
        });
        return;
    }

    [self.scanTimer invalidate];
    __weak DYStorageDeveloperScanner *weakSelf = self;
    self.scanTimer = [NSTimer timerWithTimeInterval:0.75 repeats:YES block:^(__unused NSTimer *timer) {
        [weakSelf captureVisibleInterface];
    }];
    [[NSRunLoop mainRunLoop] addTimer:self.scanTimer forMode:NSRunLoopCommonModes];
    [self captureVisibleInterface];
}

- (void)captureVisibleInterface {
    if (!self.isScanning) return;
    UIViewController *controller = DYScannerTopController();
    if (!controller || [controller isKindOfClass:[UIAlertController class]] ||
        [controller isKindOfClass:[UIActivityViewController class]]) return;
    if (DYScannerIgnoredPageTitle(DYScannerControllerTitle(controller))) return;

    id viewModel = DYScannerValue(controller, @"viewModel");
    if (viewModel) [self captureSettingsController:controller viewModel:viewModel];

    NSString *pluginTitle = nil;
    NSArray<NSString *> *pagePath = [self pagePathForController:controller pluginTitle:&pluginTitle];
    if (pluginTitle.length == 0 || pagePath.count == 0) {
        NSString *className = NSStringFromClass(controller.class);
        if (className.length == 0) return;
        pluginTitle = [@"未识别:" stringByAppendingString:className];
        pagePath = @[ pluginTitle ];
    }
    if (DYScannerIgnoredPageTitle(pluginTitle)) return;

    [self captureVisibleTextsInView:controller.view
                         controller:controller
                              plugin:pluginTitle
                                path:pagePath
                               depth:14];
}

- (void)captureVisibleTextsInView:(UIView *)view
                       controller:(UIViewController *)controller
                            plugin:(NSString *)plugin
                              path:(NSArray<NSString *> *)path
                             depth:(NSInteger)depth {
    if (!view || depth < 0 || view.hidden || view.alpha < 0.01 || view.window == nil) return;

    NSString *text = nil;
    if ([view isKindOfClass:[UILabel class]]) {
        text = ((UILabel *)view).text;
    } else if ([view isKindOfClass:[UIButton class]]) {
        text = [(UIButton *)view titleForState:UIControlStateNormal];
    } else if ([view isKindOfClass:[UISegmentedControl class]]) {
        UISegmentedControl *control = (UISegmentedControl *)view;
        NSMutableArray<NSString *> *segments = [NSMutableArray array];
        for (NSInteger index = 0; index < control.numberOfSegments; index++) {
            NSString *segment = [control titleForSegmentAtIndex:index];
            if (segment.length) [segments addObject:segment];
        }
        text = [segments componentsJoinedByString:@" / "];
    }

    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length > 0 && text.length <= 200 &&
        ![text isEqualToString:@"DYStorage"] && ![text isEqualToString:@"插件收纳"]) {
        NSString *pathKey = [path componentsJoinedByString:@"/"];
        NSString *viewClass = NSStringFromClass(view.class) ?: @"";
        NSString *recordKey = [NSString stringWithFormat:@"%@|%@|%@|%@", plugin, pathKey, viewClass, text];
        NSDictionary *record = @{
            @"plugin": plugin,
            @"controllerClass": NSStringFromClass(controller.class) ?: @"",
            @"pagePath": path,
            @"pageTitle": DYScannerControllerTitle(controller) ?: @"",
            @"text": text,
            @"viewClass": viewClass,
            @"accessibilityIdentifier": view.accessibilityIdentifier ?: @""
        };
        @synchronized (self) {
            self.visibleTextsByKey[recordKey] = record;
        }
    }

    for (UIView *subview in view.subviews) {
        [self captureVisibleTextsInView:subview controller:controller plugin:plugin path:path depth:depth - 1];
    }
}

- (NSArray<NSString *> *)pagePathForController:(UIViewController *)controller pluginTitle:(NSString **)pluginTitle {
    NSMutableArray<NSString *> *path = [NSMutableArray array];
    NSArray<UIViewController *> *controllers = controller.navigationController.viewControllers;
    NSUInteger currentIndex = [controllers indexOfObjectIdenticalTo:controller];
    NSUInteger anchorIndex = NSNotFound;
    BOOL anchoredToSettings = NO;

    if (currentIndex != NSNotFound) {
        for (NSUInteger index = 0; index < currentIndex; index++) {
            NSString *title = DYScannerControllerTitle(controllers[index]);
            if ([title isEqualToString:@"DYStorage"] || [title isEqualToString:@"设置"] || [title isEqualToString:@"插件收纳"]) {
                anchorIndex = index;
                anchoredToSettings = YES;
            }
        }

        NSUInteger startIndex = anchorIndex == NSNotFound ? 0 : anchorIndex + 1;
        for (NSUInteger index = startIndex; index <= currentIndex; index++) {
            NSString *title = DYScannerControllerTitle(controllers[index]);
            if (!DYScannerIgnoredPageTitle(title) && ![path.lastObject isEqualToString:title]) [path addObject:title];
        }
    } else {
        NSString *title = DYScannerControllerTitle(controller);
        if (!DYScannerIgnoredPageTitle(title)) [path addObject:title];
    }

    UIViewController *presenting = controller.navigationController.presentingViewController ?: controller.presentingViewController;
    while (presenting && !anchoredToSettings) {
        NSString *title = DYScannerControllerTitle(presenting);
        if ([title isEqualToString:@"DYStorage"] || [title isEqualToString:@"设置"] || [title isEqualToString:@"插件收纳"]) {
            anchoredToSettings = YES;
            break;
        }
        presenting = presenting.presentingViewController;
    }

    NSString *rootTitle = path.firstObject;
    @synchronized (self) {
        if (anchoredToSettings && rootTitle.length) {
            self.activePluginTitle = rootTitle;
        } else if (self.activePluginTitle.length) {
            rootTitle = self.activePluginTitle;
            if (![path.firstObject isEqualToString:rootTitle]) [path insertObject:rootTitle atIndex:0];
        } else if (rootTitle.length) {
            self.activePluginTitle = rootTitle;
        }
    }
    if (pluginTitle) *pluginTitle = rootTitle;
    return path;
}

- (void)captureSettingsController:(UIViewController *)controller viewModel:(id)viewModel {
    if (!controller || !viewModel) return;

    @synchronized (self) {
        if (!self.scanning) return;
    }

    NSString *pluginTitle = nil;
    NSArray<NSString *> *pagePath = [self pagePathForController:controller pluginTitle:&pluginTitle];
    if (DYScannerIgnoredPageTitle(pluginTitle) || pagePath.count == 0) return;

    NSArray *sections = DYScannerArray(viewModel, @"sectionDataArray");
    if (sections.count == 0) return;

    for (id section in sections) {
        NSString *sectionTitle = DYScannerString(section, @"sectionHeaderTitle") ?: @"";
        NSArray *items = DYScannerArray(section, @"itemArray");
        for (id item in items) {
            NSString *title = DYScannerString(item, @"title");
            NSString *identifier = DYScannerString(item, @"identifier") ?: @"";
            if (title.length == 0 || [identifier hasPrefix:@"com.xlzs001.dystorage."]) continue;

            id cellTypeValue = DYScannerValue(item, @"cellType");
            NSNumber *cellType = [cellTypeValue isKindOfClass:[NSNumber class]] ? cellTypeValue : @0;
            NSDictionary *record = @{
                @"plugin": pluginTitle,
                @"controllerClass": NSStringFromClass(controller.class) ?: @"",
                @"pagePath": pagePath,
                @"pageTitle": controller.title ?: @"",
                @"section": sectionTitle,
                @"title": title,
                @"detail": DYScannerString(item, @"detail") ?: @"",
                @"identifier": identifier,
                @"itemClass": NSStringFromClass([item class]) ?: @"",
                @"cellType": cellType
            };
            NSString *pathKey = [pagePath componentsJoinedByString:@"/"];
            NSString *itemKey = identifier.length ? identifier : title;
            NSString *recordKey = [NSString stringWithFormat:@"%@|%@|%@|%@", pluginTitle, pathKey, sectionTitle, itemKey];
            @synchronized (self) {
                self.recordsByKey[recordKey] = record;
            }
        }
    }
}

- (NSArray<NSDictionary *> *)loadedTweakImages {
    NSMutableArray<NSDictionary *> *images = [NSMutableArray array];
    NSMutableSet<NSString *> *seenPaths = [NSMutableSet set];
    uint32_t count = _dyld_image_count();
    for (uint32_t index = 0; index < count; index++) {
        const char *imageName = _dyld_get_image_name(index);
        if (!imageName) continue;
        NSString *path = [NSString stringWithUTF8String:imageName];
        if (path.length == 0 || [seenPaths containsObject:path]) continue;

        BOOL systemImage = [path hasPrefix:@"/System/Library/"] ||
                           [path hasPrefix:@"/usr/lib/"] ||
                           [path containsString:@"/System/Library/"];
        BOOL loadableImage = [path.pathExtension.lowercaseString isEqualToString:@"dylib"] ||
                             [path containsString:@".framework/"];
        if (systemImage || !loadableImage) continue;

        [seenPaths addObject:path];
        [images addObject:@{
            @"name": path.lastPathComponent ?: @"",
            @"path": path
        }];
    }
    return [images sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
    }];
}

- (NSDictionary *)reportDictionary {
    NSArray<NSDictionary *> *records = nil;
    NSArray<NSDictionary *> *visibleTexts = nil;
    NSDate *startedAt = nil;
    @synchronized (self) {
        records = [self.recordsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSString *leftKey = [NSString stringWithFormat:@"%@|%@|%@", left[@"plugin"], left[@"pageTitle"], left[@"title"]];
            NSString *rightKey = [NSString stringWithFormat:@"%@|%@|%@", right[@"plugin"], right[@"pageTitle"], right[@"title"]];
            return [leftKey localizedCaseInsensitiveCompare:rightKey];
        }];
        visibleTexts = [self.visibleTextsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSString *leftKey = [NSString stringWithFormat:@"%@|%@|%@", left[@"plugin"], left[@"pageTitle"], left[@"text"]];
            NSString *rightKey = [NSString stringWithFormat:@"%@|%@|%@", right[@"plugin"], right[@"pageTitle"], right[@"text"]];
            return [leftKey localizedCaseInsensitiveCompare:rightKey];
        }];
        startedAt = self.startedAt;
    }

    NSISO8601DateFormatter *formatter = [[NSISO8601DateFormatter alloc] init];
    return @{
        @"schemaVersion": @1,
        @"generatedAt": [formatter stringFromDate:[NSDate date]],
        @"startedAt": startedAt ? [formatter stringFromDate:startedAt] : @"",
        @"systemVersion": UIDevice.currentDevice.systemVersion ?: @"",
        @"records": records ?: @[],
        @"visibleTexts": visibleTexts ?: @[],
        @"loadedTweakImages": [self loadedTweakImages]
    };
}

- (BOOL)exportReportFromController:(UIViewController *)controller error:(NSError **)error {
    NSDictionary *report = [self reportDictionary];
    NSData *data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;

    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (json.length) UIPasteboard.generalPasteboard.string = json;

    long long timestamp = (long long)[NSDate date].timeIntervalSince1970;
    NSString *filename = [NSString stringWithFormat:@"DYStorage-scan-%@.json", @(timestamp)];
    NSURL *fileURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
    if (![data writeToURL:fileURL options:NSDataWritingAtomic error:error]) return NO;

    UIViewController *presenter = controller;
    while (presenter.presentedViewController && !presenter.presentedViewController.isBeingDismissed) {
        presenter = presenter.presentedViewController;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ fileURL ] applicationActivities:nil];
    activity.popoverPresentationController.sourceView = presenter.view;
    activity.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMaxY(presenter.view.bounds), 1, 1);
    [presenter presentViewController:activity animated:YES completion:nil];
    return YES;
}

@end
