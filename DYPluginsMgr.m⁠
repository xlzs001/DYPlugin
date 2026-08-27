#import "DYPluginsMgr.h"

@implementation DYPluginsMgr
+ (instancetype)sharedInstance {
    static DYPluginsMgr *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DYPluginsMgr alloc] init];
        instance.plugins = [NSMutableArray array];
    });
    return instance;
}
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controllerName {
    DYPluginModel *model = [[DYPluginModel alloc] init];
    model.isController = YES;
    model.title = title;
    model.version = version;
    model.controllerName = controllerName;
    [self.plugins addObject:model];
}
- (void)registerSwitchWithTitle:(NSString *)title key:(NSString *)key {
    DYPluginModel *model = [[DYPluginModel alloc] init];
    model.isController = NO;
    model.title = title;
    model.key = key;
    [self.plugins addObject:model];
}
@end

