#import "DYStorageManager.h"

@implementation DYStorageRegistration
@end

static NSString *DYStorageStringValue(id object, NSString *key) {
    if (!object || key.length == 0) return nil;
    @try {
        id value = [object valueForKey:key];
        return [value isKindOfClass:[NSString class]] ? value : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *DYStorageNormalizedKey(NSString *value) {
    if (value.length == 0) return nil;
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmed.lowercaseString.length ? trimmed.lowercaseString : nil;
}

static NSString *DYStorageKeyForSettingItem(id item) {
    NSString *identifier = DYStorageNormalizedKey(DYStorageStringValue(item, @"identifier"));
    if (identifier.length) return [@"identifier:" stringByAppendingString:identifier];

    NSString *title = DYStorageNormalizedKey(DYStorageStringValue(item, @"title"));
    return title.length ? [@"title:" stringByAppendingString:title] : nil;
}

@interface DYStorageManager ()
- (BOOL)upsertRegistrationWithIdentifier:(NSString *)identifier
                                   title:(NSString *)title
                                 version:(NSString *)version
                      controllerClassName:(NSString *)controllerClassName
                                  action:(DYStorageAction)action;
@end

@implementation DYStorageManager {
    NSMutableArray *_capturedSettingsItems;
    NSMutableArray<DYStorageRegistration *> *_registeredPlugins;
}

+ (instancetype)sharedManager {
    static DYStorageManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _capturedSettingsItems = [NSMutableArray array];
        _registeredPlugins = [NSMutableArray array];
    }
    return self;
}

- (void)captureSettingsItems:(NSArray *)items {
    if (![items isKindOfClass:[NSArray class]] || items.count == 0) return;

    @synchronized (self) {
        for (id item in items) {
            NSString *key = DYStorageKeyForSettingItem(item);
            if (!key.length) continue;

            NSUInteger existingIndex = NSNotFound;
            for (NSUInteger index = 0; index < _capturedSettingsItems.count; index++) {
                if ([DYStorageKeyForSettingItem(_capturedSettingsItems[index]) isEqualToString:key]) {
                    existingIndex = index;
                    break;
                }
            }

            if (existingIndex == NSNotFound) {
                [_capturedSettingsItems addObject:item];
            } else {
                // Settings view models are recreated during refreshes. Keep the
                // latest item so its click block never points at a stale model.
                _capturedSettingsItems[existingIndex] = item;
            }
        }
    }
}

- (void)replaceCapturedSettingsItems:(NSArray *)items {
    if (![items isKindOfClass:[NSArray class]]) return;

    NSMutableArray *deduplicated = [NSMutableArray array];
    NSMutableSet *keys = [NSMutableSet set];
    for (id item in items) {
        NSString *key = DYStorageKeyForSettingItem(item);
        if (!key.length || [keys containsObject:key]) continue;
        [keys addObject:key];
        [deduplicated addObject:item];
    }

    @synchronized (self) {
        _capturedSettingsItems = deduplicated;
    }
}

- (NSArray *)capturedSettingsItems {
    @synchronized (self) {
        return [_capturedSettingsItems copy];
    }
}

- (NSArray<DYStorageRegistration *> *)registeredPlugins {
    @synchronized (self) {
        return [_registeredPlugins copy];
    }
}

- (BOOL)registerActionWithIdentifier:(NSString *)identifier
                               title:(NSString *)title
                             version:(NSString *)version
                              action:(DYStorageAction)action {
    if (title.length == 0 || !action) return NO;
    return [self upsertRegistrationWithIdentifier:identifier
                                             title:title
                                           version:version
                                controllerClassName:nil
                                            action:action];
}

- (BOOL)registerControllerWithIdentifier:(NSString *)identifier
                                    title:(NSString *)title
                                  version:(NSString *)version
                               controller:(NSString *)controllerClassName {
    if (title.length == 0 || controllerClassName.length == 0) return NO;
    return [self upsertRegistrationWithIdentifier:identifier
                                             title:title
                                           version:version
                                controllerClassName:controllerClassName
                                            action:nil];
}

- (BOOL)registerActionWithTitle:(NSString *)title
                         version:(NSString *)version
                          action:(DYStorageAction)action {
    NSString *identifier = [@"title:" stringByAppendingString:DYStorageNormalizedKey(title) ?: @""];
    return [self registerActionWithIdentifier:identifier title:title version:version action:action];
}

- (void)unregisterPluginWithIdentifier:(NSString *)identifier {
    NSString *key = DYStorageNormalizedKey(identifier);
    if (!key.length) return;

    @synchronized (self) {
        NSIndexSet *indexes = [_registeredPlugins indexesOfObjectsPassingTest:^BOOL(DYStorageRegistration *plugin, NSUInteger index, BOOL *stop) {
            return [DYStorageNormalizedKey(plugin.identifier) isEqualToString:key];
        }];
        if (indexes.count) [_registeredPlugins removeObjectsAtIndexes:indexes];
    }
}

- (BOOL)upsertRegistrationWithIdentifier:(NSString *)identifier
                                   title:(NSString *)title
                                 version:(NSString *)version
                      controllerClassName:(NSString *)controllerClassName
                                  action:(DYStorageAction)action {
    NSString *key = DYStorageNormalizedKey(identifier);
    if (!key.length) key = DYStorageNormalizedKey(title);
    if (!key.length) return NO;

    DYStorageRegistration *registration = [[DYStorageRegistration alloc] init];
    registration.identifier = key;
    registration.title = title;
    registration.version = version;
    registration.controllerClassName = controllerClassName;
    registration.action = action;

    @synchronized (self) {
        NSUInteger existingIndex = NSNotFound;
        for (NSUInteger index = 0; index < _registeredPlugins.count; index++) {
            if ([DYStorageNormalizedKey(_registeredPlugins[index].identifier) isEqualToString:key]) {
                existingIndex = index;
                break;
            }
        }
        if (existingIndex == NSNotFound) {
            [_registeredPlugins addObject:registration];
        } else {
            _registeredPlugins[existingIndex] = registration;
        }
    }
    return YES;
}

@end
