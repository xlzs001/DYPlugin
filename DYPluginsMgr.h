#import <Foundation/Foundation.h>
#import "DYPluginModel.h"

@interface DYPluginsMgr : NSObject
@property (nonatomic, strong) NSMutableArray<DYPluginModel *> *plugins;
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controllerName;
- (void)registerSwitchWithTitle:(NSString *)title key:(NSString *)key;
@end
