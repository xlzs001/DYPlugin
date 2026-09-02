#import <Foundation/Foundation.h>

typedef void (^DYStorageAction)(void);

/// A plug-in setting page registered explicitly with DYStorage.
///
/// Third-party tweaks can use DYStorageManager through the Objective-C runtime,
/// so they do not need to link against this project.
@interface DYStorageRegistration : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *controllerClassName;
@property (nonatomic, copy) DYStorageAction action;
@end

/// Process-wide registry shared by DYStorage and compatible tweaks.
@interface DYStorageManager : NSObject

+ (instancetype)sharedManager;

/// Registers a block that presents a tweak's own settings UI.
- (BOOL)registerActionWithIdentifier:(NSString *)identifier
                               title:(NSString *)title
                             version:(NSString *)version
                              action:(DYStorageAction)action;

/// Registers a UIViewController class name whose default initializer opens a
/// tweak's settings page.
- (BOOL)registerControllerWithIdentifier:(NSString *)identifier
                                    title:(NSString *)title
                                  version:(NSString *)version
                               controller:(NSString *)controllerClassName;

/// Compatibility form for integrations that identify themselves by title.
- (BOOL)registerActionWithTitle:(NSString *)title
                         version:(NSString *)version
                          action:(DYStorageAction)action;

- (void)unregisterPluginWithIdentifier:(NSString *)identifier;

/// Internal bridge used by the Hook layer. The objects are Aweme setting-item
/// models and deliberately stay untyped so the tweak remains version-tolerant.
- (void)captureSettingsItems:(NSArray *)items;
- (void)replaceCapturedSettingsItems:(NSArray *)items;
- (NSArray *)capturedSettingsItems;
- (NSArray<DYStorageRegistration *> *)registeredPlugins;

@end
