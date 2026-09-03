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

@interface DYStorageDeveloperScanner ()
@property (nonatomic, readwrite, getter=isScanning) BOOL scanning;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary *> *recordsByKey;
@property (nonatomic, strong) NSDate *startedAt;
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
    }
    return self;
}

- (NSUInteger)recordCount {
    @synchronized (self) {
        return self.recordsByKey.count;
    }
}

- (void)startNewScan {
    @synchronized (self) {
        [self.recordsByKey removeAllObjects];
        self.startedAt = [NSDate date];
        self.scanning = YES;
    }
}

- (void)stopScanning {
    @synchronized (self) {
        self.scanning = NO;
    }
}

- (NSArray<NSString *> *)pagePathForController:(UIViewController *)controller pluginTitle:(NSString **)pluginTitle {
    NSMutableArray<NSString *> *path = [NSMutableArray array];
    NSArray<UIViewController *> *controllers = controller.navigationController.viewControllers;
    NSUInteger currentIndex = [controllers indexOfObjectIdenticalTo:controller];
    NSUInteger anchorIndex = NSNotFound;

    if (currentIndex != NSNotFound) {
        for (NSUInteger index = 0; index < currentIndex; index++) {
            NSString *title = controllers[index].title;
            if ([title isEqualToString:@"DYStorage"] || [title isEqualToString:@"设置"] || [title isEqualToString:@"插件收纳"]) {
                anchorIndex = index;
            }
        }

        NSUInteger startIndex = anchorIndex == NSNotFound ? 0 : anchorIndex + 1;
        for (NSUInteger index = startIndex; index <= currentIndex; index++) {
            NSString *title = controllers[index].title;
            if (!DYScannerIgnoredPageTitle(title) && ![path.lastObject isEqualToString:title]) [path addObject:title];
        }
    } else if (!DYScannerIgnoredPageTitle(controller.title)) {
        [path addObject:controller.title];
    }

    NSString *rootTitle = path.firstObject;
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

        BOOL tweakPath = [path containsString:@"/DynamicLibraries/"] ||
                         [path containsString:@"/TweakInject/"] ||
                         [path containsString:@"/Library/Tweaks/"];
        if (!tweakPath) continue;

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
    NSDate *startedAt = nil;
    @synchronized (self) {
        records = [self.recordsByKey.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            NSString *leftKey = [NSString stringWithFormat:@"%@|%@|%@", left[@"plugin"], left[@"pageTitle"], left[@"title"]];
            NSString *rightKey = [NSString stringWithFormat:@"%@|%@|%@", right[@"plugin"], right[@"pageTitle"], right[@"title"]];
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
